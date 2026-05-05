# frozen_string_literal: true

##
# Chat::CompactionService — Summarizes older messages to manage context window limits.
#
# Works on ALL chats (regular user chats + agent chats). Agent chats get the
# bonus of agent-guided summaries — the agent's instructions tell the summarizer
# what's important to preserve.
#
# The summary is stored on the chat record (not as a message) and injected into
# the system prompt by ChatStreamJob. Original messages are preserved in DB
# marked `compacted: true` for audit trail and UI display.
#
# Concurrency: Uses `compacting_since` datetime column as a lock. Atomic
# UPDATE with WHERE clause ensures only one process compacts a given chat.
# Stale locks auto-expire after LOCK_TIMEOUT (process crash recovery).
# Works on both SQLite and Postgres.
#
# Usage:
#   Chat::CompactionService.new(chat).compact_if_needed!  # normal auto-compact
#   Chat::CompactionService.new(chat).force_compact!       # manual/UI trigger
#   Chat::CompactionService.new(chat).compact_on_overflow! # context overflow recovery
#
class Chat::CompactionService
  THRESHOLD_RATIO = 0.6           # Compact at 60% of model's context window
  FALLBACK_THRESHOLD = 100_000    # When model info unavailable
  KEEP_RECENT_TURNS = 5           # Keep last 5 complete user/assistant turns verbatim
  KEEP_RECENT_TOKENS_MIN = 20_000 # Minimum recent tokens to preserve
  MIN_MESSAGES_TO_COMPACT = 10    # Don't compact tiny conversations
  COOLDOWN_PERIOD = 30.minutes    # Minimum time between compactions
  LOCK_TIMEOUT = 5.minutes        # Stale lock auto-expires (process crash recovery)

  SUMMARY_FALLBACK_MODEL = "claude-haiku-4-5"
  MAX_SUMMARY_OUTPUT = 16_384     # 16KB hard cap on summary text
  MAX_TRANSCRIPT_CHARS = 80_000   # Budget for summarizer input

  def initialize(chat)
    @chat = chat
  end

  # Auto-compact if threshold exceeded and cooldown elapsed.
  def compact_if_needed!
    return false unless should_compact?
    with_compaction_lock { perform_compaction! }
  end

  # Compact regardless of cooldown (for manual/UI trigger).
  def force_compact!
    with_compaction_lock { perform_compaction! }
  end

  # Compact on context overflow — ignores cooldown, used by retry logic.
  def compact_on_overflow!
    with_compaction_lock { perform_compaction! }
  end

  def should_compact?
    return false if active_messages_count < MIN_MESSAGES_TO_COMPACT
    return false if recently_compacted?
    estimated_tokens > threshold
  end

  private

  # --- Concurrency lock (works on SQLite + Postgres) ---
  #
  # Atomic UPDATE ensures only one process can acquire the lock per chat.
  # Stale locks (from crashed processes) auto-expire after LOCK_TIMEOUT.

  def with_compaction_lock
    return false unless acquire_compaction_lock!
    begin
      yield
    ensure
      release_compaction_lock!
    end
  end

  def acquire_compaction_lock!
    rows = Chat.where(id: @chat.id)
      .where("compacting_since IS NULL OR compacting_since < ?", LOCK_TIMEOUT.ago)
      .update_all(compacting_since: Time.current)
    if rows > 0
      true
    else
      Rails.logger.info "[Compaction] Chat #{@chat.id}: skipped, already in progress"
      false
    end
  end

  def release_compaction_lock!
    @chat.update_columns(compacting_since: nil)
  end

  # --- Summary model ---

  def summary_model
    @chat.model&.model_id.presence || SUMMARY_FALLBACK_MODEL
  end

  # --- Core compaction ---

  def perform_compaction!
    messages_to_keep, messages_to_compact = partition_messages
    return false if messages_to_compact.empty?

    compacted_message_ids = messages_to_compact.map(&:id)
    previous_summary = @chat.compaction_summary

    # LLM call OUTSIDE transaction — if it fails, DB is untouched
    summary_text = generate_summary(messages_to_compact, previous_summary)

    ActiveRecord::Base.transaction do
      Message.where(id: compacted_message_ids).update_all(compacted: true)
      @chat.update_columns(
        compaction_summary: summary_text,
        last_compacted_at: Time.current
      )
    end

    @chat.messages.reset  # Clear AR association cache after update_all
    broadcast_compacted_messages(compacted_message_ids)
    Rails.logger.info "[Compaction] Chat #{@chat.id}: compacted #{messages_to_compact.size} messages"
    true
  end

  def broadcast_compacted_messages(message_ids)
    Message.where(id: message_ids).find_each(&:broadcast_full_replace!)
  rescue => e
    Rails.logger.error "[Compaction] Chat #{@chat.id}: failed to broadcast compacted messages: #{e.class}: #{e.message}"
  end

  # --- Threshold ---

  def threshold
    return @chat.compaction_token_threshold if @chat.compaction_token_threshold.present?

    model_id = @chat.model&.model_id.presence || RubyLLM.config.default_model
    model_info = begin
      RubyLLM.models.find(model_id)
    rescue
      nil
    end
    model_info&.context_window ? (model_info.context_window * THRESHOLD_RATIO).to_i : FALLBACK_THRESHOLD
  end

  # --- Token estimation ---
  #
  # Primary: Use input_tokens from the last assistant message — this is the
  # actual token count the API reported for the full context window on that turn.
  # It includes system prompt, tool definitions, and all message history.
  #
  # Fallback: chars/4 estimate for seeded/imported messages without token data.
  #
  def estimated_tokens
    last_input = @chat.messages
      .where(role: :assistant, compacted: false, skip_llm_context: false)
      .where.not(input_tokens: [ nil, 0 ])
      .order(created_at: :desc)
      .pick(:input_tokens)

    return last_input if last_input

    # Fallback for chats without API token data (seeded, imported, etc.)
    chars = active_messages_scope.sum("COALESCE(LENGTH(content), 0)")
    chars / 4
  end

  def active_messages_count
    active_messages_scope.count
  end

  def active_messages_scope
    @chat.messages.where(compacted: false, skip_llm_context: false)
  end

  # --- Partitioning ---

  def partition_messages
    all = active_messages_scope
      .order(:created_at)
      .to_a

    return [ all, [] ] if all.size < MIN_MESSAGES_TO_COMPACT

    # Find where the last N turns start (turn = user msg + response chain)
    turn_idx = find_turn_boundary(all, KEEP_RECENT_TURNS)
    token_idx = find_token_boundary(all, KEEP_RECENT_TOKENS_MIN)

    # Token boundary returns 0 when all content fits within the minimum —
    # in that case, ignore it and use the turn boundary only.
    split_idx = if token_idx == 0
      turn_idx
    else
      [ turn_idx, token_idx ].min
    end
    split_idx = find_safe_split(all, split_idx)

    return [ all, [] ] if split_idx < 2

    [ all[split_idx..], all[0...split_idx] ]
  end

  def find_turn_boundary(msgs, turns)
    found = 0
    (msgs.size - 1).downto(0) do |i|
      if msgs[i].role.to_s == "user" && msgs[i].tool_call_id.nil?
        found += 1
        return i if found >= turns
      end
    end
    0
  end

  def find_token_boundary(msgs, min_tokens)
    budget = min_tokens
    msgs.reverse_each.with_index do |msg, idx|
      budget -= (msg.content.to_s.length / 4)
      return msgs.size - idx - 1 if budget <= 0
    end
    0
  end

  # Ensure split happens at a user message boundary (not mid-tool-chain)
  def find_safe_split(msgs, proposed)
    idx = proposed
    idx -= 1 while idx > 0 && !(msgs[idx].role.to_s == "user" && msgs[idx].tool_call_id.nil?)
    idx == 0 ? proposed : idx
  end

  # --- Summary generation ---

  def generate_summary(messages, previous_content)
    transcript = build_transcript(messages)

    previous_block = if previous_content.present?
      "\n## Previous summary (merge into your new summary):\n\n#{previous_content.truncate(10_000)}\n"
    else
      ""
    end

    # Agent instructions guide what's worth preserving.
    agent_guidance = if (agent = @chat.agent)
      focus = agent.resolved_instructions&.truncate(1000)
      "\nThis is a persistent agent. Its purpose:\n#{focus}\n" \
        "Preserve what matters for this agent's ongoing work.\n"
    else
      ""
    end

    prompt = <<~PROMPT
      Summarize this conversation into a concise working memory document.
      The original messages will be removed from context. Only your summary
      and the most recent messages (kept verbatim) will remain.

      Rules:
      - Keep what matters going forward. Drop resolved/completed items.
      - Be concise but complete. Under 2000 words.
      - Use clear headings to organize the summary.
      #{agent_guidance}#{previous_block}
      ## Conversation:

      #{transcript}
    PROMPT

    response = RubyLLM.chat(model: summary_model).ask(prompt)
    content = response.content.truncate(MAX_SUMMARY_OUTPUT)

    range = "#{messages.first.created_at.strftime('%b %d')} – #{messages.last.created_at.strftime('%b %d, %Y')}"

    <<~SUMMARY
      [Context Summary — #{Time.current.strftime('%b %d, %Y')}]
      [#{messages.size} messages compacted, #{range}]

      #{content}

      [End of summary. Recent messages follow verbatim.]
    SUMMARY
  end

  def build_transcript(messages)
    budget = [ MAX_TRANSCRIPT_CHARS / messages.size, 2000 ].min
    messages.map { |m|
      role = m.role.to_s.capitalize
      text = m.content.to_s.truncate(budget)
      "#{role}: #{text}"
    }.join("\n\n").truncate(MAX_TRANSCRIPT_CHARS)
  end

  def recently_compacted?
    @chat.last_compacted_at.present? && @chat.last_compacted_at > COOLDOWN_PERIOD.ago
  end
end

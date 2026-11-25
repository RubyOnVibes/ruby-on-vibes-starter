# frozen_string_literal: true

class ChatStreamJob < ApplicationJob
  queue_as :agents
  discard_on ActiveRecord::RecordNotFound
  
  # How often to poll DB for cancellation (seconds)
  STOP_CHECK_INTERVAL = ENV.fetch('CHAT_STOP_CHECK_INTERVAL', 0.3).to_f
  CLAIM_RETRY_WAIT = 2.seconds
  CLAIM_RETRY_LIMIT = 150

  # New deliveries carry only the durable run ID. Accept the old payload
  # during rolling upgrades, but never allow it to select another chat/actor.
  def perform(run_or_chat_id, legacy_message_id = nil, legacy_run_id = nil, legacy_options = {})
    @chat_run = ChatRun.find(legacy_run_id || run_or_chat_id)
    if legacy_run_id
      raise ArgumentError, "Chat does not match run" unless @chat_run.chat_id == run_or_chat_id.to_i
      if legacy_message_id && @chat_run.input_message_id.nil?
        @chat_run.update!(input_message: @chat_run.chat.messages.find(legacy_message_id))
      end
    end
    @options = @chat_run.execution_options.symbolize_keys
    @options.merge!(legacy_options.symbolize_keys.slice(:task_continuation, :approval_resume, :continuation_depth, :claim_retries)) if legacy_run_id
    @task_continuation = @options[:task_continuation] == true
    @approval_resume = @options[:approval_resume] == true
    RubyLLM.with_owner(@chat_run) { perform_run(@chat_run.chat_id, @chat_run.input_message_id) }
  end

  private def perform_run(chat_id, user_msg_id)
    return unless @chat_run.active?
    if @chat_run.chat.running?
      # A new turn can arrive before the previous run releases its native
      # claim. Keep that turn queued; duplicate deliveries of the running turn
      # itself still leave the worker that owns it alone.
      return retry_after_claim(chat_id, user_msg_id) if @chat_run.status_pending? || @options[:claim_retries].to_i.positive?
      return
    end

    # Legacy application tasks need a persisted continuation turn. Native
    # tasks resume their tool call directly, without adding user messages.
    if @chat_run.status_awaiting_tasks? && @chat_run.chat.pending_tasks.empty?
      return @chat_run.resume_tasks!
    end
    setup_chat(chat_id, user_msg_id)

    @last_stop_check = Time.current
    @chat_run.with_lock do
      return unless @chat_run.active?
      @chat_run.update!(status: :running)
    end
    stream_response
    return unless @chat_run.reload.active?
    # A competing delivery can return without claiming the chat. It must not
    # mark the process that actually owns the conversation loop complete.
    return retry_after_claim(chat_id, user_msg_id) if @chat.running?

    # Project native state while holding the same lock used by approvals and
    # cancellation. Reload after a competing delivery so cached history cannot
    # turn another worker's approval wait into a completed run.
    @chat_run.with_lock do
      return unless @chat_run.active?
      @chat.reload
      return if @chat.running?
      # RubyLLM deliberately parks the completion loop before executing a tool
      # declared with `requires_approval`. Persist enough metadata for an
      # authorized human to decide it from any process, then leave this ChatRun
      # active until the controller resumes it.
      if park_for_tool_approval!
        return @chat_run
      end

      # Decide whether to enter awaiting_tasks or complete.
      #
      # Two cases need awaiting_tasks:
      # 1. Tasks are still actively running (wait for them)
      # 2. Initial run created tasks that already completed (fast tasks)
      #    — the LLM couldn't have seen their results, so we need a continuation
      #
      # For continuation runs, only re-enter awaiting_tasks if NEW tasks are
      # still active (to avoid re-summarizing already-covered tasks).
      #
      # Max depth prevents infinite loops if continuations keep creating tasks.
      continuation_depth = @options[:continuation_depth].to_i
      max_depth = ENV.fetch('MAX_CONTINUATION_DEPTH', 5).to_i
      if @chat.pending_tasks.any?
        @chat_run.transition_to_awaiting_tasks!
        working = @chat.pending_tasks.reject(&:input_required?)
        if working.any?
          interval = working.map { |task| task.poll_interval.to_f.positive? ? task.poll_interval.to_f : 5 }.min.clamp(1, 300)
          @chat_run.dispatch!(wait: interval)
        else
          @chat_run.update!(resume_at: nil)
        end
        return @chat_run
      end

      tasks_during_run = @chat_run.business_tasks

      if tasks_during_run.active.exists?
        if continuation_depth >= max_depth
          Rails.logger.warn "[ChatStreamJob] Max continuation depth (#{max_depth}) reached, completing despite active tasks"
          @chat_run.update!(status: :completed)
        else
          @chat_run.transition_to_awaiting_tasks!
        end
      elsif !@task_continuation && tasks_during_run.exists?
        # Initial run: tasks created and already completed — auto-continue to summarize
        @chat_run.transition_to_awaiting_tasks!
      else
        @chat_run.update!(status: :completed)
      end

      @chat_run.dispatch!(wait: 5) if @chat_run.status_awaiting_tasks?
    end
    @llm_msg&.broadcast_upsert_to_chat!
    @chat_run
  rescue RubyLLM::ToolRoundLimitError
    # This is an intentional stop, not a retryable provider failure. RubyLLM
    # has saved the completed tool results; keep them for the next user turn.
    @chat_run.reload
    unless @chat_run.status_cancelled?
      @chat_run.update!(status: :failed)
      @llm_msg = @chat.messages.create!(
        role: :assistant,
        content: "I reached this response's tool limit. Send another message to continue."
      )
      @llm_msg.broadcast_append_to_chat
    end
  rescue RubyLLM::Error => e
    # RubyLLM errors (including tool call mismatches from cancellation race)
    Rails.logger.error "[ChatStreamJob] RubyLLM error: #{e.class} - #{e.message}"

    # RubyLLM distinguishes context overflow from quota and authentication errors.
    # Compact and retry once; unrelated provider errors must not trigger another
    # paid summarization request.
    if e.is_a?(RubyLLM::ContextLengthExceededError) && !@overflow_retried
      @overflow_retried = true
      if Chat::CompactionService.new(@chat).compact_on_overflow!
        @chat.messages.reset  # Clear AR cache so retry sees compacted=true
        @chat.reload          # Refresh compaction_summary for system prompt
        Rails.logger.info "[ChatStreamJob] Compacted on overflow, retrying"
        retry
      end
    end

    # Don't overwrite cancelled status
    @chat_run&.reload
    unless @chat_run&.status_cancelled?
      @chat_run&.update!(status: :failed)

      error_content = if e.message.include?('tool_call') || e.message.include?('tool_use')
        "I encountered an error with tool execution. Please try again."
      else
        "Error: #{e.message}"
      end

      # IMPORTANT: RubyLLM's cleanup_failed_messages may have destroyed @llm_msg
      # from the DB while the Ruby object still exists. Check DB existence before
      # updating, otherwise update_columns silently updates 0 rows and no error
      # message persists — leaving orphaned user messages that break the next API call.
      persist_error_message(error_content)
    end

    # Don't re-raise — handled gracefully
  rescue => e
    Rails.logger.error "[ChatStreamJob] Job failed: #{e.class} - #{e.message}"

    @chat_run&.reload
    unless @chat_run&.status_cancelled?
      @chat_run&.update!(status: :failed)
      persist_error_message("Error: #{e.message}")
    end
    raise
  ensure
    capture_and_publish_usage
  end

  private

  def retry_after_claim(chat_id, user_msg_id)
    attempts = @options[:claim_retries].to_i
    if attempts >= CLAIM_RETRY_LIMIT
      @chat_run.update!(status: :failed)
      @chat ||= Chat.find(chat_id)
      persist_error_message("The previous response is still running. Please try again when it finishes.")
      return
    end

    self.class.set(wait: CLAIM_RETRY_WAIT).perform_later(
      chat_id, user_msg_id, @chat_run.id, @options.merge(claim_retries: attempts + 1)
    )
  end
  
  def stopped?
    # Throttle DB queries - only reload if interval has passed
    if Time.current - @last_stop_check >= STOP_CHECK_INTERVAL
      @chat_run.reload
      @last_stop_check = Time.current
    end
    
    @chat_run.stopping?
  end

  def setup_chat(chat_id, user_msg_id)
    @llm_msg = nil
    @chat = Chat.find(chat_id)

    @sender_member = @chat_run.execution_member!
    @sender_user = @sender_member.user
    @sender_workspace = @sender_member.workspace
    @user_msg = @chat.messages.find(user_msg_id) if user_msg_id


    # Auto-compact if context is getting large (best-effort — never block streaming)
    begin
      Chat::CompactionService.new(@chat).compact_if_needed!
    rescue => e
      Rails.logger.error "[ChatStreamJob] Compaction failed, continuing: #{e.class} - #{e.message}"
    end


    @chat = ChatPurpose.bind(chat: @chat, run: @chat_run, user_message: @user_msg, options: @options)
    add_new_message_callback
  end

  def add_new_message_callback
    @chat.before_message do
      if stopped?
        Rails.logger.info "[ChatStreamJob] Skipping new message tracking (run cancelled)"
        next
      end

      latest = @chat.messages.where(role: :assistant, content: "").order(id: :desc).first

      if latest
        Rails.logger.info "[ChatStreamJob] 🆕 New message placeholder: #{latest.id}"
        # Set @llm_msg to the latest empty assistant message.
        # This may be a real assistant response OR a tool placeholder —
        # we can't tell yet because tool calls aren't persisted until after_message.
        # For tool placeholders, no streaming chunks arrive so this is harmless.
        @llm_msg = latest
        @accumulated = '' if defined?(@accumulated)
        @llm_msg.broadcast_upsert_to_chat!
      end
    end

    @chat.before_tool_call do |tool_call|
      Rails.logger.info "[ChatStreamJob] 🔧 Executing: #{tool_call.name}"
    end

    @chat.after_tool_result do |result|
      Rails.logger.info "[ChatStreamJob] ✅ Tool completed"
    end

    @chat.after_message do |message|
      next unless message

      # persist_message_completion already updated the AR record with final
      # role, content, tool_calls, and tokens. Reload to pick up changes.
      #
      # Always use broadcast_upsert_to_chat! (full element replacement) here:
      # - Streaming is DONE for this message — no more chunks arrive.
      # - The listObserver detects the replacement (childList mutation) and
      #   updates React state with final metadata (role, tool_calls, etc.).
      #   Content regression is guarded: upsert content only wins if >= existing length.
      # - Tool messages need full re-render (role changes assistant → tool).
      # - Assistant messages with tool_calls need tool_call UI rendered.
      @llm_msg&.reload
      @llm_msg&.broadcast_upsert_to_chat!
      Rails.logger.info "[ChatStreamJob] End message: #{@llm_msg&.id} (role=#{@llm_msg&.role})"
    end
  end

  def stream_response
    @accumulated = ''
    @chunk_count = 0

    @chat.complete do |chunk|
      # CRITICAL: Check for cancellation on every chunk (throttled polling)

      chunk_text = extract_chunk_text(chunk)
      next if chunk_text.nil? || chunk_text.empty?

      @accumulated += chunk_text
      @chunk_count += 1

      # CRITICAL: Only update if we have the final message
      # During tool execution, @llm_msg will be nil until the final message arrives
      if @llm_msg
        Rails.logger.debug "[ChatStreamJob] 📡 chunk##{@chunk_count} msg=#{@llm_msg.id} accLen=#{@accumulated.length}"
        # Stream a transient view; RubyLLM alone persists/fences final content.
        @llm_msg.content = @accumulated
        @llm_msg.broadcast_streaming_content!
      else
        Rails.logger.debug "[ChatStreamJob] ⏳ chunk##{@chunk_count} @llm_msg=nil accLen=#{@accumulated.length} (tool execution)"
      end
    end

    Rails.logger.info "[ChatStreamJob] 🏁 Streaming complete: #{@chunk_count} chunks, #{@accumulated.length} chars"
  end

  def park_for_tool_approval!
    questions = @chat.pending_questions
    return false if questions.empty?

    requested_at = Time.current.iso8601
    questions.group_by { |question| question.tool_call.id }.each do |call_id, call_questions|
      tool_call = @chat.find_tool_call(call_id)
      tool_call.update!(
        metadata: tool_call.metadata.merge(
          "requires_approval" => call_questions.any?(&:approval?),
          "chat_run_id" => @chat_run.id,
          "requester_member_id" => @sender_member&.id,
          "requester_user_id" => @sender_user&.id,
          "requested_at" => requested_at
        )
      )
      tool_call.message.broadcast_upsert_to_chat! if tool_call.message.respond_to?(:broadcast_upsert_to_chat!)
    end

    @chat_run.transition_to_awaiting_approval!
    true
  end

  def capture_and_publish_usage
    return unless @chat_run

    summary = @chat_run.capture_usage!
    return if summary["attempts"].to_i.zero?

    message = if @llm_msg && Message.exists?(@llm_msg.id)
      @llm_msg.reload
    elsif @chat
      @chat.messages.where(role: :assistant)
        .where("created_at >= ?", @chat_run.created_at)
        .order(:id)
        .last
    end
    return unless message

    message.update_columns(
      metadata: (message.metadata || {}).merge("run_usage" => summary),
      updated_at: Time.current
    )
    message.broadcast_upsert_to_chat!
  rescue => e
    Rails.logger.error "[ChatStreamJob] Usage capture failed: #{e.class} - #{e.message}"
  end
  
  def extract_chunk_text(chunk)
    case chunk
    when RubyLLM::Chunk
      chunk.content || ''
    when String
      chunk
    else
      chunk.respond_to?(:content) ? (chunk.content || '') : chunk.to_s
    end
  end

  ##
  # Persist an error message to the chat, handling the case where RubyLLM's
  # cleanup_failed_messages may have already destroyed @llm_msg from the DB.
  #
  # Without this check, update_columns silently updates 0 rows (destroyed
  # record), no error message persists, and subsequent user messages pile up
  # without assistant responses — causing "Invalid request" on the next API call.
  #
  def persist_error_message(content)
    if @llm_msg && Message.exists?(@llm_msg.id)
      @llm_msg.update_columns(content: content)
      @llm_msg.broadcast_upsert_to_chat!
    elsif @chat
      error_msg = @chat.messages.create!(role: :assistant, content: content)
      error_msg.broadcast_append_to_chat
    end
  end
end

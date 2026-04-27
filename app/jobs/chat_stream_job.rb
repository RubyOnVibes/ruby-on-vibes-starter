# frozen_string_literal: true

class ChatStreamJob < AsyncQueueJob
  self.queue_adapter = :async_job  # Force async-job for this job
  
  # How often to poll DB for cancellation (seconds)
  STOP_CHECK_INTERVAL = ENV.fetch('CHAT_STOP_CHECK_INTERVAL', 0.3).to_f

  # user_msg_id is nil for task continuation runs (no user message triggers them).
  # options may include sender_member_id and sender_user_id for continuation context.
  def perform(chat_id, user_msg_id, chat_run_id, options = {})
    @options = options.is_a?(Hash) ? options.symbolize_keys : {}
    @continuation_mode = user_msg_id.nil?
    @chat_run = ChatRun.find(chat_run_id)
    setup_chat(chat_id, user_msg_id)

    @last_stop_check = Time.current
    return if stopped?

    # Recover from incomplete tool chains left by previous crashed runs.
    # Must run before streaming — broken chains cause API errors.
    @chat.recover_from_tool_errors!

    # Continuation mode: inject a system-generated user message.
    # Anthropic's API requires conversations to end with a user message.
    # Without this, complete() sends history ending with an assistant message → API error.
    if @continuation_mode
      @chat.messages.create!(
        role: :user,
        content: "My background tasks have finished. Please check the results and let me know what happened.",
        user_submitted: false,
        skip_llm_context: false
      )
    end

    @chat_run.update!(status: :running)
    stream_response
    return if stopped?

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
    tasks_during_run = @chat.agent_tasks.where("created_at >= ?", @chat_run.created_at)

    if tasks_during_run.active.exists?
      if continuation_depth >= max_depth
        Rails.logger.warn "[ChatStreamJob] Max continuation depth (#{max_depth}) reached, completing despite active tasks"
        @chat_run.update!(status: :completed)
      else
        @chat_run.transition_to_awaiting_tasks!
      end
    elsif !@continuation_mode && tasks_during_run.exists?
      # Initial run: tasks created and already completed — auto-continue to summarize
      @chat_run.transition_to_awaiting_tasks!
    else
      @chat_run.update!(status: :completed)
    end

    @llm_msg.broadcast_upsert_to_chat!
    @chat_run
  rescue RubyLLM::Error => e
    # RubyLLM errors (including tool call mismatches from cancellation race)
    Rails.logger.error "[ChatStreamJob] RubyLLM error: #{e.class} - #{e.message}"

    # Context overflow recovery: detect via error-message regex, compact, retry once.
    # We use string matching rather than a programmatic context-size check because
    # provider token accounting differs between models and isn't reliably exposed
    # before the request fails. One retry only — if compaction doesn't free enough
    # space, surfacing the error is better than retrying indefinitely.
    if e.message.match?(/context|token|length|too long/i) && !@overflow_retried
      @overflow_retried = true
      if Chat::CompactionService.new(@chat).compact_on_overflow!
        @chat.messages.reset  # Clear AR cache so retry sees compacted=true
        @chat.reload          # Refresh compaction_summary for system prompt
        Rails.logger.info "[ChatStreamJob] Compacted on overflow, retrying"
        retry
      end
    end

    # Try to recover the chat for next time
    begin
      @chat.recover_from_tool_errors!
    rescue => recovery_error
      Rails.logger.error "[ChatStreamJob] Recovery failed: #{recovery_error.message}"
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
  end

  private
  
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

    # Auto-compact if context is getting large (best-effort — never block streaming)
    begin
      Chat::CompactionService.new(@chat).compact_if_needed!
    rescue => e
      Rails.logger.error "[ChatStreamJob] Compaction failed, continuing: #{e.class} - #{e.message}"
    end

    if user_msg_id
      @user_msg = Message.find(user_msg_id)
      # Context about the user who SENT the message we're responding to
      # NOTE: In multi-workspace chats, sender may be from a different workspace than @chat.workspace
      @sender_user = @user_msg.user
      @sender_member = @user_msg.member
      @sender_workspace = @user_msg.member.workspace
    else
      # Continuation mode: no user message triggered this run.
      # Sender context passed from the controller (the user who triggered the continuation).
      @user_msg = nil
      @sender_member = Member.find(@options[:sender_member_id]) if @options[:sender_member_id]
      @sender_user = User.find(@options[:sender_user_id]) if @options[:sender_user_id]
      @sender_workspace = @sender_member&.workspace
    end

    add_tools
    add_instructions
    add_new_message_callback
  end

  def add_new_message_callback
    @chat.on_new_message do
      if stopped?
        Rails.logger.info "[ChatStreamJob] Skipping new message tracking (run cancelled)"
        next
      end

      latest = @chat.messages.where(role: :assistant, content: "").order(id: :desc).first

      if latest
        Rails.logger.info "[ChatStreamJob] 🆕 New message placeholder: #{latest.id}"
        # Set @llm_msg to the latest empty assistant message.
        # This may be a real assistant response OR a tool placeholder —
        # we can't tell yet because tool_calls aren't persisted until on_end_message.
        # For tool placeholders, no streaming chunks arrive so this is harmless.
        @llm_msg = latest
        @accumulated = '' if defined?(@accumulated)
        @llm_msg.broadcast_upsert_to_chat!
      end
    end

    @chat.on_tool_call do |tool_call|
      Rails.logger.info "[ChatStreamJob] 🔧 Executing: #{tool_call.name}"
    end

    @chat.on_tool_result do |result|
      Rails.logger.info "[ChatStreamJob] ✅ Tool completed"
    end

    @chat.on_end_message do |message|
      next unless message

      if stopped?
        @llm_msg&.reload
        if @llm_msg && !@llm_msg.skip_llm_context?
          @llm_msg.update_columns(skip_llm_context: true)
          Rails.logger.info "[ChatStreamJob] Marked post-cancel message #{@llm_msg.id} as skip_llm_context"
        end
        next
      end

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

  ##
  # Setup RubyLLM tools with proper context
  #
  # Context Architecture:
  # - @chat: The chat instance (access @chat.workspace for chat's owning workspace)
  # - @sender_*: The user/member/org who SENT the message we're responding to
  #
  # Why the distinction?
  # - Multi-org chats: Chat owned by Org A, but User from Org B can be invited as member
  # - Tools may need sender's org or member or user for permissions (e.g., can they delete resources?)
  # - Tools may need chat's org for data access (e.g., which org's data to query?)
  #
  # Example: Permission check in a tool:
  #   if @sender_member.admin? && @sender_workspace == @chat.workspace
  #     # Sender is admin in chat's org - allow privileged operation
  #   end
  #
  def add_tools
    @toolset = ToolsetService.new(
      user_message: @user_msg,
      chat: @chat,
      sender_user: @sender_user,
      sender_member: @sender_member,
      sender_workspace: @sender_workspace
    )
    tools = @toolset.tools
    @chat.with_tools(*tools, replace: true)
  end
  
  ##
  # Inject dynamic context into chat instructions
  # Called after setup_chat, before streaming
  #
  # This is where you add context that varies per message:
  # - @mentions (what records the user referenced)
  # - Session state
  # - Etc.
  #
  # NOTE: File attachments are persisted on the user message and included
  # automatically when RubyLLM replays the conversation via to_llm.
  #
  def add_instructions
    validate_mentionable_contexts

    parts = []

    # Core assistant identity — use agent instructions if chat belongs to an agent
    parts << core_instructions

    # Continuation directive: inject specific task results so the LLM
    # summarizes only the tasks from this run (not all historical tasks).
    if @continuation_mode
      parts << build_continuation_directive
    end

    # Tools (if any)
    if @toolset.tools.any?
      parts << "You have tools available: #{@toolset.tools.map(&:name).join(', ')}"
    end

    # User's explicit @mentions - this IS content the user referenced
    if @user_msg&.mentions&.any?
      parts << build_mentions_context
    end

    # Agent task awareness - history summary + recently completed results
    if (agent_tasks_context = build_agent_tasks_context)
      parts << agent_tasks_context
    end

    # Environment metadata (workspace, participants) - NOT user content
    parts << build_environment_context

    # Linking instructions (condensed)
    parts << build_linking_instructions

    instructions = parts.compact.join("\n\n")
    @chat.with_instructions(instructions, replace: true)
  end
  
  ##
  # Core identity instructions.
  # If the chat belongs to an agent, use the agent's resolved instructions.
  # Otherwise, use the default assistant identity.
  #
  def core_instructions
    parts = []

    # Compaction summary (compressed history from older messages)
    if @chat.compaction_summary.present?
      parts << @chat.compaction_summary
    end

    # Agent or default identity
    if (agent = @chat.agent)
      parts << agent.resolved_instructions
    else
      parts << "You are a helpful assistant."
    end

    parts.join("\n\n")
  end

  ##
  # Build structured context for @mentioned records
  # Uses RecordContext schemas for consistent, validated serialization
  #
  def build_mentions_context
    contexts = @user_msg.mentions.includes(:mentionable).map do |mention|
      next nil unless mention.mentionable
      
      # Get structured context (RecordContext instance or hash)
      ctx = mention.mentionable.to_llm_context
      
      # Format based on context type (duck typing - does it quack like a RecordContext?)
      if ctx.respond_to?(:to_json_schema) && ctx.respond_to?(:to_h)
        format_structured_context(mention.label, ctx)
      else
        # Fallback for models without RecordContext
        Rails.logger.warn "[ChatStreamJob] ⚠️  Mentionable model #{mention.mentionable_type} doesn't have a corresponding #{mention.mentionable_type}Context class. Consider creating app/models/contexts/#{mention.mentionable_type.underscore}_context.rb"
        "- @#{mention.label}: #{format_simple_context(ctx)}"
      end
    end.compact
    
    return nil if contexts.empty?
    
    <<~CONTEXT
      ### User Mentioned These Records
      
      The user referenced the following records in their message. Use this context to provide relevant, informed responses:
      
      #{contexts.join("\n\n")}
    CONTEXT
  end

  ##
  # Build agent task context for LLM awareness
  #
  # Two parts:
  # 1. Historical summary: total counts by status (so the agent knows the scope)
  # 2. Recently completed: full result summaries for tasks completed since last response
  #
  # The agent can always use ListAgentTasksTool to drill deeper.
  #
  def build_agent_tasks_context
    return nil unless @chat.agent_tasks.exists?

    parts = []

    # Historical summary
    counts = @chat.agent_tasks.group(:status).count
    status_summary = counts.map { |status, count|
      label = AgentTask.statuses.key(status) || status
      "#{label}: #{count}"
    }.join(", ")
    parts << "This chat has #{@chat.agent_tasks.count} agent task(s) (#{status_summary})."

    # Active tasks
    active = @chat.agent_tasks.active
    if active.exists?
      active_summaries = active.map { |t| "- #{t.to_param} (#{t.kind}): #{t.mentionable_summary}" }
      parts << "Currently running:\n#{active_summaries.join("\n")}"
    end

    # Recently completed (since last assistant message)
    last_response_at = @chat.messages.where(role: :assistant).maximum(:created_at)
    if last_response_at
      recently_completed = @chat.agent_tasks.status_completed
        .where("completed_at > ?", last_response_at)
        .order(:completed_at)

      if recently_completed.exists?
        summaries = recently_completed.map do |task|
          result_preview = task.result.to_json.truncate(500)
          "- **#{task.mentionable_label}** (#{task.kind}): #{task.progress_text || 'Completed'}. Result: #{result_preview}"
        end

        parts << "### Recently Completed Agent Tasks\n\nThese tasks finished since your last response. Incorporate their results naturally:\n\n#{summaries.join("\n")}"
      end
    end

    parts << <<~RULE.strip
      IMPORTANT: After creating an agent task, do NOT call agent_task_status or list_agent_tasks to poll for progress. The system automatically monitors running tasks and will re-invoke you to summarize results once all tasks complete — this happens without any user action. Simply acknowledge that the task has been queued. Do NOT ask the user to notify you, do NOT say "let me know when it's done", and do NOT suggest you will check back later. You will automatically be called again with the results.
    RULE

    <<~CONTEXT
      ### Agent Tasks

      #{parts.join("\n\n")}
    CONTEXT
  end

  ##
  # Build environment context using XML-style tags for clear separation
  #
  # This metadata tells the LLM about the chat environment but is NOT
  # content from the user's message. LLMs handle XML tags well for
  # distinguishing system metadata from conversational content.
  #
  def build_environment_context
    chat_members = @chat.chat_members.includes(member: [:user, :workspace])

    lines = []

    # Chat's workspace (if teams mode) - this is the workspace that OWNS the chat
    if RubyOnVibes.teams? && @chat.workspace
      ws = @chat.workspace
      lines << "chat_workspace: #{ws.name} | id: #{ws.to_param} | path: #{ws.mentionable_path}"
    end

    # Sender info - include THEIR workspace (may differ from chat's workspace)
    if @sender_member
      sender_name = [@sender_user.first_name, @sender_user.last_name].compact.join(' ').presence || @sender_user&.email
      sender_ws = @sender_member.workspace
      lines << "message_sender: #{sender_name} | id: #{@sender_member.to_param} | path: #{@sender_member.mentionable_path} | from_workspace: #{sender_ws.name} (#{sender_ws.to_param})"
    end

    # Participants - include each member's workspace
    if chat_members.size == 1
      member = chat_members.first.member
      member_ws = member.workspace
      lines << "participant: #{member.mentionable_label} | id: #{member.to_param} | path: #{member.mentionable_path} | from_workspace: #{member_ws.name} (#{member_ws.to_param})"
    else
      chat_members.each do |cm|
        member = cm.member
        member_ws = member.workspace
        role = cm.role_owner? ? "owner" : "member"
        lines << "participant: #{member.mentionable_label} | id: #{member.to_param} | path: #{member.mentionable_path} | from_workspace: #{member_ws.name} (#{member_ws.to_param}) | role: #{role}"
      end
    end

    <<~CONTEXT
      <environment>
      #{lines.join("\n")}
      </environment>

      The <environment> block contains context about who you're chatting with.
      - chat_workspace: The workspace that owns this chat
      - message_sender: Who sent the current message (may be from a different workspace)
      - participant: Each member in this chat with their home workspace
      Use this to personalize responses (e.g., "who am I?" → use message_sender's name, path, and workspace).
      These are NOT @mentions—only the "User Mentioned These Records" section contains explicit references.
    CONTEXT
  end
  
  ##
  # Format structured context for LLM consumption
  # Includes schema information for better LLM understanding
  #
  # @param label [String] Display label for the context
  # @param context [Object] Context instance (RecordContext or similar)
  # @return [String] Formatted context block
  #
  def format_structured_context(label, context)
    schema = context.to_json_schema

    <<~TEXT.strip
      **#{label}** (#{schema[:name]}):
      ```json
      #{JSON.pretty_generate(context.to_h)}
      ```
    TEXT
  end
  
  ##
  # Format simple hash context (fallback)
  #
  def format_simple_context(ctx)
    return ctx[:summary] if ctx[:summary].present?
    
    parts = []
    parts << "Type: #{ctx[:type]}" if ctx[:type]
    parts << ctx[:label] if ctx[:label]
    
    parts.join(", ")
  end
  
  def build_linking_instructions
    patterns = build_path_patterns

    <<~INSTRUCTIONS.strip
      LINKING:
      - Internal records: `[Label](/path)` — use the path from context or tool results as-is
      - External sites: `[Label](https://example.com)` — full URL
      - Never prepend a domain to internal paths
      #{patterns.any? ? "\nPath patterns:\n#{patterns.map { |model, pattern| "- #{model}: `#{pattern}`" }.join("\n")}" : ""}
    INSTRUCTIONS
  end

  ##
  # Discover path patterns for all registered mentionable models
  # Uses Rails route helpers via mentionable_path on sample records
  #
  # @return [Array<Array(String, String)>] Array of [ModelName, PathPattern] pairs
  #
  def build_path_patterns
    return [] unless defined?(Mentionables)

    Mentionables.all.filter_map do |model_class|
      # Get a sample record to discover the path pattern
      sample = model_class.first
      next unless sample

      path = sample.mentionable_path
      param = sample.to_param

      # Replace the actual ID with {id} placeholder to show the pattern
      # e.g., "/members/mbr_R2KyJoOvBpa3cnl06qZDwkb4" → "/members/{id}"
      pattern = path.gsub(param, '{id}')

      [model_class.name, pattern]
    rescue => e
      Rails.logger.debug "[ChatStreamJob] Could not determine path pattern for #{model_class.name}: #{e.message}"
      nil
    end
  end
  
  ##
  # Optional: Validate that Mentionable models have corresponding RecordContext classes
  # Logs warnings in development, non-blocking
  #
  def validate_mentionable_contexts
    return unless Rails.env.development?
    return unless defined?(Mentionables)

    mentionable_models = Mentionables.all
    return if mentionable_models.empty?

    mentionable_models.each do |model_class|
      model_name = model_class.name
      context_class = Mentionables.context_class_for(model_class)

      unless context_class
        expected_context = "#{model_name}Context"
        Rails.logger.warn "[ChatStreamJob] ⚠️  Mentionable model #{model_name} doesn't have a corresponding #{expected_context} class. Consider creating app/models/contexts/#{model_name.underscore}_context.rb"
      end
    end
  end

  ##
  # Build continuation directive with inline task results.
  # Scoped to tasks created during this chat run so the LLM only summarizes
  # what just finished — not the entire task history.
  #
  def build_continuation_directive
    tasks = @chat.agent_tasks.where("created_at >= ?", @chat_run.created_at)

    # TODO: Consider injecting an effects summary per task here so the LLM can
    # report what each task actually did (records created/updated/deleted, files
    # attached, notifications sent). Currently effects are available on-demand via
    # AgentTaskStatusTool. Injecting here would make summaries richer but costs
    # tokens — evaluate after real-world usage shows whether users frequently ask
    # "what exactly did it do?" after task completion.
    summaries = tasks.order(:created_at).map do |task|
      line = "- **#{task.mentionable_label}** (#{task.kind}): #{task.status}"
      line += " — #{task.progress_text}" if task.progress_text.present?
      if task.status_completed? && task.result.present?
        line += "\n  Result: #{task.result.to_json.truncate(800)}"
      elsif task.status_failed?
        line += "\n  Error: #{task.error_message}" if task.respond_to?(:error_message) && task.error_message.present?
      end
      line
    end

    <<~DIRECTIVE.strip
      The following agent tasks were created during this conversation turn and have just finished running in the background. Summarize ONLY these results for the user — do not call list_agent_tasks or summarize older tasks.

      #{summaries.join("\n")}

      Provide any relevant links or next steps based on the results above.
    DIRECTIVE
  end

  def stream_response
    @accumulated = ''
    @chunk_count = 0

    @chat.complete do |chunk|
      # CRITICAL: Check for cancellation on every chunk (throttled polling)
      break if stopped?

      chunk_text = extract_chunk_text(chunk)
      next if chunk_text.nil? || chunk_text.empty?

      @accumulated += chunk_text
      @chunk_count += 1

      # CRITICAL: Only update if we have the final message
      # During tool execution, @llm_msg will be nil until the final message arrives
      if @llm_msg
        Rails.logger.debug "[ChatStreamJob] 📡 chunk##{@chunk_count} msg=#{@llm_msg.id} accLen=#{@accumulated.length}"
        @llm_msg.update_columns(content: @accumulated)
        @llm_msg.broadcast_streaming_content!
      else
        Rails.logger.debug "[ChatStreamJob] ⏳ chunk##{@chunk_count} @llm_msg=nil accLen=#{@accumulated.length} (tool execution)"
      end
    end

    Rails.logger.info "[ChatStreamJob] 🏁 Streaming complete: #{@chunk_count} chunks, #{@accumulated.length} chars"
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
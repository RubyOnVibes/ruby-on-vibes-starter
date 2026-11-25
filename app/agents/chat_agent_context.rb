# frozen_string_literal: true

# Runtime context for the built-in ChatAgent. Tools always act as the member
# who initiated the run, including after a worker restart or human approval.
class ChatAgentContext
  attr_reader :chat, :run, :user_message, :member

  def initialize(chat:, run:, user_message: nil, options: {})
    @chat = chat
    @run = @chat_run = run
    @user_message = @user_msg = user_message
    @member = @sender_member = run.initiated_by_member
    @sender_user = @sender_member&.user
    @sender_workspace = @sender_member&.workspace
    @task_continuation = options.to_h.symbolize_keys[:task_continuation]
  end

  def tools
    @tools ||= ToolsetService.new(
      user_message: user_message,
      chat: chat,
      sender_user: @sender_user,
      sender_member: member,
      sender_workspace: @sender_workspace
    ).tools
  end

  def stable_instructions
    parts = [assistant_identity]
    parts << "You have tools available: #{tools.map(&:name).join(', ')}" if tools.any?
    parts.join("\n\n")
  end

  def dynamic_instructions
    validate_mentionable_contexts
    parts = []
    parts << chat.compaction_summary if chat.compaction_summary.present?
    parts << build_continuation_directive if @task_continuation
    parts << build_mentions_context if user_message&.mentions&.any?
    parts << build_agent_tasks_context
    parts << build_environment_context
    parts << build_linking_instructions
    parts.compact.join("\n\n")
  end

  private

  def assistant_identity
    if (agent = @chat.agent)
      agent.resolved_instructions
    else
      "You are a helpful assistant."
    end
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
        Rails.logger.warn "[ChatAgentContext] ⚠️  Mentionable model #{mention.mentionable_type} doesn't have a corresponding #{mention.mentionable_type}Context class. Consider creating app/models/contexts/#{mention.mentionable_type.underscore}_context.rb"
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
    # Route examples come only from the authorized conversation, never a
    # sample record belonging to an unrelated workspace.
    records = [@chat, @sender_member, @sender_workspace]
    records.concat(@user_msg.mentions.includes(:mentionable).filter_map(&:mentionable)) if @user_msg
    records.compact.uniq(&:class).filter_map do |record|
      next unless record.respond_to?(:mentionable_path)

      [record.class.name, record.mentionable_path.gsub(record.to_param, "{id}")]
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
        Rails.logger.warn "[ChatAgentContext] ⚠️  Mentionable model #{model_name} doesn't have a corresponding #{expected_context} class. Consider creating app/models/contexts/#{model_name.underscore}_context.rb"
      end
    end
  end

  ##
  # Build continuation directive with inline task results.
  # Scoped to tasks created during this chat run so the LLM only summarizes
  # what just finished — not the entire task history.
  #
  def build_continuation_directive
    tasks = @chat_run.business_tasks

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

end

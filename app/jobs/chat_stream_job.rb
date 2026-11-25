# frozen_string_literal: true

# Rails delivers the persisted intent; RubyLLM owns execution and claims.
class ChatStreamJob < ApplicationJob
  queue_as :agents
  discard_on ActiveRecord::RecordNotFound

  def perform(run_id)
    @chat_run = ChatRun.find(run_id)
    RubyLLM.with_owner(@chat_run) { perform_run }
  end

  private

  def perform_run
    return unless @chat_run.active?
    return if @chat_run.status_awaiting_approval? || @chat_run.chat.running?
    if @chat_run.status_awaiting_tasks?
      tasks = @chat_run.chat.pending_tasks
      return if tasks.any?(&:input_required?)
    end

    setup_chat(@chat_run.chat_id, @chat_run.input_message_id)
    @chat_run.with_lock do
      return unless @chat_run.active?
      @chat_run.update!(status: :running)
    end
    stream_response

    # Duplicate delivery may return without acquiring the native claim. Leave
    # the owner alone; persisted intent and the recovery sweep handle a crash.
    @chat_run.with_lock do
      return unless @chat_run.active?
      @chat.reload
      return if @chat.running?
      return if park_for_tool_approval!

      tasks = @chat.pending_tasks
      if tasks.any?
        @chat_run.transition_to_awaiting_tasks!
        # complete resumes every pending task, so a human wait parks the
        # whole conversation. Domain jobs may continue independently.
        if tasks.any?(&:input_required?)
          @chat_run.update!(resume_at: nil)
        else
          interval = tasks.map { |task| task.poll_interval.to_f.positive? ? task.poll_interval.to_f : 5 }.min.clamp(1, 300)
          @chat_run.dispatch!(wait: interval)
        end
      # Finalization reads the persisted transcript independently of runtime
      # instructions, which RubyLLM can reapply after a halted tool on reload.
      elsif Chat.find(@chat.id).complete?
        @chat_run.update!(status: :completed, resume_at: nil)
      end
      # A duplicate may have returned busy before another worker parked and a
      # person answered. No questions/tasks then remain, but the approved call
      # still needs execution. Keep its recovery intent until native completion.
    end
    @llm_msg&.broadcast_upsert_to_chat!
  rescue RubyLLM::CancelledError
    @chat_run.with_lock { @chat_run.update!(status: :cancelled, resume_at: nil) if @chat_run.active? }
  rescue RubyLLM::ToolRoundLimitError
    fail_run!("I reached this response's tool limit. Send another message to continue.")
  rescue RubyLLM::ContextLengthExceededError => error
    if !@overflow_retried && @chat_run.reload.active? && @chat
      @overflow_retried = true
      if Chat::CompactionService.new(@chat).compact_on_overflow!
        @chat.messages.reset
        @chat.reload
        retry
      end
    end
    log_failure(error)
    fail_run!("This conversation is too large to process. Please start a new chat.")
  rescue RubyLLM::Error => error
    log_failure(error)
    fail_run!("The model request failed. Please try again.")
  rescue => error
    log_failure(error)
    fail_run!("This request could not be completed. Please try again.")
    raise
  ensure
    capture_and_publish_usage
  end

  def log_failure(error)
    Rails.logger.error "[ChatStreamJob] Run #{@chat_run&.id}: #{error.class}: #{error.message}"
  end

  def fail_run!(message)
    return unless @chat_run
    @chat_run.with_lock do
      return unless @chat_run.active?
      # A duplicate delivery can fail during setup after another worker took
      # the native claim. Its failure must not end that worker's execution.
      return if @chat&.running?

      begin
        settle_native_cancellation
      rescue => error
        # Keep the original error and the active recovery intent. A new user
        # message must not hide calls whose cancellation has not settled yet.
        Rails.logger.error "[ChatStreamJob] Run #{@chat_run.id} cancellation settlement failed: #{error.class}"
        return
      end
      @chat_run.update!(status: :failed, resume_at: nil)
      persist_error_message(message)
    end
  end

  # run_tools takes RubyLLM's claim and observes cancellation before any tool
  # can execute. It closes unanswered calls without making a model request,
  # including when authorization failed before an agent could be bound.
  def settle_native_cancellation
    return unless @chat

    @chat.cancel
    @chat.run_tools
  rescue RubyLLM::CancelledError
    # Expected: the native cancellation checkpoint persisted terminal results.
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


    @chat = ChatPurpose.bind(chat: @chat, run: @chat_run, user_message: @user_msg)
    add_new_message_callback
  end

  def add_new_message_callback
    @chat.before_message do
      unless @chat_run.reload.active?
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
        @accumulated = "" if defined?(@accumulated)
        @llm_msg.broadcast_upsert_to_chat!
      end
    end

    @chat.before_tool_call do |tool_call|
      raise RubyLLM::CancelledError, "Run cancelled" unless @chat_run.reload.active?
      @chat_run.execution_member!
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
    @accumulated = ""
    @chunk_count = 0

    @chat.complete do |chunk|
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
      chunk.content || ""
    when String
      chunk
    else
      chunk.respond_to?(:content) ? (chunk.content || "") : chunk.to_s
    end
  end

  # Keep completed tool results and streamed evidence intact when reporting a
  # failed run. Errors are a separate assistant message, never a replacement.
  def persist_error_message(content)
    return unless @chat

    error_msg = @chat.messages.create!(role: :assistant, content: content, skip_llm_context: true)
    error_msg.broadcast_append_to_chat
  end
end

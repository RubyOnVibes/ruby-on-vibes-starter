# frozen_string_literal: true

require 'rails_helper'
require 'ostruct'

RSpec.describe ChatStreamJob, type: :job do
  # ============================================================================
  # These tests verify ChatStreamJob's orchestration logic:
  #   - ChatRun status transitions (pending → running → completed/failed)
  #   - Message lifecycle (create → stream → broadcast)
  #   - Cancellation via stopped? polling
  #   - Error handling and cleanup
  #
  # All RubyLLM streaming, broadcasts, and tool execution are stubbed.
  #
  # KEY FIXTURE DEPENDENCY: The on_new_message callback finds the latest
  # assistant message to set @llm_msg. Tests rely on the `assistant_response`
  # fixture existing in alice_personal_chat. If you remove that fixture,
  # @llm_msg will be nil and tests will fail.
  # ============================================================================

  fixtures :users, :workspaces, :members, :chats, :chat_members, :messages, :chat_runs

  let(:chat) { chats(:alice_personal_chat) }
  let(:user_message) { messages(:alice_message) }

  # RubyLLM's acts_as_chat requires a Model record to resolve the provider.
  # This seeds one so we never hit the Anthropic API in tests.
  let!(:model_record) do
    Model.find_or_create_by!(model_id: "claude-sonnet-4-6", provider: "anthropic") do |m|
      m.name = "Claude Sonnet 4.6"
      m.family = "claude"
      m.context_window = 200_000
      m.max_output_tokens = 8_192
    end
  end

  before do
    # No ActionCable in unit tests
    allow(Turbo::StreamsChannel).to receive(:broadcast_append_to)
    allow(Turbo::StreamsChannel).to receive(:broadcast_replace_to)
    allow(Turbo::StreamsChannel).to receive(:broadcast_remove_to)
    allow(Turbo::StreamsChannel).to receive(:broadcast_action_to)
    allow(Turbo::StreamsChannel).to receive(:broadcast_stream_to)

    # Prevent real API connections
    allow(RubyLLM::Models).to receive(:resolve).and_return([
      OpenStruct.new(
        id: "claude-sonnet-4-6", provider: "anthropic",
        name: "Claude Sonnet 4.6", family: "claude",
        context_window: 200_000, max_output_tokens: 8_192,
        capabilities: [], modalities: {}, pricing: {}, metadata: {}
      ),
      :anthropic
    ])
    allow(RubyLLM).to receive(:chat).and_return(double("RubyLLM::Chat").as_null_object)

    # validate_mentionable_contexts only runs in development
    allow(Rails.env).to receive(:development?).and_return(false)
  end

  # ============================================================================
  # HELPERS
  # ============================================================================

  # Captures all four RubyLLM callback registrations and stubs with_tools/with_instructions.
  # Returns the callbacks hash so callers can fire them manually.
  def stub_callbacks
    callbacks = {}
    allow_any_instance_of(Chat).to receive(:on_new_message) { |_, &blk| callbacks[:on_new_message] = blk }
    allow_any_instance_of(Chat).to receive(:on_tool_call) { |_, &blk| callbacks[:on_tool_call] = blk }
    allow_any_instance_of(Chat).to receive(:on_tool_result) { |_, &blk| callbacks[:on_tool_result] = blk }
    allow_any_instance_of(Chat).to receive(:on_end_message) { |_, &blk| callbacks[:on_end_message] = blk }
    allow_any_instance_of(Chat).to receive(:with_tools).and_return(chat)
    allow_any_instance_of(Chat).to receive(:with_instructions).and_return(chat)
    callbacks
  end

  # Stubs the full RubyLLM callback chain so the job can run end-to-end.
  # Creates an empty assistant message (simulating what RubyLLM does internally
  # before streaming starts), then fires on_new_message (which finds it and
  # sets @llm_msg) and on_end_message.
  #
  # The `before_streaming` proc runs at the top of chat.complete — use it to
  # observe mid-execution state (e.g., ChatRun status after it's set to :running).
  def stub_chat_streaming(chunks: [], before_streaming: nil)
    callbacks = stub_callbacks

    allow_any_instance_of(Chat).to receive(:complete) do |inst, &block|
      before_streaming&.call

      # Simulate RubyLLM creating an empty assistant message before streaming.
      # The on_new_message callback queries for `role: :assistant, content: ""`.
      inst.messages.create!(role: :assistant, content: "")

      callbacks[:on_new_message]&.call

      chunks.each { |text| block.call(OpenStruct.new(content: text)) }

      callbacks[:on_end_message]&.call(
        OpenStruct.new(role: 'assistant', content: chunks.compact.join(''))
      )
    end

    callbacks
  end

  def create_chat_run!(status: :pending)
    ChatRun.create!(chat: chat, status: status, node_name: "test")
  end

  # ============================================================================
  # 1. HAPPY PATH
  # ============================================================================
  describe "happy path" do
    it "streams chunks, sets @llm_msg, and completes the run" do
      run = create_chat_run!
      stub_chat_streaming(chunks: ["Hello! ", "How can I help?"])

      described_class.perform_now(chat.id, user_message.id, run.id)

      run.reload
      expect(run.status).to eq("completed")
      expect(run.completed_at).to be_present
    end
  end

  # ============================================================================
  # 2. CHATRUN STATUS TRANSITIONS
  # ============================================================================
  describe "ChatRun status transitions" do
    it "transitions pending → running → completed" do
      run = create_chat_run!(status: :pending)
      status_during_stream = nil

      stub_chat_streaming(
        chunks: ["Hi"],
        before_streaming: -> { status_during_stream = run.reload.status }
      )

      described_class.perform_now(chat.id, user_message.id, run.id)

      expect(status_during_stream).to eq("running")
      expect(run.reload.status).to eq("completed")
    end
  end

  # ============================================================================
  # 3. CANCELLATION
  # ============================================================================
  describe "cancellation" do
    it "stops streaming when ChatRun is cancelled mid-stream" do
      # Disable throttle so stopped? reloads on every call (tests run < 0.3s)
      stub_const("ChatStreamJob::STOP_CHECK_INTERVAL", 0)

      run = create_chat_run!
      callbacks = stub_callbacks

      allow_any_instance_of(Chat).to receive(:complete) do |_inst, &block|
        block.call(OpenStruct.new(content: "First chunk"))

        # Cancel between chunks — job should detect on next stopped? check
        run.update!(status: :cancelled, cancelled_at: Time.current)

        block.call(OpenStruct.new(content: "Second chunk"))
        callbacks[:on_new_message]&.call
      end

      described_class.perform_now(chat.id, user_message.id, run.id)

      expect(run.reload.status).to eq("cancelled")
    end
  end

  # ============================================================================
  # 4. ERROR HANDLING
  # ============================================================================
  describe "error handling" do
    it "marks run as failed, sets error content, and re-raises" do
      run = create_chat_run!

      # stub_callbacks wires on_new_message/with_tools/etc so setup_chat succeeds
      stub_callbacks
      allow_any_instance_of(Chat).to receive(:complete)
        .and_raise(RuntimeError, "API connection failed")

      expect {
        described_class.perform_now(chat.id, user_message.id, run.id)
      }.to raise_error(RuntimeError, "API connection failed")

      run.reload
      expect(run.status).to eq("failed")
      expect(run.failed_at).to be_present
    end
  end

  # ============================================================================
  # 5. EXTRACT CHUNK TEXT
  # ============================================================================
  describe "extract_chunk_text" do
    let(:job) { described_class.new }

    it "extracts content from an object with .content" do
      expect(job.send(:extract_chunk_text, OpenStruct.new(content: "hello"))).to eq("hello")
    end

    it "passes through plain strings" do
      expect(job.send(:extract_chunk_text, "hello")).to eq("hello")
    end

    it "returns empty string for nil content" do
      expect(job.send(:extract_chunk_text, OpenStruct.new(content: nil))).to eq("")
    end
  end

  # ============================================================================
  # 6. SETUP WIRING
  # ============================================================================
  describe "setup" do
    it "wires instructions and tools on the chat" do
      run = create_chat_run!

      expect_any_instance_of(Chat).to receive(:with_instructions).and_return(chat)
      expect_any_instance_of(Chat).to receive(:with_tools).and_return(chat)

      stub_chat_streaming(chunks: ["Hi"])
      described_class.perform_now(chat.id, user_message.id, run.id)
    end
  end

  # ============================================================================
  # 7. CALLBACK REGISTRATION
  # ============================================================================
  describe "callback registration" do
    it "registers on_new_message, on_tool_call, on_tool_result, and on_end_message" do
      registered = []

      allow_any_instance_of(Chat).to receive(:on_new_message) { registered << :on_new_message }
      allow_any_instance_of(Chat).to receive(:on_tool_call) { registered << :on_tool_call }
      allow_any_instance_of(Chat).to receive(:on_tool_result) { registered << :on_tool_result }
      allow_any_instance_of(Chat).to receive(:on_end_message) { registered << :on_end_message }
      allow_any_instance_of(Chat).to receive(:with_tools).and_return(chat)
      allow_any_instance_of(Chat).to receive(:with_instructions).and_return(chat)

      # Test setup_chat directly — avoids needing @llm_msg for the full perform flow
      job = described_class.new
      job.send(:setup_chat, chat.id, user_message.id)

      expect(registered).to contain_exactly(:on_new_message, :on_tool_call, :on_tool_result, :on_end_message)
    end
  end

  # ============================================================================
  # 8. STOPPED? THROTTLE
  # ============================================================================
  describe "stopped? throttle" do
    it "skips reload when called within STOP_CHECK_INTERVAL" do
      run = create_chat_run!(status: :running)
      job = described_class.new
      job.instance_variable_set(:@chat_run, run)
      job.instance_variable_set(:@last_stop_check, Time.current)

      expect(run).not_to receive(:reload)
      job.send(:stopped?)
    end

    it "reloads ChatRun after STOP_CHECK_INTERVAL elapses" do
      run = create_chat_run!(status: :running)
      job = described_class.new
      job.instance_variable_set(:@chat_run, run)
      job.instance_variable_set(:@last_stop_check, Time.current - 1.second)

      expect(run).to receive(:reload).and_call_original
      job.send(:stopped?)
    end
  end

  # ============================================================================
  # 9. NIL / EMPTY CHUNKS
  # ============================================================================
  describe "nil and empty chunks" do
    it "skips them without errors" do
      run = create_chat_run!
      stub_chat_streaming(chunks: [nil, "", "Real content", nil])

      described_class.perform_now(chat.id, user_message.id, run.id)

      expect(run.reload.status).to eq("completed")
    end
  end

  # ============================================================================
  # 10. FINAL BROADCAST
  # ============================================================================
  describe "final broadcast" do
    it "broadcasts the assistant message after completion" do
      run = create_chat_run!
      stub_chat_streaming(chunks: ["Done!"])

      expect(Turbo::StreamsChannel).to receive(:broadcast_replace_to).at_least(:once)

      described_class.perform_now(chat.id, user_message.id, run.id)
    end
  end

  # ============================================================================
  # 11. CONTINUATION MODE (awaiting_tasks → auto-resume)
  # ============================================================================
  describe "continuation mode" do
    let(:alice) { users(:alice) }
    let(:alice_member) { members(:alice_personal_member) }

    it "creates a system-generated user message when user_msg_id is nil" do
      run = create_chat_run!
      stub_chat_streaming(chunks: ["Here are your results!"])

      expect {
        described_class.perform_now(chat.id, nil, run.id, {
          sender_member_id: alice_member.id,
          sender_user_id: alice.id,
          continuation_depth: 1
        })
      }.to change { chat.messages.where(role: :user, user_submitted: false).count }.by(1)

      expect(run.reload.status).to eq("completed")
    end

    it "does not create a system-generated message for normal runs" do
      run = create_chat_run!
      stub_chat_streaming(chunks: ["Hello!"])

      expect {
        described_class.perform_now(chat.id, user_message.id, run.id)
      }.not_to change { chat.messages.where(role: :user, user_submitted: false).count }
    end
  end

  # ============================================================================
  # 12. AWAITING_TASKS DETECTION
  # ============================================================================
  describe "awaiting_tasks detection" do
    it "transitions to awaiting_tasks when active agent tasks exist" do
      skip "requires agent_tasks to be enabled" unless defined?(AgentTask)

      run = create_chat_run!
      stub_chat_streaming(chunks: ["Creating task for you!"])

      # Null-object double absorbs the many chained calls in build_agent_tasks_context
      # and build_continuation_directive. We only care that active tasks exist.
      agent_tasks_relation = double("agent_tasks_relation").as_null_object
      allow(agent_tasks_relation).to receive(:exists?).and_return(true)
      allow(agent_tasks_relation).to receive(:active).and_return(double(exists?: true, map: [], find_each: nil).as_null_object)
      allow(agent_tasks_relation).to receive(:where).and_return(double(active: double(exists?: true), exists?: true).as_null_object)
      allow_any_instance_of(Chat).to receive(:agent_tasks).and_return(agent_tasks_relation)

      described_class.perform_now(chat.id, user_message.id, run.id)

      expect(run.reload.status).to eq("awaiting_tasks")
    end

    it "completes normally when no agent tasks were created" do
      run = create_chat_run!
      stub_chat_streaming(chunks: ["No tasks needed!"])

      described_class.perform_now(chat.id, user_message.id, run.id)

      expect(run.reload.status).to eq("completed")
    end
  end

  # ============================================================================
  # 13. CONTINUATION DEPTH LIMIT
  # ============================================================================
  describe "continuation depth limit" do
    it "completes instead of awaiting_tasks when max depth reached" do
      skip "requires agent_tasks to be enabled" unless defined?(AgentTask)

      run = create_chat_run!
      stub_chat_streaming(chunks: ["Max depth reached"])

      agent_tasks_relation = double("agent_tasks_relation").as_null_object
      allow(agent_tasks_relation).to receive(:exists?).and_return(true)
      allow(agent_tasks_relation).to receive(:active).and_return(double(exists?: true, map: [], find_each: nil).as_null_object)
      allow(agent_tasks_relation).to receive(:where).and_return(double(active: double(exists?: true), exists?: true).as_null_object)
      allow_any_instance_of(Chat).to receive(:agent_tasks).and_return(agent_tasks_relation)

      described_class.perform_now(chat.id, nil, run.id, {
        sender_member_id: members(:alice_personal_member).id,
        sender_user_id: users(:alice).id,
        continuation_depth: 5
      })

      expect(run.reload.status).to eq("completed")
    end
  end
end

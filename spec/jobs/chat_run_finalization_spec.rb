# frozen_string_literal: true

require "rails_helper"
require 'ruby_llm/test_helper'

RSpec.describe 'Native delivery finalization race', type: :job do
  include RubyLLM::TestHelper

  let(:chat) { chats(:alice_personal_chat) }
  let(:member) { members(:alice_personal_member) }

  before do
    chat.chat_runs.active.delete_all
    chat.messages.destroy_all
    chat.with_model('gpt-5-nano', provider: :openai)
    allow(Turbo::StreamsChannel).to receive(:broadcast_action_to)
    allow(Turbo::StreamsChannel).to receive(:broadcast_replace_to)
    allow(Turbo::StreamsChannel).to receive(:broadcast_append_to)
    allow(Turbo::StreamsChannel).to receive(:broadcast_stream_to)
    allow(ChatStreamJob).to receive(:perform_later)
  end

  [ :length, :content_filter, nil ].each do |reason|
    it "completes an empty native response with #{reason || 'recorded usage'} without retrying" do
      stub_replies ""
      allow_any_instance_of(RubyLLM::Providers::OpenAI).to receive(:complete).and_wrap_original do |original, *args, **kwargs, &block|
        reply = original.call(*args, **kwargs, &block)
        RubyLLM::Message.new(role: reply.role, content: reply.content, model: reply.model,
          tokens: reply.tokens, finish_reason: reason)
      end
      input = chat.messages.create!(role: :user, content: 'Answer', member: member, user: member.user)
      run = chat.chat_runs.create!(input_message: input, initiated_by_member: member)

      ChatStreamJob.perform_now(run.id)

      expect(run.reload).to be_status_completed
      expect(Chat.find(chat.id)).to be_complete
      expect(chat.messages.where(role: :assistant).sole.finish_reason).to eq(reason)
      ResumeChatRunsJob.perform_now
      ChatStreamJob.perform_now(run.id)
      expect(ChatStreamJob).not_to have_received(:perform_later)
      expect(run.owned_llm_usages.count).to eq(1)
    end
  end

  it 'completes a native tool halt without requesting another model response' do
    tool = Class.new(RubyLLM::Tool) do
      description 'Return a final answer directly'
      define_method(:initialize) { |**| }
      def execute = halt('Final tool answer')
    end
    stub_const('FinalizationHaltTool', tool)
    allow_any_instance_of(ToolsetService).to receive(:tool_classes).and_return([ FinalizationHaltTool ])
    stub_replies tool_call(FinalizationHaltTool.tool_name), 'Must not be requested'
    input = chat.messages.create!(role: :user, content: 'Answer directly', member: member, user: member.user)
    run = chat.chat_runs.create!(input_message: input, initiated_by_member: member)

    ChatStreamJob.perform_now(run.id)

    expect(run.reload).to be_status_completed
    expect(Chat.find(chat.id)).to be_complete
    expect(chat.messages.where(role: :tool).sole.to_llm).to be_halted
    expect(run.owned_llm_usages.count).to eq(1)
  end

  it 'keeps approved but unexecuted work active after a duplicate returned busy' do
    executed = []
    tool = Class.new(RubyLLM::Tool) do
      description 'Perform an operation after approval'
      requires_approval
      define_method(:initialize) { |**| }
      define_method(:execute) { executed << :once; 'Done' }
    end
    stub_const('FinalizationApprovalTool', tool)
    allow_any_instance_of(ToolsetService).to receive(:tool_classes).and_return([ FinalizationApprovalTool ])
    stub_replies tool_call(FinalizationApprovalTool.tool_name), 'Operation complete'
    input = chat.messages.create!(role: :user, content: 'Do operation', member: member, user: member.user)
    run = chat.chat_runs.create!(input_message: input, initiated_by_member: member)
    # Pause the duplicate before claiming, then after its real native busy
    # return. The original job and a human decision fit between those points.
    duplicate = Fiber.new { ChatStreamJob.perform_now(run.id) }
    allow_any_instance_of(Chat).to receive(:complete).and_wrap_original do |original, *args, **kwargs, &block|
      if Fiber.current == duplicate
        Fiber.yield :before_claim
        result = original.call(*args, **kwargs, &block)
        Fiber.yield :busy_returned
        result
      else
        original.call(*args, **kwargs, &block)
      end
    end
    first = true
    allow_any_instance_of(RubyLLM::Providers::OpenAI).to receive(:complete).and_wrap_original do |original, *args, **kwargs, &block|
      if first
        first = false
        expect(duplicate.resume).to eq(:busy_returned)
      end
      original.call(*args, **kwargs, &block)
    end
    expect(duplicate.resume).to eq(:before_claim)
    ChatStreamJob.perform_now(run.id)
    expect(run.reload).to be_status_awaiting_approval
    question = run.pending_questions.sole
    run.answer_question!(question.id, member: member, decision: :approved)
    expect(run.reload).to be_status_running
    duplicate.resume
    expect(run.reload).to be_status_running
    expect(executed).to be_empty
    # The decision's queue delivery can be lost; persisted intent must remain
    # recoverable after the duplicate has finished its own job.
    ResumeChatRunsJob.perform_now
    expect(ChatStreamJob).to have_received(:perform_later).with(run.id)
    ChatStreamJob.perform_now(run.id)
    expect(run.reload).to be_status_completed
    expect(executed).to eq([ :once ])
    expect(chat.messages.where(role: :user).count).to eq(1)
    expect(run.owned_llm_usages.count).to eq(2)
  end
end

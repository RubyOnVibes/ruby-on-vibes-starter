# frozen_string_literal: true

require "rails_helper"
require "ruby_llm/test_helper"

RSpec.describe ChatPurpose do
  include RubyLLM::TestHelper

  let(:chat) { chats(:alice_personal_chat) }
  let(:member) { members(:alice_personal_member) }
  let(:message) { messages(:alice_message) }
  let(:run) { chat.chat_runs.create!(initiated_by_member: member, status: :pending) }

  before do
    chat.chat_runs.active.delete_all
    allow(Turbo::StreamsChannel).to receive(:broadcast_append_to)
    allow(Turbo::StreamsChannel).to receive(:broadcast_replace_to)
    allow(Turbo::StreamsChannel).to receive(:broadcast_action_to)
    allow(Turbo::StreamsChannel).to receive(:broadcast_stream_to)
    allow_any_instance_of(ToolsetService).to receive(:tool_classes).and_return([CurrentDateTimeTool])
  end

  def bind(**options)
    described_class.bind(chat: chat, run: run, user_message: message, **options)
  end

  it "binds the existing record without writing runtime instructions to history" do
    expect { expect(bind).to equal(chat) }.not_to change { chat.messages.count }
    expect(chat.to_llm.agent_class).to eq(ChatAgent)
    expect(chat.tools).to have_key(CurrentDateTimeTool.tool_name.to_sym)
    expect(chat.file_store).to be_a(RubyLLM::ActiveRecord::FileStore)
  end

  it "preserves explicit mentions, participants, compaction and record links" do
    message.mentions.create!(mentionable: member)
    allow(chat).to receive(:compaction_summary).and_return("Earlier discussion: two pending invoices.")

    instructions = bind.to_llm.messages.select { |item| item.role == :system }.map(&:content).join("\n")

    expect(instructions).to include("User Mentioned These Records", member.user.name,
      "message_sender:", member.workspace.name, member.mentionable_path,
      "Earlier discussion: two pending invoices.", "LINKING:")
  end

  it "uses the original actor on resume even when options name another member" do
    configured = described_class.bind(chat: chat, run: run, options: {
      sender_member_id: members(:bob_team_member).id,
      sender_user_id: users(:bob).id
    })

    expect(configured.tools.fetch(CurrentDateTimeTool.tool_name.to_sym).sender_member).to eq(member)
  end

  it "fails closed when the original actor is missing" do
    run.update!(initiated_by_member: nil)

    expect { bind }.to raise_error(ChatPurpose::InvalidContext)
  end

  it "fails closed if the initiating member was removed from the chat" do
    chat.chat_members.where(member: member).delete_all

    expect { bind }.to raise_error(ChatPurpose::InvalidContext)
  end

  it "rejects a message or run from another chat" do
    expect {
      described_class.bind(chat: chat, run: run, user_message: messages(:bob_message))
    }.to raise_error(ChatPurpose::InvalidContext)

    expect {
      described_class.bind(chat: chats(:team_chat), run: run)
    }.to raise_error(ChatPurpose::InvalidContext)
  end

  it "rejects arbitrary class names instead of resolving request input" do
    chat.purpose = "ApplicationAgent"

    expect { bind }.to raise_error(ChatPurpose::UnknownPurpose)
  end

  it "keeps purpose-specific native instructions and tools through a real completion" do
    tool_class = Class.new(RubyLLM::Tool) do
      description "Return the reviewed document status"
      def execute = "reviewed"
    end
    stub_const("PurposeReviewTool", tool_class)
    agent_class = Class.new(ApplicationAgent) do
      instructions "You review documents."
      tools PurposeReviewTool
    end
    stub_const("PurposeReviewAgent", agent_class)
    allow(described_class).to receive(:registry).and_return("review" => PurposeReviewAgent)
    chat.purpose = "review"
    chat.messages.destroy_all
    input = chat.messages.create!(role: :user, content: "Review it", member: member, user: member.user)
    stub_replies tool_call(:purpose_review), "Reviewed."

    configured = described_class.bind(chat: chat, run: run, user_message: input)
    configured.complete

    expect(configured.to_llm.agent_class).to eq(PurposeReviewAgent)
    expect(configured.to_llm.messages.find { |item| item.role == :system }.content).to eq("You review documents.")
    expect(chat.messages.where(role: :tool).sole.content).to eq("reviewed")
    expect(chat.messages.where(role: :assistant).last.content).to eq("Reviewed.")
  end

  it "keeps usage owned by the run and files shared across runs" do
    chat.messages.where(role: :assistant).destroy_all
    stub_replies "Ready.", cost: 0.01

    RubyLLM.with_owner(run) { bind.complete }

    expect(run.owned_llm_usages.sole.owner).to eq(run)
    expect(chat.to_llm.owner).to be_nil
    expect(chat.file_store.owner).to be_nil
  end

  it "keeps the stable cache prefix separate from per-turn context" do
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with("LLM_PROMPT_CACHING").and_return("true")
    system_messages = bind.to_llm.messages.select { |item| item.role == :system }

    expect(system_messages.first).to be_cache_until_here
    expect(system_messages.first.content).not_to include("<environment>")
    expect(system_messages.last.content).to include("<environment>")
    expect(chat.caching).to eq({})
  end
end

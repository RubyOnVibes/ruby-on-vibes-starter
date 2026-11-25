# frozen_string_literal: true

require 'rails_helper'
require 'ruby_llm/test_helper'

RSpec.describe Chat::CompactionService do
  include ActiveSupport::Testing::TimeHelpers
  include RubyLLM::TestHelper

  let(:workspace) { workspaces(:alice_personal) }
  let(:member) { members(:alice_personal_member) }
  let(:chat) { member.owned_chats.create!(name: "Compaction Test") }

  def seed_turns(count, chat:)
    count.times do |i|
      chat.messages.create!(role: :user, content: "Question #{i + 1}: " + ("x" * 200), user_submitted: false)
      chat.messages.create!(role: :assistant, content: "Answer #{i + 1}: " + ("y" * 500))
    end
  end

  describe '#should_compact?' do
    it 'returns false when fewer than MIN_MESSAGES_TO_COMPACT messages' do
      seed_turns(3, chat: chat)
      expect(described_class.new(chat).should_compact?).to be false
    end

    it 'returns false when under token threshold' do
      seed_turns(6, chat: chat)
      # Default threshold is 100K tokens; 12 messages with ~175 tokens each is ~2K
      expect(described_class.new(chat).should_compact?).to be false
    end

    it 'returns true when over custom token threshold' do
      seed_turns(8, chat: chat)
      chat.update_columns(compaction_token_threshold: 100) # Very low threshold
      expect(described_class.new(chat).should_compact?).to be true
    end

    it 'returns false during cooldown period' do
      seed_turns(8, chat: chat)
      chat.update_columns(compaction_token_threshold: 100, last_compacted_at: 5.minutes.ago)
      expect(described_class.new(chat).should_compact?).to be false
    end
  end

  describe '#force_compact!' do
    before do
      seed_turns(10, chat: chat)
      # Stub the LLM call
      fake_response = double(content: "Summary of the conversation.")
      fake_chat = double(ask: fake_response)
      allow(RubyLLM).to receive(:chat).and_return(fake_chat)
    end

    it 'marks older messages as compacted' do
      described_class.new(chat).force_compact!
      expect(chat.messages.where(compacted: true).count).to be > 0
    end

    it 'preserves recent messages uncompacted' do
      described_class.new(chat).force_compact!
      kept = chat.messages.where(compacted: false)
      # Should keep at least 5 turns (10 messages)
      expect(kept.count).to be >= 10
    end

    it 'stores compaction summary on the chat' do
      described_class.new(chat).force_compact!
      chat.reload
      expect(chat.compaction_summary).to be_present
      expect(chat.compaction_summary).to include("Context Summary")
    end

    it 'sets last_compacted_at' do
      described_class.new(chat).force_compact!
      chat.reload
      expect(chat.last_compacted_at).to be_within(5.seconds).of(Time.current)
    end

    it 'does not compact when too few messages to split' do
      # With only 10 turns and KEEP_RECENT_TURNS=5, the split point
      # may be too low (< 2) depending on message structure
      small_chat = member.owned_chats.create!(name: "Small Chat")
      seed_turns(5, chat: small_chat)
      described_class.new(small_chat).force_compact!
      small_chat.reload
      expect(small_chat.compaction_summary).to be_nil
    end

    it 'keeps provider checkpoints intact instead of replacing them with a text summary' do
      checkpoint = chat.messages.create!(role: :assistant, content: "", raw_content: {
        object: "response.compaction",
        output: [ { type: "compaction", encrypted_content: "provider-checkpoint" } ]
      })
      expect(RubyLLM).not_to receive(:chat)

      expect(described_class.new(chat).force_compact!).to be false
      expect(chat.reload.compaction_summary).to be_nil
      expect(chat.messages.where(compacted: true)).to be_empty
      expect(checkpoint.reload.raw_content["output"].first["encrypted_content"]).to eq("provider-checkpoint")
    end

    it 'preserves system instructions outside the summarized conversation' do
      instruction = chat.messages.create!(role: :system, content: "Never disclose another workspace's records.",
        created_at: 1.day.ago)
      model = double
      expect(model).to receive(:ask).with(satisfy { |prompt| !prompt.include?(instruction.content) })
        .and_return(double(content: "Conversation summary"))
      allow(RubyLLM).to receive(:chat).and_return(model)

      expect(described_class.new(chat).force_compact!).to be true
      expect(instruction.reload).not_to be_compacted
      expect(chat.send(:eager_load_messages).map(&:id)).to include(instruction.id)
    end
  end

  describe 'tool-chain boundaries' do
    it 'keeps a whole first tool chain when recent-token retention would split it' do
      tool = Class.new(RubyLLM::Tool) do
        description "Reads a large source document"

        def execute
          "source data " * 9_000
        end
      end
      stub_const("LargeCompactionSourceTool", tool)
      stub_replies tool_call(LargeCompactionSourceTool.tool_name), "Document read."
      chat.with_tools(LargeCompactionSourceTool).ask("Read the source document")
      call = chat.messages.find_by!(role: :assistant).ruby_llm_tool_calls.sole
      expect(call.result).to be_present
      seed_turns(5, chat: chat)
      expect(RubyLLM).not_to receive(:chat)

      expect(described_class.new(chat).force_compact!).to be false
      expect(chat.messages.where(compacted: true)).to be_empty
      replay = chat.send(:eager_load_messages).map(&:id)
      expect(replay).to include(call.message_id, call.result_id)
    end
  end

  describe '#force_compact! with stacked compaction' do
    before do
      fake_response = double(content: "Updated summary merging old and new.")
      fake_chat = double(ask: fake_response)
      allow(RubyLLM).to receive(:chat).and_return(fake_chat)
    end

    it 'feeds previous summary into next compaction' do
      seed_turns(10, chat: chat)
      described_class.new(chat).force_compact!

      # Add more messages and compact again
      chat.update_columns(last_compacted_at: nil)
      seed_turns(10, chat: chat)

      expect(RubyLLM).to receive(:chat).and_return(
        double(ask: double(content: "Merged summary."))
      )
      described_class.new(chat).force_compact!

      chat.reload
      expect(chat.compaction_summary).to include("Merged summary")
    end
  end

  describe 'order_messages_for_llm excludes compacted messages' do
    before do
      seed_turns(10, chat: chat)
      fake_response = double(content: "Summary.")
      allow(RubyLLM).to receive(:chat).and_return(double(ask: fake_response))
      described_class.new(chat).force_compact!
    end

    it 'filters out compacted messages' do
      all_messages = chat.messages.order(:created_at)
      llm_messages = chat.order_messages_for_llm(all_messages)

      compacted_ids = chat.messages.where(compacted: true).pluck(:id)
      llm_ids = llm_messages.map(&:id)

      expect(llm_ids & compacted_ids).to be_empty
    end
  end

  describe 'compaction lock' do
    before do
      seed_turns(10, chat: chat)
      chat.update_columns(compaction_token_threshold: 100)
      fake_response = double(content: "Summary.")
      allow(RubyLLM).to receive(:chat).and_return(double(ask: fake_response))
    end

    it 'skips compaction when another process holds the lock' do
      chat.update_columns(compacting_since: 1.minute.ago)
      expect(described_class.new(chat).compact_if_needed!).to be false
      expect(chat.reload.compaction_summary).to be_nil
    end

    it 'acquires a stale lock from a crashed process' do
      chat.update_columns(compacting_since: 10.minutes.ago)
      described_class.new(chat).force_compact!
      expect(chat.reload.compaction_summary).to be_present
    end

    it 'releases the lock after compaction' do
      described_class.new(chat).force_compact!
      expect(chat.reload.compacting_since).to be_nil
    end

    it 'releases the lock even when compaction errors' do
      allow(RubyLLM).to receive(:chat).and_raise(StandardError, "API down")
      expect { described_class.new(chat).force_compact! }.to raise_error(StandardError)
      expect(chat.reload.compacting_since).to be_nil
    end

    it 'does not publish or release another worker\'s lease after takeover' do
      allow(RubyLLM).to receive(:chat).and_return(double.tap do |model|
        allow(model).to receive(:ask) do
          Fiber.yield :summarizing
          double(content: "Current owner's summary.")
        end
      end)
      old_worker = Fiber.new { described_class.new(Chat.find(chat.id)).force_compact! }
      new_worker = Fiber.new { described_class.new(Chat.find(chat.id)).force_compact! }

      expect(old_worker.resume).to eq(:summarizing)
      travel 6.minutes do
        expect(new_worker.resume).to eq(:summarizing)
        new_token = chat.reload.compaction_token

        expect(old_worker.resume).to be false
        expect(chat.reload.compaction_token).to eq(new_token)
        expect(chat.compaction_summary).to be_nil
        expect(chat.messages.where(compacted: true)).to be_empty

        expect(new_worker.resume).to be true
        expect(chat.reload.compaction_summary).to include("Current owner's summary")
        expect(chat.compaction_token).to be_nil
      end
    end

    it 'does not replace a newer summary when an expired worker finishes last' do
      allow(RubyLLM).to receive(:chat).and_return(double.tap do |model|
        allow(model).to receive(:ask) do
          summary = Fiber.yield :summarizing
          double(content: summary)
        end
      end)
      old_worker = Fiber.new { described_class.new(Chat.find(chat.id)).force_compact! }
      new_worker = Fiber.new { described_class.new(Chat.find(chat.id)).force_compact! }
      old_worker.resume

      travel 6.minutes do
        new_worker.resume
        expect(new_worker.resume("New summary")).to be true
        summary = chat.reload.compaction_summary
        compacted_ids = chat.messages.where(compacted: true).pluck(:id)

        expect(old_worker.resume("Stale summary")).to be false
        expect(chat.reload.compaction_summary).to eq(summary)
        expect(chat.messages.where(compacted: true).pluck(:id)).to eq(compacted_ids)
      end
    end

    it 'refuses to publish after the lease expires even without a takeover' do
      model = double
      allow(model).to receive(:ask) do
        travel 6.minutes
        double(content: "Expired summary")
      end
      allow(RubyLLM).to receive(:chat).and_return(model)

      expect(described_class.new(chat).force_compact!).to be false
      expect(chat.reload.compaction_summary).to be_nil
      expect(chat.compaction_token).to be_nil
      expect(chat.messages.where(compacted: true)).to be_empty
    ensure
      travel_back
    end

    it 'does not start summarizing while a native worker owns the chat' do
      chat.update_columns(claim_token: SecureRandom.uuid, claimed_until: 1.minute.from_now)
      expect(RubyLLM).not_to receive(:chat)

      expect(described_class.new(chat).force_compact!).to be false
      expect(chat.reload.compaction_token).to be_nil
    end

    it 'leaves the transcript intact when a native worker starts during summarization' do
      model = double
      allow(model).to receive(:ask) do
        chat.update_columns(claim_token: SecureRandom.uuid, claimed_until: 1.minute.from_now)
        double(content: "Concurrent summary")
      end
      allow(RubyLLM).to receive(:chat).and_return(model)

      expect(described_class.new(Chat.find(chat.id)).force_compact!).to be false
      expect(chat.reload.compaction_summary).to be_nil
      expect(chat.messages.where(compacted: true)).to be_empty
      expect(chat).to be_running
    end

    it 'refreshes the previous summary before summarizing a stale chat instance' do
      stale_chat = Chat.find(chat.id)
      chat.update_columns(compaction_summary: "A summary committed by a previous worker")
      model = double
      expect(model).to receive(:ask).with(include("A summary committed by a previous worker"))
        .and_return(double(content: "Merged summary"))
      allow(RubyLLM).to receive(:chat).and_return(model)

      expect(described_class.new(stale_chat).force_compact!).to be true
    end

    it 'rechecks cooldown after acquiring the lease with a stale chat instance' do
      stale_chat = Chat.find(chat.id)
      chat.update_columns(last_compacted_at: Time.current, compaction_summary: "Recently summarized")
      expect(RubyLLM).not_to receive(:chat)

      expect(described_class.new(stale_chat).compact_if_needed!).to be false
      expect(chat.reload.compaction_summary).to eq("Recently summarized")
      expect(chat.messages.where(compacted: true)).to be_empty
    end
  end

  describe 'agent-guided compaction' do
    let(:agent_chat) { member.owned_chats.create!(name: "Agent Chat") }
    let(:agent) do
      Agent.create!(
        workspace: workspace,
        member: member,
        chat: agent_chat,
        name: "Test Agent",
        identifier: "test_agent",
        instructions: "You are a reporting agent. Focus on metrics and trends."
      )
    end

    it 'includes agent instructions in summary prompt' do
      agent # Force creation (let is lazy)
      seed_turns(10, chat: agent_chat)

      # Capture the prompt sent to the summarizer
      captured_prompt = nil
      fake_chat_obj = double
      allow(fake_chat_obj).to receive(:ask) do |prompt|
        captured_prompt = prompt
        double(content: "Agent-guided summary.")
      end
      allow(RubyLLM).to receive(:chat).and_return(fake_chat_obj)

      described_class.new(agent_chat).force_compact!

      expect(captured_prompt).to include("persistent agent")
      expect(captured_prompt).to include("reporting agent")
    end
  end
end

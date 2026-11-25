# frozen_string_literal: true

require 'rails_helper'
require 'faraday/adapter/test'

RSpec.describe 'Native chat replay', type: :model do
  let(:chat) { chats(:alice_personal_chat) }

  before do
    chat.chat_runs.active.delete_all
    chat.messages.destroy_all
    allow(Turbo::StreamsChannel).to receive(:broadcast_action_to)
    allow(Turbo::StreamsChannel).to receive(:broadcast_append_to)
    allow(Turbo::StreamsChannel).to receive(:broadcast_replace_to)
  end

  it 'replays a native compaction checkpoint after reload and preserves the audit transcript' do
    stubs = Faraday::Adapter::Test::Stubs.new
    adapter = Class.new(Faraday::Adapter::Test) do
      define_method(:initialize) { |app, **options| super(app, stubs, **options) }
    end
    allow(RubyLLM.config).to receive(:faraday_adapter).and_return(adapter)
    chat.with_model('gpt-5-nano', provider: :openai, protocol: :responses)
    original = chat.messages.create!(role: :user, content: 'Remember the original requirements')
    checkpoint = { type: 'compaction', encrypted_content: 'opaque-provider-checkpoint' }
    stubs.post('/v1/responses/compact') do
      [ 200, { 'Content-Type' => 'application/json' }, {
        object: 'response.compaction', output: [ checkpoint ], usage: { input_tokens: 10, output_tokens: 5 }
      }.to_json ]
    end

    chat.compact
    saved_checkpoint = chat.messages.order(:id).last
    expect(saved_checkpoint.content).to eq('')

    stubs.post('/v1/responses') do |request|
      input = JSON.parse(request.body).fetch('input')
      expect(input.first).to eq(checkpoint.stringify_keys)
      expect(input.to_json).to include('Continue from the checkpoint')
      expect(input.to_json).not_to include('Remember the original requirements')
      [ 200, { 'Content-Type' => 'application/json' }, {
        id: 'resp_replayed', object: 'response', model: 'gpt-5-nano', status: 'completed',
        output: [ { type: 'message', role: 'assistant', content: [ { type: 'output_text', text: 'Continuing.' } ] } ],
        usage: { input_tokens: 6, output_tokens: 2 }
      }.to_json ]
    end

    reloaded = Chat.find(chat.id).with_model('gpt-5-nano', provider: :openai, protocol: :responses)
    reloaded.ask('Continue from the checkpoint')

    stubs.verify_stubbed_calls
    expect(chat.messages.exists?(original.id)).to be true
    expect(chat.messages.exists?(saved_checkpoint.id)).to be true
  end

  it 'keeps reasoning and provider replay state even when visible text is empty' do
    reasoning = chat.messages.create!(role: :assistant, content: '', thinking_signature: 'signed-reasoning')
    raw = chat.messages.create!(role: :assistant, content: '', raw_reasoning: [ { type: 'reasoning', encrypted_content: 'opaque' } ])
    continuation = chat.messages.create!(role: :assistant, content: '', continuation: 'provider-continuation')
    attachment = chat.messages.create!(role: :assistant, content: '')
    attachment.attachments.attach(io: StringIO.new('generated artifact'), filename: 'result.txt', content_type: 'text/plain')

    messages = Chat.find(chat.id).to_llm.messages
    expect(messages.any? { |message| message.thinking&.signature == reasoning.thinking_signature }).to be true
    expect(messages.any? { |message| message.raw_reasoning == raw.raw_reasoning }).to be true
    expect(messages.any? { |message| message.continuation == continuation.continuation }).to be true
    expect(messages.any? { |message| message.attachments.any? }).to be true
  end

  it 'still honors explicit application context exclusions for native payloads' do
    chat.messages.create!(role: :assistant, content: '', raw_content: { object: 'response.compaction', output: [] }, skip_llm_context: true)
    expect(Chat.find(chat.id).to_llm.messages).to be_empty
  end
end

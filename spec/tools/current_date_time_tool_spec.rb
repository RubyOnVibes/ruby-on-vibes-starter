# frozen_string_literal: true

require "rails_helper"

RSpec.describe CurrentDateTimeTool do
  let(:user) { instance_double(User) }
  subject(:tool) { described_class.new(chat: chats(:alice_personal_chat), sender_user: user) }

  it "returns a stable validation result for an unknown time zone" do
    expect(tool.execute(timezone: "Invalid/Zone")).to eq(error: "Invalid timezone: Invalid/Zone")
  end

  it "lets unexpected infrastructure errors reach the application error handler" do
    allow(user).to receive(:time_zone).and_raise(RuntimeError, "private user-store credentials")

    expect { tool.execute }.to raise_error(RuntimeError, "private user-store credentials")
  end
end

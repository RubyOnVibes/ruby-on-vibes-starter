# frozen_string_literal: true

class RandomNumberTool < RubyLLM::Tool
  description <<~DESC
    Generates a truly random number using OS-level entropy.

    WHEN TO USE THIS:
    - When the user asks for a random number, dice roll, coin flip, or random selection
    - When randomness needs to be genuine (not LLM-approximated)
    - For games, decision-making, shuffling, or sampling

    Examples: "roll a d20", "pick a number between 1 and 100", "flip a coin"
  DESC

  params do
    integer :min, description: "Minimum value (inclusive, default: 1)", required: false
    integer :max, description: "Maximum value (inclusive, default: 100)", required: false
    integer :count, description: "How many random numbers to generate (default: 1, max: 20)", required: false
  end

  attr_reader :chat, :sender_user, :sender_member, :sender_workspace

  def initialize(chat:, sender_user: nil, sender_member: nil, sender_workspace: nil)
    @chat = chat
    @sender_user = sender_user
    @sender_member = sender_member
    @sender_workspace = sender_workspace
  end

  def execute(min: nil, max: nil, count: nil)
    min = (min || 1).to_i
    max = (max || 100).to_i
    count = [[((count || 1).to_i), 1].max, 20].min

    return { error: "min (#{min}) must be less than or equal to max (#{max})" } if min > max

    results = count.times.map { SecureRandom.random_number(min..max) }

    {
      results: results,
      min: min,
      max: max,
      count: count
    }
  end
end

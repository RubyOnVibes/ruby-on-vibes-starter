# frozen_string_literal: true

##
# Represents a subscription plan with pricing, billing interval, and features.
#
# Plans are displayed to users during checkout and determine the subscription
# terms for a workspace. Supports monthly and yearly billing intervals with
# optional trial periods.
#
# @example Creating a plan
#   Plan.create!(
#     name: "Pro",
#     amount: 1999,      # in cents
#     currency: "usd",
#     interval: "month",
#     trial_period_days: 14,
#     features: ["Unlimited projects", "Priority support"]
#   )
#
# @example Retrieving sorted visible plans
#   Plan.visible.sorted  # Monthly plans first, then yearly, ordered by price
#
class Plan < ApplicationRecord
  # Store plan metadata including features list and tax settings
  store_accessor :metadata, :stripe_tax, :features

  has_prefix_id :plan

  normalizes :currency, with: ->(currency) { currency.strip.downcase }

  attribute :currency, default: "usd"

  validates :interval, inclusion: { in: %w[month year], message: "must be 'month' or 'year'" }
  validates :currency, format: { with: /\A[a-zA-Z]{3}\z/, message: "must be a 3-letter ISO currency code" }
  validates :unit_label, presence: true, if: :charge_per_unit?
  validates :interval, :name, :amount, :currency, presence: true
  validates :trial_period_days, numericality: { only_integer: true, greater_than_or_equal_to: 0 }

  # Sort order: monthly plans first, then yearly, each sorted by amount ascending
  INTERVAL_ORDER = { "month" => 0, "year" => 1 }.freeze

  ##
  # Returns plans sorted by interval (monthly first) then by amount ascending.
  # Uses Ruby sorting to support complex ordering not easily done in SQL.
  scope :sorted, -> {
    all.sort_by { |plan| [INTERVAL_ORDER.fetch(plan.interval, 99), plan.amount] }
  }

  scope :monthly, -> { where(interval: "month") }
  scope :yearly, -> { where(interval: "year") }
  scope :visible, -> { where(hidden: false) }
  scope :hidden, -> { where(hidden: true) }

  ##
  # Returns the default free plan, creating it if it doesn't exist.
  # Used for the fake payment processor during development/testing.
  #
  # @return [Plan] the free plan instance
  def self.secret_free_plan
    find_or_initialize_by(name: "Free Plan").tap do |plan|
      next unless plan.new_record?

      plan.update!(
        hidden: true,
        currency: "usd",
        amount: 0,
        interval: "month",
        trial_period_days: 0,
        fake_processor_id: "free"
      )
    end
  end

  ##
  # Whether this plan includes a trial period.
  #
  # @return [Boolean]
  def trial_period?
    trial_period_days.to_i > 0
  end

  ##
  # Returns the features list, always as an array.
  #
  # @return [Array<String>] list of feature descriptions
  def features
    Array.wrap(super)
  end

  ##
  # Whether this is a yearly/annual billing plan.
  #
  # @return [Boolean]
  def yearly?
    interval == "year"
  end
  alias_method :annual?, :yearly?

  ##
  # Whether this is a monthly billing plan.
  #
  # @return [Boolean]
  def monthly?
    interval == "month"
  end

  # Cast stripe_tax to boolean when setting
  def stripe_tax=(value)
    super(ActiveModel::Type::Boolean.new.cast(value))
  end

  ##
  # Whether this plan should collect tax via Stripe.
  #
  # @return [Boolean]
  def taxed?
    ActiveModel::Type::Boolean.new.cast(stripe_tax)
  end

  ##
  # Human-readable display name with interval.
  #
  # @return [String] e.g., "Pro (Monthly)" or "Pro (Yearly)"
  def display_name
    suffix = monthly? ? "Monthly" : "Yearly"
    "#{name} (#{suffix})"
  end
end  
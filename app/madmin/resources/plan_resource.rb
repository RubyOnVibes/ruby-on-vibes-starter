class PlanResource < Madmin::Resource
  menu parent: "Payments", position: 1

  scope :visible
  scope :hidden

  # Attributes
  attribute :id, form: false
  attribute :name, description: "Plan name"
  attribute :stripe_id, label: "Stripe ID"
  attribute :fake_processor_id, label: "Fake Processor ID"
  attribute :description, description: "Brief plan description"
  attribute :hidden, index: true, description: "Hidden plans are only accessible with direct links or via existing subscriptions."
  attribute :amount, description: "Plan Amount (priced in cents)", index: true
  attribute :currency, description: "Plan currency (must be a 3-letter ISO currency code)"
  attribute :interval, :select, collection: ["month", "year"], index: true
  attribute :interval_count, description: "How many intervals to wait before billing a subscription again. e.g.) with interval as 'month' & interval_count to 3, it bills the customer every three months"
  attribute :stripe_tax, :boolean do |config|
    config.description = "Collect tax via Stripe?"
  end
  attribute :contact_url
  attribute :trial_period_days, description: "Trial period days (0 for no trial)"
  attribute :charge_per_unit, description: "Per-user (or other unit) based pricing"
  attribute :unit_label, description: "Label for per-user (or other unit) based pricing (e.g. 'user' or 'project' per day/month/year)"

  attribute :created_at, form: false
  attribute :updated_at, form: false

  attribute :features, field: ArrayField

  def self.display_name(record)
    "Plan ##{ record.id }: #{ record.name }"
  end

  def self.default_sort_column
    "updated_at"
  end
  
  def self.default_sort_direction
    "desc"
  end
end

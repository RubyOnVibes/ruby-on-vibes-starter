class ModelResource < Madmin::Resource
  menu parent: "LLMs", position: 0

  # Attributes
  attribute :id, form: false
  attribute :name, description: "LLM Name"
  attribute :provider, label: "LLM Provider"
  attribute :pricing, field: ModelPricingField, index: true

  attribute :created_at, form: false
  attribute :updated_at, form: false

  def self.display_name(record)
    "LLM ##{ record.id }: #{ record.name }"
  end

  def self.default_sort_column
    "updated_at"
  end
  
  def self.default_sort_direction
    "desc"
  end
end

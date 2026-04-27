class Refer::ReferralResource < Madmin::Resource
  menu parent: "Users", position: 2

  # Attributes
  attribute :id, form: false
  attribute :created_at, form: false
  attribute :updated_at, form: false
  attribute :completed_at

  # Associations
  attribute :referrer
  attribute :referee
  attribute :referral_code

  # Add scopes to easily filter records
  # scope :published

  # Add actions to the resource's show page
  # member_action do |record|
  #   link_to "Do Something", some_path
  # end

  # Customize the display name of records in the admin area.
  # def self.display_name(record) = record.name

  # Customize the default sort column and direction.
  # def self.default_sort_column = "created_at"
  #
  # def self.default_sort_direction = "desc"
end

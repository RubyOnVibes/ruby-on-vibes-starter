class UserResource < Madmin::Resource
  menu parent: "Users", position: 1

  # Attributes
  attribute :id, form: false
  attribute :email, index: true
  attribute :encrypted_password
  attribute :reset_password_token
  attribute :reset_password_sent_at
  attribute :remember_created_at
  attribute :sign_in_count, form: false
  attribute :current_sign_in_at
  attribute :last_sign_in_at
  attribute :current_sign_in_ip
  attribute :last_sign_in_ip
  attribute :failed_attempts
  attribute :unlock_token
  attribute :locked_at
  attribute :preferences
  attribute :first_name, index: true
  attribute :last_name, index: true
  attribute :time_zone
  attribute :admin, index: true
  attribute :gravatar_url
  attribute :avatar, index: false
  attribute :created_at, form: false
  attribute :updated_at, form: false

  # Associations
  attribute :referral_codes
  attribute :referrals
  attribute :referral
  attribute :members
  attribute :workspaces

  # Add actions to the resource's show page
  member_action do |user|
    button_to "Login As", madmin_user_sessions_path(user), class: "btn btn-secondary"
  end

  # Customize the display name of records in the admin area.
  # def self.display_name(record) = record.name

  # Customize the default sort column and direction.
  # def self.default_sort_column = "created_at"
  #
  # def self.default_sort_direction = "desc"
end

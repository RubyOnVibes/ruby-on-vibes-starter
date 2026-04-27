class User < ApplicationRecord
  # Include default devise modules.
    # Add :confirmable to enable email confs upon signup or email change.
    # Add omniauth_providers to enable omniauth for the given providers.
    # Add :omniauthable to enable omniauth
  devise :database_authenticatable, :registerable,
        :recoverable, :rememberable, :validatable,
        :trackable, :lockable
  
  has_prefix_id :user

  has_referrals

  has_one_attached :avatar

  before_validation :generate_username, on: :create, if: -> { username.blank? }
  validates :username, presence: true, 
            uniqueness: { case_sensitive: false },
            format: { with: /\A[a-z0-9_]+\z/, message: "only lowercase letters, numbers, and underscores" },
            length: { in: 3..30 }
    
  before_validation :parse_full_name, if: :full_name?
  before_validation :set_gravatar_url, if: :email_changed?
  
  attr_accessor :full_name
  
  validate :full_name_present, on: :create
  validates :first_name, presence: true, unless: :new_record?

  scope :admins, -> { where(admin: true) }

  has_many :members, dependent: :destroy
  has_many :workspaces, through: :members
  has_many :owned_workspaces, class_name: "Workspace", inverse_of: :owner, foreign_key: :owner_id, dependent: :destroy
  
  # Chats belong to members (not directly to users)
  # Access via personal_workspace.members.first.chats or through_members
  has_many :chats, through: :members
  
  # Noticed gem - notifications belong to users
  has_many :notifications, as: :recipient, dependent: :destroy, class_name: "Noticed::Notification"
  has_many :notification_mentions, as: :record, dependent: :destroy, class_name: "Noticed::Event"
  has_many :notification_tokens, dependent: :destroy

  # Each user gets a personal workspace by default - team workspaces are optional.
  has_one :personal_workspace, -> { where(is_team_workspace: false) }, class_name: "Workspace", inverse_of: :owner, foreign_key: :owner_id, dependent: :destroy
  after_create :create_personal_workspace

  accepts_nested_attributes_for :owned_workspaces, reject_if: :all_blank

  def name  
    "#{first_name} #{last_name}".strip.presence || "User #{id}"
  end

  def avatar_url
    # For views, use avatar_url helper which handles ActiveStorage properly
    # This method is used for JSON serialization and always returns gravatar
    gravatar_url.presence || "https://www.gravatar.com/avatar/#{Digest::MD5.hexdigest(email&.downcase || '')}?d=identicon"
  end

  def create_personal_workspace
    return personal_workspace if personal_workspace.present?

    User.transaction do
      # All personal workspaces named "Personal Workspace" (simpler than user's name)
      workspace = owned_workspaces.create!(name: "Personal Workspace", is_team_workspace: false)
      members.find_or_initialize_by(workspace: workspace, user: self).tap { |m| m.update!(admin: true) unless m.persisted? }
    end

    personal_workspace
  end

  def full_name?
    full_name.present?
  end

  def primary_referral_code
    referral_codes.first_or_create
  end

  private

  def generate_username
    self.username = UsernameGeneratorService.generate
  rescue StandardError
    self.username = "user_#{SecureRandom.hex(6)}"
  end

  def parse_full_name
    return if full_name.blank?
    
    parts = full_name.strip.split(' ', 2)
    self.first_name = parts[0] || ''
    self.last_name = parts[1] || ''
  end

  def set_gravatar_url
    self.gravatar_url = "https://www.gravatar.com/avatar/#{Digest::MD5.hexdigest(email&.downcase)}?d=identicon"
  end

  def full_name_present
    return if first_name.present?

    if full_name.blank?
      errors.add(:full_name, "is required")
    end
  end
end

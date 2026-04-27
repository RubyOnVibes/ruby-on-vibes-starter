# frozen_string_literal: true

##
# A Workspace is the primary organizational unit for multi-tenancy.
#
# Workspaces can be personal (single user) or team-based (multiple members).
# Each workspace has its own billing, members, and resources.
#
# @example Creating a team workspace
#   workspace = Workspace.create!(
#     name: "Acme Corp",
#     owner: current_user,
#     is_team_workspace: true
#   )
#
class Workspace < ApplicationRecord
  has_prefix_id :ws

  include Mentionable

  # Pay gem integration for subscription billing
  pay_customer

  has_one_attached :avatar

  belongs_to :owner, class_name: "User"

  has_many :invitations, dependent: :destroy
  has_many :workspace_notifications, as: :record, dependent: :destroy, class_name: "Noticed::Event"
  has_many :members, dependent: :destroy
  has_many :users, through: :members
  has_many :chats, through: :members
  has_many :agent_tasks, dependent: :destroy  # Denormalized for direct workspace-level queries
  has_many :agents, dependent: :destroy  # Persistent agents belonging to this workspace

  before_create :ensure_owner_admin_built

  scope :personal, -> { where(personal: true) }
  scope :team, -> { where(personal: false) }

  validates_variable_content_type :avatar
  validates :name, presence: true, uniqueness: { scope: :owner_id, message: "already exists for this owner" }

  # ============================================================================
  # Pay Gem / Billing Integration
  # ============================================================================

  # Determines when to sync workspace data to the payment processor.
  # Called by Pay gem after_commit hooks.
  def self.pay_should_sync_customer?
    saved_change_to_name? || saved_change_to_owner_id? || saved_change_to_billing_email?
  end

  ##
  # Primary contact email for billing and receipts.
  # Prefers explicit billing_email, falls back to workspace owner.
  #
  # @return [String] email address
  def email
    billing_contact
  end

  ##
  # Returns the billing contact email address.
  # Uses billing_email if configured, otherwise the owner's email.
  #
  # @return [String] email address for billing communications
  def billing_contact
    billing_email.presence || owner&.email
  end

  ##
  # Quantity for per-seat/per-unit subscription billing.
  # Override this method if using a different billing model (e.g., per-project).
  #
  # @return [Integer] number of billable units
  def per_unit_quantity
    members.count
  end

  ##
  # Display name for billing invoices and receipts.
  #
  # @return [String] workspace name
  def billable_name
    name
  end

  # ============================================================================
  # Workspace Type Helpers
  # ============================================================================

  def personal?
    !team?
  end

  def team?
    is_team_workspace?
  end
  
  ##
  # Mentionable label - just the name (already descriptive)
  #
  def mentionable_label
    name
  end
  
  ##
  # Brief summary for LLM context
  #
  def mentionable_summary
    parts = []
    
    # Name and type
    type_label = personal? ? "Personal" : "Team"
    parts << "#{type_label} workspace '#{name}'"
    
    # Member count
    parts << "#{members_count} #{members_count == 1 ? 'member' : 'members'}"
    
    # Owner
    owner_name = [owner.first_name, owner.last_name].join(' ').presence || owner.email
    parts << "owned by #{owner_name}"
    
    parts.join(', ')
  end
  
  ##
  # Custom path - link to workspace settings/dashboard
  #
  def mentionable_path
    Rails.application.routes.url_helpers.workspace_path(self)
  end

  private

  def ensure_owner_admin_built
    members.new(user: owner, admin: true) unless members.any? { |m| m.user == owner }
  end
end

# frozen_string_literal: true

##
# AgentTaskEffect - Tracks what an agent task did
#
# Each effect records a single action taken by a background task:
# creating a record, updating one, attaching a file, etc.
#
# The target is always the business record being acted upon (Customer,
# Order, etc.) — never a blob or attachment object. File metadata
# goes in the details JSON.
#
# Usage from an AgentTaskJob subclass (via track_* helpers):
#   customer = track_create(Customer, name: "Acme Corp")
#   track_update(customer, status: "active")
#   track_attach(customer, :documents, io: file, filename: "invoice.pdf")
#   track_destroy(old_record)
#
class AgentTaskEffect < ApplicationRecord
  belongs_to :agent_task
  belongs_to :target, polymorphic: true, optional: true

  ACTIONS = %w[
    created
    updated
    deleted
    attached
    detached
    enqueued
    notified
    custom
  ].freeze

  validates :action, inclusion: { in: ACTIONS }
  validates :description, presence: true

  scope :for_record, ->(record) { where(target: record) }
  scope :mutations, -> { where(action: %w[created updated deleted]) }
  scope :attachments, -> { where(action: %w[attached detached]) }
  scope :by_recency, -> { order(created_at: :asc) }
end

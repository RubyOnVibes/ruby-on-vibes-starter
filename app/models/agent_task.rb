# frozen_string_literal: true

##
# AgentTask - Tracks autonomous background work triggered through chat
#
# When a tool needs to do work that takes longer than a chat response
# (reports, batch operations, analysis), it creates an AgentTask and
# enqueues a job. The task tracks progress and results. The frontend
# polls for updates. The chat agent learns about completed tasks on
# the next conversational turn.
#
# Status flow:
#   pending → running → (completed | failed | cancelled | awaiting_approval)
#
# Usage from a tool:
#   task = AgentTask.create!(
#     chat: @chat,
#     workspace: @sender_workspace,
#     member: @sender_member,
#     kind: "customer_analysis"
#   )
#   CustomerAnalysisJob.perform_later(task.id)
#
class AgentTask < ApplicationRecord
  has_prefix_id :agent_task
  include Mentionable

  belongs_to :chat
  belongs_to :workspace
  belongs_to :member
  belongs_to :parent_task, class_name: "AgentTask", optional: true
  has_many :subtasks, class_name: "AgentTask", foreign_key: :parent_task_id, dependent: :nullify
  has_many :effects, class_name: "AgentTaskEffect", dependent: :destroy

  has_many_attached :attachments

  validates :kind, presence: true,
    format: { with: /\A[a-z][a-z0-9_]*\z/, message: "must be lowercase alphanumeric with underscores (used in partial paths)" }

  enum :status, {
    pending: 0,
    running: 1,
    completed: 2,
    cancelled: 3,
    failed: 4,
    awaiting_approval: 5
  }, prefix: true

  scope :active, -> { where(status: [:pending, :running]) }
  scope :terminal, -> { where(status: [:completed, :cancelled, :failed]) }
  scope :recent_completed, -> { status_completed.where("completed_at > ?", 24.hours.ago) }

  # ── Progress helpers (called from AgentTaskJob subclasses) ──

  def start!
    update!(status: :running, started_at: started_at || Time.current)
  end

  def update_progress!(pct, text = nil)
    update!(progress: pct, progress_text: text)
  end

  def complete!(result_data = {})
    update!(status: :completed, progress: 100, result: result_data, completed_at: Time.current)
  end

  def fail!(message)
    text = attempts > 1 ? "Failed after #{attempts} attempts" : "Failed"
    update!(status: :failed, error_message: message, progress_text: text, completed_at: Time.current)
  end

  def cancel!
    return false unless active?

    update!(status: :cancelled, completed_at: Time.current)
    subtasks.active.find_each(&:cancel!)
    true
  end

  def await_approval!(result_data = {})
    update!(status: :awaiting_approval, result: result_data)
  end

  # ── Query helpers ──

  def active?
    status_pending? || status_running?
  end

  def terminal?
    status_completed? || status_cancelled? || status_failed?
  end

  # ── Mentionable ──

  def mentionable_label
    "#{kind.humanize} #{to_param}"
  end

  def mentionable_summary
    parts = [kind.humanize, status]
    parts << progress_text if progress_text.present?
    parts.join(" — ")
  end

  def mentionable_kind
    "agent_task"
  end
end

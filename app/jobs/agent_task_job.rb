# frozen_string_literal: true

##
# AgentTaskJob - Base class for background agent task execution
#
# This is the foundation for all long-running, autonomous work in the app.
# When a user asks the AI to do something that takes time (analyze data,
# generate reports, process records), a Tool creates an AgentTask record
# and enqueues a job that inherits from this class.
#
# == Why this exists (Tools vs Agent Tasks)
#
# Tools run INLINE in the chat fiber — fast, synchronous, results appear
# immediately. Agent tasks run in BACKGROUND via SolidQueue/Sidekiq —
# for anything that takes > ~10 seconds, needs retries, or should track
# progress. See docs/building_with_agents.md for the full guide.
#
# == How to create a new agent task
#
# 1. Create a Tool (app/tools/) that creates an AgentTask and enqueues your job
# 2. Create a Job (app/jobs/) that inherits from AgentTaskJob
# 3. Implement #execute(task) — return a hash that becomes task.result
# 4. Register the tool in ToolsetService#tool_classes
#
# The base class handles everything else: status transitions, retries,
# cancellation polling, and error recovery.
#
# == Subclass contract
#
#   class MyJob < AgentTaskJob
#     def max_attempts = 3                          # Optional: enable retries (default: 1)
#     def retry_delay(attempt) = 10.seconds * attempt  # Optional: custom backoff
#
#     def execute(task)
#       # Do your work here. Access task.metadata for input config.
#       # Call task.update_progress!(pct, text) to update the UI.
#       # Call `break if cancelled?` in loops to respect cancellation.
#       # Use track_create/track_update/track_destroy for auditable operations.
#       # Return a hash — it becomes task.result (JSON) on completion.
#       { analyzed: 42, insights: "..." }
#     end
#   end
#
# == Retries
#
# Retries are tracked on the AgentTask record, not the job queue. This makes
# retry behavior identical across SolidQueue and Sidekiq. On failure, the job
# re-enqueues itself via perform_later — it does NOT re-raise (which would
# trigger the queue's own retry mechanism). On final failure, it DOES re-raise
# so error trackers (Sentry, Honeybadger) see it.
#
class AgentTaskJob < ApplicationJob
  # How often to check the DB for cancellation (seconds)
  CANCEL_CHECK_INTERVAL = 2.0

  # Sidekiq users: uncomment to prevent Sidekiq's own retry mechanism from
  # re-running the job after final failure. Not harmful without this (the
  # terminal? guard makes re-runs a no-op), but saves a wasted execution.
  #
  # sidekiq_options retry: 0

  def perform(agent_task_id)
    @task = AgentTask.find(agent_task_id)
    @last_cancel_check = Time.current

    # Already terminal (cancelled/failed by a previous run, or queue double-delivery)
    return if @task.terminal?

    @task.increment!(:attempts)
    @task.start!
    result = execute(@task)

    # Job may have been cancelled mid-execution
    @task.reload
    return if @task.status_cancelled?

    @task.complete!(result || {})
  rescue => e
    handle_failure(e)
  end

  private

  ##
  # Subclasses implement this method.
  # Return a hash — it becomes task.result on completion.
  #
  def execute(task)
    raise NotImplementedError, "#{self.class}#execute must be implemented"
  end

  ##
  # Maximum number of attempts before permanent failure.
  # Override in subclasses to enable retries. Default: 1 (no retries).
  #
  def max_attempts
    1
  end

  ##
  # Delay before retrying. Receives the current attempt number (1-indexed).
  # Override in subclasses for custom backoff. Default: 5s * attempt.
  #
  def retry_delay(attempt)
    5.seconds * attempt
  end

  ##
  # Check if the task has been cancelled.
  # Call this in loops: `break if cancelled?`
  # Throttled to avoid excessive DB queries.
  #
  def cancelled?
    if Time.current - @last_cancel_check >= CANCEL_CHECK_INTERVAL
      @task.reload
      @last_cancel_check = Time.current
    end
    @task.status_cancelled?
  end

  # ── Effect-tracking helpers ──────────────────────────────────────
  #
  # Each helper wraps the ActiveRecord operation and its effect log in
  # a single transaction. If either fails, both roll back.
  #
  # If you're already inside a transaction, these participate as
  # savepoints — standard Rails behavior, no nesting issues.

  ##
  # Create a record and log the effect.
  #
  #   customer = track_create(Customer, name: "Acme Corp", email: "a@example.com")
  #   track_create(Invoice, description: "Generated monthly invoice", account: customer)
  #
  def track_create(klass, description: nil, **attributes)
    record = nil
    ActiveRecord::Base.transaction do
      record = klass.create!(attributes)
      @task.effects.create!(
        action: "created",
        target: record,
        description: description || "Created #{klass.model_name.human} #{record_label(record)}"
      )
    end
    record
  end

  ##
  # Update a record and log the changes.
  #
  #   track_update(customer, status: "active", tier: "premium")
  #
  def track_update(record, description: nil, **attributes)
    ActiveRecord::Base.transaction do
      record.assign_attributes(attributes)
      changes = record.changes.transform_values { |from, to| { from: from, to: to } }
      record.save!
      @task.effects.create!(
        action: "updated",
        target: record,
        description: description || "Updated #{record.class.model_name.human} #{record_label(record)}",
        details: { changes: changes }
      )
    end
    record
  end

  ##
  # Destroy a record and log the effect.
  # Creates the effect first (capturing target_type/target_id), then destroys.
  #
  #   track_destroy(old_customer)
  #
  def track_destroy(record, description: nil)
    ActiveRecord::Base.transaction do
      snapshot = record.attributes.except("created_at", "updated_at")
      @task.effects.create!(
        action: "deleted",
        target_type: record.class.name,
        target_id: record.id,
        description: description || "Deleted #{record.class.model_name.human} #{record_label(record)}",
        details: { snapshot: snapshot }
      )
      record.destroy!
    end
  end

  ##
  # Attach a file to a record and log the effect.
  #
  #   track_attach(customer, :documents, io: file, filename: "invoice.pdf")
  #   track_attach(@task, :attachments, io: csv, filename: "report.csv")  # attach to task itself
  #
  def track_attach(record, attachment_name, description: nil, **attach_args)
    ActiveRecord::Base.transaction do
      proxy = record.public_send(attachment_name)
      proxy.attach(attach_args)
      blob = if proxy.is_a?(ActiveStorage::Attached::One)
        proxy.blob
      else
        record.public_send(:"#{attachment_name}_blobs").order(id: :desc).first
      end
      @task.effects.create!(
        action: "attached",
        target: record,
        description: description || "Attached #{attach_args[:filename]} to #{record.class.model_name.human} #{record_label(record)}",
        details: {
          attachment_name: attachment_name.to_s,
          filename: blob.filename.to_s,
          content_type: blob.content_type,
          byte_size: blob.byte_size
        }
      )
    end
    record
  end

  ##
  # Detach a file from a record and log the effect.
  # Accepts a filename string or an ActiveStorage::Blob.
  #
  #   track_detach(customer, :documents, "old_logo.png")
  #
  def track_detach(record, attachment_name, blob_or_filename = nil, description: nil)
    ActiveRecord::Base.transaction do
      proxy = record.public_send(attachment_name)

      if proxy.is_a?(ActiveStorage::Attached::One)
        raise ActiveRecord::RecordNotFound, "No attachment on #{attachment_name}" unless proxy.attached?
        attachment = proxy.attachment
        blob = proxy.blob
      else
        attachment = if blob_or_filename.is_a?(String)
          proxy.find { |a| a.filename.to_s == blob_or_filename }
        elsif blob_or_filename.is_a?(ActiveStorage::Blob)
          proxy.find { |a| a.blob_id == blob_or_filename.id }
        else
          blob_or_filename
        end

        raise ActiveRecord::RecordNotFound, "Attachment '#{blob_or_filename}' not found" unless attachment
        blob = attachment.is_a?(ActiveStorage::Attachment) ? attachment.blob : attachment
      end

      details = {
        attachment_name: attachment_name.to_s,
        filename: blob.filename.to_s,
        content_type: blob.content_type,
        byte_size: blob.byte_size
      }

      @task.effects.create!(
        action: "detached",
        target: record,
        description: description || "Removed #{blob.filename} from #{record.class.model_name.human} #{record_label(record)}",
        details: details
      )

      proxy.is_a?(ActiveStorage::Attached::One) ? proxy.purge : attachment.purge
    end
    record
  end

  ##
  # Log a custom effect (external API call, notification, etc.)
  #
  #   track_effect("notified", target: user, description: "Sent Slack message to #general")
  #   track_effect("custom", description: "Called Stripe API to create invoice", details: { stripe_id: "inv_xxx" })
  #
  def track_effect(action, target: nil, description:, details: {})
    attrs = { action: action, description: description, details: details }
    attrs[:target] = target if target
    @task.effects.create!(attrs)
  end

  ##
  # Create a subtask and enqueue its job.
  #
  # The subtask is linked to the current task via parent_task_id and shares
  # the same chat, workspace, and member. The chat's frontend will see it
  # as an additional active task and wait for it before summarization.
  #
  #   subtask = track_enqueue_subtask(DataExportJob, kind: "data_export",
  #     description: "Exporting customer data to CSV",
  #     metadata: { format: "csv", filters: { status: "active" } })
  #
  def track_enqueue_subtask(job_class, kind:, description: nil, metadata: {})
    subtask = AgentTask.create!(
      chat: @task.chat,
      workspace: @task.workspace,
      member: @task.member,
      parent_task: @task,
      kind: kind,
      metadata: metadata
    )

    job_class.perform_later(subtask.id)

    @task.effects.create!(
      action: "enqueued",
      target: subtask,
      description: description || "Enqueued #{kind.humanize} subtask",
      details: {
        subtask_id: subtask.to_param,
        job_class: job_class.name,
        kind: kind
      }
    )

    subtask
  end

  ##
  # Derive a human-readable label for a record.
  #
  def record_label(record)
    if record.respond_to?(:mentionable_label)
      record.mentionable_label
    elsif record.respond_to?(:name) && record.name.present?
      "'#{record.name}'"
    elsif record.respond_to?(:title) && record.title.present?
      "'#{record.title}'"
    else
      "##{record.id}"
    end
  end

  ##
  # Handle execution failure: retry if under max_attempts, fail permanently otherwise.
  #
  # When retrying, we set the task back to pending and re-enqueue.
  # We do NOT re-raise — this prevents the job queue from also retrying.
  #
  # On final failure, we re-raise so the error appears in logs/error trackers.
  #
  def handle_failure(error)
    return unless @task

    Rails.logger.error "[AgentTaskJob] #{self.class.name} attempt #{@task.attempts}/#{max_attempts} failed: #{error.class} - #{error.message}"
    Rails.logger.error error.backtrace&.first(5)&.join("\n")

    if @task.attempts < max_attempts
      delay = retry_delay(@task.attempts)
      reason = error.message.truncate(100)
      @task.update!(
        status: :pending,
        progress: 0,
        progress_text: "Retry #{@task.attempts + 1}/#{max_attempts}: #{reason}"
      )
      self.class.set(wait: delay).perform_later(@task.id)
      # Don't re-raise — we're handling the retry ourselves
    else
      @task.fail!(error.message)
      raise
    end
  end
end

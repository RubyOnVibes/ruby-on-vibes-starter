# frozen_string_literal: true

require "digest"

module Examples
  # A concrete business record, not a second agent task engine. The application
  # prepares an immutable report and its business key before offering publication.
  class ReportPublication < ApplicationRecord
    self.table_name = "example_report_publications"

    belongs_to :workspace, inverse_of: :example_report_publications
    belongs_to :chat, inverse_of: :example_report_publications
    belongs_to :member, inverse_of: :example_report_publications
    belongs_to :chat_run, optional: true, inverse_of: :example_report_publications

    enum :status, { draft: "draft", queued: "queued", published: "published", cancelled: "cancelled" }, prefix: true

    validates :publication_key, :title, :body, :content_digest, presence: true
    validates :publication_key, uniqueness: { scope: :workspace_id }
    validates :title, length: { maximum: 200 }
    validates :body, length: { maximum: 100_000 }
    validate :workspace_matches_context
    validate :snapshot_is_immutable, on: :update
    before_validation :set_content_digest, on: :create

    def request_publication!(run:)
      with_lock do
        authorize_run!(run)
        raise ArgumentError, "This publication was cancelled; prepare a new revision" if status_cancelled?
        update!(status: :queued, chat_run: run) if status_draft?
      end
      dispatch_if_pending!
      self
    end

    # The native task polls this durable record and can redeliver a lost job.
    # Duplicate deliveries are safe because publication is a single transaction.
    def dispatch_if_pending!
      PublishReportJob.perform_later(id) if status_queued?
    rescue ActiveJob::EnqueueError, SolidQueue::Job::EnqueueError => error
      Rails.logger.warn("Report publication #{id} will retry delivery after #{error.class}")
      false
    end

    def publish!
      with_publishable_record do
        update!(status: :published, published_at: Time.current)
      end
    end

    # The tool can die after committing queued but before its native task or
    # queue job exists. Recover this business delivery intent independently.
    def recover!
      dispatch_if_pending! if with_publishable_record { true } == true
    end

    def cancel!
      with_lock do
        update!(status: :cancelled) if status_draft? || status_queued?
      end
      self
    end

    def result
      { report_id: id, status: status, content_digest: content_digest, published_at: published_at&.iso8601 }
    end

    def authorize_run!(run)
      actor = run.execution_member!
      unless run.chat_id == chat_id && actor.id == member_id && actor.workspace_id == workspace_id
        raise Pundit::NotAuthorizedError, "Publication is outside this run's authorized scope"
      end
      actor
    end

    private

    def with_publishable_record
      return unless status_queued?

      run = chat_run
      return cancel! unless run

      # Cancellation and publication serialize on the same run lock. Keep all
      # effects local and short; never hold these locks across a provider call.
      run.with_lock do
        with_lock do
          return unless status_queued?
          unless run.active?
            update!(status: :cancelled)
            return
          end
          authorize_run!(run)
          yield
        end
      end
    rescue Pundit::NotAuthorizedError
      cancel!
    end

    def set_content_digest
      self.content_digest = Digest::SHA256.hexdigest(JSON.generate([ title, body ]))
    end

    def workspace_matches_context
      errors.add(:workspace, "must match the chat and member") unless
        chat && member && workspace_id == chat.workspace.id && workspace_id == member.workspace_id
      errors.add(:chat_run, "must belong to this chat") if chat_run && chat_run.chat_id != chat_id
    end

    def snapshot_is_immutable
      %w[workspace_id chat_id member_id publication_key title body content_digest].each do |field|
        errors.add(field, "is an immutable prepared snapshot") if will_save_change_to_attribute?(field)
      end
      if published_at_in_database && will_save_change_to_published_at?
        errors.add(:published_at, "cannot change after publication")
      end
    end
  end
end

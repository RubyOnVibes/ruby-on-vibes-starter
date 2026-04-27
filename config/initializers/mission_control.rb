# Extend AsyncJobAdapter with Mission Control interface
if defined?(ActiveJob::QueueAdapters::AsyncJobAdapter)
  ActiveJob::QueueAdapters::AsyncJobAdapter.include ActiveJob::QueueAdapters::AsyncExt
end

MissionControl::Jobs.http_basic_auth_enabled = false
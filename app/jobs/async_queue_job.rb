##
# AsyncQueueJob - A job that runs on the async_job queue
# This job is used to test the async_job adapter
# You may inherit from this job in your own jobs to run on the async_job queue
# 
class AsyncQueueJob < ApplicationJob
  self.queue_adapter = :async_job

  def perform(message = "Hello from async_job")
    counter_file_path = "#{Rails.root}/tmp/async_job_counter.txt".freeze
    counter = 0

    # Read the current counter value if file exists, else initialize it to 0
    if File.exist?(counter_file_path)
      content = File.read(counter_file_path).strip
      counter = content.to_i
    end

    # Increment the counter
    counter += 1

    # Write the new counter value to the file
    File.open(counter_file_path, "w") { |file| file.write(counter.to_s) }

    Rails.logger.info "AsyncQueueJob: #{message} (counter: #{counter})"
  end
end
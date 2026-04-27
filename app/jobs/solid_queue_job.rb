##
# SolidQueueJob - A job that runs on the solid_queue queue
# This job is used to test the solid_queue adapter
# You may inherit from this job in your own jobs to run on the solid_queue queue
# 

class SolidQueueJob < ApplicationJob
  self.queue_adapter = :solid_queue

  def perform(message = "Hello from solid_queue")
    counter_file_path = "#{Rails.root}/tmp/solid_queue_counter.txt".freeze
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

    Rails.logger.info "SolidQueueJob: #{message} (counter: #{counter})"
  end
end
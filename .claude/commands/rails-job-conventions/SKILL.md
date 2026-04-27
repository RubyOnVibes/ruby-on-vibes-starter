---
name: rails-job-conventions
description: Use when creating or modifying Rails jobs in app/jobs
---

# Rails Job Conventions

Conventions for background jobs in this Ruby on Vibes app.

## Stack Context

This app uses:
- **async-job-adapter** for LLM/IO-heavy work (streaming, real-time)
- **SolidQueue** for most other background jobs
- **Falcon server** with async capabilities

## Core Principles

1. **Jobs are disposable** - Can be retried, requeued, or fail
2. **Idempotent** - Running twice produces same result
3. **Small payloads** - Pass IDs, not full objects
4. **Fail gracefully** - Handle missing records, timeouts

## Queue Selection

```ruby
# For LLM streaming and real-time work
class ChatStreamJob < ApplicationJob
  self.queue_adapter = :async  # Async-job for IO-bound work
  queue_as :default
end

# For regular background work
class SendEmailJob < ApplicationJob
  self.queue_adapter = :solid_queue  # SolidQueue for most jobs
  queue_as :default
end
```

## Idempotency Pattern

```ruby
class ProcessPaymentJob < ApplicationJob
  def perform(order_id)
    order = Order.find_by(id: order_id)
    return unless order  # Record may have been deleted

    # Guard against double-processing
    return if order.paid?

    order.process_payment!
  end
end
```

## Error Handling

```ruby
class ImportDataJob < ApplicationJob
  # Retry with exponential backoff
  retry_on StandardError, wait: :exponentially_longer, attempts: 3

  # Don't retry certain errors
  discard_on ActiveRecord::RecordNotFound

  def perform(import_id)
    import = Import.find(import_id)
    import.process!
  rescue => e
    import.update!(status: :failed, error_message: e.message)
    raise  # Re-raise to trigger retry
  end
end
```

## LLM Job Pattern (RubyLLM)

```ruby
class ChatStreamJob < ApplicationJob
  self.queue_adapter = :async
  queue_as :default

  def perform(chat_id, user_message_id)
    chat = Chat.find(chat_id)

    # Use RubyLLM for streaming
    chat.complete do |chunk|
      # Stream chunks to frontend via ActionCable
      ChatChannel.broadcast_to(chat, { chunk: chunk.content })
    end
  end
end
```

## Quick Reference

| Do | Don't |
|----|-------|
| Pass record IDs | Pass full ActiveRecord objects |
| Check if record exists | Assume record is present |
| Use retry_on/discard_on | Catch all errors silently |
| Set queue_adapter explicitly | Assume default adapter |
| Guard against double-processing | Process without idempotency check |

## Common Mistakes

1. **Passing objects instead of IDs** - Objects can't be serialized properly
2. **Not handling missing records** - Records can be deleted between enqueue and perform
3. **Not setting queue adapter** - Wrong adapter for the job type
4. **Heavy compute in jobs** - Keep compute minimal, IO is fine
5. **No idempotency guards** - Jobs can run multiple times

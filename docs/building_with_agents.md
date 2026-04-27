# Building with Agents

This guide covers how to add AI-powered capabilities to your application using the chat system, tools, and agent tasks.

## Architecture Overview

The app uses Ruby's async/fiber ecosystem for concurrency. `ChatStreamJob` runs as an
in-process fiber via `async-job` — not a thread-based worker. This means:

- **Fibers are lightweight**: ~3μs to allocate (vs ~80μs for threads), ~0.1μs context switch
- **I/O multiplexing**: One thread monitors thousands of connections via epoll/kqueue
- **No slot starvation**: Fibers yield during I/O (LLM streaming, HTTP requests), freeing the
  event loop for other work. Thread-based workers would each hold a database connection and
  OS thread while waiting for tokens.
- **Transparent**: Existing Ruby code becomes non-blocking automatically under Falcon + async.
  No syntax changes, no `await` keywords, no library migrations.

The web server (Falcon) and chat jobs share the same fiber scheduler. Tools run inline in the
chat fiber. Agent tasks run in a separate SolidQueue worker process for true background work.

There are two ways your AI agent executes work:

### 1. Tools (Inline, Fast)

Tools run **inside the chat fiber** — the same async process that handles the LLM conversation.
Because fibers yield during I/O, a tool making an HTTP request (like fetching a web page) doesn't
block other conversations. They're for operations that complete in seconds.

```
User message → ChatStreamJob (fiber) → LLM calls Tool → Tool returns result → LLM responds
```

**Use tools when:**
- The operation completes in under ~10 seconds
- No retries are needed
- The result should appear immediately in the conversation
- Examples: fetch a web page, look up a record, check the current time

**Creating a tool:**

```ruby
# app/tools/lookup_customer_tool.rb
class LookupCustomerTool < RubyLLM::Tool
  description "Look up a customer by email address."

  params do
    string :email, description: "The customer's email address", required: true
  end

  attr_reader :chat, :sender_user, :sender_member, :sender_workspace

  def initialize(chat:, sender_user: nil, sender_member: nil, sender_workspace: nil)
    @chat = chat
    @sender_user = sender_user
    @sender_member = sender_member
    @sender_workspace = sender_workspace
  end

  def execute(email:)
    customer = @sender_workspace.customers.find_by(email: email)
    return "No customer found with email #{email}" unless customer

    "Found: #{customer.name} (#{customer.email}) — #{customer.orders.count} orders, " \
      "last order #{customer.orders.last&.created_at&.strftime('%B %d, %Y') || 'never'}"
  end
end
```

Register it in `app/services/toolset_service.rb`:

```ruby
def tool_classes
  tools = [
    CurrentDateTimeTool,
    WebFetchTool,
    LookupCustomerTool,  # Add your tool here
  ]
  # ...
end
```

### 2. Agent Tasks (Background, Long-Running)

Agent tasks run in **SolidQueue** (or Sidekiq) — a separate worker process, not a fiber.
This is intentional: fibers are great for I/O-bound work (streaming LLM tokens, HTTP requests),
but CPU-intensive or very long-running operations should run in a dedicated process so they
don't compete with the chat event loop. Agent tasks are for work that takes time, needs retries,
or should run independently of the chat.

```
User message → ChatStreamJob → LLM calls Tool → Tool creates AgentTask + enqueues Job
                                                → Tool returns "Task started"
                                                → Job runs in background, updates progress
                                                → Frontend polls for progress
                                                → Next chat turn: agent sees completed result
```

**Use agent tasks when:**
- The operation takes more than ~10 seconds
- You need retry logic (network failures, rate limits, etc.)
- The operation is CPU-intensive or involves many records
- You want progress tracking visible to the user
- The work should continue even if the user navigates away
- Examples: analyze all customers, generate a report, batch-process records, call external APIs with rate limits

**Creating an agent task requires two files:**

**1. The Tool** (triggers the task from chat):

```ruby
# app/tools/analyze_customers_tool.rb
class AnalyzeCustomersTool < RubyLLM::Tool
  description "Analyze all customers who haven't ordered in 30 days. " \
              "Runs in the background — you'll see progress updates below."

  params do
    integer :days, description: "Inactivity threshold in days (default: 30)", required: false
  end

  attr_reader :chat, :sender_user, :sender_member, :sender_workspace

  def initialize(chat:, sender_user: nil, sender_member: nil, sender_workspace: nil)
    @chat = chat
    @sender_user = sender_user
    @sender_member = sender_member
    @sender_workspace = sender_workspace
  end

  def execute(days: nil)
    days ||= 30

    task = AgentTask.create!(
      chat: @chat,
      workspace: @sender_workspace,
      member: @sender_member,
      kind: "customer_analysis",
      metadata: { days: days }
    )

    CustomerAnalysisJob.perform_later(task.id)

    { task_id: task.to_param, message: "Analyzing inactive customers (#{days}+ days). Track progress below." }
  end
end
```

**2. The Job** (does the actual work):

```ruby
# app/jobs/customer_analysis_job.rb
class CustomerAnalysisJob < AgentTaskJob
  # Retry up to 3 times with increasing delay
  def max_attempts = 3
  def retry_delay(attempt) = 10.seconds * attempt

  private

  def execute(task)
    days = task.metadata["days"] || 30
    cutoff = days.days.ago
    customers = task.workspace.customers.where("last_order_at < ? OR last_order_at IS NULL", cutoff)
    total = customers.count

    insights = []

    customers.find_each.with_index do |customer, i|
      break if cancelled?  # Check for user cancellation

      # Update progress bar in the UI
      task.update_progress!(
        ((i + 1).to_f / total * 100).round,
        "Analyzed #{i + 1} of #{total} customers..."
      )

      # Do your analysis here
      if customer.orders.sum(:total) > 1000
        insights << { name: customer.name, total_spent: customer.orders.sum(:total) }
        # Track the effect for audit trail
        track_effect("flagged", target: customer, description: "Flagged as high-value inactive customer")
      end
    end

    # Return value becomes task.result (JSON)
    { total_analyzed: total, high_value_inactive: insights.length, insights: insights }
  end
end
```

Register the tool in `toolset_service.rb` and the job runs automatically when triggered.

## How the Agent Learns About Completed Tasks

You don't need to do anything special. When a user sends their next message after a task completes, `ChatStreamJob` automatically injects a summary of recently completed tasks into the agent's context. The agent sees the results and can respond naturally:

> "The analysis finished — I found 12 high-value inactive customers. Here are the top 5 by total spend..."

## Effect Tracking (Audit Trail)

Agent task jobs have built-in helpers for tracking what they did. Every tracked operation creates an `AgentTaskEffect` record visible on the task's show page.

```ruby
# Inside your AgentTaskJob#execute method:

# Create a record and log it
customer = track_create(Customer, name: "Acme", email: "a@example.com")

# Update a record and log the changes
track_update(customer, status: "active", tier: "premium")

# Delete a record and log a snapshot
track_destroy(old_record)

# Attach a file
track_attach(@task, :artifacts, io: csv_data, filename: "report.csv",
             description: "Generated customer report")

# Log a custom effect (API call, notification, etc.)
track_effect("notified", target: user, description: "Sent Slack notification")

# Spawn a subtask
track_enqueue_subtask(DataExportJob, kind: "data_export",
                      metadata: { format: "csv" })
```

## Decision Guide: Tool or Agent Task?

| Question | Tool | Agent Task |
|----------|------|------------|
| How long does it take? | < 10 seconds | > 10 seconds |
| Need retries? | No | Yes |
| Need progress tracking? | No | Yes |
| CPU-intensive? | No | Yes |
| Processes many records? | No (or few) | Yes |
| Should continue if user navigates away? | N/A | Yes |
| Result needed immediately in conversation? | Yes | No (next turn) |

When in doubt, start with a tool. If it's too slow or unreliable, graduate it to an agent task.

## File Conventions

```
app/tools/           — Tool classes (RubyLLM::Tool subclasses)
app/jobs/            — Job classes (AgentTaskJob subclasses for tasks, ApplicationJob for other jobs)
app/models/          — AgentTask, AgentTaskEffect models
app/services/        — ToolsetService (tool registration)
app/controllers/api/ — Polling endpoints for task progress
```

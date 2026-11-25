# Building with Agents

This guide covers how to add AI-powered capabilities to your application using the chat system, tools, and agent tasks.

## RubyLLM 2.2: choose the integration you need

The starter uses RubyLLM 2.2. Configure a provider as described in the
[README](../README.md#quickstart), then use the smallest building block that
fits your feature:

| Need | Entry point | What the starter supplies |
| --- | --- | --- |
| A typed answer in a normal Rails feature | `RubyLLM.chat.with_schema(...)` | Provider configuration; your controller/service owns permissions and presentation. |
| A reusable AI behavior | Subclass `ApplicationAgent` | A native `RubyLLM::Agent` base with `chat_class Chat`; plain `.new` agents remain in memory. |
| User-visible conversation and actions | `Chat`, `ChatStreamJob`, `ToolsetService` | Workspace access, streaming, tool decisions, and `ChatRun` usage. |
| Long work with progress | `AgentTask` + `AgentTaskJob` | Job retries, cancellation, progress, effects, and conversation continuation. |
| Scheduled or webhook-triggered workers | The application's `Agent` model | Identity, workspace membership, stored configuration, and scheduling. |
| Regression measurement | `RubyLLM::Evaluation` | Native library API; add your own dataset and explicit run command. |

The application's database-backed `Agent` is distinct from a Ruby class derived
from `RubyLLM::Agent`. A standalone `RubyLLM.chat` or native agent call does not
automatically create a `ChatRun`, enforce workspace access, or appear in the
starter's chat UI. Attribute usage with `RubyLLM.with_owner(your_record)` when
calling outside the chat job, and pass only records the current member may use.

Core MCP, skills, file stores, provider-hosted tools, and code execution are
available to application code. This starter does not automatically connect MCP
servers, install skills, enable a sandbox, or provide UI for every core feature.
Add a feature deliberately and exercise its lifecycle through the intended UI
or job. See [optional dependencies](#optional-companion-tools) below.

For the built-in conversation, `ChatStreamJob#add_tools` rebuilds the toolset
each run; register tools in `ToolsetService`, and apply additional chat options
in the job's setup path on every run. An option set on a different in-memory
chat will not configure the next UI turn. For MCP OAuth, configure Rails Active
Record encryption from ENV before storing credentials; a credential table alone
does not configure encryption. Use the [MCP guide](https://rubyllm.com/mcp/)
for server lifecycle and authentication.

### Tool-loop and logging defaults

`config/initializers/ruby_llm.rb` sets
`Rails.configuration.x.llm.tool_options = { rounds: 25, calls: 50 }`.
Both the UI's `ChatStreamJob` and `ApplicationAgent` use these defaults. Native
agent subclasses can override them with `tool_options`; customize the shared
configuration for the built-in chat flow. Tool execution remains sequential.

`calls` caps tools executed from one model response. Excess calls receive an
error result without execution or approval. `rounds` bounds one `complete`
invocation, including its repeated model/tool loop. A human-question pause or
another completion resets that counter: these are not total-run, token, or
spending budgets. The UI marks an exhausted run failed, keeps completed tool
results and usage, and asks for a new user message before continuing. Native
agents raise `RubyLLM::ToolRoundLimitError` for their caller to handle.

RubyLLM request/response body logging is disabled with `config.log_bodies = false`.
Application tools and other loggers still need to avoid logging private data.
Question dropdowns use RubyLLM's choice titles while submitting the original
values, including typed values in multi-select questions.

See the [November maintenance review](maintenance-2026-11.md) for the capability
inventory and proposed lifecycle work. In particular, native deferred tasks
and automatic recovery of interrupted runs need application integration;
stored `Agent.schedule` values do not themselves install recurring jobs.

### Structured output and a reusable agent

For example, create a schema and an agent for a narrow extraction task:

```ruby
# app/schemas/invoice_fields.rb
class InvoiceFields < Schematist::Schema
  string :vendor
  integer :total_cents
end

# app/agents/invoice_extraction_agent.rb
class InvoiceExtractionAgent < ApplicationAgent
  instructions "Extract the invoice vendor and total in integer cents."
  schema InvoiceFields
end
```

`InvoiceExtractionAgent.new.ask(text).parsed` returns the structured Hash;
`.content` is JSON text. This call uses the configured provider and may incur
usage charges. Validate business rules before saving its result. Schematist
describes output shape; it does not establish factual correctness.

### Test behavior without provider requests

RubyLLM's test helper stubs chat replies while retaining the real conversation
loop. For example, after adding the agent above:

```ruby
require "rails_helper"
require "ruby_llm/test_helper"

RSpec.describe InvoiceExtractionAgent do
  include RubyLLM::TestHelper

  it "returns a parsed invoice" do
    stub_replies '{"vendor":"Acme","total_cents":12500}'
    result = described_class.new.ask("Acme invoice, total $125.00")
    expect(result.parsed).to eq("vendor" => "Acme", "total_cents" => 12500)
  end
end
```

Use `stub_replies tool_call(:your_tool, argument: "value"), "Done"` to exercise
tool execution. These stubs cover chat requests; operations such as embeddings
still need their own test doubles. This verifies application behavior, not a
model's extraction quality.

### Evaluate quality explicitly

Add an opt-in evaluation for real model quality. This example uses deterministic
checks without a second model grading the answer:

```ruby
# app/evals/invoice_evaluation.rb
class InvoiceEvaluation < RubyLLM::Evaluation
  evaluator false

  def perform(input)
    unless ENV["RUN_LIVE_LLM_EVALS"] == "true"
      raise "Set RUN_LIVE_LLM_EVALS=true to allow provider requests"
    end

    InvoiceExtractionAgent.new.ask(input).parsed
  end

  def assertions
    assert_equal expected_output, output
  end
end
```

```yaml
# app/evals/invoice_evaluation.yml
cases:
  - name: simple_invoice
    inputs: "Invoice from Acme. Total due: $125.00."
    expected_output:
      vendor: Acme
      total_cents: 12500
```

Run only when you intend to make paid provider calls:

```bash
RUN_LIVE_LLM_EVALS=true bin/rails "ruby_llm:eval[InvoiceEvaluation]"
```

`evaluator false` disables grading calls, not the agent call in `perform`.
The native report records verdicts and usage under `tmp/evaluations`. Keep
real, reviewed cases in version control and compare the same cases after a
prompt or model change. Add model grading only when deterministic checks cannot
express the desired result; inspect grader disagreements yourself. See the
[evaluation guide](https://rubyllm.com/evaluations/).

## Architecture Overview

`ChatStreamJob` runs in a separate Solid Queue worker. Falcon serves HTTP and
WebSockets; Solid Cable delivers updates across processes. Each delivery binds
the chat's named native agent purpose and original actor. RubyLLM owns claims,
message persistence, tool execution and task/question suspension. Rails persists
dispatch intent and retries missing delivery through `ResumeChatRunsJob`.

See [agent foundations](agent-foundations.md) for the ownership contract,
[chat purposes](chat_purposes.md) for configuration and [chat files](chat-files.md)
for uploads and artifacts. Do not use in-process async jobs for work that must
survive web restarts. CPU-heavy or long external work should return a native
`RubyLLM::Task` and resume from persisted state.

There are two ways your AI agent executes work:

### 1. Tools (Inline, Fast)

Tools run inside the durable conversation job. Keep inline operations short;
long work should return a native task. Worker concurrency and provider limits
determine how many conversations can run at once.

```
User message → ChatStreamJob (Solid Queue) → LLM calls Tool → Tool returns result → LLM responds
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

  parameters do
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

### Human approval for writes

Reading data and changing data are different trust boundaries. Any tool that
sends, publishes, charges, deletes, or mutates important records should declare
`requires_approval` and still enforce authorization inside `execute`:

```ruby
class PublishPostTool < RubyLLM::Tool
  description "Publish a reviewed draft"
  requires_approval

  parameters do
    integer :post_id, required: true
  end

  def initialize(chat:, sender_member:, **)
    @chat = chat
    @sender_member = sender_member
  end

  def execute(post_id:)
    post = @sender_member.workspace.posts.find(post_id)
    raise Pundit::NotAuthorizedError unless PostPolicy.new(@sender_member, post).publish?

    post.update!(published_at: Time.current)
    { published: true, post_id: post.id }
  end
end
```

The chat loop persists the pending call, parks its `ChatRun` in
`awaiting_approval`, and renders the exact arguments. RubyLLM 2.2 represents
approvals and tool questions through `pending_questions`; decisions use
`approve`, `decline`, or `answer`. The starter's question endpoints enforce
membership and run ownership before passing a decision to RubyLLM. Use those
endpoints from the UI rather than writing internal approval columns.

Tool questions can request form values or a visit to a server-supplied URL.
Their saved state survives a refresh. A tool that asks a question executes again
from the beginning after the answer: ask before performing a side effect.
Approval is consent to attempt the action, not authorization: scope records and
check permissions again inside the tool. Make writes idempotent because any
background system can retry after failure.

`Examples::RenameChatTool` is a reversible reference implementation available
with `VIBES_DEBUG_TOOLS=true`.

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

  parameters do
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

## Run usage, prompt caching, and fallbacks

Each `ChatRun` snapshots RubyLLM's persisted usage ledger, including physical
retry attempts, input/output/cache tokens, and cost when pricing is known. The
final assistant message shows a compact usage line. Unknown cost remains blank;
it is never converted to a misleading zero.

Two resilience features are opt-in:

```env
LLM_PROMPT_CACHING=true
LLM_FALLBACK_MODELS=gpt-5-nano,claude-haiku-4-5
```

When caching is enabled, stable assistant/agent instructions form the cached
prefix. Mentions, participants, task results, compaction summaries, and other
per-turn context remain outside that prefix. Provider cache minimums still
apply, so confirm cache hits through `ChatRun#cache_read_tokens`.

Fallbacks apply only to RubyLLM's supported transient failure classes. Configure
credentials for every listed model and choose models that support the tools and
modalities your conversation uses.

## Optional companion tools

- **Schematist** is already a RubyLLM dependency. Use `Schematist::Schema`;
  do not add the legacy `ruby_llm-schema` forwarding gem.
- **MCP, evaluations, and instrumentation** ship in core. Do not add the old
  placeholder `ruby_llm-evaluations` or `ruby_llm-opentelemetry` packages.
  The separate community `ruby_llm-mcp` conflicts with core's namespace.
- **`mxc >= 0.4.1`** is needed only for RubyLLM's local code-execution sandbox.
  Define permitted paths, network access, and runtime limits before exposing
  code execution. It is not required for regular Ruby tools.
- **`skill`** is an optional installer CLI, not an application runtime dependency.
  RubyLLM includes a version-matched coding skill. To install it deliberately
  into this project's coding-agent configuration after reviewing its contents:

  ```bash
  gem exec skill add "$(bundle show ruby_llm)" --skill rubyllm --agents coding
  ```

- **OpenTelemetry** can use the native integration with your chosen SDK and
  exporter when you have a tracing destination. It is not enabled by default.
- **ArchSpec** can add development-time architecture checks; **Kamal Backup**
  can support a deployed app. Neither is required for the local AI baseline.

See the official [ecosystem](https://rubyllm.com/ecosystem/),
[sandbox](https://rubyllm.com/sandboxes/), and
[skills](https://rubyllm.com/skills/) guides. Upgrade dependencies against the
[starter and platform compatibility plan](rubyllm-upgrade.md).

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

# Building with agents

Use native RubyLLM agents and tools inside normal Rails application boundaries.
Start with [agent foundations](agent-foundations.md), then choose the smallest
integration your feature needs.

| Need | Entry point | Application responsibility |
| --- | --- | --- |
| A typed answer | `RubyLLM.chat.with_schema(...)` or an agent `schema` | Authorize inputs, validate business rules and render the result. |
| A conversation in the existing UI | Named `ApplicationAgent` purpose + `ChatRun` | Original actor, scoped records and durable dispatch. |
| Slow tool work | `RubyLLM::Task` + normal Active Job | Persist a business-operation reference, perform the work and resume with its result. |
| Scheduled/webhook automation | Database `Agent` + `AgentDelivery` | Worker identity, trigger deduplication and application authorization. |
| Quality/cost measurement | `RubyLLM::Evaluation` | Reviewed fixtures, assertions and an explicit opt-in command. |

A standalone native chat or agent call does not automatically create a `ChatRun`,
enforce workspace permissions or appear in the starter UI. Use
`RubyLLM.with_owner(your_record)` to attribute usage when calling outside the
chat job. The database `Agent` stores a worker's configuration; it is distinct
from a Ruby class derived from `RubyLLM::Agent`.

## Define behavior on a purpose

Subclass `ApplicationAgent`, declare native tools/instructions/schema, then
register an application-owned name in `ChatPurpose.registry`. See
[named purposes](chat_purposes.md). `ChatStreamJob.perform(run_id)` reconstructs
that purpose on every delivery; feature code does not belong in the job.

Native purpose callbacks compose with the worker callbacks. Use the native
`before_tool_call`, `around_tool_call`, and `after_message` declarations when a
feature needs them; each business operation still enforces its own access. A
persisted chat keeps its saved model during binding/resume; select it before
starting work as described in [named purposes](chat_purposes.md#ownership-and-provider-choices).

Feature agents can declare their tools directly. `ToolsetService` is the default
assistant's toolset and the allowlist for database-backed worker selections.
Add optional selectable tools to `additional_tool_classes`; do not give every
assistant a feature tool merely to make one purpose work.

## Structured output

Create an application schema and agent:

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

`InvoiceExtractionAgent.new.ask(text).parsed` returns the structured hash;
`.content` is JSON text. This standalone call uses your configured provider.
Authorize the supplied text and validate domain rules before saving any result.
A schema verifies shape, not factual correctness.

## Tools and authorization

Tools inherit directly from `RubyLLM::Tool`. Declare input with `parameters do`.
The constructor receives the scoped chat and original member from its purpose.
This example assumes the application has a workspace-owned `Customer` model:

```ruby
class LookupCustomerTool < RubyLLM::Tool
  description "Look up a customer by email address in the member's workspace."

  parameters do
    string :email, required: true
  end

  def initialize(chat:, member:)
    @chat = chat
    @member = member
  end

  def execute(email:)
    @member.reload
    raise Pundit::NotAuthorizedError unless @chat.member_exists?(@member)

    customer = @member.workspace.customers.find_by(email: email)
    return { found: false } unless customer

    # Apply any additional Customer policy before returning customer data.
    { found: true, id: customer.to_param, name: customer.name }
  end
end

class CustomerSupportAgent < ApplicationAgent
  instructions "Help the member find their customer records."
  tools { [LookupCustomerTool.new(chat: chat, member: run_context.member)] }
end
```

Chat participants can belong to different workspaces. Pick and authorize the
resource scope deliberately; do not infer access from a matching chat ID or from
a model-generated identifier. Prefix IDs are virtual: use `find` or
`find_by_prefix_id`, never `find_by(prefix_id: ...)`.

For expected failures, return a small stable domain error. Unexpected failures
should reach the normal error handler with a generic user-facing message. Do
not return raw `exception.message`, SQL, provider bodies or credentials to the
model or conversation participants.

## Human decisions and business effects

Use native `requires_approval` for actions needing confirmation. RubyLLM persists
the question and parks the run; the authenticated question routes call native
`approve`, `decline` or `answer`. Do not write internal approval columns.

Confirmation never substitutes for authorization. The default permits the
requester or chat owner to decide; products requiring a distinct approver must
add that business policy. Recheck permissions when the effect executes, even
when an earlier approval was valid. A tool using `ask` starts again from its
beginning after an answer, so ask before performing an effect.

For local effects, use a business-operation key and database transaction. For
external effects, use provider idempotency or an explicit reconciliation path.
A repeated business request can appear under a different tool-call ID, so a
per-call key alone is insufficient.

See [native task recipe](native-task-recipe.md): it uses a prepared immutable
report, an approval-gated tool, a normal Rails job and one publication per
workspace business key. `Examples::RenameChatTool` remains a smaller reversible
confirmation example in the optional debug toolset.

## Deferred tools

A slow tool returns a native `RubyLLM::Task` carrying a persisted operation
reference. RubyLLM stores the task on the tool call. A later delivery invokes
`Tool#resume`; it reads the operation and returns a task that is still waiting
or the finished result. It does not execute the original command again or add a
new user message.

Use plain `ApplicationJob` subclasses for work and Rails retry facilities for
explicitly retryable failures. Domain records own progress, cancellation and
evidence. A task cancellation hook must connect cancellation to the business
job; native task state alone cannot stop an arbitrary application job.

Working tasks are polled by durable delivery. `input_required` tasks remain
parked until an authorized application callback invokes
`run.resume_tasks!(explicit: true)`. The browser displays state; it does not
schedule execution. Refer to the runnable recipe instead of implementing a
second task base class, continuation-depth loop or progress polling tool.

## Instructions and source material

Application instructions express trusted policy. Mentioned records, document
text, tool results and compaction summaries are source material. The default
assistant keeps mentioned records and summaries in user-role content through
`Message#to_llm`, and native results remain tool content. Never elevate record
text into instructions. Role separation helps, but authorization and constrained
business operations remain the enforcement boundary.

Keep the default context small. Add source material only when needed, and measure
its effect on accepted outcomes and token usage. Feature purposes do not need
the general assistant's complete toolset.

## Limits, caching and provider choices

`Rails.configuration.x.llm.tool_options` defaults to `{ rounds: 25, calls: 50 }`.
Native agent subclasses can override `tool_options`. `calls` limits tools from
one model response; `rounds` bounds one completion loop. A pause/resume begins
another completion, so these limits are not lifetime run, token or spending
budgets. Exhaustion preserves completed results and marks the run failed.

Request/response body logging is disabled. Keep application logs free of
credentials and private source text too. `LLM_PROMPT_CACHING=true` enables a stable
instruction prefix; verify hits through reported cache-read usage. Set
`LLM_FALLBACK_MODELS` only when you have configured and verified every fallback's
credentials and required capabilities. Fallbacks can change providers and cost.

## Provider-free tests and explicit evaluations

RubyLLM's test helper keeps the real loop and supplies scripted model replies:

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

Use `stub_replies tool_call(:your_tool, argument: "value"), "Done"` for real tool
execution. This verifies application behavior, not model quality. Deferred-tool
specs should verify original actor, restart/resume, duplicate delivery,
cancellation, denied access and effect identity.

Quality evaluation needs actual model outputs on reviewed examples. Define a
native evaluation and dataset; this example assumes the extraction agent above:

```ruby
class InvoiceEvaluation < RubyLLM::Evaluation
  evaluator false

  def perform(input)
    raise "Set RUN_LIVE_LLM_EVALS=true" unless ENV["RUN_LIVE_LLM_EVALS"] == "true"
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

```sh
RUN_LIVE_LLM_EVALS=true bin/rails "ruby_llm:eval[InvoiceEvaluation]"
```

`evaluator false` removes grading calls, not the application call. Keep live
requests out of the default test suite. Native reports include verdicts and
usage under `tmp/evaluations`; use deterministic business assertions first and
inspect grader disagreements when model grading is needed. These reports measure
application inference, not the coding-agent tokens used to build the feature.
See the [evaluation guide](https://rubyllm.com/evaluations/).

## Optional integrations

Core RubyLLM already supplies schemas, MCP, skills, evaluations and
instrumentation. Add application configuration only for a concrete capability:

- Use `Schematist::Schema`; no legacy schema forwarding gem is needed.
- For MCP, configure Active Record encryption from ENV before storing credentials,
  authorize server/tool selection, and verify reconnect/revoke and resume behavior.
  Core MCP does not need the competing `ruby_llm-mcp` package.
- Sandboxed code execution requires the native sandbox dependency and an explicit
  paths/network/runtime policy. It is unnecessary for ordinary Ruby tools.
- OpenTelemetry needs the native integration plus an SDK/exporter and tracing
  destination. Do not add the old placeholder tracing or evaluation packages.

See the official [MCP](https://rubyllm.com/mcp/),
[sandbox](https://rubyllm.com/sandboxes/) and [skills](https://rubyllm.com/skills/)
guides. Keep the [webhook delivery guide](webhooks.md) and
[release exercises](llm_release_exercises.md) with the implementation as it evolves.

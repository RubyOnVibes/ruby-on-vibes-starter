---
name: ruby-llm-tools-conventions
description: Use when creating or modifying RubyLLM tools in app/tools
---

# RubyLLM tool conventions

Use `RubyLLM::Tool` directly. Declare feature tools on the named
`ApplicationAgent` that needs them; they do not need to become default assistant
tools. `ToolsetService` supplies the default assistant and the code-owned
allowlist for database-backed worker selections. Use `additional_tool_classes`
for optional selectable tools, and keep defaults small.

## Input and context

Use `parameters do` for tool inputs. It is distinct from provider request
configuration. The purpose supplies trusted context through the constructor;
the model supplies only the declared parameters.

```ruby
class LookupCustomerTool < RubyLLM::Tool
  description "Find a customer in the member's workspace by email."

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

    # This example assumes the application defines workspace-owned customers.
    # Apply any additional Customer policy before returning record data.
    customer = @member.workspace.customers.find_by(email: email)
    customer ? { id: customer.to_param, name: customer.name } : { found: false }
  end
end

class CustomerSupportAgent < ApplicationAgent
  instructions "Help the member find their customer records."
  tools { [LookupCustomerTool.new(chat: chat, member: run_context.member)] }
end
```

A constructor used through `ToolsetService` must accept the context that service
passes; direct purpose declarations can choose a narrower constructor. Do not
infer a member or workspace from model arguments or ambient `Current` state.

## Authorization and trust

- The run's original actor remains the actor after approval, resume or restart.
- Recheck current permissions inside every effect and in its asynchronous job.
- Chat participants can belong to different workspaces. Deliberately authorize
  the intended domain scope; chat participation alone does not grant access to
  every record in the chat's workspace.
- Prefix IDs are virtual. Use `find` or `find_by_prefix_id`, never
  `find_by(prefix_id: ...)`.
- Source records and tool results are untrusted content, not policy instructions.
  Keep them in message/tool content and enforce permissions in code.

## Human decisions

Declare `requires_approval` when an action needs human confirmation. RubyLLM
persists the question; use its native question/approval methods through the
application's authenticated routes. Approval does not replace authorization.
A separate-approver requirement belongs in the business policy.

A tool that uses `ask` executes again from its beginning after an answer. Ask
before effects, and make repeated business requests safe with operation-level
keys, transactions or provider idempotency. A tool-call ID cannot deduplicate
another call proposing the same business command.

## Slow work

Return a `RubyLLM::Task` with a persisted business-operation reference. Use
`resume(task, **arguments)` to read progress and return either continued waiting
or the result. A normal `ApplicationJob` performs work. The native task is not a
job queue, universal business model, or automatic cancellation of that job.
Connect its cancellation callback to the operation's explicit policy.

See `docs/native-task-recipe.md` and the `Examples::PublishReportTool` /
`Examples::ReportPublicationTask` / `Examples::PublishReportJob` implementation.
Do not create another task base class, synthetic user turn or polling tool.

## Results and failures

Return a hash/string for a normal result, use native rich content for files, and
use `halt` only when a direct result should stop the model loop. Keep result data
bounded. Use native schema declarations for structured model answers.

Return stable domain errors for expected failures. Let unexpected errors reach
the generic application error handler; never expose `exception.message`, SQL,
provider bodies, credentials or internal stack details in tool results. Log only
safe diagnostic identifiers and exception classes where practical.

## Verification

Use `RubyLLM::TestHelper` with the real conversation loop and scripted replies.
Verify authorization, denial, duplicate delivery, lost delivery, resume, revoked
access and effect identity. Add checks across different calls/runs for business
idempotency. Run provider-based quality evaluations only through explicit opt-in
commands; fixture replies do not prove model quality.

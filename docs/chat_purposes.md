# Named chat purposes

Each persisted `Chat` has an application-owned `purpose`, defaulting to
`assistant`. `ChatPurpose.registry` maps names to native `ApplicationAgent`
subclasses. Unknown names fail closed. Each durable delivery binds the authorized
chat and rebuilds the purpose's declarations for its original initiating actor.

## Add a feature

```ruby
class DocumentReviewAgent < ApplicationAgent
  instructions "Review the provided document and identify missing details."
  tools { [ReviewDocumentTool.new(chat: chat, member: run_context.member)] }
  file_store
end

# In ChatPurpose:
def self.registry
  { "assistant" => ChatAgent, "document_review" => DocumentReviewAgent }
end
```

Create the chat with `purpose: "document_review"` in an authorized application
flow. Add schemas, native tasks, questions, approval rules or MCP configuration
using RubyLLM declarations on that agent. Do not modify `ChatStreamJob` to add
feature-specific behavior. The [native task recipe](native-task-recipe.md) supplies
an opt-in example purpose with an approved background operation.

`run_context` exposes `chat`, `run`, `member`, and the original `user_message`.
The original actor must still have access when execution resumes; the approver or
worker's ambient request context never replaces that actor. Purpose changes are
rejected while a run or native conversation claim is active. Each business tool
must still authorize the actual resources and effects it uses.

## Source content and instructions

The default `ChatAgent` declares a small policy and any trusted instructions from
its configured database `Agent`. Mentioned record data and compaction summaries
are added to user-role content by `Message#to_llm`. Native tool results stay in
tool messages. Do not interpolate untrusted records, document text or prior model
output into application instructions. Source content is evidence, not authority.

`LLM_PROMPT_CACHING=true` opts into caching a stable instruction prefix. Source
content remains outside that prefix. Provider cache requirements still apply;
inspect the reported cache-read usage rather than assuming a cache hit.

## Tool selection

Feature purposes declare their tools directly. They do not inherit the general
assistant's tools. The database `Agent` is an optional workspace worker identity
for schedules and webhooks; it is separate from a `RubyLLM::Agent` class.

For the default assistant and database-backed Agent selections,
`ToolsetService.registry` is the code-owned allowlist. Add optional tools to
`additional_tool_classes` only when they should be selectable by those workers.
`tool_config: nil` uses defaults; `tool_config: []` grants no application tools.
An explicit selection receives exactly its selected application tools. Unknown
or disabled names fail validation and execution; they are never resolved into
arbitrary Ruby constants. Native file tools are a separate `file_store`
declaration.

## Ownership and provider choices

The chat job attributes usage to `ChatRun` with `RubyLLM.with_owner(run)`. Calls
outside that job must establish their own usage owner explicitly. Do not set
`chat.with_owner` merely to track per-run cost: it also changes file-store
ownership. A purpose's `file_store` uses the shared authorized chat and Rails
Active Storage.

`LLM_FALLBACK_MODELS` explicitly overrides model fallbacks. Configure credentials
and verify tool/schema support for every listed model; fallback changes may alter
provider choice and billing.

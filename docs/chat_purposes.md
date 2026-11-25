# Named chat purposes

Each persisted `Chat` has a `purpose`, defaulting to `assistant`. `ChatPurpose`
maps these application-owned names to native `ApplicationAgent` subclasses.
Every durable run rebuilds that agent's tools and instructions on the existing
chat. Unknown names fail closed; a request cannot choose an arbitrary Ruby class.

The default `ChatAgent` retains the starter's tools, explicit mentions, sender
and participant context, compaction summary, and background task results.
`ChatAgentContext` builds that context and gives tools the run's initiating
member. A continuation or an approval never adopts the identity of the person
who happened to trigger the worker. Runtime instructions do not rewrite the
persisted transcript. `LLM_PROMPT_CACHING=true` enables a stable instruction
prefix; environment and per-turn context remain after its cache boundary.

To add application behavior, create a native agent and register it in
`ChatPurpose.registry`:

```ruby
class DocumentReviewAgent < ApplicationAgent
  instructions "Review the provided document and explain any missing details."
  tools { [ReviewDocumentTool.new(chat: chat, member: run_context.member)] }
  file_store
end

def self.registry
  { "assistant" => ChatAgent, "document_review" => DocumentReviewAgent }
end
```

Set `purpose: "document_review"` when your authorized application flow creates
the chat. Add schemas, tools, native tasks, approval policies, or MCP configuration
to that agent using RubyLLM's declarations. If the feature needs the starter's
context, declare `instructions(append: true, persist: false) {
run_context.dynamic_instructions }` after its own instructions. `run_context`
also exposes `chat`, `run`, and the optional original `user_message`.

`ChatPurpose.bind(chat:, run:, user_message:, options:)` returns a configured
ActiveRecord Chat. It binds the already scoped record; it does not find a chat
from untrusted identifiers. The run must belong to that chat and its initiating
member must still participate. Purpose changes while work is active are rejected
by the Chat model. Tools must still authorize every resource or effect they use.

The persisted `Agent` model remains the optional workspace worker identity used
by schedules and webhooks. It is separate from a native `RubyLLM::Agent` class.
The assistant purpose continues to honor a persisted Agent's instructions and
tool configuration through `ToolsetService`.

Persisted tool selections resolve through `ToolsetService.registry`, built from
the enabled default tools and `additional_tool_classes`. Register an optional
application tool in the latter when only selected workers should receive it.
`tool_config: nil` uses defaults; `tool_config: []` enables no application tools.
An explicit selection receives exactly those application tools, without silently
adding task-management capabilities. Native file tools remain a separate agent
declaration. Unknown or disabled tool names fail validation and execution instead
of resolving arbitrary Ruby constants or silently changing permissions.

Usage remains attributed to `ChatRun` with `RubyLLM.with_owner(run)`. Do not add
`owner` or call `chat.with_owner` simply to organize files: that also changes
usage attribution. The default native file store is shared within the authorized
conversation. A purpose enables it with `file_store`; Rails Active Storage
provides persistence. `LLM_FALLBACK_MODELS` is an explicit application override
for comma-separated fallback models and can affect provider choice and billing.

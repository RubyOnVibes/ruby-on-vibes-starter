# LLM and Agent Release Exercises

Use this checklist after changing RubyLLM, models, chat streaming, tools, agent
tasks, compaction, or the chat UI. Automated specs remain the primary safety net;
these exercises verify behavior that depends on a live model and browser.

## Setup

1. Use a disposable development database and sign in as the chat owner.
2. Configure one supported provider key.
3. Enable the reference tools:

   ```env
   LLMS_ENABLED=true
   VIBES_DEBUG_TOOLS=true
   ```

4. Open the browser console and application logs. Start each numbered group in a
   fresh chat unless it explicitly tests conversation history.
5. Record provider, model, result, and any unexpected tool calls. Model wording
   may vary; verify persisted state and transitions rather than exact prose.

## Core tool loop — run every release

### 1. Parallel tools

> Roll a d20 and tell me what time it is.

Pass:

- `random_number` and `current_date_time` both run.
- Both results render before one final assistant response.
- The ChatRun finishes `completed`.

### 2. Dependent tools

> Roll a d100. Then roll another die where the maximum is whatever you just rolled.

Pass:

- The second call uses the first result.
- The tool chain completes without duplicate or orphaned result messages.

### 3. Text followed by a tool

> First explain what you are about to do, then roll 3d6.

Pass:

- Text and a tool request can coexist in the assistant turn.
- The final answer includes the roll.

### 4. Parallel calls to one tool

> Roll a d4, a d6, a d8, and a d20 all at once.

Pass:

- Four calls, or one equivalent batched call, execute successfully.
- Every requested result is present.

### 5. Cross-tool dependency

> What time is it? Then roll a die where the maximum is the current minute.

Pass:

- The time result determines the die range.
- No polling or repeated tool call occurs.

### 6. Three-round chain

> Roll a d20. Roll that many d6s. Then tell me the time and whether the d6 total is greater than the current hour.

Pass:

- All dependent rounds complete in order.
- The final comparison uses the returned values.

### 7. Model-selected chain

> Get the time in Tokyo and New York, then randomly choose which timezone I should use for a meeting.

Pass:

- Both timezone calls precede the random choice.
- One final response explains the result.

## Agent tasks — run when agent-task code changes

### 8. One task and automatic continuation

> Run the echo task with the message “hello from Puerto Rico” and a duration of 2 seconds.

Pass:

- The first turn queues the task without polling.
- The ChatRun enters `awaiting_tasks`.
- Completion triggers one automatic continuation.
- The final response summarizes the result and the run becomes `completed`.

### 9. Parallel tasks

> Run two echo tasks for 2 seconds: one saying “task A” and one saying “task B”.

Pass:

- Exactly two tasks are created.
- Continuation waits until both are terminal and fires only once.

### 10. Cancellation

Start a 10-second echo task, then press Stop while it is running.

Pass:

- ChatRun and active task become `cancelled`.
- The composer unlocks immediately.
- No later continuation or duplicate result appears.

### 11. Parent task, subtask, and effects

> Run the side-effects exercise with one subtask.

Pass:

- Parent and child tasks complete.
- The task detail shows all expected effect types without duplicates.
- One continuation summarizes only this run's tasks.

### 12. Failed background task

> Run the failing task.

Pass:

- Retries follow the configured policy.
- The task ends `failed` with a useful error.
- The chat remains usable and the continuation reports failure without polling.

## Human-approved tools — run every release

### 13. Approve a reversible write

Before starting, note the current chat name.

> Rename this chat to “Approval Exercise”.

Pass:

- The ChatRun enters `awaiting_approval`.
- A card shows the exact tool name and arguments.
- The name has not changed before approval.
- Approve once. The same run resumes, the tool executes once, the name changes,
  and the model gives a final response.
- Refreshing while parked does not lose the approval card.

### 14. Deny a write

> Rename this chat to “This Must Not Be Applied”.

Pass:

- Deny the approval request.
- The title never changes.
- RubyLLM receives a structured denial and produces a final response.
- The run becomes `completed`, not stuck.

### 15. Authorization remains inside the tool

Invite a non-owner to a group chat and have that member request a rename.

Pass:

- Approval does not bypass application authorization.
- The tool returns “Only the chat owner can rename this chat.”
- The title remains unchanged.

### 16. Cancel while awaiting approval

Request another rename, then press Stop instead of approving or denying.

Pass:

- The run becomes `cancelled`.
- The pending call cannot be approved afterward.
- A new user message can start a clean run.

## Usage and resilience — run when configuration changes

### 17. Run accounting

Complete any tool exercise and inspect the small usage line under the final answer
and the corresponding `ChatRun`.

Pass:

- Attempts include every physical provider request, including tool rounds.
- Input/output token totals are populated when reported.
- Cost is shown only when RubyLLM has defensible pricing.
- Cancellation or a failed attempt is not silently reported as zero cost.

### 18. Prompt caching

Set `LLM_PROMPT_CACHING=true`. Use an agent with stable instructions long enough
to meet the selected provider's caching minimum, then send two similar turns.

Pass:

- Both turns succeed normally.
- The later ChatRun reports positive `cache_read_tokens` when the provider
  actually returns a cache hit.
- Per-turn mentions, participant context, and task results remain current; they
  must not be reused from the cached prefix.

Unset the flag after the exercise.

### 19. Model fallbacks

Configure two provider credentials and set, for example:

```env
LLM_FALLBACK_MODELS=gpt-5-nano,claude-haiku-4-5
```

Use a controlled adapter/spec to make the primary raise a transient timeout; do
not induce a production outage manually.

Pass:

- A configured fallback handles only a supported transient error.
- Tools and instructions remain attached.
- Run accounting includes failed and successful attempts.

### 20. Attachment replay

Upload a small image or PDF and ask for a concrete fact from it. Follow up with a
question that depends on the same file.

Pass:

- The first answer uses the attachment.
- The follow-up replays valid attachment context without duplicating messages.
- Unsupported file errors leave the chat usable.

### 21. Compaction

Use a disposable chat and temporarily lower its compaction threshold. Create
enough turns, including a completed tool chain, to trigger compaction.

Pass:

- Compaction never splits an assistant tool request from its tool result.
- Recent turns remain verbatim and older context is represented by the summary.
- The next live response succeeds and uses relevant facts from before compaction.

## Failure triage

For any failure, preserve:

- ChatRun id and status history.
- Message ids/roles around the failure.
- Tool-call id, approval value, and result relationship.
- AgentTask ids and effects.
- RubyLLM usage rows for the run.
- Provider/model and server logs.

Never paste provider keys, webhook tokens, message contents containing private
customer data, or raw credentials into an issue.


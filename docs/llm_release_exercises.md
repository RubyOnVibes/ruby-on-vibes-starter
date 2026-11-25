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

## Native deferred tools — run when task execution changes

Use the opt-in [native task recipe](native-task-recipe.md) and its prepared report
fixture for this group. Register its named purpose in the test application; the
example is not enabled in ordinary assistant chats. Run `bin/jobs` separately
from the web process. No legacy task runner or browser scheduler is involved.

### 8. Approval, background work, and resume

Ask the report-publication agent to publish a prepared report, then approve it.

Pass:

- No publication occurs before the authorized approval.
- The approved tool returns a native task and the ChatRun enters `awaiting_tasks`.
- A normal Rails job performs the business operation.
- The same tool call resumes with the saved operation result; `execute` does not
  run again and no synthetic user message is created.
- The final assistant response completes the original run.

### 9. Restart and duplicate delivery

Stop and restart the worker while the native task is parked, then deliver the
same job more than once.

Pass:

- The original actor and input survive.
- One business publication exists, and the tool returns its stable result.
- A delayed duplicate cannot mark a live execution failed or complete it early.

### 10. Cancellation and revoked access

Pause work before publication, then cancel the run or revoke the initiating
member's access before allowing the job to continue.

Pass:

- The operation does not publish after cancellation or authorization revocation.
- The task's cancellation hook applies the application's cancellation policy;
  native task state alone is not proof that an arbitrary background job stopped.
- Another participant's approval never substitutes that participant as actor.

### 11. Repeat the same business command

Request the same publication again through a new tool call or a new run.

Pass:

- The workspace's business publication key identifies the same operation.
- Exactly one publication effect exists, including concurrent deliveries.
- Changing the approved input requires a new reviewed operation; it cannot
  silently change the evidence associated with the earlier approval.

### 12. Lost job delivery

Use a controlled fixture to fail enqueueing or lose the business job delivery
while the publication remains queued.

Pass:

- The durable operation remains queued without a partial effect.
- Native task polling can request delivery again after the queue recovers.
- Duplicate recovered deliveries still produce one publication.
- Recovery needs neither a new user turn nor an open browser.

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
- Per-turn source records and native tool results remain current; they
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
- Native tool task data and the linked business operation/effect identity.
- RubyLLM usage rows for the run.
- Provider/model and server logs.

Never paste provider keys, webhook tokens, message contents containing private
customer data, or raw credentials into an issue.


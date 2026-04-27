# Notifications

[Noticed](https://github.com/excid3/noticed) lets your app send notifications to people, in many ways—like email, text, Slack, or live in the browser.

You can:

- Send one notification to many people (bulk)
- Or send a separate notification to each person (individual)

Recommended:

- Use Noticed for notifications
- Denormalize display data in notification params (see below)

## Denormalizing Data

**Why:** Notifications often outlive the records they reference. If a record is deleted, the notification should still display a meaningful message.

**How:** Pass display strings (names, titles) as separate params alongside record associations:

```ruby
# When delivering, include denormalized display values:
SomeNotifier.with(
  record: some_record,
  actor_name: actor.name,       # denormalized
  target_name: target.name      # denormalized
).deliver(recipient)
```

```ruby
# In notifier, prefer params over association lookups:
def actor_name
  params[:actor_name] || params[:record]&.actor&.name || "Someone"
end
```

**When:** Always denormalize any data used in notification messages. Assume any referenced record could be deleted before the user views the notification.

See the [Noticed docs](https://github.com/excid3/noticed) for details.
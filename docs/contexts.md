# Structured record data

`RecordContext` is an optional application serializer. Use it when a tool or
feature needs a stable data shape; plain hashes or `mentionable_summary` are
usually sufficient. A schema describes source data and does not make that data
trusted policy or enforce access to the underlying record.

## Default mention behavior

`Message#to_llm` enriches referenced records with their bounded
`mentionable_summary` and link in user-role content after checking the current run actor’s access.
Unknown actors and inaccessible records remain opaque placeholders. It uses `to_llm_mention`, not
an automatic dump of each record's full context schema. Keep summaries concise
and suitable for the conversation's audience:

```ruby
class Project < ApplicationRecord
  include Mentionable

  def mentionable_summary
    "Project #{name}, status: #{status}"
  end
end
```

## Explicit structured serialization

When a feature needs more detail, define a serializer:

```ruby
# app/models/contexts/project_context.rb
class ProjectContext < RecordContext
  schema do
    description "Project data"
    string :id
    string :name
    string :status
  end

  def self.from_record(project)
    new(id: project.to_param, name: project.name, status: project.status)
  end
end
```

`project.to_llm_context` discovers `ProjectContext` through `Mentionables`; without
a matching class it falls back to the lightweight `to_llm_mention` hash. The
returned context supports `to_h`, `to_json`, and `to_json_schema`.

Call this only after scoping and authorizing the record for the current actor
and conversation audience. Return the serialized data in a tool result or other
source-content message. Defining a serializer does not automatically include
it in chat instructions or grant permission to expose the record.

RecordContext checks required fields. It does not validate every value's type
or business rules; enforce those with model/domain validation. If the model must
produce structured output, use `Schematist::Schema` directly on the native agent
as shown in [building with agents](building_with_agents.md).

# RecordContexts

Schema-driven LLM context serialization for Rails models.

## What is This?

`RecordContext` provides a standardized way to serialize ActiveRecord models for LLM consumption. Contexts use **JSON Schema** to define structure and enable validation.

## Why Use RecordContext?

**Before (ad-hoc strings):**
```ruby
"Workspace: #{org.name}, Type: #{org.personal? ? 'Personal' : 'Team'}, Members: #{org.members_count}"
```

**After (schema-driven):**
```ruby
WorkspaceContext.from_record(org).to_json
# {
#   "id": "org_xxx",
#   "name": "Acme Corp",
#   "type": "team",
#   "members_count": 5,
#   "owner": { ... }
# }
```

**Benefits:**
- ✅ **Type Safety**: Schema defines expected structure
- ✅ **Consistency**: Same model always serialized identically
- ✅ **Validation**: Catches bugs in development
- ✅ **Self-Documenting**: Schemas describe themselves
- ✅ **LLM-Friendly**: Structured data performs better than prose

## Quick Start

### 1. Define a Context

```ruby
# app/models/contexts/project_context.rb
class ProjectContext < RecordContext
  schema do
    description "A project within an workspace"
    
    string :id, description: "Prefixed project ID"
    string :name, description: "Project name"
    string :status, enum: ['active', 'archived'], description: "Project status"
    integer :tasks_count, minimum: 0
    
    object :owner do
      string :name
      string :email, format: 'email'
    end
  end
  
  def self.from_record(project)
    new(
      id: project.to_param,
      name: project.name,
      status: project.archived? ? 'archived' : 'active',
      tasks_count: project.tasks.count,
      owner: {
        name: project.owner.full_name,
        email: project.owner.email
      }
    )
  end
  
  def summary
    "#{data[:name]} (#{data[:status]}, #{data[:tasks_count]} tasks)"
  end
end
```

### 2. Integrate with Model

```ruby
# app/models/project.rb
class Project < ApplicationRecord
  include Mentionable

  # Mentionable automatically uses ProjectContext if it exists
  # via to_llm_context method
end
```

### 3. Use in Chat

Contexts are automatically used when models are @mentioned in chat.
The LLM receives structured JSON instead of ad-hoc strings.

## Schema DSL

RecordContext uses [RubyLLM::Schema](https://github.com/danielfriis/ruby_llm-schema) for schema definitions.

### Primitive Types

```ruby
schema do
  string :name, description: "User's name"
  integer :age, minimum: 0, maximum: 120
  number :price, minimum: 0.0
  boolean :active
  null :placeholder
end
```

### String Constraints

```ruby
string :email, format: 'email'
string :status, enum: ['draft', 'published', 'archived']
string :code, min_length: 3, max_length: 10
string :phone, pattern: '\d{3}-\d{3}-\d{4}'
```

### Objects

```ruby
object :address do
  string :street
  string :city
  string :country, required: false
end
```

### Arrays

```ruby
array :tags, of: :string
array :scores, of: :number

array :items do
  object do
    string :name
    number :quantity
  end
end
```

### Optional Fields

```ruby
string :middle_name, required: false
integer :phone_number, required: false
```

### Enums

```ruby
string :status, enum: ['pending', 'active', 'suspended']
string :role, enum: ['admin', 'member', 'guest']
```

## Best Practices

### 1. Keep Schemas Focused

Only include fields relevant for LLM understanding:

```ruby
# ✅ Good - LLM-relevant fields
schema do
  string :name
  string :status
  integer :tasks_count
end

# ❌ Bad - internal implementation details
schema do
  string :encrypted_password
  string :reset_password_token
  datetime :last_synced_at
end
```

### 2. Add Descriptions

Help the LLM understand field meaning:

```ruby
string :status, 
  description: "Project status - active projects are in progress, archived are complete",
  enum: ['active', 'archived']
```

### 3. Use Enums for Constrained Values

```ruby
# ✅ Good - enum ensures consistency
string :priority, enum: ['low', 'medium', 'high']

# ❌ Bad - string allows any value
string :priority
```

### 4. Nest Related Data

```ruby
object :owner do
  string :name
  string :email
end

# Better than:
# string :owner_name
# string :owner_email
```

### 5. Implement `summary` Method

Provide human-readable summaries:

```ruby
def summary
  "#{data[:name]} (#{data[:status]}, #{data[:tasks_count]} tasks)"
end
```

## Example: Full Implementation

```ruby
# app/models/contexts/invoice_context.rb
class InvoiceContext < RecordContext
  schema do
    description "A customer invoice with line items and payment status"
    
    string :id, description: "Invoice ID (inv_xxx)"
    string :number, description: "Human-friendly invoice number"
    string :status, 
      enum: ['draft', 'sent', 'paid', 'overdue'],
      description: "Payment status"
    
    number :amount, description: "Total amount in dollars"
    string :currency, description: "Currency code (USD, EUR, etc)"
    
    object :customer do
      string :name
      string :email, format: 'email'
    end
    
    array :line_items do
      object do
        string :description
        integer :quantity, minimum: 1
        number :unit_price
        number :total
      end
    end
    
    string :due_date, description: "Payment due date (ISO8601)"
    string :issued_at, description: "Invoice issue date (ISO8601)"
  end
  
  def self.from_record(invoice)
    new(
      id: invoice.to_param,
      number: invoice.number,
      status: invoice.status,
      amount: invoice.total_amount.to_f,
      currency: invoice.currency,
      customer: {
        name: invoice.customer.name,
        email: invoice.customer.email
      },
      line_items: invoice.line_items.map do |item|
        {
          description: item.description,
          quantity: item.quantity,
          unit_price: item.unit_price.to_f,
          total: item.total.to_f
        }
      end,
      due_date: invoice.due_date.iso8601,
      issued_at: invoice.created_at.iso8601
    )
  end
  
  def summary
    status_emoji = { 'draft' => '📝', 'sent' => '📤', 'paid' => '✅', 'overdue' => '⚠️' }
    "#{status_emoji[data[:status]]} Invoice #{data[:number]} - $#{data[:amount]} (#{data[:status]})"
  end
end
```

## Validation

Contexts automatically validate on initialization:

```ruby
# Raises error if required field missing
context = WorkspaceContext.new(name: "Acme")  
# ArgumentError: WorkspaceContext: Missing required field 'id'

# All required fields from schema must be provided
```

## Testing

Test your contexts:

```ruby
# spec/models/contexts/workspace_context_spec.rb
require 'rails_helper'

RSpec.describe WorkspaceContext do
  let(:workspace) { create(:workspace) }
  let(:context) { described_class.from_record(workspace) }
  
  it "serializes workspace" do
    expect(context.id).to eq(workspace.to_param)
    expect(context.name).to eq(workspace.name)
  end
  
  it "has valid schema" do
    schema = context.to_json_schema
    expect(schema[:schema][:properties]).to include(:id, :name, :type)
  end
end
```

## Debugging

Enable validation and inspect schemas:

```ruby
# In console
context = WorkspaceContext.from_record(Workspace.first)

context.to_h          # => Hash of data
context.to_json       # => JSON string
context.summary       # => "Team workspace 'Acme Corp' (5 members)"
context.to_json_schema  # => Full JSON Schema
```

## Migration Guide

### From String-Based Context

**Before:**
```ruby
def build_workspace_context
  "Workspace: #{org.name}, Type: #{org.type}, Members: #{org.members_count}"
end
```

**After:**
```ruby
def build_workspace_context
  context = WorkspaceContext.from_record(@chat.workspace)
  context.to_json
end
```

### From Hash-Based Context

**Before:**
```ruby
def to_llm_mention
  {
    name: name,
    type: type,
    members_count: members_count
  }
end
```

**After:**
```ruby
# Define schema once in WorkspaceContext
# Use everywhere via to_llm_context
@chat.workspace.to_llm_context.to_h
```

## Resources

- [RubyLLM Documentation](https://ruby-llm.com)
- [RubyLLM::Schema DSL](https://github.com/danielfriis/ruby_llm-schema)
- [JSON Schema Spec](https://json-schema.org/)

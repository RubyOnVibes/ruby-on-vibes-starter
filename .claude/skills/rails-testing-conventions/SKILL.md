---
name: rails-testing-conventions
description: Use when creating or modifying specs in spec/
---

# Rails Testing Conventions

Conventions for RSpec tests in this Ruby on Vibes app.

## Stack Context

This app uses:
- **RSpec** for testing (not Minitest)
- **FactoryBot** for test data
- **Shoulda Matchers** for one-liner tests
- **VCR/WebMock** for external HTTP

## Core Principles

1. **Test behavior, not implementation** - Focus on what, not how
2. **One assertion per test** (when practical)
3. **Descriptive test names** - Read like documentation
4. **Fast tests** - Mock external services, avoid database when possible

## File Organization

```
spec/
  models/           # Unit tests for models
  requests/         # Integration tests for controllers
  system/           # End-to-end browser tests
  jobs/             # Background job tests
  services/         # Service object tests
  support/          # Shared helpers and config
  factories/        # FactoryBot factories
```

## Model Specs

```ruby
# spec/models/user_spec.rb
RSpec.describe User, type: :model do
  describe 'associations' do
    it { is_expected.to have_many(:projects) }
    it { is_expected.to belong_to(:account) }
  end

  describe 'validations' do
    it { is_expected.to validate_presence_of(:email) }
  end

  describe '#full_name' do
    let(:user) { build(:user, first_name: 'John', last_name: 'Doe') }

    it 'returns first and last name' do
      expect(user.full_name).to eq('John Doe')
    end
  end
end
```

## Request Specs

```ruby
# spec/requests/projects_spec.rb
RSpec.describe 'Projects', type: :request do
  let(:user) { create(:user) }

  before { sign_in user }

  describe 'GET /projects' do
    it 'returns success' do
      get projects_path
      expect(response).to have_http_status(:success)
    end
  end

  describe 'POST /projects' do
    let(:valid_params) { { project: { name: 'New Project' } } }

    it 'creates a project' do
      expect {
        post projects_path, params: valid_params
      }.to change(Project, :count).by(1)
    end
  end
end
```

## Factory Patterns

```ruby
# spec/factories/users.rb
FactoryBot.define do
  factory :user do
    sequence(:email) { |n| "user#{n}@example.com" }
    password { 'password123' }
    first_name { 'John' }
    last_name { 'Doe' }

    trait :admin do
      admin { true }
    end

    trait :with_projects do
      after(:create) do |user|
        create_list(:project, 3, user: user)
      end
    end
  end
end
```

## Testing Jobs

```ruby
# spec/jobs/send_email_job_spec.rb
RSpec.describe SendEmailJob, type: :job do
  let(:user) { create(:user) }

  it 'sends an email' do
    expect {
      described_class.perform_now(user.id)
    }.to change { ActionMailer::Base.deliveries.count }.by(1)
  end

  it 'handles missing user gracefully' do
    expect {
      described_class.perform_now(-1)
    }.not_to raise_error
  end
end
```

## Quick Reference

| Do | Don't |
|----|-------|
| `let` for lazy evaluation | Instance variables in before blocks |
| `build` when DB not needed | `create` for everything |
| `have_http_status(:success)` | Check exact status codes everywhere |
| Mock external APIs | Hit real external services |
| Test public interface | Test private methods directly |

## Common Mistakes

1. **Testing implementation** - Focus on behavior/outcomes
2. **Slow tests** - Use `build` instead of `create` when possible
3. **Shared state** - Each test should be independent
4. **Not testing edge cases** - nil values, empty strings, etc.
5. **Brittle assertions** - Avoid testing exact error messages
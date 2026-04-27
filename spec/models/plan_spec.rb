# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Plan, type: :model do
  describe 'validations' do
    let(:valid_attributes) do
      {
        name: 'Pro',
        amount: 1999,
        currency: 'usd',
        interval: 'month',
        trial_period_days: 14
      }
    end

    it 'is valid with valid attributes' do
      plan = Plan.new(valid_attributes)
      expect(plan).to be_valid
    end

    it 'requires name' do
      plan = Plan.new(valid_attributes.merge(name: nil))
      expect(plan).not_to be_valid
      expect(plan.errors[:name]).to be_present
    end

    it 'requires amount' do
      plan = Plan.new(valid_attributes.merge(amount: nil))
      expect(plan).not_to be_valid
      expect(plan.errors[:amount]).to be_present
    end

    it 'requires currency' do
      plan = Plan.new(valid_attributes.merge(currency: nil))
      expect(plan).not_to be_valid
    end

    it 'requires 3-letter currency code' do
      plan = Plan.new(valid_attributes.merge(currency: 'us'))
      expect(plan).not_to be_valid
      expect(plan.errors[:currency]).to be_present

      plan.currency = 'usd'
      expect(plan).to be_valid
    end

    it 'requires valid interval' do
      plan = Plan.new(valid_attributes.merge(interval: 'week'))
      expect(plan).not_to be_valid
      expect(plan.errors[:interval]).to be_present
    end

    it 'allows month interval' do
      plan = Plan.new(valid_attributes.merge(interval: 'month'))
      expect(plan).to be_valid
    end

    it 'allows year interval' do
      plan = Plan.new(valid_attributes.merge(interval: 'year'))
      expect(plan).to be_valid
    end

    it 'requires integer trial_period_days' do
      plan = Plan.new(valid_attributes.merge(trial_period_days: 'abc'))
      expect(plan).not_to be_valid
    end
  end

  describe 'currency normalization' do
    it 'downcases currency' do
      plan = Plan.new(currency: 'USD')
      expect(plan.currency).to eq('usd')
    end
  end

  describe 'scopes' do
    let!(:monthly_plan) do
      Plan.create!(
        name: 'Monthly',
        amount: 999,
        currency: 'usd',
        interval: 'month',
        trial_period_days: 0,
        hidden: false
      )
    end

    let!(:yearly_plan) do
      Plan.create!(
        name: 'Yearly',
        amount: 9999,
        currency: 'usd',
        interval: 'year',
        trial_period_days: 0,
        hidden: false
      )
    end

    let!(:hidden_plan) do
      Plan.create!(
        name: 'Hidden',
        amount: 0,
        currency: 'usd',
        interval: 'month',
        trial_period_days: 0,
        hidden: true
      )
    end

    describe '.monthly' do
      it 'returns only monthly plans' do
        expect(Plan.monthly).to include(monthly_plan)
        expect(Plan.monthly).not_to include(yearly_plan)
      end
    end

    describe '.yearly' do
      it 'returns only yearly plans' do
        expect(Plan.yearly).to include(yearly_plan)
        expect(Plan.yearly).not_to include(monthly_plan)
      end
    end

    describe '.visible' do
      it 'returns non-hidden plans' do
        expect(Plan.visible).to include(monthly_plan, yearly_plan)
        expect(Plan.visible).not_to include(hidden_plan)
      end
    end

    describe '.hidden' do
      it 'returns only hidden plans' do
        expect(Plan.hidden).to include(hidden_plan)
        expect(Plan.hidden).not_to include(monthly_plan)
      end
    end

    describe '.sorted' do
      it 'returns plans as an array' do
        sorted = Plan.sorted
        expect(sorted).to be_an(Array)
      end

      it 'sorts monthly plans before yearly plans' do
        sorted = Plan.sorted
        monthly_index = sorted.index(monthly_plan)
        yearly_index = sorted.index(yearly_plan)

        expect(monthly_index).to be < yearly_index
      end

      it 'sorts by amount within same interval' do
        cheap_monthly = Plan.create!(
          name: 'Cheap',
          amount: 100,
          currency: 'usd',
          interval: 'month',
          trial_period_days: 0
        )

        sorted = Plan.sorted
        cheap_index = sorted.index(cheap_monthly)
        monthly_index = sorted.index(monthly_plan)

        # cheap (100) should come before monthly (999)
        expect(cheap_index).to be < monthly_index
      end
    end
  end

  describe '.secret_free_plan' do
    it 'returns a free plan' do
      plan = Plan.secret_free_plan
      expect(plan.name).to eq('Free Plan')
      expect(plan.amount).to eq(0)
    end

    it 'creates the plan if it does not exist' do
      Plan.where(name: 'Free').destroy_all
      expect { Plan.secret_free_plan }.to change { Plan.count }.by(1)
    end

    it 'returns existing free plan without creating duplicate' do
      Plan.secret_free_plan # Create it
      expect { Plan.secret_free_plan }.not_to change { Plan.count }
    end

    it 'sets the plan as hidden' do
      plan = Plan.secret_free_plan
      expect(plan.hidden).to be true
    end
  end

  describe '#monthly?' do
    it 'returns true for monthly interval' do
      plan = Plan.new(interval: 'month')
      expect(plan.monthly?).to be true
    end

    it 'returns false for yearly interval' do
      plan = Plan.new(interval: 'year')
      expect(plan.monthly?).to be false
    end
  end

  describe '#yearly? / #annual?' do
    it 'returns true for yearly interval' do
      plan = Plan.new(interval: 'year')
      expect(plan.yearly?).to be true
      expect(plan.annual?).to be true
    end

    it 'returns false for monthly interval' do
      plan = Plan.new(interval: 'month')
      expect(plan.yearly?).to be false
    end
  end

  describe '#trial_period?' do
    it 'returns true when trial_period_days > 0' do
      plan = Plan.new(trial_period_days: 14)
      expect(plan.trial_period?).to be true
    end

    it 'returns false when trial_period_days is 0' do
      plan = Plan.new(trial_period_days: 0)
      expect(plan.trial_period?).to be false
    end
  end

  describe '#features' do
    it 'returns array even when nil' do
      plan = Plan.new
      expect(plan.features).to eq([])
    end

    it 'returns array when set' do
      plan = Plan.new
      plan.features = ['Feature 1', 'Feature 2']
      expect(plan.features).to eq(['Feature 1', 'Feature 2'])
    end
  end

  describe '#stripe_tax / #taxed?' do
    it 'casts stripe_tax to boolean' do
      plan = Plan.new
      plan.stripe_tax = "1"
      expect(plan.taxed?).to be true

      plan.stripe_tax = "0"
      expect(plan.taxed?).to be false

      plan.stripe_tax = true
      expect(plan.taxed?).to be true
    end
  end

  describe '#display_name' do
    it 'includes interval for monthly plans' do
      plan = Plan.new(name: 'Pro', interval: 'month')
      expect(plan.display_name).to eq('Pro (Monthly)')
    end

    it 'includes interval for yearly plans' do
      plan = Plan.new(name: 'Pro', interval: 'year')
      expect(plan.display_name).to eq('Pro (Yearly)')
    end
  end
end

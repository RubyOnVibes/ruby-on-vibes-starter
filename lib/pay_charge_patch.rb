module PayChargePatch
  extend ActiveSupport::Concern

  included do
    after_create :complete_referral!, if: -> { defined?(Refer) }
    has_prefix_id :ch
  end

  def complete_referral!
    workspace, user = customer.owner, customer.owner.owner
    user.referral&.complete!
  end
end
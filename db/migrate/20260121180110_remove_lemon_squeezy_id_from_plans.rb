class RemoveLemonSqueezyIdFromPlans < ActiveRecord::Migration[8.1]
  def change
    remove_column :plans, :lemon_squeezy_id
  end
end

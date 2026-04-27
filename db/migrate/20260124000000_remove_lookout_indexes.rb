class RemoveLookoutIndexes < ActiveRecord::Migration[8.1]
  def change
    remove_index :ahoy_visits, :started_at, if_exists: true
    remove_index :ahoy_events, :visit_id, if_exists: true
    remove_index :ahoy_events, :time, if_exists: true
  end
end

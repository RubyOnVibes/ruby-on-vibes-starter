class RemoveLevaTables < ActiveRecord::Migration[8.1]
  def up
    drop_table :leva_evaluation_results, if_exists: true
    drop_table :leva_runner_results, if_exists: true
    drop_table :leva_optimization_runs, if_exists: true
    drop_table :leva_experiments, if_exists: true
    drop_table :leva_dataset_records, if_exists: true
    drop_table :leva_prompts, if_exists: true
    drop_table :leva_datasets, if_exists: true
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end
end

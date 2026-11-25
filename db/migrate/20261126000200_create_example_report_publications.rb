class CreateExampleReportPublications < ActiveRecord::Migration[8.1]
  def change
    create_table :example_report_publications do |t|
      t.references :workspace, null: false, foreign_key: true
      t.references :chat, null: false, foreign_key: true
      t.references :member, null: false, foreign_key: true
      t.references :chat_run, foreign_key: true
      t.string :publication_key, null: false
      t.string :title, null: false
      t.text :body, null: false
      t.string :content_digest, null: false
      t.string :status, null: false, default: "draft"
      t.datetime :published_at
      t.timestamps
    end
    add_index :example_report_publications, [:workspace_id, :publication_key], unique: true,
      name: "index_example_publications_on_business_key"
  end
end

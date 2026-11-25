# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_11_26_000200) do
  create_table "action_text_rich_texts", force: :cascade do |t|
    t.string "name", null: false
    t.text "body"
    t.string "record_type", null: false
    t.bigint "record_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["record_type", "record_id", "name"], name: "index_action_text_rich_texts_uniqueness", unique: true
  end

  create_table "active_storage_attachments", force: :cascade do |t|
    t.string "name", null: false
    t.string "record_type", null: false
    t.bigint "record_id", null: false
    t.bigint "blob_id", null: false
    t.datetime "created_at", null: false
    t.index ["blob_id"], name: "index_active_storage_attachments_on_blob_id"
    t.index ["record_type", "record_id", "name", "blob_id"], name: "index_active_storage_attachments_uniqueness", unique: true
  end

  create_table "active_storage_blobs", force: :cascade do |t|
    t.string "key", null: false
    t.string "filename", null: false
    t.string "content_type"
    t.text "metadata"
    t.string "service_name", null: false
    t.bigint "byte_size", null: false
    t.string "checksum"
    t.datetime "created_at", null: false
    t.index ["key"], name: "index_active_storage_blobs_on_key", unique: true
  end

  create_table "active_storage_variant_records", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.string "variation_digest", null: false
    t.index ["blob_id", "variation_digest"], name: "index_active_storage_variant_records_uniqueness", unique: true
  end

  create_table "agent_deliveries", force: :cascade do |t|
    t.integer "agent_id", null: false
    t.integer "chat_id", null: false
    t.integer "initiated_by_member_id"
    t.integer "input_message_id"
    t.integer "chat_run_id"
    t.string "trigger", null: false
    t.string "idempotency_key"
    t.string "payload_digest", null: false
    t.string "event_type"
    t.text "payload", default: "", null: false
    t.integer "status", default: 0, null: false
    t.string "rejection_reason"
    t.datetime "next_attempt_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["agent_id", "trigger", "idempotency_key"], name: "idx_on_agent_id_trigger_idempotency_key_0c220e2c98", unique: true
    t.index ["agent_id"], name: "index_agent_deliveries_on_agent_id"
    t.index ["chat_id"], name: "index_agent_deliveries_on_chat_id"
    t.index ["chat_run_id"], name: "index_agent_deliveries_on_chat_run_id", unique: true
    t.index ["initiated_by_member_id"], name: "index_agent_deliveries_on_initiated_by_member_id"
    t.index ["input_message_id"], name: "index_agent_deliveries_on_input_message_id", unique: true
    t.index ["status", "next_attempt_at"], name: "index_agent_deliveries_on_status_and_next_attempt_at"
  end

  create_table "agents", force: :cascade do |t|
    t.integer "workspace_id", null: false
    t.integer "member_id", null: false
    t.integer "chat_id", null: false
    t.string "name", null: false
    t.string "identifier", null: false
    t.text "instructions"
    t.string "instructions_prompt"
    t.json "tool_config"
    t.string "schedule"
    t.boolean "active", default: true, null: false
    t.string "webhook_token"
    t.json "metadata", default: {}
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["chat_id"], name: "index_agents_on_chat_id"
    t.index ["member_id"], name: "index_agents_on_member_id"
    t.index ["webhook_token"], name: "index_agents_on_webhook_token", unique: true
    t.index ["workspace_id", "active"], name: "index_agents_on_workspace_id_and_active"
    t.index ["workspace_id", "identifier"], name: "index_agents_on_workspace_id_and_identifier", unique: true
    t.index ["workspace_id"], name: "index_agents_on_workspace_id"
  end

  create_table "ahoy_events", force: :cascade do |t|
    t.integer "visit_id"
    t.integer "user_id"
    t.string "name"
    t.text "properties"
    t.datetime "time"
    t.index ["name", "time"], name: "index_ahoy_events_on_name_and_time"
    t.index ["user_id"], name: "index_ahoy_events_on_user_id"
  end

  create_table "ahoy_visits", force: :cascade do |t|
    t.string "visit_token"
    t.string "visitor_token"
    t.integer "user_id"
    t.string "ip"
    t.text "user_agent"
    t.text "referrer"
    t.string "referring_domain"
    t.text "landing_page"
    t.string "browser"
    t.string "os"
    t.string "device_type"
    t.string "country"
    t.string "region"
    t.string "city"
    t.float "latitude"
    t.float "longitude"
    t.string "utm_source"
    t.string "utm_medium"
    t.string "utm_term"
    t.string "utm_content"
    t.string "utm_campaign"
    t.string "app_version"
    t.string "os_version"
    t.string "platform"
    t.datetime "started_at"
    t.index ["user_id"], name: "index_ahoy_visits_on_user_id"
    t.index ["visit_token"], name: "index_ahoy_visits_on_visit_token", unique: true
    t.index ["visitor_token", "started_at"], name: "index_ahoy_visits_on_visitor_token_and_started_at"
  end

  create_table "blazer_audits", force: :cascade do |t|
    t.integer "user_id"
    t.integer "query_id"
    t.text "statement"
    t.string "data_source"
    t.datetime "created_at"
    t.index ["query_id"], name: "index_blazer_audits_on_query_id"
    t.index ["user_id"], name: "index_blazer_audits_on_user_id"
  end

  create_table "blazer_checks", force: :cascade do |t|
    t.integer "creator_id"
    t.integer "query_id"
    t.string "state"
    t.string "schedule"
    t.text "emails"
    t.text "slack_channels"
    t.string "check_type"
    t.text "message"
    t.datetime "last_run_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["creator_id"], name: "index_blazer_checks_on_creator_id"
    t.index ["query_id"], name: "index_blazer_checks_on_query_id"
  end

  create_table "blazer_dashboard_queries", force: :cascade do |t|
    t.integer "dashboard_id"
    t.integer "query_id"
    t.integer "position"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["dashboard_id"], name: "index_blazer_dashboard_queries_on_dashboard_id"
    t.index ["query_id"], name: "index_blazer_dashboard_queries_on_query_id"
  end

  create_table "blazer_dashboards", force: :cascade do |t|
    t.integer "creator_id"
    t.string "name"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["creator_id"], name: "index_blazer_dashboards_on_creator_id"
  end

  create_table "blazer_queries", force: :cascade do |t|
    t.integer "creator_id"
    t.string "name"
    t.text "description"
    t.text "statement"
    t.string "data_source"
    t.string "status"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["creator_id"], name: "index_blazer_queries_on_creator_id"
  end

  create_table "chat_invitations", force: :cascade do |t|
    t.integer "chat_id", null: false
    t.integer "inviter_id", null: false
    t.integer "invitee_id", null: false
    t.integer "status", default: 0, null: false
    t.datetime "responded_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["chat_id", "invitee_id"], name: "index_chat_invitations_on_chat_invitee_active", unique: true, where: "status IN (0, 1)"
    t.index ["chat_id"], name: "index_chat_invitations_on_chat_id"
    t.index ["invitee_id"], name: "index_chat_invitations_on_invitee_id"
    t.index ["inviter_id"], name: "index_chat_invitations_on_inviter_id"
    t.index ["status", "invitee_id"], name: "index_chat_invitations_on_status_and_invitee_id"
  end

  create_table "chat_members", force: :cascade do |t|
    t.integer "chat_id", null: false
    t.integer "member_id", null: false
    t.integer "role", default: 1, null: false
    t.datetime "last_read_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["chat_id", "member_id"], name: "index_chat_members_on_chat_id_and_member_id", unique: true
    t.index ["chat_id"], name: "index_chat_members_on_chat_id"
    t.index ["chat_id"], name: "index_chat_members_on_chat_id_unique_owner", unique: true, where: "role = 0"
    t.index ["member_id"], name: "index_chat_members_on_member_id"
  end

  create_table "chat_runs", force: :cascade do |t|
    t.integer "chat_id", null: false
    t.integer "status", default: 0, null: false
    t.datetime "cancelled_at"
    t.string "cancelled_by"
    t.string "node_name"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.datetime "completed_at"
    t.datetime "failed_at"
    t.integer "initiated_by_member_id"
    t.integer "llm_attempts", default: 0, null: false
    t.integer "input_tokens"
    t.integer "output_tokens"
    t.integer "cache_read_tokens"
    t.integer "cache_write_tokens"
    t.integer "thinking_tokens"
    t.decimal "total_cost", precision: 16, scale: 10
    t.json "usage_metadata", default: {}, null: false
    t.integer "input_message_id"
    t.datetime "resume_at"
    t.string "trigger", default: "user", null: false
    t.index ["chat_id", "status"], name: "index_chat_runs_on_chat_id_and_status"
    t.index ["chat_id"], name: "index_chat_runs_on_chat_active", unique: true, where: "status IN (0, 1, 5, 6)"
    t.index ["chat_id"], name: "index_chat_runs_on_chat_id"
    t.index ["initiated_by_member_id"], name: "index_chat_runs_on_initiated_by_member_id"
    t.index ["input_message_id"], name: "index_chat_runs_on_input_message_id"
    t.index ["status", "resume_at"], name: "index_chat_runs_on_status_and_resume_at"
    t.index ["status"], name: "index_chat_runs_on_status"
  end

  create_table "chats", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "user_id"
    t.integer "ruby_llm_model_id"
    t.integer "member_id"
    t.string "name", default: "", null: false
    t.boolean "has_multiple_members", default: false, null: false
    t.text "compaction_summary"
    t.datetime "last_compacted_at"
    t.integer "compaction_token_threshold"
    t.datetime "compacting_since"
    t.boolean "cancelled", default: false, null: false
    t.string "claim_token"
    t.datetime "claimed_until"
    t.string "purpose", default: "assistant", null: false
    t.index ["claimed_until"], name: "index_chats_on_claimed_until", where: "claim_token IS NOT NULL"
    t.index ["has_multiple_members"], name: "index_chats_on_has_multiple_members"
    t.index ["member_id"], name: "index_chats_on_member_id"
    t.index ["name"], name: "index_chats_on_name"
    t.index ["ruby_llm_model_id"], name: "index_chats_on_ruby_llm_model_id"
    t.index ["user_id"], name: "index_chats_on_user_id"
  end

  create_table "example_report_publications", force: :cascade do |t|
    t.integer "workspace_id", null: false
    t.integer "chat_id", null: false
    t.integer "member_id", null: false
    t.integer "chat_run_id"
    t.string "publication_key", null: false
    t.string "title", null: false
    t.text "body", null: false
    t.string "content_digest", null: false
    t.string "status", default: "draft", null: false
    t.datetime "published_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["chat_id"], name: "index_example_report_publications_on_chat_id"
    t.index ["chat_run_id"], name: "index_example_report_publications_on_chat_run_id"
    t.index ["member_id"], name: "index_example_report_publications_on_member_id"
    t.index ["workspace_id", "publication_key"], name: "index_example_publications_on_business_key", unique: true
    t.index ["workspace_id"], name: "index_example_report_publications_on_workspace_id"
  end

  create_table "invitations", force: :cascade do |t|
    t.string "name", null: false
    t.string "email", null: false
    t.bigint "workspace_id", null: false
    t.bigint "originator_id", null: false
    t.json "roles", default: {}, null: false
    t.string "token", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["originator_id"], name: "index_invitations_on_originator_id"
    t.index ["token"], name: "index_account_invitations_on_token", unique: true
    t.index ["workspace_id", "email"], name: "index_account_invitations_on_account_id_and_email", unique: true
  end

  create_table "members", force: :cascade do |t|
    t.integer "workspace_id", null: false
    t.integer "user_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.boolean "admin", default: false, null: false
    t.json "roles", default: {}, null: false
    t.index ["user_id"], name: "index_members_on_user_id"
    t.index ["workspace_id", "user_id"], name: "index_members_on_workspace_id_and_user_id", unique: true
    t.index ["workspace_id"], name: "index_members_on_workspace_id"
  end

  create_table "mentions", force: :cascade do |t|
    t.integer "message_id", null: false
    t.string "mentionable_type", null: false
    t.text "metadata", default: "{}"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "mentionable_id", null: false
    t.index ["mentionable_type", "mentionable_id"], name: "index_mentions_on_mentionable_type_and_mentionable_id"
    t.index ["mentionable_type"], name: "index_mentions_on_mentionable_type"
    t.index ["message_id"], name: "index_mentions_on_message_id"
    t.index ["message_id"], name: "index_mentions_on_message_id_and_sgid"
  end

  create_table "messages", force: :cascade do |t|
    t.integer "chat_id", null: false
    t.string "role", null: false
    t.text "content"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.json "metadata", default: {}
    t.boolean "user_submitted", default: false, null: false
    t.integer "user_id"
    t.integer "member_id"
    t.text "thinking_text"
    t.text "thinking_signature"
    t.boolean "skip_llm_context", default: false, null: false
    t.boolean "compacted", default: false, null: false
    t.boolean "cache_until_here", default: false, null: false
    t.string "finish_reason"
    t.json "citations"
    t.json "server_tool_calls"
    t.json "raw_content"
    t.json "raw_reasoning"
    t.string "cache_ttl"
    t.string "phase"
    t.text "continuation"
    t.index ["chat_id", "compacted"], name: "index_messages_on_chat_id_and_compacted"
    t.index ["chat_id"], name: "index_messages_on_chat_id"
    t.index ["member_id"], name: "index_messages_on_member_id"
    t.index ["user_id"], name: "index_messages_on_user_id"
    t.index ["user_submitted"], name: "index_messages_on_user_submitted"
  end

  create_table "noticed_events", force: :cascade do |t|
    t.string "type"
    t.string "record_type"
    t.bigint "record_id"
    t.json "params"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "notifications_count"
    t.index ["record_type", "record_id"], name: "index_noticed_events_on_record"
  end

  create_table "noticed_notifications", force: :cascade do |t|
    t.string "type"
    t.bigint "event_id", null: false
    t.string "recipient_type", null: false
    t.bigint "recipient_id", null: false
    t.datetime "read_at", precision: nil
    t.datetime "seen_at", precision: nil
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["event_id"], name: "index_noticed_notifications_on_event_id"
    t.index ["recipient_type", "recipient_id"], name: "index_noticed_notifications_on_recipient"
  end

  create_table "pay_charges", force: :cascade do |t|
    t.bigint "customer_id", null: false
    t.bigint "subscription_id"
    t.string "processor_id", null: false
    t.integer "amount", null: false
    t.string "currency"
    t.integer "application_fee_amount"
    t.integer "amount_refunded"
    t.json "metadata"
    t.json "data"
    t.string "stripe_account"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "type"
    t.json "object"
    t.index ["customer_id", "processor_id"], name: "index_pay_charges_on_customer_id_and_processor_id", unique: true
    t.index ["subscription_id"], name: "index_pay_charges_on_subscription_id"
  end

  create_table "pay_customers", force: :cascade do |t|
    t.string "owner_type"
    t.bigint "owner_id"
    t.string "processor", null: false
    t.string "processor_id"
    t.boolean "default"
    t.json "data"
    t.string "stripe_account"
    t.datetime "deleted_at", precision: nil
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "type"
    t.json "object"
    t.index ["owner_type", "owner_id", "deleted_at"], name: "pay_customer_owner_index", unique: true
    t.index ["processor", "processor_id"], name: "index_pay_customers_on_processor_and_processor_id", unique: true
  end

  create_table "pay_merchants", force: :cascade do |t|
    t.string "owner_type"
    t.bigint "owner_id"
    t.string "processor", null: false
    t.string "processor_id"
    t.boolean "default"
    t.json "data"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "type"
    t.index ["owner_type", "owner_id", "processor"], name: "index_pay_merchants_on_owner_type_and_owner_id_and_processor"
  end

  create_table "pay_payment_methods", force: :cascade do |t|
    t.bigint "customer_id", null: false
    t.string "processor_id", null: false
    t.boolean "default"
    t.string "payment_method_type"
    t.json "data"
    t.string "stripe_account"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "type"
    t.index ["customer_id", "processor_id"], name: "index_pay_payment_methods_on_customer_id_and_processor_id", unique: true
  end

  create_table "pay_subscriptions", force: :cascade do |t|
    t.bigint "customer_id", null: false
    t.string "name", null: false
    t.string "processor_id", null: false
    t.string "processor_plan", null: false
    t.integer "quantity", default: 1, null: false
    t.string "status", null: false
    t.datetime "current_period_start", precision: nil
    t.datetime "current_period_end", precision: nil
    t.datetime "trial_ends_at", precision: nil
    t.datetime "ends_at", precision: nil
    t.boolean "metered"
    t.string "pause_behavior"
    t.datetime "pause_starts_at", precision: nil
    t.datetime "pause_resumes_at", precision: nil
    t.decimal "application_fee_percent", precision: 8, scale: 2
    t.json "metadata"
    t.json "data"
    t.string "stripe_account"
    t.string "payment_method_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "type"
    t.json "object"
    t.index ["customer_id", "processor_id"], name: "index_pay_subscriptions_on_customer_id_and_processor_id", unique: true
    t.index ["metered"], name: "index_pay_subscriptions_on_metered"
    t.index ["pause_starts_at"], name: "index_pay_subscriptions_on_pause_starts_at"
  end

  create_table "pay_webhooks", force: :cascade do |t|
    t.string "processor"
    t.string "event_type"
    t.json "event"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "plans", force: :cascade do |t|
    t.string "name", default: "", null: false
    t.integer "amount", default: 0, null: false
    t.string "unit_label"
    t.boolean "charge_per_unit", default: false, null: false
    t.string "interval", null: false
    t.integer "interval_count", default: 1
    t.integer "trial_period_days", default: 0, null: false
    t.string "stripe_id"
    t.string "braintree_id"
    t.string "fake_processor_id"
    t.boolean "hidden", default: false, null: false
    t.string "contact_url", default: "", null: false
    t.datetime "created_at", precision: nil, null: false
    t.string "currency"
    t.string "description", default: "", null: false
    t.json "metadata", default: {}, null: false
    t.datetime "updated_at", precision: nil, null: false
  end

  create_table "refer_referral_codes", force: :cascade do |t|
    t.string "referrer_type", null: false
    t.integer "referrer_id", null: false
    t.string "code", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "referrals_count", default: 0
    t.integer "visits_count", default: 0
    t.index ["code"], name: "index_refer_referral_codes_on_code", unique: true
    t.index ["referrer_type", "referrer_id"], name: "index_refer_referral_codes_on_referrer"
  end

  create_table "refer_referrals", force: :cascade do |t|
    t.string "referrer_type", null: false
    t.integer "referrer_id", null: false
    t.string "referee_type", null: false
    t.integer "referee_id", null: false
    t.integer "referral_code_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.datetime "completed_at"
    t.index ["referee_type", "referee_id"], name: "index_refer_referrals_on_referee"
    t.index ["referral_code_id"], name: "index_refer_referrals_on_referral_code_id"
    t.index ["referrer_type", "referrer_id"], name: "index_refer_referrals_on_referrer"
  end

  create_table "refer_visits", force: :cascade do |t|
    t.integer "referral_code_id", null: false
    t.string "ip"
    t.text "user_agent"
    t.text "referrer"
    t.string "referring_domain"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["referral_code_id"], name: "index_refer_visits_on_referral_code_id"
  end

  create_table "ruby_llm_batches", force: :cascade do |t|
    t.string "provider_batch_id", null: false
    t.string "provider", null: false
    t.string "status", null: false
    t.string "raw_status"
    t.boolean "completed", default: false, null: false
    t.string "chat_type"
    t.string "batch_protocol"
    t.json "chat_ids", default: []
    t.json "request_counts"
    t.json "reported_cost"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["provider", "provider_batch_id"], name: "index_ruby_llm_batches_on_provider_and_provider_batch_id", unique: true
    t.index ["status"], name: "index_ruby_llm_batches_on_status"
  end

  create_table "ruby_llm_chat_files", force: :cascade do |t|
    t.string "chat_type", null: false
    t.bigint "chat_id", null: false
    t.string "owner_type"
    t.bigint "owner_id"
    t.string "path", null: false
    t.string "content_type"
    t.bigint "byte_size"
    t.string "digest"
    t.text "text"
    t.string "read_digest"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["chat_type", "chat_id", "path"], name: "index_ruby_llm_chat_files_on_chat_type_and_chat_id_and_path"
    t.index ["owner_type", "owner_id"], name: "index_ruby_llm_chat_files_on_owner_type_and_owner_id"
  end

  create_table "ruby_llm_mcp_credentials", force: :cascade do |t|
    t.string "owner_type"
    t.bigint "owner_id"
    t.string "key", null: false
    t.text "data"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["key"], name: "index_ruby_llm_mcp_credentials_on_key", unique: true
    t.index ["owner_type", "owner_id"], name: "index_ruby_llm_mcp_credentials_on_owner"
  end

  create_table "ruby_llm_models", force: :cascade do |t|
    t.string "model_id", null: false
    t.string "name", null: false
    t.string "provider", null: false
    t.string "family"
    t.datetime "model_created_at"
    t.integer "context_window"
    t.integer "max_output_tokens"
    t.date "knowledge_cutoff"
    t.json "modalities", default: {}
    t.json "capabilities", default: []
    t.json "pricing", default: {}
    t.json "metadata", default: {}
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.datetime "unlisted_at"
    t.index ["family"], name: "index_ruby_llm_models_on_family"
    t.index ["provider", "model_id"], name: "index_ruby_llm_models_on_provider_and_model_id", unique: true
    t.index ["provider"], name: "index_ruby_llm_models_on_provider"
  end

  create_table "ruby_llm_provider_files", force: :cascade do |t|
    t.string "blob_key", null: false
    t.string "provider", null: false
    t.string "account", null: false
    t.text "file_id", null: false
    t.datetime "expires_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["blob_key", "provider", "account"], name: "index_ruby_llm_provider_files_uniqueness", unique: true
  end

  create_table "ruby_llm_queued_messages", force: :cascade do |t|
    t.string "chat_type", null: false
    t.bigint "chat_id", null: false
    t.string "sender_type"
    t.bigint "sender_id"
    t.text "content"
    t.boolean "steer", default: true, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["chat_type", "chat_id"], name: "index_ruby_llm_queued_messages_on_chat_type_and_chat_id"
    t.index ["sender_type", "sender_id"], name: "index_ruby_llm_queued_messages_on_sender_type_and_sender_id"
  end

  create_table "ruby_llm_tool_calls", force: :cascade do |t|
    t.integer "message_id", null: false
    t.string "tool_call_id", null: false
    t.string "name", null: false
    t.json "arguments", default: {}
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.json "metadata", default: {}, null: false
    t.text "thought_signature"
    t.string "message_type", null: false
    t.string "result_type"
    t.integer "result_id"
    t.string "approval"
    t.boolean "remote", default: false, null: false
    t.json "mcp_state"
    t.json "mcp_result"
    t.string "provider_call_id"
    t.string "namespace"
    t.datetime "claimed_until"
    t.index ["message_type", "message_id"], name: "index_ruby_llm_tool_calls_on_message_type_and_message_id"
    t.index ["name"], name: "index_ruby_llm_tool_calls_on_name"
    t.index ["result_type", "result_id"], name: "index_ruby_llm_tool_calls_on_result_type_and_result_id"
    t.index ["tool_call_id"], name: "index_ruby_llm_tool_calls_on_tool_call_id", unique: true
  end

  create_table "ruby_llm_usages", force: :cascade do |t|
    t.string "chat_type"
    t.integer "chat_id"
    t.string "message_type"
    t.integer "message_id"
    t.string "operation", null: false
    t.string "provider", null: false
    t.string "model", null: false
    t.string "status", null: false
    t.integer "input_tokens"
    t.integer "output_tokens"
    t.integer "cache_read_tokens"
    t.integer "cache_write_tokens"
    t.integer "thinking_tokens"
    t.decimal "input_cost", precision: 16, scale: 10
    t.decimal "output_cost", precision: 16, scale: 10
    t.decimal "cache_read_cost", precision: 16, scale: 10
    t.decimal "cache_write_cost", precision: 16, scale: 10
    t.decimal "thinking_cost", precision: 16, scale: 10
    t.decimal "total_cost", precision: 16, scale: 10
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.json "server_tool_use"
    t.string "owner_type"
    t.bigint "owner_id"
    t.string "workflow_id"
    t.string "workflow_name"
    t.string "workflow_step_id"
    t.string "workflow_step_name"
    t.integer "characters"
    t.decimal "audio_seconds", precision: 16, scale: 6
    t.integer "search_units"
    t.decimal "characters_cost", precision: 16, scale: 10
    t.decimal "audio_seconds_cost", precision: 16, scale: 10
    t.decimal "search_units_cost", precision: 16, scale: 10
    t.index ["chat_type", "chat_id"], name: "index_ruby_llm_usages_on_chat_type_and_chat_id"
    t.index ["message_type", "message_id"], name: "index_ruby_llm_usages_on_message_type_and_message_id"
    t.index ["owner_type", "owner_id"], name: "index_ruby_llm_usages_on_owner"
    t.index ["status"], name: "index_ruby_llm_usages_on_status"
    t.index ["workflow_id"], name: "index_ruby_llm_usages_on_workflow_id"
    t.check_constraint "operation IN ('chat', 'embedding', 'moderation', 'image', 'speech', 'transcription', 'ocr', 'rerank', 'judgment', 'video', 'research', 'code_execution')"
    t.check_constraint "status IN ('pending', 'succeeded', 'failed', 'cancelled')"
  end

  create_table "solid_cable_messages", force: :cascade do |t|
    t.binary "channel", limit: 1024, null: false
    t.binary "payload", limit: 536870912, null: false
    t.datetime "created_at", null: false
    t.integer "channel_hash", limit: 8, null: false
    t.index ["channel_hash"], name: "index_solid_cable_messages_on_channel_hash"
    t.index ["created_at"], name: "index_solid_cable_messages_on_created_at"
  end

  create_table "users", force: :cascade do |t|
    t.string "email", default: "", null: false
    t.string "encrypted_password", default: "", null: false
    t.string "reset_password_token"
    t.datetime "reset_password_sent_at"
    t.datetime "remember_created_at"
    t.integer "sign_in_count", default: 0, null: false
    t.datetime "current_sign_in_at"
    t.datetime "last_sign_in_at"
    t.string "current_sign_in_ip"
    t.string "last_sign_in_ip"
    t.integer "failed_attempts", default: 0, null: false
    t.string "unlock_token"
    t.datetime "locked_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.json "preferences", default: {}, null: false
    t.string "first_name", default: "", null: false
    t.string "last_name", default: "", null: false
    t.string "time_zone", default: "UTC", null: false
    t.boolean "admin", default: false, null: false
    t.string "gravatar_url", default: "", null: false
    t.string "unconfirmed_email"
    t.integer "invitations_count", default: 0, null: false
    t.string "username", null: false
    t.index ["email"], name: "index_users_on_email", unique: true
    t.index ["invitations_count"], name: "index_users_on_invitations_count"
    t.index ["reset_password_token"], name: "index_users_on_reset_password_token", unique: true
    t.index ["unlock_token"], name: "index_users_on_unlock_token", unique: true
    t.index ["username"], name: "index_users_on_username", unique: true
  end

  create_table "workspaces", force: :cascade do |t|
    t.string "name", default: "", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "owner_id", null: false
    t.integer "members_count", default: 0
    t.boolean "is_team_workspace", default: true, null: false
    t.string "billing_email", default: "", null: false
    t.string "extra_billing_info", default: "", null: false
    t.index ["owner_id"], name: "index_workspaces_on_owner_id"
  end

  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "agent_deliveries", "agents"
  add_foreign_key "agent_deliveries", "chat_runs"
  add_foreign_key "agent_deliveries", "chats"
  add_foreign_key "agent_deliveries", "members", column: "initiated_by_member_id"
  add_foreign_key "agent_deliveries", "messages", column: "input_message_id"
  add_foreign_key "agents", "chats"
  add_foreign_key "agents", "members"
  add_foreign_key "agents", "workspaces"
  add_foreign_key "chat_invitations", "chats"
  add_foreign_key "chat_invitations", "members", column: "invitee_id"
  add_foreign_key "chat_invitations", "members", column: "inviter_id"
  add_foreign_key "chat_members", "chats"
  add_foreign_key "chat_members", "members"
  add_foreign_key "chat_runs", "chats"
  add_foreign_key "chat_runs", "members", column: "initiated_by_member_id"
  add_foreign_key "chat_runs", "messages", column: "input_message_id", on_delete: :nullify
  add_foreign_key "chats", "members"
  add_foreign_key "chats", "ruby_llm_models"
  add_foreign_key "chats", "users"
  add_foreign_key "example_report_publications", "chat_runs"
  add_foreign_key "example_report_publications", "chats"
  add_foreign_key "example_report_publications", "members"
  add_foreign_key "example_report_publications", "workspaces"
  add_foreign_key "invitations", "users", column: "originator_id"
  add_foreign_key "invitations", "workspaces"
  add_foreign_key "members", "users"
  add_foreign_key "members", "workspaces"
  add_foreign_key "mentions", "messages"
  add_foreign_key "messages", "chats"
  add_foreign_key "messages", "members"
  add_foreign_key "messages", "users"
  add_foreign_key "pay_charges", "pay_customers", column: "customer_id"
  add_foreign_key "pay_charges", "pay_subscriptions", column: "subscription_id"
  add_foreign_key "pay_payment_methods", "pay_customers", column: "customer_id"
  add_foreign_key "pay_subscriptions", "pay_customers", column: "customer_id"
  add_foreign_key "refer_visits", "refer_referral_codes", column: "referral_code_id"
  add_foreign_key "workspaces", "users", column: "owner_id"
end

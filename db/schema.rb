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

ActiveRecord::Schema[8.1].define(version: 2026_04_20_000000) do
  create_table "action_text_rich_texts", force: :cascade do |t|
    t.text "body"
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.bigint "record_id", null: false
    t.string "record_type", null: false
    t.datetime "updated_at", null: false
    t.index ["record_type", "record_id", "name"], name: "index_action_text_rich_texts_uniqueness", unique: true
  end

  create_table "active_storage_attachments", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.bigint "record_id", null: false
    t.string "record_type", null: false
    t.index ["blob_id"], name: "index_active_storage_attachments_on_blob_id"
    t.index ["record_type", "record_id", "name", "blob_id"], name: "index_active_storage_attachments_uniqueness", unique: true
  end

  create_table "active_storage_blobs", force: :cascade do |t|
    t.bigint "byte_size", null: false
    t.string "checksum"
    t.string "content_type"
    t.datetime "created_at", null: false
    t.string "filename", null: false
    t.string "key", null: false
    t.text "metadata"
    t.string "service_name", null: false
    t.index ["key"], name: "index_active_storage_blobs_on_key", unique: true
  end

  create_table "active_storage_variant_records", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.string "variation_digest", null: false
    t.index ["blob_id", "variation_digest"], name: "index_active_storage_variant_records_uniqueness", unique: true
  end

  create_table "agent_task_effects", force: :cascade do |t|
    t.string "action", null: false
    t.integer "agent_task_id", null: false
    t.datetime "created_at", null: false
    t.string "description", null: false
    t.json "details", default: {}
    t.integer "target_id"
    t.string "target_type"
    t.datetime "updated_at", null: false
    t.index ["action"], name: "index_agent_task_effects_on_action"
    t.index ["agent_task_id", "created_at"], name: "index_agent_task_effects_on_agent_task_id_and_created_at"
    t.index ["agent_task_id"], name: "index_agent_task_effects_on_agent_task_id"
    t.index ["target_type", "target_id"], name: "index_agent_task_effects_on_target"
  end

  create_table "agent_tasks", force: :cascade do |t|
    t.integer "attempts", default: 0, null: false
    t.integer "chat_id", null: false
    t.datetime "completed_at"
    t.datetime "created_at", null: false
    t.text "error_message"
    t.string "idempotency_key"
    t.string "kind", null: false
    t.integer "member_id", null: false
    t.json "metadata", default: {}
    t.integer "parent_task_id"
    t.integer "progress", default: 0
    t.string "progress_text"
    t.json "result", default: {}
    t.datetime "started_at"
    t.integer "status", default: 0, null: false
    t.string "trigger", default: "chat", null: false
    t.datetime "updated_at", null: false
    t.integer "workspace_id", null: false
    t.index ["chat_id", "idempotency_key"], name: "index_agent_tasks_on_chat_id_and_idempotency_key", unique: true
    t.index ["chat_id", "status"], name: "index_agent_tasks_on_chat_id_and_status"
    t.index ["chat_id"], name: "index_agent_tasks_on_chat_id"
    t.index ["member_id"], name: "index_agent_tasks_on_member_id"
    t.index ["parent_task_id"], name: "index_agent_tasks_on_parent_task_id"
    t.index ["workspace_id", "status"], name: "index_agent_tasks_on_workspace_id_and_status"
    t.index ["workspace_id"], name: "index_agent_tasks_on_workspace_id"
  end

  create_table "agents", force: :cascade do |t|
    t.boolean "active", default: true, null: false
    t.integer "chat_id", null: false
    t.datetime "created_at", null: false
    t.string "identifier", null: false
    t.text "instructions"
    t.string "instructions_prompt"
    t.integer "member_id", null: false
    t.json "metadata", default: {}
    t.string "name", null: false
    t.string "schedule"
    t.json "tool_config"
    t.datetime "updated_at", null: false
    t.string "webhook_token"
    t.integer "workspace_id", null: false
    t.index ["chat_id"], name: "index_agents_on_chat_id"
    t.index ["member_id"], name: "index_agents_on_member_id"
    t.index ["webhook_token"], name: "index_agents_on_webhook_token", unique: true
    t.index ["workspace_id", "active"], name: "index_agents_on_workspace_id_and_active"
    t.index ["workspace_id", "identifier"], name: "index_agents_on_workspace_id_and_identifier", unique: true
    t.index ["workspace_id"], name: "index_agents_on_workspace_id"
  end

  create_table "ahoy_events", force: :cascade do |t|
    t.string "name"
    t.text "properties"
    t.datetime "time"
    t.integer "user_id"
    t.integer "visit_id"
    t.index ["name", "time"], name: "index_ahoy_events_on_name_and_time"
    t.index ["user_id"], name: "index_ahoy_events_on_user_id"
  end

  create_table "ahoy_visits", force: :cascade do |t|
    t.string "app_version"
    t.string "browser"
    t.string "city"
    t.string "country"
    t.string "device_type"
    t.string "ip"
    t.text "landing_page"
    t.float "latitude"
    t.float "longitude"
    t.string "os"
    t.string "os_version"
    t.string "platform"
    t.text "referrer"
    t.string "referring_domain"
    t.string "region"
    t.datetime "started_at"
    t.text "user_agent"
    t.integer "user_id"
    t.string "utm_campaign"
    t.string "utm_content"
    t.string "utm_medium"
    t.string "utm_source"
    t.string "utm_term"
    t.string "visit_token"
    t.string "visitor_token"
    t.index ["user_id"], name: "index_ahoy_visits_on_user_id"
    t.index ["visit_token"], name: "index_ahoy_visits_on_visit_token", unique: true
    t.index ["visitor_token", "started_at"], name: "index_ahoy_visits_on_visitor_token_and_started_at"
  end

  create_table "blazer_audits", force: :cascade do |t|
    t.datetime "created_at"
    t.string "data_source"
    t.integer "query_id"
    t.text "statement"
    t.integer "user_id"
    t.index ["query_id"], name: "index_blazer_audits_on_query_id"
    t.index ["user_id"], name: "index_blazer_audits_on_user_id"
  end

  create_table "blazer_checks", force: :cascade do |t|
    t.string "check_type"
    t.datetime "created_at", null: false
    t.integer "creator_id"
    t.text "emails"
    t.datetime "last_run_at"
    t.text "message"
    t.integer "query_id"
    t.string "schedule"
    t.text "slack_channels"
    t.string "state"
    t.datetime "updated_at", null: false
    t.index ["creator_id"], name: "index_blazer_checks_on_creator_id"
    t.index ["query_id"], name: "index_blazer_checks_on_query_id"
  end

  create_table "blazer_dashboard_queries", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "dashboard_id"
    t.integer "position"
    t.integer "query_id"
    t.datetime "updated_at", null: false
    t.index ["dashboard_id"], name: "index_blazer_dashboard_queries_on_dashboard_id"
    t.index ["query_id"], name: "index_blazer_dashboard_queries_on_query_id"
  end

  create_table "blazer_dashboards", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "creator_id"
    t.string "name"
    t.datetime "updated_at", null: false
    t.index ["creator_id"], name: "index_blazer_dashboards_on_creator_id"
  end

  create_table "blazer_queries", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "creator_id"
    t.string "data_source"
    t.text "description"
    t.string "name"
    t.text "statement"
    t.string "status"
    t.datetime "updated_at", null: false
    t.index ["creator_id"], name: "index_blazer_queries_on_creator_id"
  end

  create_table "chat_invitations", force: :cascade do |t|
    t.integer "chat_id", null: false
    t.datetime "created_at", null: false
    t.integer "invitee_id", null: false
    t.integer "inviter_id", null: false
    t.datetime "responded_at"
    t.integer "status", default: 0, null: false
    t.datetime "updated_at", null: false
    t.index ["chat_id", "invitee_id"], name: "index_chat_invitations_on_chat_and_invitee_pending", unique: true, where: "status = 0"
    t.index ["chat_id"], name: "index_chat_invitations_on_chat_id"
    t.index ["invitee_id"], name: "index_chat_invitations_on_invitee_id"
    t.index ["inviter_id"], name: "index_chat_invitations_on_inviter_id"
    t.index ["status", "invitee_id"], name: "index_chat_invitations_on_status_and_invitee_id"
  end

  create_table "chat_members", force: :cascade do |t|
    t.integer "chat_id", null: false
    t.datetime "created_at", null: false
    t.datetime "last_read_at"
    t.integer "member_id", null: false
    t.integer "role", default: 1, null: false
    t.datetime "updated_at", null: false
    t.index ["chat_id", "member_id"], name: "index_chat_members_on_chat_id_and_member_id", unique: true
    t.index ["chat_id"], name: "index_chat_members_on_chat_id"
    t.index ["chat_id"], name: "index_chat_members_on_chat_id_unique_owner", unique: true, where: "role = 0"
    t.index ["member_id"], name: "index_chat_members_on_member_id"
  end

  create_table "chat_runs", force: :cascade do |t|
    t.datetime "cancelled_at"
    t.string "cancelled_by"
    t.integer "chat_id", null: false
    t.datetime "completed_at"
    t.datetime "created_at", null: false
    t.datetime "failed_at"
    t.string "node_name"
    t.integer "status", default: 0, null: false
    t.datetime "updated_at", null: false
    t.index ["chat_id", "status"], name: "index_chat_runs_on_chat_id_and_status"
    t.index ["chat_id"], name: "index_chat_runs_on_chat_active", unique: true, where: "status IN (0, 1, 5)"
    t.index ["chat_id"], name: "index_chat_runs_on_chat_id"
    t.index ["status"], name: "index_chat_runs_on_status"
  end

  create_table "chats", force: :cascade do |t|
    t.datetime "agent_tasks_dismissed_at"
    t.datetime "compacting_since"
    t.text "compaction_summary"
    t.integer "compaction_token_threshold"
    t.datetime "created_at", null: false
    t.boolean "has_multiple_members", default: false, null: false
    t.datetime "last_compacted_at"
    t.integer "member_id"
    t.integer "model_id"
    t.string "name", default: "", null: false
    t.datetime "updated_at", null: false
    t.integer "user_id"
    t.index ["has_multiple_members"], name: "index_chats_on_has_multiple_members"
    t.index ["member_id"], name: "index_chats_on_member_id"
    t.index ["model_id"], name: "index_chats_on_model_id"
    t.index ["name"], name: "index_chats_on_name"
    t.index ["user_id"], name: "index_chats_on_user_id"
  end

  create_table "invitations", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "email", null: false
    t.string "name", null: false
    t.bigint "originator_id", null: false
    t.json "roles", default: {}, null: false
    t.string "token", null: false
    t.datetime "updated_at", null: false
    t.bigint "workspace_id", null: false
    t.index ["originator_id"], name: "index_invitations_on_originator_id"
    t.index ["token"], name: "index_account_invitations_on_token", unique: true
    t.index ["workspace_id", "email"], name: "index_account_invitations_on_account_id_and_email", unique: true
  end

  create_table "members", force: :cascade do |t|
    t.boolean "admin", default: false, null: false
    t.datetime "created_at", null: false
    t.json "roles", default: {}, null: false
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.integer "workspace_id", null: false
    t.index ["user_id"], name: "index_members_on_user_id"
    t.index ["workspace_id", "user_id"], name: "index_members_on_workspace_id_and_user_id", unique: true
    t.index ["workspace_id"], name: "index_members_on_workspace_id"
  end

  create_table "mentions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "mentionable_id", null: false
    t.string "mentionable_type", null: false
    t.integer "message_id", null: false
    t.text "metadata", default: "{}"
    t.datetime "updated_at", null: false
    t.index ["mentionable_type", "mentionable_id"], name: "index_mentions_on_mentionable_type_and_mentionable_id"
    t.index ["mentionable_type"], name: "index_mentions_on_mentionable_type"
    t.index ["message_id"], name: "index_mentions_on_message_id"
    t.index ["message_id"], name: "index_mentions_on_message_id_and_sgid"
  end

  create_table "messages", force: :cascade do |t|
    t.integer "cache_creation_tokens"
    t.integer "cached_tokens"
    t.integer "chat_id", null: false
    t.boolean "compacted", default: false, null: false
    t.text "content"
    t.json "content_raw"
    t.datetime "created_at", null: false
    t.integer "input_tokens"
    t.integer "member_id"
    t.json "metadata", default: {}
    t.integer "model_id"
    t.integer "output_tokens"
    t.string "role", null: false
    t.boolean "skip_llm_context", default: false, null: false
    t.text "thinking_signature"
    t.text "thinking_text"
    t.integer "thinking_tokens"
    t.integer "tool_call_id"
    t.datetime "updated_at", null: false
    t.integer "user_id"
    t.boolean "user_submitted", default: false, null: false
    t.index ["chat_id", "compacted"], name: "index_messages_on_chat_id_and_compacted"
    t.index ["chat_id"], name: "index_messages_on_chat_id"
    t.index ["member_id"], name: "index_messages_on_member_id"
    t.index ["model_id"], name: "index_messages_on_model_id"
    t.index ["role"], name: "index_messages_on_role"
    t.index ["tool_call_id"], name: "index_messages_on_tool_call_id"
    t.index ["user_id"], name: "index_messages_on_user_id"
    t.index ["user_submitted"], name: "index_messages_on_user_submitted"
  end

  create_table "models", force: :cascade do |t|
    t.json "capabilities", default: []
    t.integer "context_window"
    t.datetime "created_at", null: false
    t.string "family"
    t.date "knowledge_cutoff"
    t.integer "max_output_tokens"
    t.json "metadata", default: {}
    t.json "modalities", default: {}
    t.datetime "model_created_at"
    t.string "model_id", null: false
    t.string "name", null: false
    t.json "pricing", default: {}
    t.string "provider", null: false
    t.datetime "updated_at", null: false
    t.index ["family"], name: "index_models_on_family"
    t.index ["provider", "model_id"], name: "index_models_on_provider_and_model_id", unique: true
    t.index ["provider"], name: "index_models_on_provider"
  end

  create_table "noticed_events", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "notifications_count"
    t.json "params"
    t.bigint "record_id"
    t.string "record_type"
    t.string "type"
    t.datetime "updated_at", null: false
    t.index ["record_type", "record_id"], name: "index_noticed_events_on_record"
  end

  create_table "noticed_notifications", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "event_id", null: false
    t.datetime "read_at", precision: nil
    t.bigint "recipient_id", null: false
    t.string "recipient_type", null: false
    t.datetime "seen_at", precision: nil
    t.string "type"
    t.datetime "updated_at", null: false
    t.index ["event_id"], name: "index_noticed_notifications_on_event_id"
    t.index ["recipient_type", "recipient_id"], name: "index_noticed_notifications_on_recipient"
  end

  create_table "pay_charges", force: :cascade do |t|
    t.integer "amount", null: false
    t.integer "amount_refunded"
    t.integer "application_fee_amount"
    t.datetime "created_at", null: false
    t.string "currency"
    t.bigint "customer_id", null: false
    t.json "data"
    t.json "metadata"
    t.json "object"
    t.string "processor_id", null: false
    t.string "stripe_account"
    t.bigint "subscription_id"
    t.string "type"
    t.datetime "updated_at", null: false
    t.index ["customer_id", "processor_id"], name: "index_pay_charges_on_customer_id_and_processor_id", unique: true
    t.index ["subscription_id"], name: "index_pay_charges_on_subscription_id"
  end

  create_table "pay_customers", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.json "data"
    t.boolean "default"
    t.datetime "deleted_at", precision: nil
    t.json "object"
    t.bigint "owner_id"
    t.string "owner_type"
    t.string "processor", null: false
    t.string "processor_id"
    t.string "stripe_account"
    t.string "type"
    t.datetime "updated_at", null: false
    t.index ["owner_type", "owner_id", "deleted_at"], name: "pay_customer_owner_index", unique: true
    t.index ["processor", "processor_id"], name: "index_pay_customers_on_processor_and_processor_id", unique: true
  end

  create_table "pay_merchants", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.json "data"
    t.boolean "default"
    t.bigint "owner_id"
    t.string "owner_type"
    t.string "processor", null: false
    t.string "processor_id"
    t.string "type"
    t.datetime "updated_at", null: false
    t.index ["owner_type", "owner_id", "processor"], name: "index_pay_merchants_on_owner_type_and_owner_id_and_processor"
  end

  create_table "pay_payment_methods", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "customer_id", null: false
    t.json "data"
    t.boolean "default"
    t.string "payment_method_type"
    t.string "processor_id", null: false
    t.string "stripe_account"
    t.string "type"
    t.datetime "updated_at", null: false
    t.index ["customer_id", "processor_id"], name: "index_pay_payment_methods_on_customer_id_and_processor_id", unique: true
  end

  create_table "pay_subscriptions", force: :cascade do |t|
    t.decimal "application_fee_percent", precision: 8, scale: 2
    t.datetime "created_at", null: false
    t.datetime "current_period_end", precision: nil
    t.datetime "current_period_start", precision: nil
    t.bigint "customer_id", null: false
    t.json "data"
    t.datetime "ends_at", precision: nil
    t.json "metadata"
    t.boolean "metered"
    t.string "name", null: false
    t.json "object"
    t.string "pause_behavior"
    t.datetime "pause_resumes_at", precision: nil
    t.datetime "pause_starts_at", precision: nil
    t.string "payment_method_id"
    t.string "processor_id", null: false
    t.string "processor_plan", null: false
    t.integer "quantity", default: 1, null: false
    t.string "status", null: false
    t.string "stripe_account"
    t.datetime "trial_ends_at", precision: nil
    t.string "type"
    t.datetime "updated_at", null: false
    t.index ["customer_id", "processor_id"], name: "index_pay_subscriptions_on_customer_id_and_processor_id", unique: true
    t.index ["metered"], name: "index_pay_subscriptions_on_metered"
    t.index ["pause_starts_at"], name: "index_pay_subscriptions_on_pause_starts_at"
  end

  create_table "pay_webhooks", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.json "event"
    t.string "event_type"
    t.string "processor"
    t.datetime "updated_at", null: false
  end

  create_table "plans", force: :cascade do |t|
    t.integer "amount", default: 0, null: false
    t.string "braintree_id"
    t.boolean "charge_per_unit", default: false, null: false
    t.string "contact_url", default: "", null: false
    t.datetime "created_at", precision: nil, null: false
    t.string "currency"
    t.string "description", default: "", null: false
    t.string "fake_processor_id"
    t.boolean "hidden", default: false, null: false
    t.string "interval", null: false
    t.integer "interval_count", default: 1
    t.json "metadata", default: {}, null: false
    t.string "name", default: "", null: false
    t.string "stripe_id"
    t.integer "trial_period_days", default: 0, null: false
    t.string "unit_label"
    t.datetime "updated_at", precision: nil, null: false
  end

  create_table "refer_referral_codes", force: :cascade do |t|
    t.string "code", null: false
    t.datetime "created_at", null: false
    t.integer "referrals_count", default: 0
    t.integer "referrer_id", null: false
    t.string "referrer_type", null: false
    t.datetime "updated_at", null: false
    t.integer "visits_count", default: 0
    t.index ["code"], name: "index_refer_referral_codes_on_code", unique: true
    t.index ["referrer_type", "referrer_id"], name: "index_refer_referral_codes_on_referrer"
  end

  create_table "refer_referrals", force: :cascade do |t|
    t.datetime "completed_at"
    t.datetime "created_at", null: false
    t.integer "referee_id", null: false
    t.string "referee_type", null: false
    t.integer "referral_code_id"
    t.integer "referrer_id", null: false
    t.string "referrer_type", null: false
    t.datetime "updated_at", null: false
    t.index ["referee_type", "referee_id"], name: "index_refer_referrals_on_referee"
    t.index ["referral_code_id"], name: "index_refer_referrals_on_referral_code_id"
    t.index ["referrer_type", "referrer_id"], name: "index_refer_referrals_on_referrer"
  end

  create_table "refer_visits", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "ip"
    t.integer "referral_code_id", null: false
    t.text "referrer"
    t.string "referring_domain"
    t.datetime "updated_at", null: false
    t.text "user_agent"
    t.index ["referral_code_id"], name: "index_refer_visits_on_referral_code_id"
  end

  create_table "tool_calls", force: :cascade do |t|
    t.json "arguments", default: {}
    t.datetime "created_at", null: false
    t.integer "message_id", null: false
    t.json "metadata", default: {}, null: false
    t.string "name", null: false
    t.string "thought_signature"
    t.string "tool_call_id", null: false
    t.datetime "updated_at", null: false
    t.index ["message_id"], name: "index_tool_calls_on_message_id"
    t.index ["name"], name: "index_tool_calls_on_name"
    t.index ["tool_call_id"], name: "index_tool_calls_on_tool_call_id", unique: true
  end

  create_table "users", force: :cascade do |t|
    t.boolean "admin", default: false, null: false
    t.datetime "created_at", null: false
    t.datetime "current_sign_in_at"
    t.string "current_sign_in_ip"
    t.string "email", default: "", null: false
    t.string "encrypted_password", default: "", null: false
    t.integer "failed_attempts", default: 0, null: false
    t.string "first_name", default: "", null: false
    t.string "gravatar_url", default: "", null: false
    t.integer "invitations_count", default: 0, null: false
    t.string "last_name", default: "", null: false
    t.datetime "last_sign_in_at"
    t.string "last_sign_in_ip"
    t.datetime "locked_at"
    t.json "preferences", default: {}, null: false
    t.datetime "remember_created_at"
    t.datetime "reset_password_sent_at"
    t.string "reset_password_token"
    t.integer "sign_in_count", default: 0, null: false
    t.string "time_zone", default: "UTC", null: false
    t.string "unconfirmed_email"
    t.string "unlock_token"
    t.datetime "updated_at", null: false
    t.string "username", null: false
    t.index ["email"], name: "index_users_on_email", unique: true
    t.index ["invitations_count"], name: "index_users_on_invitations_count"
    t.index ["reset_password_token"], name: "index_users_on_reset_password_token", unique: true
    t.index ["unlock_token"], name: "index_users_on_unlock_token", unique: true
    t.index ["username"], name: "index_users_on_username", unique: true
  end

  create_table "workspaces", force: :cascade do |t|
    t.string "billing_email", default: "", null: false
    t.datetime "created_at", null: false
    t.string "extra_billing_info", default: "", null: false
    t.boolean "is_team_workspace", default: true, null: false
    t.integer "members_count", default: 0
    t.string "name", default: "", null: false
    t.integer "owner_id", null: false
    t.datetime "updated_at", null: false
    t.index ["owner_id"], name: "index_workspaces_on_owner_id"
  end

  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "agent_task_effects", "agent_tasks"
  add_foreign_key "agent_tasks", "agent_tasks", column: "parent_task_id"
  add_foreign_key "agent_tasks", "chats"
  add_foreign_key "agent_tasks", "members"
  add_foreign_key "agent_tasks", "workspaces"
  add_foreign_key "agents", "chats"
  add_foreign_key "agents", "members"
  add_foreign_key "agents", "workspaces"
  add_foreign_key "chat_invitations", "chats"
  add_foreign_key "chat_invitations", "members", column: "invitee_id"
  add_foreign_key "chat_invitations", "members", column: "inviter_id"
  add_foreign_key "chat_members", "chats"
  add_foreign_key "chat_members", "members"
  add_foreign_key "chat_runs", "chats"
  add_foreign_key "chats", "members"
  add_foreign_key "chats", "models"
  add_foreign_key "chats", "users"
  add_foreign_key "invitations", "users", column: "originator_id"
  add_foreign_key "invitations", "workspaces"
  add_foreign_key "members", "users"
  add_foreign_key "members", "workspaces"
  add_foreign_key "mentions", "messages"
  add_foreign_key "messages", "chats"
  add_foreign_key "messages", "members"
  add_foreign_key "messages", "models"
  add_foreign_key "messages", "tool_calls"
  add_foreign_key "messages", "users"
  add_foreign_key "pay_charges", "pay_customers", column: "customer_id"
  add_foreign_key "pay_charges", "pay_subscriptions", column: "subscription_id"
  add_foreign_key "pay_payment_methods", "pay_customers", column: "customer_id"
  add_foreign_key "pay_subscriptions", "pay_customers", column: "customer_id"
  add_foreign_key "refer_visits", "refer_referral_codes", column: "referral_code_id"
  add_foreign_key "tool_calls", "messages"
  add_foreign_key "workspaces", "users", column: "owner_id"
end

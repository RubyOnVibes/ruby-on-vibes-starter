# frozen_string_literal: true

##
# Remove assistant_message_id from ChatRun
#
# REASONING:
# - ChatRun tracks JOB EXECUTION (when, status, which node)
# - Message tracks CONTENT (what the LLM said)
# - They're related via time window + chat_id, not direct FK
# - This separation is cleaner and more flexible:
#   * One run can involve multiple messages (tool calls, retries)
#   * Messages can be found via chat.messages.where(created_at: run.created_at..run.completed_at)
#   * No optional FK confusion
#
class RemoveAssistantMessageFromChatRuns < ActiveRecord::Migration[8.0]
  def change
    remove_reference :chat_runs, :assistant_message, foreign_key: { to_table: :messages } if column_exists?(:chat_runs, :assistant_message_id)
  end
end


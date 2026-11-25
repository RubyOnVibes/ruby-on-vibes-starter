# frozen_string_literal: true

require "ruby_llm/active_record/file_store"

# RubyLLM 2.2.3's native FileStore uses ActiveRecord's deprecated .connection
# inside its row-lock helper. Keep Falcon's permanent-checkout protection and
# borrow a connection only for that operation. This delegates the actual
# SQLite/PostgreSQL locking to RubyLLM. Remove when upstream uses with_connection.
module RubyLLMFileStoreConnection
  private

  def lock_chat
    chat.class.with_connection(prevent_permanent_checkout: true) { super }
  end
end

RubyLLM::ActiveRecord::FileStore.prepend(RubyLLMFileStoreConnection)

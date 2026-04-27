# frozen_string_literal: true

##
# ChatChannel - ActionCable channel for real-time chat
#
# Broadcasts:
# - new_message: New message added to chat
# - update_message: Message content updated (streaming)
# - remove_message: Message removed from chat
#
# Compatible with:
# - async-cable (Falcon) - default for Rails 8
# - anycable (Go) - for scale
# - standard ActionCable (Redis) - fallback
#
class ChatChannel < ApplicationCable::Channel
  def subscribed
    chat = Chat.find(params[:id])

    unless authorized?(chat)
      reject
      return
    end

    stream_from "chat_#{chat.id}"

    Rails.logger.info "[ChatChannel] Subscribed to chat_#{chat.id}"
  end

  def unsubscribed
    Rails.logger.info "[ChatChannel] Unsubscribed from chat_#{params[:id]}"
    stop_all_streams
  end

  private

  def authorized?(chat)
    # User may have members across multiple workspaces — any of them
    # being a chat participant grants access.
    member_ids = Member.where(user: current_user).select(:id)
    chat.chat_members.where(member_id: member_ids).exists?
  end
end


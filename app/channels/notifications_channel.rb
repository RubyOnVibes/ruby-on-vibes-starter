# frozen_string_literal: true

##
# NotificationsChannel
#
# ActionCable channel for real-time notification updates
# Used by Inertia adapter and for cross-tab sync
#
class NotificationsChannel < ApplicationCable::Channel
  def subscribed
    # Subscribe to user's notification stream
    stream_from "notifications_#{current_user.id}" if current_user
  end
  
  def unsubscribed
    # Cleanup when channel is unsubscribed
    stop_all_streams
  end
end

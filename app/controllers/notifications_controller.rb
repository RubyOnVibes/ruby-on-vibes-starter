class NotificationsController < ApplicationController
  before_action :authenticate_user!
  include Pagy::Method
  
  def index
    @pagy, @notifications = pagy(
      current_user.notifications.order(created_at: :desc),
      limit: 25
    )
    
    @unread_count = current_user.notifications.unread.count
    
    respond_to do |format|
      format.html { render :index }
      format.json do
        render json: {
          notifications: @notifications.map { |n| serialize_notification(n) },
          unreadCount: @unread_count,
          pagination: @pagy.data_hash
        }
      end
    end
  end
  
  def mark_as_read
    @notification = current_user.notifications.find(params[:id])
    @notification.mark_as_read!
    
    respond_to do |format|
      format.html { redirect_back(fallback_location: notifications_path) }
      format.json { head :ok }
    end
  end
  
  def mark_all_as_read
    current_user.notifications.unread.update_all(read_at: Time.current)
    
    respond_to do |format|
      format.html { redirect_back(fallback_location: notifications_path) }
      format.json { head :ok }
    end
  end
  
  private
  
  def serialize_notification(notification)
    {
      id: notification.id,
      type: notification.type,
      message: notification.message,
      title: notification.try(:title),
      url: notification.url,
      icon: notification.try(:icon),
      iconColor: notification.try(:icon_color),
      actionLabel: notification.try(:action_label),
      actionUrl: notification.try(:action_url),
      params: notification.event&.params || {},
      readAt: notification.read_at&.iso8601,
      seenAt: notification.seen_at&.iso8601,
      createdAt: notification.created_at.iso8601,
      updatedAt: notification.updated_at.iso8601
    }
  end
end

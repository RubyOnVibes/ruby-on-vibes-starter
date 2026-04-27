module NotificationsHelper
  def unread_notifications_data_attrs
    return { count: 0, url: '/notifications' }.to_json unless user_signed_in?
    
    {
      count: current_user.notifications.unread.count,
      url: notifications_path
    }.to_json
  end
  def unread_notifications_count
    return 0 unless user_signed_in?
    
    current_user.notifications.unread.count
  end
  
  def notification_time_ago(notification)
    time_ago_in_words(notification.created_at)
  end
  
  def notification_icon_class(notification)
    notification.try(:icon_color) || 'bg-surface-2'
  end
end

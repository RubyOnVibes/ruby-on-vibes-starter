import NotificationItem from './NotificationItem'

export default function NotificationList({
  notifications,
  onMarkAsRead,
  onMarkAllAsRead,
  isLoading = false,
  emptyState,
  className = ''
}) {
  const unreadCount = notifications.filter(n => !n.readAt).length

  if (isLoading) {
    return (
      <div className="flex items-center justify-center py-12">
        <div className="animate-spin h-8 w-8 border-2 border-primary border-t-transparent rounded-full" />
      </div>
    )
  }

  if (notifications.length === 0) {
    return (
      <div className={`flex flex-col items-center justify-center py-20 ${className}`}>
        {emptyState || (
          <div className="flex flex-col items-center max-w-sm text-center">
            <div className="relative mb-6">
              <div className="absolute inset-0 bg-gradient-to-br from-primary/10 to-primary/5 rounded-full blur-2xl" />
              <svg
                className="relative w-12 h-12 text-muted-foreground"
                fill="none"
                viewBox="0 0 24 24"
                stroke="currentColor"
                strokeWidth={1.5}
              >
                <path
                  strokeLinecap="round"
                  strokeLinejoin="round"
                  d="M15 17h5l-1.405-1.405A2.032 2.032 0 0118 14.158V11a6.002 6.002 0 00-4-5.659V5a2 2 0 10-4 0v.341C7.67 6.165 6 8.388 6 11v3.159c0 .538-.214 1.055-.595 1.436L4 17h5m6 0v1a3 3 0 11-6 0v-1m6 0H9"
                />
              </svg>
            </div>

            {/* Elegant typography */}
            <h3 className="text-base font-medium text-foreground mb-2">
              No notifications yet
            </h3>
            <p className="text-sm text-muted-foreground leading-relaxed">
              When you receive notifications, they'll appear here
            </p>
          </div>
        )}
      </div>
    )
  }

  return (
    <div className={`space-y-6 ${className}`}>
      {unreadCount > 0 && (
        <div className="flex items-center justify-between mb-6">
          <p className="text-sm text-secondary-foreground">
            {unreadCount} unread notification{unreadCount !== 1 ? 's' : ''}
          </p>
          <button
            onClick={onMarkAllAsRead}
            className="text-sm font-medium text-primary hover:underline"
          >
            mark all as read
          </button>
        </div>
      )}

      <div className="space-y-0">
        {notifications.map((notification) => (
          <NotificationItem
            key={notification.id}
            notification={notification}
            onMarkAsRead={onMarkAsRead}
          />
        ))}
      </div>
    </div>
  )
}

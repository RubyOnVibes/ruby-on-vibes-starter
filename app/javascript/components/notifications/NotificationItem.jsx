import { formatRelativeTime } from './types'

export default function NotificationItem({
  notification,
  onMarkAsRead,
  onClick,
  className = ''
}) {
  const isUnread = !notification.readAt

  const handleClick = () => {
    if (isUnread && onMarkAsRead) {
      onMarkAsRead(notification.id)
    }

    if (onClick) {
      onClick(notification)
    } else if (notification.url) {
      window.location.href = notification.url
    }
  }

  return (
    <div
      onClick={handleClick}
      className={`
        group relative cursor-pointer transition-colors mb-2
        ${isUnread ? 'bg-background' : 'bg-muted'}
        border-l-2 ${isUnread ? 'border-primary' : 'border-border'}
        ${className}
      `}
    >
      <div className="px-4 py-3 flex items-start gap-3">
        {/* Icon (optional) */}
        {notification.icon && (
          <div className={`flex-shrink-0 w-8 h-8 rounded-full flex items-center justify-center ${notification.iconColor || 'bg-surface-2'}`}>
            {notification.icon.startsWith('http') ? (
              <img src={notification.icon} alt="" className="w-5 h-5" />
            ) : (
              <span className="text-sm">{notification.icon}</span>
            )}
          </div>
        )}

        <div className="flex-1 min-w-0">
          {notification.title && (
            <div className={`text-sm font-semibold text-primary mb-0.5 ${isUnread ? 'font-bold' : ''}`}>
              {notification.title}
            </div>
          )}

          <div className={`text-sm text-secondary-foreground ${isUnread ? 'font-medium' : ''}`}>
            {notification.message}
          </div>

          <div className="text-xs text-muted-foreground mt-1">
            {formatRelativeTime(notification.createdAt)}
          </div>

          {notification.actionLabel && notification.actionUrl && (
            <a
              href={notification.actionUrl}
              onClick={(e) => e.stopPropagation()}
              className="inline-block mt-2 text-xs font-medium text-primary hover:underline"
            >
              {notification.actionLabel} →
            </a>
          )}
        </div>
      </div>
    </div>
  )
}

import { useEffect, useRef } from 'react'
import NotificationItem from './NotificationItem'

export default function NotificationDropdown({
  notifications,
  unreadCount,
  isOpen,
  onClose,
  onMarkAsRead,
  onMarkAllAsRead,
  onViewAll,
  isLoading = false,
  className = ''
}) {
  const dropdownRef = useRef(null)

  useEffect(() => {
    if (!isOpen) return

    const handleClickOutside = (event) => {
      if (dropdownRef.current && !dropdownRef.current.contains(event.target)) {
        onClose()
      }
    }

    document.addEventListener('mousedown', handleClickOutside)
    return () => document.removeEventListener('mousedown', handleClickOutside)
  }, [isOpen, onClose])

  useEffect(() => {
    if (!isOpen) return

    const handleEscape = (event) => {
      if (event.key === 'Escape') {
        onClose()
      }
    }

    document.addEventListener('keydown', handleEscape)
    return () => document.removeEventListener('keydown', handleEscape)
  }, [isOpen, onClose])

  if (!isOpen) return null

  const recentNotifications = notifications.slice(0, 5)
  const hasMore = notifications.length > 5

  return (
    <div
      ref={dropdownRef}
      className={`
        mt-2 w-96 max-w-[calc(100vw-2rem)]
        bg-surface-0 border-border rounded-lg shadow-xl z-50
        fixed left-1/2 -translate-x-1/2 top-16
        md:absolute md:left-auto md:right-0 md:translate-x-0 md:top-auto
        ${className}
      `}
    >
      {unreadCount > 0 && (
        <div className="flex items-center justify-end px-4 py-2 border-border-b">
          <button
            onClick={onMarkAllAsRead}
            className="text-xs font-medium text-primary hover:underline"
          >
            Mark all as read
          </button>
        </div>
      )}

      <div className="max-h-96 overflow-y-auto">
        {isLoading ? (
          <div className="flex items-center justify-center py-8">
            <div className="animate-spin h-6 w-6 border-2 border-primary border-t-transparent rounded-full" />
          </div>
        ) : recentNotifications.length === 0 ? (
          <div className="flex flex-col items-center justify-center py-12 px-4">
            <div className="flex flex-col items-center text-center">
              <div className="relative mb-4">
                <div className="absolute inset-0 bg-gradient-to-br from-primary/10 to-primary/5 rounded-full blur-xl" />
                <svg
                  className="relative w-10 h-10 text-muted-foreground"
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

              <p className="text-sm font-medium">
                No notifications yet
              </p>
            </div>
          </div>
        ) : (
          <div className="py-2">
            {recentNotifications.map((notification) => (
              <NotificationItem
                key={notification.id}
                notification={notification}
                onMarkAsRead={onMarkAsRead}
              />
            ))}
          </div>
        )}
      </div>

      {recentNotifications.length > 0 && (
        <div className="border-border-t px-4 py-2">
          <button
            onClick={onViewAll}
            className="w-full text-center text-sm font-medium text-primary hover:underline py-1"
          >
            View all
          </button>
        </div>
      )}
    </div>
  )
}

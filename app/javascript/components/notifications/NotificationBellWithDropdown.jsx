/**
 * NotificationBellWithDropdown - Self-contained notification bell with dropdown
 *
 * Single source of truth for notification UI. Used by:
 * - ERB: NotificationsIconIsland wraps this component
 * - Inertia: NavbarCore uses this directly
 */
import { useState, useEffect } from 'react'
import NotificationBell from './NotificationBell'
import NotificationDropdown from './NotificationDropdown'

export default function NotificationBellWithDropdown({
  initialUnreadCount = 0
}) {
  const [isOpen, setIsOpen] = useState(false)
  const [notifications, setNotifications] = useState([])
  const [unreadCount, setUnreadCount] = useState(initialUnreadCount)
  const [isLoading, setIsLoading] = useState(false)

  const fetchNotifications = async () => {
    if (isLoading) return

    setIsLoading(true)

    try {
      const response = await fetch('/notifications.json', {
        headers: {
          'Accept': 'application/json',
          'X-Requested-With': 'XMLHttpRequest'
        }
      })

      if (!response.ok) throw new Error(`HTTP ${response.status}`)

      const data = await response.json()
      setNotifications(data.notifications || [])
      setUnreadCount(data.unreadCount || 0)
    } catch (error) {
      console.error('Failed to fetch notifications:', error)
    } finally {
      setIsLoading(false)
    }
  }

  useEffect(() => {
    fetchNotifications()
  }, [])

  useEffect(() => {
    if (isOpen && !isLoading) {
      fetchNotifications()
    }
  }, [isOpen])

  const handleViewAll = () => {
    window.location.href = '/notifications'
  }

  const handleMarkAsRead = async (id) => {
    try {
      const response = await fetch(`/notifications/${id}/mark_as_read`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'X-CSRF-Token': document.querySelector('meta[name="csrf-token"]')?.content || '',
          'X-Requested-With': 'XMLHttpRequest'
        }
      })

      if (response.ok) {
        setNotifications(prev =>
          prev.map(n => n.id === id ? { ...n, readAt: new Date().toISOString() } : n)
        )
        setUnreadCount(prev => Math.max(0, prev - 1))
      }
    } catch (error) {
      console.error('Failed to mark as read:', error)
    }
  }

  const handleMarkAllAsRead = async () => {
    try {
      const response = await fetch('/notifications/mark_all_as_read', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'X-CSRF-Token': document.querySelector('meta[name="csrf-token"]')?.content || '',
          'X-Requested-With': 'XMLHttpRequest'
        }
      })

      if (response.ok) {
        const now = new Date().toISOString()
        setNotifications(prev => prev.map(n => ({ ...n, readAt: now })))
        setUnreadCount(0)
      }
    } catch (error) {
      console.error('Failed to mark all as read:', error)
    }
  }

  return (
    <div className="relative">
      <NotificationBell
        unreadCount={unreadCount}
        onClick={() => setIsOpen(!isOpen)}
      />

      <NotificationDropdown
        notifications={notifications}
        unreadCount={unreadCount}
        isOpen={isOpen}
        onClose={() => setIsOpen(false)}
        onMarkAsRead={handleMarkAsRead}
        onMarkAllAsRead={handleMarkAllAsRead}
        onViewAll={handleViewAll}
      />
    </div>
  )
}

/**
 * useInertiaNotifications Hook
 *
 * Inertia adapter for notifications using ActionCable
 * Real-time updates via WebSocket subscription
 */

import { useState, useEffect } from 'react'
import { createConsumer } from '@rails/actioncable'
import { sanitizeNotifications } from '../components/notifications/types'

/**
 * Inertia adapter for notifications with ActionCable
 */
export function useInertiaNotifications(options = {}) {
  const [notifications, setNotifications] = useState(
    sanitizeNotifications(options.initialNotifications || [], 'initial')
  )
  const [unreadCount, setUnreadCount] = useState(options.initialUnreadCount || 0)
  const [isLoading, setIsLoading] = useState(false)

  // Subscribe to ActionCable for real-time updates
  useEffect(() => {
    const cable = createConsumer()

    const subscription = cable.subscriptions.create(
      { channel: 'NotificationsChannel' },
      {
        received(data) {
          console.log('[Notifications] Received cable message:', data)

          switch (data.type) {
            case 'new_notification':
              // Add new notification to top
              if (data.notification) {
                const newNotification = data.notification
                setNotifications(prev => [newNotification, ...prev])
                setUnreadCount(prev => prev + 1)
              }
              break

            case 'mark_as_read':
              // Update notification read status
              if (data.id) {
                setNotifications(prev =>
                  prev.map(n =>
                    n.id === data.id
                      ? { ...n, readAt: data.readAt || new Date().toISOString() }
                      : n
                  )
                )
                setUnreadCount(prev => Math.max(0, prev - 1))
              }
              break

            case 'mark_all_as_read':
              // Mark all as read
              const now = new Date().toISOString()
              setNotifications(prev =>
                prev.map(n => ({ ...n, readAt: n.readAt || now }))
              )
              setUnreadCount(0)
              break

            case 'unread_count':
              // Update unread count
              if (typeof data.count === 'number') {
                setUnreadCount(data.count)
              }
              break
          }
        },

        connected() {
          console.log('[Notifications] Connected to ActionCable')
        },

        disconnected() {
          console.log('[Notifications] Disconnected from ActionCable')
        }
      }
    )

    return () => {
      subscription.unsubscribe()
    }
  }, [])

  // Mark as read
  const markAsRead = async (id) => {
    // Optimistic update
    setNotifications(prev =>
      prev.map(n =>
        n.id === id
          ? { ...n, readAt: new Date().toISOString() }
          : n
      )
    )
    setUnreadCount(prev => Math.max(0, prev - 1))

    try {
      const response = await fetch(`/notifications/${id}/mark_as_read`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'X-CSRF-Token': document.querySelector('meta[name="csrf-token"]')?.getAttribute('content') || ''
        }
      })

      if (!response.ok) {
        throw new Error('Failed to mark notification as read')
      }

      // ActionCable will broadcast the confirmation
    } catch (error) {
      console.error('[Notifications] Failed to mark as read:', error)

      // Revert optimistic update on error
      setNotifications(prev =>
        prev.map(n =>
          n.id === id
            ? { ...n, readAt: null }
            : n
        )
      )
      setUnreadCount(prev => prev + 1)
    }
  }

  // Mark all as read
  const markAllAsRead = async () => {
    // Optimistic update
    const now = new Date().toISOString()
    const prevNotifications = notifications
    const prevUnreadCount = unreadCount

    setNotifications(prev =>
      prev.map(n => ({ ...n, readAt: n.readAt || now }))
    )
    setUnreadCount(0)

    try {
      const response = await fetch('/notifications/mark_all_as_read', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'X-CSRF-Token': document.querySelector('meta[name="csrf-token"]')?.getAttribute('content') || ''
        }
      })

      if (!response.ok) {
        throw new Error('Failed to mark all notifications as read')
      }

      // ActionCable will broadcast the confirmation
    } catch (error) {
      console.error('[Notifications] Failed to mark all as read:', error)

      // Revert optimistic update on error
      setNotifications(prevNotifications)
      setUnreadCount(prevUnreadCount)
    }
  }

  // Reload notifications
  const reload = async () => {
    setIsLoading(true)
    try {
      const response = await fetch('/notifications.json')
      if (!response.ok) {
        throw new Error('Failed to reload notifications')
      }

      const data = await response.json()
      setNotifications(sanitizeNotifications(data.notifications, 'reload'))
      setUnreadCount(data.unreadCount || 0)
    } catch (error) {
      console.error('[Notifications] Failed to reload:', error)
    } finally {
      setIsLoading(false)
    }
  }

  return {
    notifications,
    unreadCount,
    isLoading,
    markAsRead,
    markAllAsRead,
    reload
  }
}

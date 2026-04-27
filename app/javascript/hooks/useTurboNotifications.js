/**
 * useTurboNotifications Hook
 *
 * ERB/Islands adapter for notifications using Turbo Streams
 * Hydrates from DOM and syncs via MutationObserver
 */

import { useState, useEffect } from 'react'
import { sanitizeNotifications } from '../components/notifications/types'

/**
 * Hydrate notifications from DOM
 */
function hydrateNotificationsFromDOM() {
  const container = document.querySelector('#notifications')
  if (!container) return []

  const notificationDivs = container.querySelectorAll('[data-notification]')
  const notifications = []

  notificationDivs.forEach(div => {
    try {
      const data = div.getAttribute('data-notification')
      if (data) {
        const notification = JSON.parse(data)
        notifications.push(notification)
      }
    } catch (error) {
      console.warn('[Notifications] Failed to parse notification from DOM:', error)
    }
  })

  return sanitizeNotifications(notifications, 'DOM hydration')
}

/**
 * Get unread count from meta tag
 */
function getUnreadCountFromDOM() {
  const meta = document.querySelector('meta[name="notifications-unread-count"]')
  if (!meta) return 0

  const content = meta.getAttribute('content')
  return content ? parseInt(content, 10) : 0
}

/**
 * Turbo adapter for notifications
 */
export function useTurboNotifications() {
  const [notifications, setNotifications] = useState([])
  const [unreadCount, setUnreadCount] = useState(0)
  const [isLoading, setIsLoading] = useState(false)

  // Hydrate initial state from DOM
  useEffect(() => {
    const initial = hydrateNotificationsFromDOM()
    const count = getUnreadCountFromDOM()

    setNotifications(initial)
    setUnreadCount(count)
  }, [])

  // Observe DOM changes via Turbo Streams
  useEffect(() => {
    const container = document.querySelector('#notifications')
    if (!container) return

    const observer = new MutationObserver((mutations) => {
      let needsUpdate = false

      mutations.forEach((mutation) => {
        if (mutation.type === 'childList' || mutation.type === 'attributes') {
          needsUpdate = true
        }
      })

      if (needsUpdate) {
        const updated = hydrateNotificationsFromDOM()
        const count = getUnreadCountFromDOM()

        setNotifications(updated)
        setUnreadCount(count)
      }
    })

    observer.observe(container, {
      childList: true,
      subtree: true,
      attributes: true,
      attributeFilter: ['data-notification']
    })

    return () => observer.disconnect()
  }, [])

  // Mark as read
  const markAsRead = async (id) => {
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

      // Turbo will broadcast the update
    } catch (error) {
      console.error('[Notifications] Failed to mark as read:', error)
    }
  }

  // Mark all as read
  const markAllAsRead = async () => {
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

      // Turbo will broadcast the update
    } catch (error) {
      console.error('[Notifications] Failed to mark all as read:', error)
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

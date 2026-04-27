/**
 * useNavbarNotifications Hook
 *
 * Lightweight adapter for navbar bell icon
 * Fetches notifications via JSON API when dropdown opens
 */

import { useState } from 'react'
import { sanitizeNotifications } from '../components/notifications/types'

/**
 * Get initial unread count from window.Notifications
 */
function getInitialCount() {
  if (typeof window === 'undefined') return 0

  try {
    const data = window.Notifications?.data?.()
    return data?.count || 0
  } catch (error) {
    console.warn('[Notifications] Failed to get initial count:', error)
    return 0
  }
}

/**
 * Fetch notifications from JSON API
 */
async function fetchNotifications() {
  try {
    const response = await fetch('/notifications.json', {
      headers: {
        'Accept': 'application/json',
        'X-Requested-With': 'XMLHttpRequest'
      }
    })

    if (!response.ok) {
      throw new Error(`HTTP ${response.status}`)
    }

    const data = await response.json()
    return {
      notifications: sanitizeNotifications(data.notifications || [], 'JSON API'),
      unreadCount: data.unreadCount || 0
    }
  } catch (error) {
    console.error('[Notifications] Failed to fetch:', error)
    return {
      notifications: [],
      unreadCount: getInitialCount()
    }
  }
}

/**
 * Mark notification as read
 */
async function markNotificationAsRead(id) {
  try {
    const response = await fetch(`/notifications/${id}/mark_as_read`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'X-CSRF-Token': document.querySelector('meta[name="csrf-token"]')?.content || '',
        'X-Requested-With': 'XMLHttpRequest'
      }
    })

    if (!response.ok) {
      throw new Error(`HTTP ${response.status}`)
    }
  } catch (error) {
    console.error('[Notifications] Failed to mark as read:', error)
    throw error
  }
}

/**
 * Mark all notifications as read
 */
async function markAllNotificationsAsRead() {
  try {
    const response = await fetch('/notifications/mark_all_as_read', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'X-CSRF-Token': document.querySelector('meta[name="csrf-token"]')?.content || '',
        'X-Requested-With': 'XMLHttpRequest'
      }
    })

    if (!response.ok) {
      throw new Error(`HTTP ${response.status}`)
    }
  } catch (error) {
    console.error('[Notifications] Failed to mark all as read:', error)
    throw error
  }
}

/**
 * Navbar adapter for notifications
 * Lightweight - only fetches when needed
 */
export function useNavbarNotifications() {
  const [notifications, setNotifications] = useState([])
  const [unreadCount, setUnreadCount] = useState(getInitialCount)
  const [isLoading, setIsLoading] = useState(false)
  const [hasFetched, setHasFetched] = useState(false)

  // Fetch notifications (lazy - only when dropdown opens)
  const fetchAndUpdate = async () => {
    if (isLoading) return

    setIsLoading(true)
    try {
      const data = await fetchNotifications()
      setNotifications(data.notifications)
      setUnreadCount(data.unreadCount)
      setHasFetched(true)
    } catch (error) {
      console.error('[Notifications] Fetch failed:', error)
    } finally {
      setIsLoading(false)
    }
  }

  // Mark as read handler
  const markAsRead = async (id) => {
    try {
      await markNotificationAsRead(id)

      // Optimistic update
      setNotifications(prev =>
        prev.map(n => n.id === id ? { ...n, readAt: new Date().toISOString() } : n)
      )
      setUnreadCount(prev => Math.max(0, prev - 1))
    } catch (error) {
      console.error('[Notifications] Mark as read failed:', error)
      // Refetch on error
      await fetchAndUpdate()
    }
  }

  // Mark all as read handler
  const markAllAsRead = async () => {
    try {
      await markAllNotificationsAsRead()

      // Optimistic update
      const now = new Date().toISOString()
      setNotifications(prev =>
        prev.map(n => ({ ...n, readAt: now }))
      )
      setUnreadCount(0)
    } catch (error) {
      console.error('[Notifications] Mark all as read failed:', error)
      // Refetch on error
      await fetchAndUpdate()
    }
  }

  return {
    notifications,
    unreadCount,
    isLoading,
    markAsRead,
    markAllAsRead,
    // Expose fetch method for lazy loading
    fetch: fetchAndUpdate,
    hasFetched
  }
}

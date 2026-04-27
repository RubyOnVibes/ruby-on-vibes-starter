export function isValidNotification(n) {
  if (!n || typeof n !== 'object') return false
  if (!n.id) return false
  if (typeof n.message !== 'string') return false
  if (typeof n.type !== 'string') return false
  if (typeof n.createdAt !== 'string') return false
  return true
}

export function sanitizeNotifications(notifications, context = 'unknown') {
  if (!Array.isArray(notifications)) return []

  const valid = notifications.filter(isValidNotification)

  if (valid.length !== notifications.length && typeof console !== 'undefined') {
    console.warn(`[Notifications] Dropped ${notifications.length - valid.length} invalid notifications (${context})`)
  }

  return valid
}

export function groupNotifications(notifications) {
  const now = new Date()
  const today = new Date(now.getFullYear(), now.getMonth(), now.getDate())
  const yesterday = new Date(today)
  yesterday.setDate(yesterday.getDate() - 1)
  const thisWeek = new Date(today)
  thisWeek.setDate(thisWeek.getDate() - 7)

  const groups = {
    Today: [],
    Yesterday: [],
    'This Week': [],
    Older: []
  }

  notifications.forEach(n => {
    const created = new Date(n.createdAt)

    if (created >= today) {
      groups.Today.push(n)
    } else if (created >= yesterday) {
      groups.Yesterday.push(n)
    } else if (created >= thisWeek) {
      groups['This Week'].push(n)
    } else {
      groups.Older.push(n)
    }
  })

  return Object.entries(groups)
    .filter(([_, notifications]) => notifications.length > 0)
    .map(([label, notifications]) => ({ label, notifications }))
}

export function formatRelativeTime(dateString) {
  const date = new Date(dateString)
  const now = new Date()
  const seconds = Math.floor((now.getTime() - date.getTime()) / 1000)

  if (seconds < 60) return 'just now'
  if (seconds < 3600) {
    const minutes = Math.floor(seconds / 60)
    return `${minutes}m ago`
  }
  if (seconds < 86400) {
    const hours = Math.floor(seconds / 3600)
    return `${hours}h ago`
  }
  if (seconds < 604800) {
    const days = Math.floor(seconds / 86400)
    return `${days}d ago`
  }

  return date.toLocaleDateString('en-US', { month: 'short', day: 'numeric' })
}

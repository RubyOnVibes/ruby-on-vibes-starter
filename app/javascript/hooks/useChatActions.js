import { useCallback } from 'react'

function getCsrfToken() {
  const token = document.querySelector('meta[name="csrf-token"]')?.content
  if (!token) throw new Error('CSRF token not found')
  return token
}

/**
 * useChatActions - Handles chat CRUD operations (stop, rename, delete, leave).
 * Extracts API calls from ChatIsland to keep the component focused on rendering.
 */
export function useChatActions(chatId, { cancelRun, canStop } = {}) {
  const handleStop = useCallback(async () => {
    if (canStop && cancelRun) {
      try {
        await cancelRun()
      } catch (err) {
        // Silently handle "already stopped" scenarios - this is expected
        // during race conditions where the run completes naturally
        console.debug('[useChatActions] Cancel completed (may have already stopped)')
      }
    }
  }, [canStop, cancelRun])

  const rename = useCallback(async (newName) => {
    if (!chatId) return

    const token = getCsrfToken()
    const response = await fetch(`/chats/${chatId}`, {
      method: 'PATCH',
      headers: {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
        'X-CSRF-Token': token
      },
      body: JSON.stringify({ chat: { name: newName } })
    })

    if (!response.ok) {
      const error = await response.json()
      throw new Error(error.error || 'Failed to rename chat')
    }

    // Update sidebar label
    const sidebarItem = document.querySelector(`.chat-list-item.active div`)
    if (sidebarItem) {
      sidebarItem.textContent = newName
    }

    return newName
  }, [chatId])

  const remove = useCallback(async () => {
    if (!chatId) return

    const token = getCsrfToken()
    const response = await fetch(`/chats/${chatId}`, {
      method: 'DELETE',
      headers: {
        'Accept': 'application/json',
        'X-CSRF-Token': token
      }
    })

    if (!response.ok) {
      const error = await response.json()
      throw new Error(error.error || 'Failed to delete chat')
    }

    window.Turbo.visit('/chats')
  }, [chatId])

  const leave = useCallback(async () => {
    if (!chatId) return

    const token = getCsrfToken()
    const response = await fetch(`/chats/${chatId}/leave`, {
      method: 'POST',
      headers: {
        'Accept': 'application/json',
        'X-CSRF-Token': token
      }
    })

    if (!response.ok) {
      const error = await response.json()
      throw new Error(error.error || 'Failed to leave chat')
    }

    window.location.href = '/chats'
  }, [chatId])

  const clear = useCallback(async () => {
    if (!chatId) return

    const token = getCsrfToken()
    const response = await fetch(`/chats/${chatId}/clear`, {
      method: 'POST',
      headers: {
        'Accept': 'application/json',
        'X-CSRF-Token': token
      }
    })

    if (!response.ok) {
      throw new Error('Failed to clear chat')
    }
  }, [chatId])

  return { handleStop, rename, remove, leave, clear }
}

import { useState, useEffect, useCallback } from 'react'

export function useChatMembers(chatId) {
  const [members, setMembers] = useState([])
  const [isLoading, setIsLoading] = useState(false)
  const [error, setError] = useState(null)

  const fetchMembers = useCallback(async () => {
    if (!chatId) {
      setMembers([])
      return
    }

    setIsLoading(true)
    setError(null)

    try {
      const response = await fetch(`/chats/${chatId}/members`, {
        headers: {
          'Accept': 'application/json'
        }
      })

      if (!response.ok) {
        throw new Error('Failed to fetch members')
      }

      const data = await response.json()
      setMembers(data)
    } catch (err) {
      console.error('[useChatMembers] Fetch error:', err)
      setError(err instanceof Error ? err.message : 'Failed to load members')
    } finally {
      setIsLoading(false)
    }
  }, [chatId])

  const removeMember = useCallback(async (chatMemberId) => {
    if (!chatId) return false

    try {
      const token = document.querySelector('meta[name="csrf-token"]')?.getAttribute('content')
      if (!token) throw new Error('CSRF token not found')

      const response = await fetch(`/chats/${chatId}/members/${chatMemberId}`, {
        method: 'DELETE',
        headers: {
          'Accept': 'application/json',
          'X-CSRF-Token': token
        }
      })

      if (!response.ok) {
        const error = await response.json()
        throw new Error(error.error || 'Failed to remove member')
      }

      // Update local state
      setMembers(prev => prev.filter(m => m.id !== chatMemberId))
      return true
    } catch (err) {
      console.error('[useChatMembers] Remove error:', err)
      setError(err instanceof Error ? err.message : 'Failed to remove member')
      return false
    }
  }, [chatId])

  useEffect(() => {
    fetchMembers()
  }, [fetchMembers])

  return {
    members,
    isLoading,
    error,
    refetch: fetchMembers,
    removeMember
  }
}

export default useChatMembers

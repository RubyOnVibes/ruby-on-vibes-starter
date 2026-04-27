import { useState, useEffect, useCallback } from 'react'

export function useChatInvitations(chatId) {
  const [invitations, setInvitations] = useState([])
  const [isLoading, setIsLoading] = useState(false)

  const fetchInvitations = useCallback(async () => {
    if (!chatId) {
      setInvitations([])
      return
    }

    setIsLoading(true)

    try {
      const response = await fetch(`/api/v1/chats/${chatId}/pending_invitations`, {
        headers: {
          'Accept': 'application/json'
        }
      })

      if (!response.ok) {
        throw new Error('Failed to fetch invitations')
      }

      const data = await response.json()
      setInvitations(data)
    } catch (err) {
      console.error('[useChatInvitations] Fetch error:', err)
      setInvitations([])
    } finally {
      setIsLoading(false)
    }
  }, [chatId])

  const cancelInvitation = useCallback(async (invitationId) => {
    try {
      const token = document.querySelector('meta[name="csrf-token"]')?.getAttribute('content')
      if (!token) throw new Error('CSRF token not found')

      const response = await fetch(`/chats/invitations/${invitationId}`, {
        method: 'DELETE',
        headers: {
          'Accept': 'application/json',
          'X-CSRF-Token': token
        }
      })

      if (!response.ok) {
        throw new Error('Failed to cancel invitation')
      }

      // Update local state
      setInvitations(prev => prev.filter(inv => inv.id !== invitationId))
      return true
    } catch (err) {
      console.error('[useChatInvitations] Cancel error:', err)
      return false
    }
  }, [chatId])

  useEffect(() => {
    fetchInvitations()
  }, [fetchInvitations])

  return {
    invitations,
    isLoading,
    refetch: fetchInvitations,
    cancelInvitation
  }
}

export default useChatInvitations

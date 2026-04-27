import { useState, useCallback } from 'react'

export function useMemberLookup() {
  const [preview, setPreview] = useState(null)
  const [isLoading, setIsLoading] = useState(false)
  const [error, setError] = useState(null)

  const lookupMember = useCallback(async (memberId) => {
    if (!memberId || !memberId.trim()) {
      setPreview(null)
      setError(null)
      return
    }

    setIsLoading(true)
    setError(null)

    try {
      const response = await fetch(`/api/v1/members/${memberId}/preview`, {
        headers: {
          'Accept': 'application/json'
        }
      })

      if (!response.ok) {
        if (response.status === 404) {
          setError('Member not found')
          setPreview(null)
          return
        }
        throw new Error('Failed to lookup member')
      }

      const data = await response.json()
      setPreview(data)
      setError(null)
    } catch (err) {
      console.error('[useMemberLookup] Error:', err)
      setError(err instanceof Error ? err.message : 'Failed to lookup member')
      setPreview(null)
    } finally {
      setIsLoading(false)
    }
  }, [])

  const clear = useCallback(() => {
    setPreview(null)
    setError(null)
  }, [])

  return {
    preview,
    isLoading,
    error,
    lookupMember,
    clear
  }
}

export default useMemberLookup

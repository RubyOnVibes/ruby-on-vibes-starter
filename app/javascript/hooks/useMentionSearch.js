/**
 * useMentionSearch - Hook for @mention autocomplete
 *
 * Provides debounced search for mentionable models
 *
 * SCOPING:
 * - Without chatId: searches current org members + current org
 * - With chatId: expands to include chat members + their orgs (cross-org support)
 */

import { useState, useCallback, useMemo } from 'react'
import { debounceAsync } from '../utils/debounce'

export function useMentionSearch(
  options = {}
) {
  const { chatId, delay = 300, types, limit = 10 } = options

  const [results, setResults] = useState([])
  const [isLoading, setIsLoading] = useState(false)
  const [error, setError] = useState(null)

  // Fetch from API
  const fetchMentionables = useCallback(async (query) => {
    if (!query || query.trim().length === 0) {
      setResults([])
      return
    }

    setIsLoading(true)
    setError(null)

    try {
      const params = new URLSearchParams({ q: query.trim() })
      // Pass chatId for cross-org scoping in group chats
      if (chatId) {
        params.append('chat_id', chatId)
      }
      if (types && types.length > 0) {
        params.append('types', types.join(','))
      }
      if (limit) {
        params.append('limit', limit.toString())
      }

      const token = document.querySelector('meta[name="csrf-token"]')?.content || ''

      const response = await fetch(`/api/v1/mentionables?${params}`, {
        headers: {
          'Accept': 'application/json',
          'X-CSRF-Token': token
        }
      })

      if (!response.ok) {
        throw new Error(`HTTP ${response.status}`)
      }

      const data = await response.json()
      setResults(data.results || [])
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Search failed')
      setResults([])
    } finally {
      setIsLoading(false)
    }
  }, [chatId, types, limit])

  // Debounced search
  const debouncedSearch = useMemo(
    () => debounceAsync(fetchMentionables, delay),
    [fetchMentionables, delay]
  )

  // Public search function
  const search = useCallback(async (query) => {
    await debouncedSearch(query)
  }, [debouncedSearch])

  // Clear results
  const clear = useCallback(() => {
    setResults([])
    setError(null)
    setIsLoading(false)
  }, [])

  return {
    results,
    isLoading,
    error,
    search,
    clear
  }
}

export default useMentionSearch

import { useState, useEffect, useCallback, useRef } from 'react'

const ACTIVE_POLL_INTERVAL = 2000  // 2 seconds when tasks are running
const IDLE_POLL_INTERVAL = 10000   // 10 seconds when chat has tasks but none active

/**
 * Hook to poll agent task state for a chat.
 *
 * Polling strategy:
 * - On mount: fetch immediately
 * - While active tasks exist: poll every 3s (progress updates)
 * - While chat has tasks but none active: poll every 10s (catch new tasks)
 * - No tasks at all: no polling (refetch() can be called externally)
 *
 * The refetch() function is exposed so ChatIsland can trigger
 * an immediate fetch when a chat run completes (the most common
 * moment a tool will have created a new task).
 */
export function useAgentTasks(chatId) {
  const [tasks, setTasks] = useState([])
  const [hasActive, setHasActive] = useState(false)
  const intervalRef = useRef(null)
  const mountedRef = useRef(true)

  const fetchTasks = useCallback(async () => {
    if (!chatId) return

    try {
      const token = document.querySelector('meta[name="csrf-token"]')?.content || ''

      const response = await fetch(`/api/v1/agent_tasks?chat_id=${encodeURIComponent(chatId)}`, {
        headers: {
          'Accept': 'application/json',
          'X-CSRF-Token': token
        }
      })

      if (!response.ok) return

      const data = await response.json()
      if (!mountedRef.current) return

      setTasks(data.tasks || [])
      setHasActive(data.has_active || false)
    } catch (err) {
      console.error('[useAgentTasks] Fetch error:', err)
    }
  }, [chatId])

  const cancelTask = useCallback(async (taskId) => {
    try {
      const token = document.querySelector('meta[name="csrf-token"]')?.content || ''

      const response = await fetch(`/api/v1/agent_tasks/${encodeURIComponent(taskId)}/cancel`, {
        method: 'POST',
        headers: {
          'Accept': 'application/json',
          'X-CSRF-Token': token
        }
      })

      if (response.ok) {
        // Immediately update local state
        setTasks(prev => prev.map(t =>
          t.id === taskId ? { ...t, status: 'cancelled' } : t
        ))
        // Then fetch fresh state
        await fetchTasks()
      }
    } catch (err) {
      console.error('[useAgentTasks] Cancel error:', err)
    }
  }, [fetchTasks])

  const dismissTasks = useCallback(async () => {
    if (!chatId) return

    try {
      const token = document.querySelector('meta[name="csrf-token"]')?.content || ''

      const response = await fetch(`/api/v1/agent_tasks/dismiss?chat_id=${encodeURIComponent(chatId)}`, {
        method: 'POST',
        headers: {
          'Accept': 'application/json',
          'X-CSRF-Token': token
        }
      })

      if (response.ok) {
        // Immediately remove terminal tasks from local state
        setTasks(prev => prev.filter(t => t.status === 'pending' || t.status === 'running'))
      }
    } catch (err) {
      console.error('[useAgentTasks] Dismiss error:', err)
    }
  }, [chatId])

  // Initial fetch
  useEffect(() => {
    mountedRef.current = true
    fetchTasks()
    return () => { mountedRef.current = false }
  }, [fetchTasks])

  // Poll: fast when active, slow when idle with tasks, off when no tasks
  useEffect(() => {
    if (intervalRef.current) {
      clearInterval(intervalRef.current)
      intervalRef.current = null
    }

    if (hasActive) {
      intervalRef.current = setInterval(fetchTasks, ACTIVE_POLL_INTERVAL)
    } else if (tasks.length > 0) {
      intervalRef.current = setInterval(fetchTasks, IDLE_POLL_INTERVAL)
    }

    return () => {
      if (intervalRef.current) {
        clearInterval(intervalRef.current)
        intervalRef.current = null
      }
    }
  }, [hasActive, tasks.length > 0, fetchTasks])

  return {
    tasks,
    hasActive,
    cancelTask,
    dismissTasks,
    refetch: fetchTasks
  }
}

export default useAgentTasks

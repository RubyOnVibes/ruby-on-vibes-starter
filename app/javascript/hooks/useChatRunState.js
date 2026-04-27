import { useState, useEffect, useCallback } from 'react'

export function useChatRunState(chatId) {
  const [activeRun, setActiveRun] = useState(null)

  const updateFromDOM = useCallback(() => {
    const stateEl = document.querySelector('#chat-run-state')

    if (!stateEl) {
      setActiveRun(null)
      return
    }

    const data = stateEl.getAttribute('data-chat-run')

    if (!data) {
      setActiveRun(null)
      return
    }

    try {
      const run = JSON.parse(data)
      console.log(`[useChatRunState] status=${run.status} isActive=${run.isActive} id=${run.id}`)

      if (run.isActive) {
        setActiveRun(run)
      } else {
        setActiveRun(null)
      }
    } catch (err) {
      console.error('[useChatRunState] Failed to parse chat run data:', err)
      setActiveRun(null)
    }
  }, [])

  useEffect(() => {
    if (!chatId) return

    const containerEl = document.querySelector('#chat-run-state-container')
    if (!containerEl) return

    updateFromDOM()

    const observer = new MutationObserver(() => {
      updateFromDOM()
    })

    observer.observe(containerEl, {
      childList: true,
      subtree: true,
      attributes: true,
      attributeFilter: ['data-chat-run']
    })

    return () => {
      observer.disconnect()
    }
  }, [chatId, updateFromDOM])

  const cancelRun = useCallback(async () => {
    if (!activeRun?.id) return

    try {
      const token = document.querySelector('meta[name="csrf-token"]')?.getAttribute('content') || ''

      const response = await fetch(`/chat_runs/${activeRun.id}/cancel`, {
        method: 'POST',
        headers: {
          'X-CSRF-Token': token,
          'Accept': 'application/json'
        }
      })

      if (!response.ok) {
        const error = await response.json()
        throw new Error(error.error || 'Failed to cancel')
      }
    } catch (err) {
      console.error('[useChatRunState] Cancel error:', err)
      throw err
    }
  }, [activeRun])

  return {
    activeRun,
    isProcessing: activeRun !== null,
    isAwaitingTasks: activeRun?.status === 'awaiting_tasks',
    canStop: activeRun !== null,
    cancelRun
  }
}

export default useChatRunState

import { useState, useEffect, useCallback, useRef, useMemo } from 'react'
import { sanitizeMessages, normalizeContent } from '../components/chat/types'

function normalizeBoolean(value) {
  return value === true || value === 'true' || value === 1 || value === '1'
}

export function useTurboChat(
  chatId,
  options = {}
) {
  const { selectors = {} } = options

  const messageListSelector = selectors.messageList || '#messages'
  const messageContentSelector = useMemo(
    () => selectors.messageContent || ((id) => `#message_${id}_content`),
    [selectors.messageContent]
  )

  const [messages, setMessages] = useState([])
  const [isSending, setIsSending] = useState(false)

  const messagesIndexRef = useRef(new Map())
  const idleTimerRef = useRef(null)
  const reconcileRef = useRef(null)

  const hydrateMessagesFromDOM = useCallback(() => {
    const listEl = document.querySelector(messageListSelector)
    if (!listEl) return []

    const items = []
    listEl.querySelectorAll("[id^='message-'][data-message]").forEach((el) => {
      try {
        const payload = JSON.parse(el.getAttribute('data-message') || '{}')
        const id = Number(payload.id)
        if (!Number.isFinite(id)) return

        if (payload.role === 'user' && payload.user_submitted === false) return

        const contentEl = document.querySelector(messageContentSelector(id))
        let content = contentEl?.getAttribute('data-raw-content') || payload.content || ''
        content = normalizeContent(content)

        const mentions = Array.isArray(payload.mentions)
          ? payload.mentions.map((m) => ({
              id: String(m.id || ''),
              model: String(m.model || ''),
              label: String(m.label || ''),
              path: m.path,
              avatar: m.avatar,
              metadata: m.metadata
            }))
          : []

        items.push({
          id,
          role: payload.role || 'assistant',
          content,
          mentions,
          attachments: payload.attachments || [],
          metadata: payload.metadata || {},
          tool_call_name: payload.tool_call_name || null,
          user: payload.user || null,
          compacted: normalizeBoolean(payload.compacted),
          createdAt: payload.created_at,
          updatedAt: payload.updated_at
        })
      } catch {
        // Skip unparseable messages
      }
    })

    return sanitizeMessages(items, 'hydrate')
  }, [messageListSelector, messageContentSelector])

  useEffect(() => {
    const listEl = document.querySelector(messageListSelector)
    if (!listEl) return

    const listObserver = new MutationObserver((mutations) => {
      const addedMessages = []
      const removedIds = new Set()
      const addedIds = new Set()

      for (const mutation of mutations) {
        if (mutation.type === 'childList') {
          mutation.removedNodes.forEach((node) => {
            if (node instanceof HTMLElement && node.id?.startsWith('message-')) {
              const id = parseInt(node.id.replace(/^message-(\d+).*$/, '$1'), 10)
              if (Number.isFinite(id)) removedIds.add(id)
            }
          })

          mutation.addedNodes.forEach((node) => {
            if (!(node instanceof HTMLElement)) return
            if (!node.id?.startsWith('message-')) return

            const json = node.getAttribute('data-message')
            if (!json) return

            try {
              const payload = JSON.parse(json)
              const id = Number(payload.id)
              if (!Number.isFinite(id)) return

              addedIds.add(id)

              const contentEl = document.querySelector(messageContentSelector(id))
              let content = contentEl?.getAttribute('data-raw-content') || payload.content || ''
              content = normalizeContent(content)

              const mentions = Array.isArray(payload.mentions)
                ? payload.mentions.map((m) => ({
                    id: String(m.id || ''),
                    model: String(m.model || ''),
                    label: String(m.label || ''),
                    path: m.path,
                    avatar: m.avatar,
                    metadata: m.metadata
                  }))
                : []

              const msgData = {
                id,
                role: payload.role || 'assistant',
                content,
                mentions,
                attachments: payload.attachments || [],
                metadata: payload.metadata || {},
                tool_call_name: payload.tool_call_name || null,
                user: payload.user || null,
                compacted: normalizeBoolean(payload.compacted),
                createdAt: payload.created_at,
                updatedAt: payload.updated_at,
                needsReconciliation: payload.role === 'user'
              }

              if (messagesIndexRef.current.has(id)) {
                setMessages((prev) => {
                  const idx = messagesIndexRef.current.get(id)
                  if (idx == null || idx >= prev.length) return prev
                  const existing = prev[idx]
                  const next = [...prev]
                  next[idx] = {
                    ...existing,
                    ...msgData,
                    // Keep existing content if longer (upsert may have stale content from element replacement)
                    content: msgData.content.length >= existing.content.length ? msgData.content : existing.content
                  }
                  return next
                })
                return
              }

              addedMessages.push(msgData)
            } catch {
              // Skip unparseable messages
            }
          })
        }
      }

      if (addedMessages.length > 0 || removedIds.size > 0) {
        setMessages((prev) => {
          let next = [...prev]
          const idx = new Map(messagesIndexRef.current)

          addedMessages.forEach((msg) => {
            // Try to reconcile user messages with optimistic placeholders
            if (msg.needsReconciliation && msg.role === 'user') {
              const recentThreshold = Date.now() - 10000
              let oldestIdx = -1
              let oldestTime = Infinity

              next.forEach((m, i) => {
                if (m.role === 'user' && m.id < 0) {
                  const msgTime = new Date(m.createdAt || 0).getTime()
                  if (msgTime > recentThreshold && msgTime < oldestTime) {
                    oldestTime = msgTime
                    oldestIdx = i
                  }
                }
              })

              if (oldestIdx !== -1) {
                const oldId = next[oldestIdx].id
                next[oldestIdx] = { ...msg, isOptimistic: false }
                idx.delete(oldId)
                idx.set(msg.id, oldestIdx)
                return
              }
            }

            // Add as new message or update if duplicate in same batch
            // (e.g., ActionCable delivers APPEND then REPLACE in one observer callback)
            const existingIdx = idx.get(msg.id)
            if (existingIdx != null) {
              next[existingIdx] = { ...next[existingIdx], ...msg }
            } else {
              idx.set(msg.id, next.length)
              next.push(msg)
            }
          })

          const trueRemovals = new Set(
            [...removedIds].filter(id => !addedIds.has(id))
          )

          if (trueRemovals.size > 0) {
            next = next.filter(m => {
              if (trueRemovals.has(m.id)) {
                return m.role === 'user'
              }
              return true
            })
          }

          // Sort by ID — optimistic messages (negative IDs) stay at the end
          next.sort((a, b) => {
            if (a.id < 0 && b.id >= 0) return 1
            if (b.id < 0 && a.id >= 0) return -1
            return a.id - b.id
          })

          const newIdx = new Map()
          next.forEach((m, i) => newIdx.set(m.id, i))
          messagesIndexRef.current = newIdx

          return next
        })
      }
    })

    listObserver.observe(listEl, {
      childList: true,
      subtree: true
    })

    return () => {
      listObserver.disconnect()
    }
  }, [messageListSelector, messageContentSelector])

  useEffect(() => {
    const initialMessages = hydrateMessagesFromDOM()
    setMessages(initialMessages)

    const idx = new Map()
    initialMessages.forEach((m, i) => idx.set(m.id, i))
    messagesIndexRef.current = idx
  }, [hydrateMessagesFromDOM])

  /**
   * Substitute @label mentions with <@id> placeholders
   * Mirrors server-side MessagesController#substitute_mentions
   */
  const substituteMentions = useCallback((content, mentions) => {
    let result = content

    mentions.forEach(mention => {
      const label = mention.label
      const stableId = mention.id || mention.metadata?.id

      if (label && stableId) {
        const escapedLabel = label.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')
        result = result.replace(new RegExp(`@${escapedLabel}`, 'g'), `<@${stableId}>`)
      }
    })

    return result
  }, [])

  const sendMessage = useCallback(async (content, options) => {
    const mentions = options?.mentions || []
    const attachments = options?.attachments || []
    const hasAttachments = attachments.length > 0

    if (!chatId || isSending) return
    if (!content.trim() && !hasAttachments) return

    const processedContent = substituteMentions(content.trim(), mentions)

    const optimisticId = -Date.now()
    const optimisticMsg = {
      id: optimisticId,
      role: 'user',
      content: processedContent,
      mentions,
      attachments: [],
      metadata: {},
      compacted: false,
      createdAt: new Date().toISOString(),
      updatedAt: new Date().toISOString(),
      isOptimistic: true
    }

    setMessages((prev) => {
      const next = [...prev, optimisticMsg]
      const idx = new Map(messagesIndexRef.current)
      idx.set(optimisticId, next.length - 1)
      messagesIndexRef.current = idx
      return next
    })

    setIsSending(true)

    try {
      const token = document.querySelector('meta[name="csrf-token"]')?.getAttribute('content') || ''

      let response

      if (hasAttachments) {
        const formData = new FormData()
        formData.append('chat_id', String(chatId))
        formData.append('content', content.trim())
        mentions.forEach(m => {
          formData.append('mentions[]', JSON.stringify({
            id: m.id || m.metadata?.id,
            model: m.model,
            label: m.label,
            path: m.path || m.metadata?.path
          }))
        })
        attachments.forEach(file => {
          formData.append('attachments[]', file)
        })

        response = await fetch('/messages', {
          method: 'POST',
          headers: {
            'Accept': 'application/json',
            'X-Requested-With': 'XMLHttpRequest',
            'X-CSRF-Token': token
          },
          body: formData
        })
      } else {
        response = await fetch('/messages', {
          method: 'POST',
          headers: {
            'Content-Type': 'application/json',
            'Accept': 'application/json',
            'X-Requested-With': 'XMLHttpRequest',
            'X-CSRF-Token': token
          },
          body: JSON.stringify({
            chat_id: chatId,
            content: content.trim(),
            mentions: mentions.map(m => ({
              id: m.id || m.metadata?.id,
              model: m.model,
              label: m.label,
              path: m.path || m.metadata?.path
            }))
          })
        })
      }

      if (response.ok) {
        try {
          const data = await response.json()
          const realId = data.message_id

          if (realId && Number.isFinite(realId)) {
            setMessages((prev) => {
              if (messagesIndexRef.current.has(realId)) return prev

              const optimisticIdx = prev.findIndex(m => m.id === optimisticId)
              if (optimisticIdx !== -1) {
                const next = [...prev]

                if (data.message) {
                  next[optimisticIdx] = { ...data.message, isOptimistic: false }
                } else {
                  next[optimisticIdx] = { ...next[optimisticIdx], id: realId, isOptimistic: false }
                }

                const idx = new Map(messagesIndexRef.current)
                idx.delete(optimisticId)
                idx.set(realId, optimisticIdx)
                messagesIndexRef.current = idx

                return next
              }

              return prev
            })
          }
        } catch {
          // Response parse failed — observer will handle reconciliation
        }
      } else {
        setMessages((prev) => {
          const next = prev.filter(m => m.id !== optimisticId)
          const idx = new Map()
          next.forEach((m, i) => idx.set(m.id, i))
          messagesIndexRef.current = idx
          return next
        })
      }
    } catch {
      setMessages((prev) => {
        const next = prev.filter(m => m.id !== optimisticId)
        const idx = new Map()
        next.forEach((m, i) => idx.set(m.id, i))
        messagesIndexRef.current = idx
        return next
      })
    } finally {
      setIsSending(false)
    }
  }, [chatId, isSending, substituteMentions])

  // Reconcile React state with server truth (called 3s after last stream event or on run completion)
  const reconcileFromServer = useCallback(async () => {
    if (!chatId) return

    try {
      const token = document.querySelector('meta[name="csrf-token"]')?.getAttribute('content') || ''
      const response = await fetch(`/chats/${chatId}/messages.json`, {
        headers: {
          'Accept': 'application/json',
          'X-CSRF-Token': token
        }
      })

      if (!response.ok) return

      const serverMessages = await response.json()

      setMessages((prev) => {
        // If server has fewer messages than local (e.g. after clear), replace entirely
        const prevReal = prev.filter(m => m.id > 0)
        if (serverMessages.length < prevReal.length) {
          const rebuilt = []
          const newIdx = new Map()
          for (const serverMsg of serverMessages) {
            if (serverMsg.role === 'user' && serverMsg.user_submitted === false) continue
            if (serverMsg.role === 'system') continue
            const msgData = {
              id: serverMsg.id,
              role: serverMsg.role || 'assistant',
              content: normalizeContent(serverMsg.content || ''),
              mentions: serverMsg.mentions || [],
              attachments: serverMsg.attachments || [],
              metadata: serverMsg.metadata || {},
              tool_call_name: serverMsg.tool_call_name || null,
              user: serverMsg.user || null,
              compacted: normalizeBoolean(serverMsg.compacted),
              createdAt: serverMsg.created_at || serverMsg.createdAt,
              updatedAt: serverMsg.updated_at || serverMsg.updatedAt
            }
            newIdx.set(serverMsg.id, rebuilt.length)
            rebuilt.push(msgData)
          }
          messagesIndexRef.current = newIdx
          return rebuilt
        }

        let changed = false
        const next = [...prev]
        const idx = new Map(messagesIndexRef.current)

        for (const serverMsg of serverMessages) {
          const sid = serverMsg.id
          const existingIdx = idx.get(sid)

          if (existingIdx != null) {
            const existing = next[existingIdx]
            const serverContent = normalizeContent(serverMsg.content || '')

            if (existing.content !== serverContent) {
              next[existingIdx] = {
                ...existing,
                content: serverContent,
                role: serverMsg.role || existing.role,
                mentions: serverMsg.mentions || existing.mentions,
                attachments: serverMsg.attachments || existing.attachments,
                compacted: normalizeBoolean(serverMsg.compacted)
              }
              changed = true
            }
          } else {
            if (serverMsg.role === 'user' && serverMsg.user_submitted === false) continue
            if (serverMsg.role === 'system') continue

            const msgData = {
              id: sid,
              role: serverMsg.role || 'assistant',
              content: normalizeContent(serverMsg.content || ''),
              mentions: serverMsg.mentions || [],
              attachments: serverMsg.attachments || [],
              metadata: serverMsg.metadata || {},
              tool_call_name: serverMsg.tool_call_name || null,
              user: serverMsg.user || null,
              compacted: normalizeBoolean(serverMsg.compacted),
              createdAt: serverMsg.created_at || serverMsg.createdAt,
              updatedAt: serverMsg.updated_at || serverMsg.updatedAt
            }
            idx.set(sid, next.length)
            next.push(msgData)
            changed = true
          }
        }

        if (!changed) return prev

        next.sort((a, b) => {
          if (a.id < 0 && b.id >= 0) return 1
          if (b.id < 0 && a.id >= 0) return -1
          return a.id - b.id
        })
        const newIdx = new Map()
        next.forEach((m, i) => newIdx.set(m.id, i))
        messagesIndexRef.current = newIdx

        return next
      })
    } catch {
      // Reconciliation failed — will retry on next trigger
    }
  }, [chatId])

  reconcileRef.current = reconcileFromServer

  // Stream-content event listener: updates React state directly during streaming
  useEffect(() => {
    const handleStreamContent = (e) => {
      const { messageId, content } = e.detail
      const normalized = normalizeContent(content)
      if (!normalized) return

      setMessages(prev => {
        const idx = messagesIndexRef.current.get(messageId)
        if (idx == null || idx >= prev.length) return prev
        const existing = prev[idx]
        if (existing.role === 'user') return prev
        if (existing.content === normalized) return prev

        const next = [...prev]
        next[idx] = { ...next[idx], content: normalized }
        return next
      })

      // Reconcile from server 3s after last stream event
      if (idleTimerRef.current) clearTimeout(idleTimerRef.current)
      idleTimerRef.current = setTimeout(() => {
        reconcileRef.current?.()
      }, 3000)
    }

    window.addEventListener('stream-content', handleStreamContent)
    return () => {
      window.removeEventListener('stream-content', handleStreamContent)
      if (idleTimerRef.current) clearTimeout(idleTimerRef.current)
    }
  }, [])

  useEffect(() => {
    return () => {
      if (idleTimerRef.current) clearTimeout(idleTimerRef.current)
    }
  }, [])

  const clearMessages = useCallback(() => {
    setMessages([])
    messagesIndexRef.current = new Map()
    // Also clear the hidden DOM container so observer doesn't resurrect old messages
    const listEl = document.querySelector(messageListSelector)
    if (listEl) listEl.innerHTML = ''
  }, [messageListSelector])

  return {
    messages,
    sendMessage,
    reconcileFromServer,
    clearMessages
  }
}

export default useTurboChat

import { useState, useEffect, useCallback, useRef } from 'react'
import { createConsumer } from '@rails/actioncable'
import { sanitizeMessages } from '../components/chat/types'

export function useInertiaChat(
  chatId,
  initialMessages = [],
  options = {}
) {
  const {
    debug = false,
    consumer: customConsumer
  } = options

  const [messages, setMessages] = useState(
    sanitizeMessages(initialMessages, 'initial')
  )
  const [isSending, setIsSending] = useState(false)

  const messagesIndexRef = useRef(new Map())
  const subscriptionRef = useRef(null)

  const log = useCallback((...args) => {
    if (debug) console.log('[useInertiaChat]', ...args)
  }, [debug])

  useEffect(() => {
    const idx = new Map()
    initialMessages.forEach((m, i) => idx.set(m.id, i))
    messagesIndexRef.current = idx
  }, [initialMessages])

  useEffect(() => {
    if (!chatId) return

    const cable = customConsumer || createConsumer()

    const subscription = cable.subscriptions.create(
      { channel: 'ChatChannel', id: chatId },
      {
        received: (data) => {
          log('Received:', data.type, data)

          if (data.type === 'new_message') {
            handleNewMessage(data.message)
          } else if (data.type === 'update_message') {
            handleUpdateMessage(data.message)
          } else if (data.type === 'remove_message') {
            handleRemoveMessage(data.message_id)
          }
        },

        connected: () => {
          log('Connected to ChatChannel', chatId)
        },

        disconnected: () => {
          log('Disconnected from ChatChannel', chatId)
        }
      }
    )

    subscriptionRef.current = subscription

    return () => {
      subscription.unsubscribe()
      subscriptionRef.current = null
    }
  }, [chatId, customConsumer, log])

  const handleNewMessage = useCallback((messageData) => {
    const msg = {
      id: messageData.id,
      role: messageData.role,
      content: messageData.content || '',
      mentions: messageData.mentions || [],
      attachments: messageData.attachments || [],
      metadata: messageData.metadata || {},
      createdAt: messageData.created_at,
      updatedAt: messageData.updated_at
    }

    setMessages((prev) => {
      if (msg.role === 'user') {
        const recentThreshold = Date.now() - 10000
        let oldestIdx = -1
        let oldestTime = Infinity

        prev.forEach((m, i) => {
          if (m.role === 'user' && m.id < 0) {
            const msgTime = new Date(m.createdAt || 0).getTime()
            if (msgTime > recentThreshold && msgTime < oldestTime) {
              oldestTime = msgTime
              oldestIdx = i
            }
          }
        })

        if (oldestIdx !== -1) {
          const next = [...prev]
          const oldId = next[oldestIdx].id
          next[oldestIdx] = {
            isOptimistic: false,
            createdAt: msg.createdAt,
            updatedAt: msg.updatedAt
          }

          const idx = new Map(messagesIndexRef.current)
          idx.delete(oldId)
          idx.set(msg.id, oldestIdx)
          messagesIndexRef.current = idx

          log(`Reconciled optimistic ${oldId} → real ${msg.id}`)
          return next
        }
      }
      if (!messagesIndexRef.current.has(msg.id)) {
        const next = [...prev, msg]
        const idx = new Map(messagesIndexRef.current)
        idx.set(msg.id, next.length - 1)
        messagesIndexRef.current = idx
        return next
      }

      return prev
    })
  }, [log])

  const handleUpdateMessage = useCallback((messageData) => {
    const id = messageData.id
    if (!Number.isFinite(id)) return

    setMessages((prev) => {
      const idx = messagesIndexRef.current.get(id)
      if (idx == null || idx >= prev.length) return prev

      const existing = prev[idx]

      if (existing.role === 'user') return prev

      const next = [...prev]
      next[idx] = {
        ...next[idx],
        content: messageData.content || next[idx].content,
        metadata: messageData.metadata || next[idx].metadata,
        mentions: messageData.mentions || next[idx].mentions,
        attachments: messageData.attachments || next[idx].attachments,
        updatedAt: messageData.updated_at || next[idx].updatedAt
      }

      return next
    })
  }, [])

  const handleRemoveMessage = useCallback((messageId) => {
    setMessages((prev) => {
      const next = prev.filter(m => m.id !== messageId)

      const idx = new Map()
      next.forEach((m, i) => idx.set(m.id, i))
      messagesIndexRef.current = idx

      return next
    })
  }, [])

  const sendMessage = useCallback(async (content, options) => {
    if (!chatId || isSending || !content.trim()) return

    const mentions = options?.mentions || []
    const attachmentIds = options?.attachmentIds || []

    const optimisticId = -Date.now()
    const optimisticMsg = {
      id: optimisticId,
      role: 'user',
      content: content.trim(),
      mentions,
      attachments: [], // Will be populated after confirmation
      metadata: {},
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

      const response = await fetch(`/chats/${chatId}/messages`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          'X-CSRF-Token': token
        },
        body: JSON.stringify({
          content: content.trim(),
          mentions: mentions,
          attachment_ids: attachmentIds
        })
      })

      if (response.ok) {
        log('Message sent successfully')
      } else {
        log('Send failed:', response.status)
        setMessages((prev) => {
          const next = prev.filter(m => m.id !== optimisticId)
          const idx = new Map()
          next.forEach((m, i) => idx.set(m.id, i))
          messagesIndexRef.current = idx
          return next
        })
      }
    } catch (err) {
      log('Send error:', err)
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
  }, [chatId, isSending, log])

  return {
    messages,
    sendMessage
  }
}

export default useInertiaChat

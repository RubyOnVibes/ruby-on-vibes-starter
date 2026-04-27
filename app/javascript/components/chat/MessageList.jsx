import React, { useEffect, useRef, useState, useCallback, useMemo } from 'react'
import { MessageBubble } from './MessageBubble'

function groupMessages(messages) {
  const groups = []
  let currentToolGroup = []

  messages.forEach((msg, index) => {
    if (msg.role === 'tool') {
      currentToolGroup.push(msg)
    } else {
      // Flush current tool group if any
      if (currentToolGroup.length > 0) {
        groups.push({
          type: 'tool-group',
          messages: currentToolGroup,
          key: `tool-group-${currentToolGroup[0].id}`
        })
        currentToolGroup = []
      }
      // Add non-tool message
      groups.push({
        type: 'single',
        message: msg,
        key: `msg-${msg.id}`
      })
    }
  })

  // Flush remaining tool group
  if (currentToolGroup.length > 0) {
    groups.push({
      type: 'tool-group',
      messages: currentToolGroup,
      key: `tool-group-${currentToolGroup[0].id}`
    })
  }

  return groups
}

function DefaultEmptyState() {
  return (
    <div className="flex-1 flex items-center justify-center text-center px-4">
      <div className="max-w-md space-y-3">
        <h3 className="text-base font-medium text-muted-foreground">
          Start a conversation
        </h3>
      </div>
    </div>
  )
}

function humanizeToolName(name) {
  if (!name) return 'Tool'
  return name
    .replace(/_tool$/i, '')
    .replace(/_/g, ' ')
    .replace(/\b\w/g, (c) => c.toUpperCase())
}

function CollapsibleToolCall({
  message,
  defaultExpanded = true,
  showHeader = true
}) {
  const [expanded, setExpanded] = useState(defaultExpanded)
  const toolName = humanizeToolName(message.metadata?.tool_name || message.tool_call_name)

  if (!showHeader) {
    return (
      <div className="rounded border px-3 py-2" style={{
        borderColor: 'color-mix(in srgb, var(--color-border) 50%, transparent)'
      }}>
        <MessageBubble message={message} showTimestamp={false} />
      </div>
    )
  }

  return (
    <div>
      <button
        type="button"
        onClick={() => setExpanded(!expanded)}
        className="flex items-center gap-2 text-xs cursor-pointer hover:opacity-70 transition py-1"
        style={{ color: 'var(--color-muted-foreground)' }}
      >
        <svg
          className="w-3 h-3 transition-transform flex-shrink-0"
          style={{ transform: expanded ? 'rotate(90deg)' : 'rotate(0deg)' }}
          viewBox="0 0 24 24"
          fill="none"
          stroke="currentColor"
          strokeWidth="2"
        >
          <path d="M9 6l6 6-6 6" strokeLinecap="round" strokeLinejoin="round" />
        </svg>
        <span>{toolName} Result</span>
      </button>

      {expanded && (
        <div className="mt-1">
          <div className="rounded border px-3 py-2" style={{
            borderColor: 'color-mix(in srgb, var(--color-border) 50%, transparent)'
          }}>
            <MessageBubble message={message} showTimestamp={false} />
          </div>
        </div>
      )}
    </div>
  )
}

function ToolCallGroup({ messages }) {
  const [groupExpanded, setGroupExpanded] = useState(false)
  const count = messages.length
  const label = `${count} Tool Result${count > 1 ? 's' : ''}`

  return (
    <div>
      <button
        type="button"
        onClick={() => setGroupExpanded(!groupExpanded)}
        className="flex items-center gap-2 text-xs cursor-pointer hover:opacity-70 transition py-1"
        style={{ color: 'var(--color-muted-foreground)' }}
      >
        <svg
          className="w-3 h-3 transition-transform flex-shrink-0"
          style={{ transform: groupExpanded ? 'rotate(90deg)' : 'rotate(0deg)' }}
          viewBox="0 0 24 24"
          fill="none"
          stroke="currentColor"
          strokeWidth="2"
        >
          <path d="M9 6l6 6-6 6" strokeLinecap="round" strokeLinejoin="round" />
        </svg>
        <span>{label}</span>
      </button>

      {groupExpanded && (
        <div className="mt-2 space-y-1 pl-5">
          {messages.map((msg) => (
            <CollapsibleToolCall key={msg.id} message={msg} defaultExpanded={false} />
          ))}
        </div>
      )}
    </div>
  )
}

function ThinkingIndicator() {
  return (
    <div className="flex items-center gap-2 mt-6 mb-2">
      <div className="flex gap-1.5">
        <div
          className="w-2 h-2 rounded-full animate-pulse"
          style={{
            backgroundColor: 'var(--color-muted-foreground)',
            animationDelay: '0ms',
            animationDuration: '1.4s'
          }}
        />
        <div
          className="w-2 h-2 rounded-full animate-pulse"
          style={{
            backgroundColor: 'var(--color-muted-foreground)',
            animationDelay: '200ms',
            animationDuration: '1.4s'
          }}
        />
        <div
          className="w-2 h-2 rounded-full animate-pulse"
          style={{
            backgroundColor: 'var(--color-muted-foreground)',
            animationDelay: '400ms',
            animationDuration: '1.4s'
          }}
        />
      </div>
    </div>
  )
}

export function MessageList({
  messages,
  currentUserId,
  isRunActive = false,
  showThinking = false,
  isGroupChat = false,
  onScroll,
  emptyState,
  renderMessage,
  className = '',
  showTimestamps = false,
  scrollTrigger
}) {
  const listRef = useRef(null)
  const lastContentHashRef = useRef('')

  const scrollToBottom = useCallback(() => {
    requestAnimationFrame(() => {
      if (listRef.current) {
        listRef.current.scrollTop = listRef.current.scrollHeight
      }
    })
  }, [])

  const messageGroups = useMemo(() => groupMessages(messages), [messages])

  const contentHash = useMemo(() => {
    return messages.map(m => `${m.id}:${m.content?.length || 0}`).join(',')
  }, [messages])

  useEffect(() => {
    if (!listRef.current) return

    const contentChanged = contentHash !== lastContentHashRef.current
    lastContentHashRef.current = contentHash

    if (!contentChanged) return

    scrollToBottom()
  }, [contentHash, scrollToBottom])

  useEffect(() => {
    if ((isRunActive || showThinking) && listRef.current) {
      scrollToBottom()
    }
  }, [isRunActive, showThinking, scrollToBottom])

  // Re-scroll when external layout changes (e.g., task panel appears/disappears)
  useEffect(() => {
    if (scrollTrigger !== undefined) {
      scrollToBottom()
    }
  }, [scrollTrigger, scrollToBottom])

  if (messages.length === 0) {
    return emptyState ? <>{emptyState}</> : <DefaultEmptyState />
  }

  return (
    <div
      ref={listRef}
      className={`
        chat-messages-scroll
        flex-1 min-h-0
        overflow-y-auto overflow-x-hidden
        px-4 py-3
        space-y-3
        ${className}
      `.trim().replace(/\s+/g, ' ')}
      style={{
        WebkitOverflowScrolling: 'touch',
        scrollBehavior: 'smooth',
        overscrollBehavior: 'contain'
      }}
      role="log"
      aria-label="Chat messages"
      aria-live="polite"
      aria-atomic="false"
    >
      {messageGroups.map((group) => {
        if (group.type === 'tool-group') {
          return <ToolCallGroup key={group.key} messages={group.messages} />
        }

        const message = group.message

        if (renderMessage) {
          return <React.Fragment key={group.key}>{renderMessage(message)}</React.Fragment>
        }

        if (message.role === 'tool') {
          return <CollapsibleToolCall key={group.key} message={message} defaultExpanded={false} />
        }

        return (
          <MessageBubble
            key={group.key}
            message={message}
            currentUserId={currentUserId}
            isGroupChat={isGroupChat}
            showTimestamp={showTimestamps}
          />
        )
      })}

      {isRunActive && (() => {
        const lastMsg = messages[messages.length - 1]
        const isStreaming = lastMsg?.role === 'assistant' && lastMsg?.content?.trim().length > 0
        return !isStreaming ? <ThinkingIndicator /> : null
      })()}
    </div>
  )
}

export default MessageList

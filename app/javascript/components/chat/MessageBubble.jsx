import React, { useState, useRef, useEffect, useMemo } from 'react'
import { Streamdown } from 'streamdown'
import { code } from '@streamdown/code'
import { MentionChip } from './MentionChip'

function StreamdownWrapper({
  children,
  className = ''
}) {
  const containerRef = useRef(null)

  // Handle link clicks for internal navigation with Turbo
  useEffect(() => {
    if (!containerRef.current) return

    const handleClick = (e) => {
      const target = e.target
      const link = target.closest('a')

      if (!link) return

      const href = link.getAttribute('href')
      if (!href) return

      // Handle relative links (internal paths)
      if (href.startsWith('/') && !href.startsWith('//')) {
        e.preventDefault()

        if (window.Turbo) {
          window.Turbo.visit(href)
        } else {
          window.location.href = href
        }
        return
      }

      // Handle absolute same-origin links
      try {
        const url = new URL(href)
        if (url.origin === window.location.origin) {
          e.preventDefault()

          if (window.Turbo) {
            window.Turbo.visit(url.pathname + url.search + url.hash)
          } else {
            window.location.href = url.pathname + url.search + url.hash
          }
        }
      } catch {
        // Not a valid URL, ignore
      }
    }

    containerRef.current.addEventListener('click', handleClick)

    return () => {
      containerRef.current?.removeEventListener('click', handleClick)
    }
  }, [])

  // linkSafety: same-origin links use Turbo, external links show modal
  const linkSafety = useMemo(() => ({
    enabled: true,
    onLinkCheck: (url) => {
      // Check if same-origin
      let isSameOrigin = false
      let turboPath = url

      try {
        const parsed = new URL(url)
        if (parsed.origin === window.location.origin) {
          isSameOrigin = true
          turboPath = parsed.pathname + parsed.search + parsed.hash
        }
      } catch {
        isSameOrigin = true // relative URLs are same-origin
      }

      if (isSameOrigin) {
        // Navigate via Turbo and return a never-resolving promise
        // so Streamdown doesn't also do window.location.href
        if (window.Turbo) {
          window.Turbo.visit(turboPath)
        } else {
          window.location.href = url
        }
        return new Promise(() => {})
      }

      return false // external links: show modal
    }
  }), [])

  const plugins = useMemo(() => ({ code }), [])

  return (
    <div ref={containerRef}>
      <Streamdown
        mode="static"
        className={className}
        linkSafety={linkSafety}
        plugins={plugins}
      >
        {children}
      </Streamdown>
    </div>
  )
}

function AttachmentPreview({ attachment }) {
  const isImage = attachment.contentType?.startsWith('image/')
  const isPDF = attachment.contentType === 'application/pdf'

  const formatBytes = (bytes) => {
    if (bytes === 0) return '0 Bytes'
    const k = 1024
    const sizes = ['Bytes', 'KB', 'MB', 'GB']
    const i = Math.floor(Math.log(bytes) / Math.log(k))
    return Math.round(bytes / Math.pow(k, i) * 100) / 100 + ' ' + sizes[i]
  }

  return (
    <div
      className="inline-flex items-center gap-3 px-3 py-2 rounded-lg border max-w-full"
      style={{
        backgroundColor: 'var(--vibes-surface-2)',
        borderColor: 'var(--color-border)',
        color: 'var(--color-foreground)'
      }}
    >
      {isImage && attachment.url ? (
        <img
          src={attachment.url}
          alt={attachment.filename}
          className="w-12 h-12 object-cover rounded"
        />
      ) : (
        <div className="flex-shrink-0">
          {isPDF ? (
            <svg className="w-8 h-8" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2">
              <path d="M14 2H6a2 2 0 00-2 2v16a2 2 0 002 2h12a2 2 0 002-2V8z" />
              <path d="M14 2v6h6M9 13h6M9 17h6" />
            </svg>
          ) : (
            <svg className="w-8 h-8" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2">
              <path d="M15.172 7l-6.586 6.586a2 2 0 102.828 2.828l6.414-6.586a4 4 0 00-5.656-5.656l-6.415 6.585a6 6 0 108.486 8.486L20.5 13" />
            </svg>
          )}
        </div>
      )}

      <div className="flex-1 min-w-0">
        <div className="text-sm font-medium truncate">{attachment.filename}</div>
        <div className="text-xs" style={{ color: 'var(--color-muted-foreground)' }}>
          {formatBytes(attachment.byteSize)}
        </div>
      </div>

      {/* Download button */}
      <a
        href={attachment.url}
        download={attachment.filename}
        className="flex-shrink-0 p-1.5 rounded-md hover:bg-opacity-80 transition"
        style={{
          color: 'var(--color-primary)'
        }}
        aria-label={`Download ${attachment.filename}`}
        title="Download"
      >
        <svg className="w-5 h-5" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2">
          <path strokeLinecap="round" strokeLinejoin="round" d="M4 16v1a3 3 0 003 3h10a3 3 0 003-3v-1m-4-4l-4 4m0 0l-4-4m4 4V4" />
        </svg>
      </a>
    </div>
  )
}

/**
 * Convert Ruby hash syntax to JSON string.
 * Handles symbol keys (:foo or foo:), hash rockets (=>), and nil/true/false.
 */
function rubyHashToJson(str) {
  let s = str
  // key: value (Ruby symbol shorthand) → "key": value
  s = s.replace(/(?<=[{,\s])(\w+):\s/g, '"$1": ')
  // :key => value (Ruby hash rocket with symbol key) → "key": value
  s = s.replace(/:(\w+)\s*=>\s*/g, '"$1": ')
  // "key" => value (hash rocket with string key) → "key": value
  s = s.replace(/"(\w+)"\s*=>\s*/g, '"$1": ')
  // :symbol values → "symbol" (only in value position after : [ ,)
  s = s.replace(/([:\[,]\s*):(\w+)\b/g, '$1"$2"')
  // nil → null (only in value position after : [ , — not inside strings)
  s = s.replace(/([:\[,]\s*)nil\b/g, '$1null')
  return s
}

/**
 * Fallback indenter: adds newlines and indentation at brackets and commas.
 * Respects quoted strings so commas inside strings aren't split.
 */
function bracketAwareIndent(str) {
  let depth = 0
  let result = ''
  let inString = false
  let stringChar = null
  const indent = () => '  '.repeat(Math.max(0, depth))

  for (let i = 0; i < str.length; i++) {
    const ch = str[i]

    if (inString) {
      result += ch
      // Count consecutive backslashes before this char to handle escaped quotes
      if (ch === stringChar) {
        let backslashes = 0
        for (let j = i - 1; j >= 0 && str[j] === '\\'; j--) backslashes++
        if (backslashes % 2 === 0) inString = false
      }
      continue
    }

    if (ch === '"' || ch === "'") {
      inString = true
      stringChar = ch
      result += ch
      continue
    }

    if (ch === '{' || ch === '[') {
      depth++
      result += ch + '\n' + indent()
    } else if (ch === '}' || ch === ']') {
      depth = Math.max(0, depth - 1)
      result += '\n' + indent() + ch
    } else if (ch === ',') {
      result += ',\n' + indent()
    } else if (ch === ' ' && i > 0 && (str[i - 1] === ',' || str[i - 1] === '{' || str[i - 1] === '[')) {
      // skip extra spaces after structural chars (we already added indentation)
      continue
    } else {
      result += ch
    }
  }
  return result
}

/**
 * Pretty-format tool content through three phases:
 * 1. JSON.parse (fast path for valid JSON)
 * 2. Ruby hash → JSON conversion (regex-based)
 * 3. Bracket-aware indentation (generic fallback)
 */
function prettyFormatContent(content) {
  if (!content || typeof content !== 'string') {
    return { formatted: String(content ?? '') }
  }

  try {
    // Phase 1: try direct JSON parse
    try {
      const parsed = JSON.parse(content)
      return { formatted: JSON.stringify(parsed, null, 2) }
    } catch { /* continue */ }

    // Phase 2: try Ruby hash → JSON conversion
    try {
      const asJson = rubyHashToJson(content)
      const parsed = JSON.parse(asJson)
      return { formatted: JSON.stringify(parsed, null, 2) }
    } catch { /* continue */ }

    // Phase 3: bracket-aware indentation fallback
    const trimmed = content.trim()
    if (trimmed.match(/^[{\[]/)) {
      return { formatted: bracketAwareIndent(trimmed) }
    }

    return { formatted: content }
  } catch {
    // Safety net: never crash, always return displayable content
    return { formatted: content }
  }
}

function ToolContentRenderer({ message }) {
  const content = message.content || ''
  const { formatted } = prettyFormatContent(content)

  const toolName = message.metadata?.tool_name || null
  const toolArgs = message.metadata?.tool_args || null

  return (
    <div className="space-y-1 text-xs">
      {toolName && (
        <div className="flex items-baseline gap-2">
          <span className="font-medium" style={{ color: 'var(--color-muted-foreground)' }}>
            Tool:
          </span>
          <span style={{ color: 'var(--color-foreground)' }}>
            {toolName}
          </span>
        </div>
      )}

      {toolArgs && (
        <div>
          <div className="font-medium mb-1" style={{ color: 'var(--color-muted-foreground)' }}>
            Arguments:
          </div>
          <pre className="text-xs px-2 py-1 rounded overflow-x-auto" style={{
            margin: 0,
            backgroundColor: 'var(--vibes-surface-2)',
            color: 'var(--color-foreground)'
          }}>
            <code>{typeof toolArgs === 'string' ? prettyFormatContent(toolArgs).formatted : JSON.stringify(toolArgs, null, 2)}</code>
          </pre>
        </div>
      )}

      <div>
        <div className="font-medium mb-1" style={{ color: 'var(--color-muted-foreground)' }}>
          Output:
        </div>
        <pre className="text-xs px-2 py-1 rounded overflow-x-auto" style={{
          margin: 0,
          backgroundColor: 'var(--vibes-surface-2)',
          color: 'var(--color-foreground)'
        }}>
          <code>{formatted}</code>
        </pre>
      </div>
    </div>
  )
}

function AssistantContentRenderer({ message }) {
  const content = message.content || ''

  return (
    <StreamdownWrapper className="prose prose-sm dark:prose-invert max-w-none">
      {content}
    </StreamdownWrapper>
  )
}

function DefaultContentRenderer({ message }) {
  const content = message.content || ''
  const mentions = message.mentions || []

  if (mentions.length === 0) {
    return <>{renderTextWithLineBreaks(content)}</>
  }

  const placeholderRegex = /<@([^>]+)>/g

  const idToMention = new Map()
  mentions.forEach((m) => {
    const mentionId = m.id || m.metadata?.id
    if (mentionId) {
      idToMention.set(mentionId, m)
    }
  })

  const nodes = []
  let lastIndex = 0
  let match
  let nodeCounter = 0

  while ((match = placeholderRegex.exec(content)) !== null) {
    const start = match.index
    const end = placeholderRegex.lastIndex
    const prefixedId = match[1]

    if (start > lastIndex) {
      const textSegment = content.slice(lastIndex, start)
      nodes.push(
        <React.Fragment key={`text-${nodeCounter}`}>
          {renderTextWithLineBreaks(textSegment)}
        </React.Fragment>
      )
      nodeCounter++
    }

    const mentionData = idToMention.get(prefixedId)

    if (mentionData) {
      nodes.push(
        <MentionChip
          key={`mention-${nodeCounter}-${prefixedId}`}
          mention={mentionData}
        />
      )
    } else {
      // Fallback for deleted/missing mentions
      nodes.push(
        <span
          key={`mention-fallback-${nodeCounter}`}
          className="inline-flex items-center gap-1 px-1.5 py-0.5 mx-0.5 text-xs font-medium rounded border"
          style={{
            backgroundColor: 'var(--vibes-surface-2)',
            color: 'var(--color-muted-foreground)',
            borderColor: 'var(--color-border)'
          }}
        >
          @{prefixedId}
        </span>
      )
    }

    lastIndex = end
    nodeCounter++
  }

  if (lastIndex < content.length) {
    const remainingText = content.slice(lastIndex)
    nodes.push(
      <React.Fragment key={`remaining-${nodeCounter}`}>
        {renderTextWithLineBreaks(remainingText)}
      </React.Fragment>
    )
  }

  return <>{nodes}</>
}

function renderTextWithLineBreaks(text) {
  if (!text) return []

  const lines = text.split('\n')
  const elements = []

  lines.forEach((line, i) => {
    if (i > 0) {
      elements.push(<br key={`br-${i}`} />)
    }
    if (line) {
      elements.push(line)
    }
  })

  return elements
}

function formatTimestamp(isoString) {
  if (!isoString) return ''

  try {
    const date = new Date(isoString)
    const now = new Date()
    const diffMs = now.getTime() - date.getTime()
    const diffMins = Math.floor(diffMs / 60000)

    if (diffMins < 1) return 'Just now'
    if (diffMins < 60) return `${diffMins}m ago`

    const diffHours = Math.floor(diffMins / 60)
    if (diffHours < 24) return `${diffHours}h ago`

    const diffDays = Math.floor(diffHours / 24)
    if (diffDays < 7) return `${diffDays}d ago`

    return date.toLocaleDateString()
  } catch {
    return ''
  }
}

function ThinkingIndicator() {
  return (
    <div className="flex items-center gap-1.5 px-1 py-3">
      {[0, 1, 2].map((i) => (
        <span
          key={i}
          className="w-1.5 h-1.5 rounded-full"
          style={{
            backgroundColor: 'var(--color-muted-foreground)',
            opacity: 0.6,
            animation: 'thinking-bounce 1.4s ease-in-out infinite',
            animationDelay: `${i * 0.16}s`
          }}
        />
      ))}
      <style>{`
        @keyframes thinking-bounce {
          0%, 80%, 100% { transform: scale(0.6); opacity: 0.4; }
          40% { transform: scale(1); opacity: 0.8; }
        }
      `}</style>
    </div>
  )
}

export function MessageBubble({
  message,
  currentUserId,
  isGroupChat = false,
  onCopy,
  renderContent,
  showTimestamp = false,
  showAvatar,
  className = ''
}) {
  const [copied, setCopied] = useState(false)

  const isUser = message.role === 'user'
  const isAssistant = message.role === 'assistant'
  const isSystem = message.role === 'system'
  const isTool = message.role === 'tool'

  const isCurrentUser = isUser && (!message.user || message.user.id === currentUserId)
  const isOtherUser = isUser && message.user && message.user.id !== currentUserId

  const isSystemEvent = message.metadata?.system_event === 'member_joined' ||
                       message.metadata?.system_event === 'member_left'

  const handleCopy = async () => {
    if (onCopy) {
      onCopy()
    } else {
      try {
        await navigator.clipboard.writeText(message.content)
      } catch {
        const textarea = document.createElement('textarea')
        textarea.value = message.content
        textarea.style.position = 'fixed'
        textarea.style.opacity = '0'
        document.body.appendChild(textarea)
        textarea.select()
        document.execCommand('copy')
        document.body.removeChild(textarea)
      }
    }

    setCopied(true)
    setTimeout(() => setCopied(false), 1200)
  }

  const contentNode = renderContent
    ? renderContent(message)
    : isTool
    ? <ToolContentRenderer message={message} />
    : isAssistant
    ? <AssistantContentRenderer message={message} />
    : <DefaultContentRenderer message={message} />

  const hasContent = message.content?.trim().length > 0

  if (!hasContent) return null

  if (isSystemEvent) {
    return (
      <div className={`flex justify-center ${className}`}>
        <div
          className="text-xs px-3 py-1.5 rounded-full"
          style={{
            backgroundColor: 'var(--vibes-surface-1)',
            color: 'var(--color-muted-foreground)'
          }}
        >
          {message.content}
        </div>
      </div>
    )
  }

  return (
    <div className={`flex flex-col gap-1 ${className}`}>
      {isCurrentUser && (
        <div className="flex items-start gap-2 justify-end">
          <div
            className="relative rounded-2xl border px-4 py-3 pb-8 text-sm max-w-[85%]"
            style={{
              backgroundColor: 'var(--vibes-surface-1)',
              borderColor: 'var(--color-border)',
              color: 'var(--color-foreground)',
              whiteSpace: 'pre-wrap'
            }}
          >
            <div className="prose prose-sm dark:prose-invert max-w-none break-words">
              {contentNode}
            </div>

            {message.attachments && message.attachments.length > 0 && (
              <div className="mt-3 flex flex-col gap-2">
                {message.attachments.map((attachment, idx) => (
                  <AttachmentPreview key={idx} attachment={attachment} />
                ))}
              </div>
            )}

            <button
              type="button"
              onClick={handleCopy}
              className="absolute bottom-1.5 right-1.5 p-1 rounded-md cursor-pointer opacity-60 hover:opacity-100"
              style={{
                color: 'var(--color-muted-foreground)'
              }}
              onMouseEnter={(e) => {
                e.currentTarget.style.color = 'var(--color-foreground)'
              }}
              onMouseLeave={(e) => {
                e.currentTarget.style.color = 'var(--color-muted-foreground)'
              }}
              aria-label="Copy message"
              title="Copy"
            >
              {copied ? (
                <svg className="w-4 h-4" viewBox="0 0 24 24" fill="none" stroke="currentColor">
                  <path d="M20 6L9 17l-5-5" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" />
                </svg>
              ) : (
                <svg className="w-4 h-4" viewBox="0 0 24 24" fill="none" stroke="currentColor">
                  <rect x="9" y="9" width="13" height="13" rx="2" ry="2" strokeWidth="2" />
                  <path d="M5 15H4a2 2 0 01-2-2V4a2 2 0 012-2h9a2 2 0 012 2v1" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" />
                </svg>
              )}
            </button>

            {showTimestamp && message.createdAt && (
              <div className="mt-1 text-[10px]" style={{ color: 'var(--color-muted-foreground)' }}>
                {formatTimestamp(message.createdAt)}
              </div>
            )}
          </div>
        </div>
      )}

      {/* Other users' messages - Same structure as assistant */}
      {isOtherUser && message.user && (
        <div className="flex flex-col gap-1 mt-4">
          <div className="flex items-center gap-2">
            <div
              className="w-5 h-5 rounded-full flex items-center justify-center text-xs font-semibold flex-shrink-0"
              style={{
                backgroundColor: 'var(--color-primary)',
                color: 'var(--color-primary-foreground)'
              }}
            >
              {message.user.firstName?.[0]?.toUpperCase() || message.user.name?.[0]?.toUpperCase() || '?'}
            </div>
            <div className="text-sm font-semibold" style={{ color: 'var(--color-foreground)' }}>
              {message.user.firstName || message.user.name}
            </div>
          </div>

          <div
            className="border-r-2 pr-3 py-3"
            style={{ borderColor: 'color-mix(in srgb, var(--color-primary) 30%, transparent)' }}
          >
            <div
              className="prose prose-sm dark:prose-invert max-w-none break-words"
              style={{ whiteSpace: 'pre-wrap' }}
            >
              {contentNode}
            </div>
          </div>

          {message.attachments && message.attachments.length > 0 && (
            <div className="mt-2 flex flex-col gap-2">
              {message.attachments.map((attachment, idx) => (
                <AttachmentPreview key={idx} attachment={attachment} />
              ))}
            </div>
          )}

          {showTimestamp && message.createdAt && (
            <div className="text-[10px] mt-1" style={{ color: 'var(--color-muted-foreground)' }}>
              {formatTimestamp(message.createdAt)}
            </div>
          )}
        </div>
      )}

      {(isAssistant || isSystem) && (
        <div className="flex flex-col gap-1 mt-4">
          {isGroupChat && isAssistant && (
            <div className="flex items-center gap-2 mb-2">
              <div className="text-sm font-semibold" style={{ color: 'var(--color-foreground)' }}>
                Assistant
              </div>
            </div>
          )}

          <div className="prose prose-sm dark:prose-invert max-w-none break-words">
            {contentNode}
          </div>

          {message.attachments && message.attachments.length > 0 && (
            <div className="mt-3 flex flex-col gap-2">
              {message.attachments.map((attachment, idx) => (
                <AttachmentPreview key={idx} attachment={attachment} />
              ))}
            </div>
          )}

          <div className="flex items-center gap-2">
            <button
              type="button"
              onClick={handleCopy}
              className="inline-flex items-center gap-1 text-xs cursor-pointer"
              style={{
                color: 'var(--color-muted-foreground)'
              }}
              onMouseEnter={(e) => {
                e.currentTarget.style.color = 'var(--color-foreground)'
              }}
              onMouseLeave={(e) => {
                e.currentTarget.style.color = 'var(--color-muted-foreground)'
              }}
              aria-label="Copy message"
              title="Copy"
            >
              {copied ? (
                <svg className="w-3.5 h-3.5" viewBox="0 0 24 24" fill="none" stroke="currentColor">
                  <path d="M20 6L9 17l-5-5" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" />
                </svg>
              ) : (
                <svg className="w-3.5 h-3.5" viewBox="0 0 24 24" fill="none" stroke="currentColor">
                  <rect x="9" y="9" width="13" height="13" rx="2" ry="2" strokeWidth="2" />
                  <path d="M5 15H4a2 2 0 01-2-2V4a2 2 0 012-2h9a2 2 0 012 2v1" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" />
                </svg>
              )}
            </button>

            {showTimestamp && message.createdAt && (
              <span className="text-[10px]" style={{ color: 'var(--color-muted-foreground)' }}>
                {formatTimestamp(message.createdAt)}
              </span>
            )}
          </div>
        </div>
      )}

      {isTool && (
        <div className="flex flex-col gap-1">
          <div className="prose prose-sm dark:prose-invert max-w-none break-words">
            {contentNode}
          </div>

          <div className="flex items-center gap-2">
            <button
              type="button"
              onClick={handleCopy}
              className="inline-flex items-center gap-1 text-xs cursor-pointer"
              style={{
                color: 'var(--color-muted-foreground)'
              }}
              onMouseEnter={(e) => {
                e.currentTarget.style.color = 'var(--color-foreground)'
              }}
              onMouseLeave={(e) => {
                e.currentTarget.style.color = 'var(--color-muted-foreground)'
              }}
              aria-label="Copy message"
              title="Copy"
            >
              {copied ? (
                <svg className="w-3.5 h-3.5" viewBox="0 0 24 24" fill="none" stroke="currentColor">
                  <path d="M20 6L9 17l-5-5" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" />
                </svg>
              ) : (
                <svg className="w-3.5 h-3.5" viewBox="0 0 24 24" fill="none" stroke="currentColor">
                  <rect x="9" y="9" width="13" height="13" rx="2" ry="2" strokeWidth="2" />
                  <path d="M5 15H4a2 2 0 01-2-2V4a2 2 0 012-2h9a2 2 0 012 2v1" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" />
                </svg>
              )}
            </button>

            {showTimestamp && message.createdAt && (
              <span className="text-[10px]" style={{ color: 'var(--color-muted-foreground)' }}>
                {formatTimestamp(message.createdAt)}
              </span>
            )}
          </div>
        </div>
      )}
    </div>
  )
}

export default MessageBubble

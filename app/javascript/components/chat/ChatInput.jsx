/**
 * ChatInput - ContentEditable input with tagged elements
 *
 * Core features:
 * - Inline @file mentions as chips
 * - Auto-resize (72-400px)
 * - Desktop: Enter to submit, Shift+Enter for newlines
 * - Mobile/tablet (<1024px): Enter for newlines, Shift+Enter to submit
 * - Drag & drop file references
 *
 * Future-ready:
 * - File attachments (Active Storage)
 * - Voice input
 * - Autocomplete
 */

import React, { useRef, useEffect, useCallback, forwardRef, useImperativeHandle, useState } from 'react'

// Match the chat sidebar's mobile breakpoint (lg: 1024px)
// Below this: Enter adds newline, above: Enter sends message
const MOBILE_BREAKPOINT = 1024

/**
 * ChatInput Component (forwardRef for imperative methods)
 */
export const ChatInput = forwardRef(({
  value = '',
  placeholder = 'Type a message...',
  disabled = false,
  maxHeight = 400,
  mentions = [],
  onMentionsChange,
  onChange,
  onSubmit,
  attachments = [],
  onAttachmentsChange,
  allowAttachments = false,
  allowVoice = false,
  onVoiceStart,
  onVoiceEnd,
  autoFocus = false,
  className = ''
}, ref) => {
  const hostRef = useRef(null)
  const mentionsRef = useRef(new Map())
  const [currentHeight, setCurrentHeight] = useState(72)
  const [isMobile, setIsMobile] = useState(() =>
    typeof window !== 'undefined' ? window.innerWidth < MOBILE_BREAKPOINT : false
  )

  // Track viewport size for Enter key behavior
  useEffect(() => {
    const mql = window.matchMedia(`(max-width: ${MOBILE_BREAKPOINT - 1}px)`)
    const onChange = () => setIsMobile(window.innerWidth < MOBILE_BREAKPOINT)
    mql.addEventListener('change', onChange)
    return () => mql.removeEventListener('change', onChange)
  }, [])

  // Initialize mentions map
  useEffect(() => {
    const map = new Map()
    mentions.forEach(m => map.set(m.label, m))
    mentionsRef.current = map
  }, [mentions])

  // Serialize contenteditable to text + mentions
  const collectState = useCallback(() => {
    const host = hostRef.current
    if (!host) return { text: '', mentionLabels: [] }

    const mentionLabels = []
    const pieces = []

    const serialize = (node) => {
      if (!node) return

      if (node.nodeType === Node.TEXT_NODE) {
        pieces.push(node.textContent || '')
      } else if (node.nodeType === Node.ELEMENT_NODE) {
        const elem = node

        // Mention chip
        if (elem.classList.contains('mention-chip')) {
          const label = elem.getAttribute('data-label') || ''
          if (label) {
            pieces.push(`@${label}`)
            mentionLabels.push(label)
          }
        }
        // Line breaks
        else if (elem.tagName === 'BR') {
          pieces.push('\n')
        }
        // Block elements
        else if (elem.tagName === 'DIV') {
          if (elem.previousSibling) pieces.push('\n')
          Array.from(elem.childNodes).forEach(child => serialize(child))
        }
        // Other elements: recurse
        else {
          Array.from(elem.childNodes).forEach(child => serialize(child))
        }
      }
    }

    Array.from(host.childNodes).forEach(child => serialize(child))

    return {
      text: pieces.join('').trim(),
      mentionLabels: Array.from(new Set(mentionLabels))
    }
  }, [])

  // Notify parent of changes
  const notifyChange = useCallback(() => {
    const { text, mentionLabels } = collectState()

    // Resolve labels to full mention objects
    const resolvedMentions = mentionLabels
      .map(label => mentionsRef.current.get(label))
      .filter((m) => m !== undefined)

    if (onChange) onChange(text)
    if (onMentionsChange) onMentionsChange(resolvedMentions)
  }, [collectState, onChange, onMentionsChange])

  // Auto-resize based on content
  const resizeInput = useCallback(() => {
    const host = hostRef.current
    if (!host) return

    const prevHeight = host.style.height
    host.style.height = 'auto'
    const scrollHeight = host.scrollHeight
    host.style.height = prevHeight

    const newHeight = Math.min(Math.max(scrollHeight, 72), maxHeight)
    setCurrentHeight(newHeight)
    host.style.overflowY = scrollHeight > maxHeight ? 'auto' : 'hidden'
  }, [maxHeight])

  // Insert mention chip
  // For v1: Simple implementation - just insert a chip
  // Future: Add autocomplete/search via onMentionSearch prop
  const insertMentionAtCaret = useCallback((mention) => {
    const host = hostRef.current
    if (!host) return

    const selection = window.getSelection()
    if (!selection || selection.rangeCount === 0) return

    const range = selection.getRangeAt(0)

    // Create chip element
    const chip = document.createElement('span')
    chip.className = 'mention-chip'
    chip.contentEditable = 'false'
    chip.setAttribute('data-label', mention.label)
    chip.setAttribute('data-sgid', mention.sgid)
    chip.style.cssText = `
      display: inline-flex;
      align-items: center;
      gap: 0.25rem;
      padding: 0.125rem 0.375rem;
      margin: 0 0.125rem;
      font-size: 0.75rem;
      font-weight: 500;
      border-radius: 0.25rem;
      background-color: color-mix(in srgb, var(--color-primary) 15%, transparent);
      color: var(--color-primary);
      border: 1px solid color-mix(in srgb, var(--color-primary) 30%, transparent);
      cursor: pointer;
    `

    // Icon (generic for v1 - can be model-specific later)
    const icon = document.createElement('span')
    icon.innerHTML = `<svg style="width: 0.75rem; height: 0.75rem;" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path stroke-linecap="round" stroke-linejoin="round" d="M7 20l4-16m2 16l4-16M6 9h14M4 15h14" /></svg>`
    chip.appendChild(icon)

    // Label
    const label = document.createElement('span')
    label.textContent = `@${mention.label}`
    chip.appendChild(label)

    // Insert chip and add space after
    range.deleteContents()
    range.insertNode(chip)
    range.setStartAfter(chip)
    range.setEndAfter(chip)
    selection.removeAllRanges()
    selection.addRange(range)

    const space = document.createTextNode(' ')
    range.insertNode(space)
    range.setStartAfter(space)
    range.setEndAfter(space)
    selection.removeAllRanges()
    selection.addRange(range)

    // Update mentions map
    mentionsRef.current.set(mention.label, mention)

    notifyChange()
    host.focus()
  }, [notifyChange])

  // Event handlers
  const handleInput = useCallback(() => {
    notifyChange()
    resizeInput()
  }, [notifyChange, resizeInput])

  const handleKeyDown = useCallback((e) => {
    if (e.key === 'Enter') {
      if (isMobile) {
        // Mobile/tablet: Enter adds newline (default), Shift+Enter or meta+Enter sends
        if (e.shiftKey || e.metaKey) {
          e.preventDefault()
          if (onSubmit && !disabled) onSubmit()
        }
      } else {
        // Desktop: Enter sends, Shift+Enter adds newline (default)
        if (!e.shiftKey) {
          e.preventDefault()
          if (onSubmit && !disabled) onSubmit()
        }
      }
    }
  }, [onSubmit, disabled, isMobile])

  const handlePaste = useCallback((e) => {
    e.preventDefault()

    const text = e.clipboardData.getData('text/plain')
    if (!text) return

    const selection = window.getSelection()
    if (!selection || selection.rangeCount === 0) return

    const range = selection.getRangeAt(0)
    range.deleteContents()
    range.insertNode(document.createTextNode(text))
    range.collapse(false)
    selection.removeAllRanges()
    selection.addRange(range)

    notifyChange()
    resizeInput()
  }, [notifyChange, resizeInput])

  const handleDrop = useCallback((e) => {
    e.preventDefault()
    e.stopPropagation()

    try {
      const data = e.dataTransfer.getData('application/json')
      if (data) {
        const parsed = JSON.parse(data)

        // Support mention drops (with sgid)
        if (parsed.sgid && parsed.label && parsed.model) {
          insertMentionAtCaret(parsed)
        }
        // Legacy: support path drops (for backwards compat)
        else if (parsed.path) {
          const mention = {
            sgid: `path:${parsed.path}`,
            model: 'File',
            label: parsed.path.split('/').pop() || parsed.path,
            metadata: { path: parsed.path }
          }
          insertMentionAtCaret(mention)
        }
      }
    } catch {}
  }, [insertMentionAtCaret])

  const handleDragOver = useCallback((e) => {
    e.preventDefault()
    e.stopPropagation()
  }, [])

  // Expose imperative methods
  useImperativeHandle(ref, () => ({
    focus: () => {
      try { hostRef.current?.focus() } catch {}
    },
    blur: () => {
      try { hostRef.current?.blur() } catch {}
    },
    clear: () => {
      try {
        const host = hostRef.current
        if (host) {
          host.innerHTML = ''
          mentionsRef.current.clear()
          notifyChange()
          setTimeout(resizeInput, 0)
        }
      } catch {}
    },
    insertPathAtCaret: (path) => {
      // Legacy API for backwards compat with platform
      // Create a simple mention for the path
      const mention = {
        sgid: `path:${path}`,  // Pseudo-sgid for compatibility
        model: 'File',
        label: path.split('/').pop() || path,
        metadata: { path } // Store full path in metadata
      }
      insertMentionAtCaret(mention)
      setTimeout(resizeInput, 0)
    }
  }), [resizeInput, notifyChange, insertMentionAtCaret])

  // Auto-focus on mount
  useEffect(() => {
    if (autoFocus && hostRef.current) {
      setTimeout(() => hostRef.current?.focus(), 100)
    }
  }, [autoFocus])

  // Resize on mount and when value changes
  useEffect(() => {
    resizeInput()
  }, [value, resizeInput])

  return (
    <div className={`relative w-full ${className}`}>
      {/* ContentEditable input */}
      <div
        ref={hostRef}
        contentEditable={!disabled}
        onInput={handleInput}
        onKeyDown={handleKeyDown}
        onPaste={handlePaste}
        onDrop={handleDrop}
        onDragOver={handleDragOver}
        role="textbox"
        aria-label="Message input"
        aria-multiline="true"
        aria-disabled={disabled}
        data-placeholder={placeholder}
        suppressContentEditableWarning
        style={{
          height: `${currentHeight}px`,
          minHeight: '72px',
          maxHeight: `${maxHeight}px`
        }}
        className={`
          w-full px-4 py-3 pr-14
          text-sm text-foreground
          bg-background
          border border-input
          rounded-xl
          focus:outline-none focus:ring-2 focus:ring-ring focus:border-transparent
          overflow-y-auto
          resize-none
          ${disabled ? 'opacity-50 cursor-not-allowed' : ''}

          empty:before:content-[attr(data-placeholder)]
          empty:before:text-muted-foreground
        `.trim().replace(/\s+/g, ' ')}
      />

      {/* Future: Attachment preview area */}
      {allowAttachments && attachments && attachments.length > 0 && (
        <div className="mt-2 flex flex-wrap gap-2">
          {attachments.map((file, i) => (
            <div
              key={i}
              className="inline-flex items-center gap-2 px-3 py-2 rounded-lg bg-muted text-sm"
            >
              <svg className="w-4 h-4" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2">
                <path strokeLinecap="round" strokeLinejoin="round" d="M15.172 7l-6.586 6.586a2 2 0 102.828 2.828l6.414-6.586a4 4 0 00-5.656-5.656l-6.415 6.585a6 6 0 108.486 8.486L20.5 13" />
              </svg>
              <span className="flex-1 truncate max-w-[150px]">{file.name}</span>
              <button
                type="button"
                onClick={() => {
                  if (onAttachmentsChange) {
                    onAttachmentsChange(attachments.filter((_, idx) => idx !== i))
                  }
                }}
                className="text-muted-foreground hover:text-foreground"
                aria-label={`Remove ${file.name}`}
              >
                <svg className="w-4 h-4" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2">
                  <path strokeLinecap="round" strokeLinejoin="round" d="M6 18L18 6M6 6l12 12" />
                </svg>
              </button>
            </div>
          ))}
        </div>
      )}

      {/* Future: Toolbar with attachment/voice buttons */}
      {(allowAttachments || allowVoice) && (
        <div className="absolute bottom-2 left-2 flex items-center gap-1">
          {allowAttachments && (
            <button
              type="button"
              disabled={disabled}
              className="p-1.5 rounded-md text-muted-foreground hover:text-foreground hover:bg-muted disabled:opacity-50 cursor-pointer"
              aria-label="Attach file"
              title="Attach file"
            >
              <svg className="w-4 h-4" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2">
                <path strokeLinecap="round" strokeLinejoin="round" d="M15.172 7l-6.586 6.586a2 2 0 102.828 2.828l6.414-6.586a4 4 0 00-5.656-5.656l-6.415 6.585a6 6 0 108.486 8.486L20.5 13" />
              </svg>
            </button>
          )}

          {allowVoice && (
            <button
              type="button"
              disabled={disabled}
              className="p-1.5 rounded-md text-muted-foreground hover:text-foreground hover:bg-muted disabled:opacity-50 cursor-pointer"
              aria-label="Voice input"
              title="Voice input"
            >
              <svg className="w-4 h-4" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2">
                <path strokeLinecap="round" strokeLinejoin="round" d="M19 11a7 7 0 01-7 7m0 0a7 7 0 01-7-7m7 7v4m0 0H8m4 0h4m-4-8a3 3 0 01-3-3V5a3 3 0 116 0v6a3 3 0 01-3 3z" />
              </svg>
            </button>
          )}
        </div>
      )}
    </div>
  )
})

ChatInput.displayName = 'ChatInput'

export default ChatInput

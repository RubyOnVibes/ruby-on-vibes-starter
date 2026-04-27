import React, { useEffect, useRef } from 'react'

function getModelIcon(modelName) {
  const model = modelName.toLowerCase()

  if (model.includes('chat') || model.includes('conversation')) {
    return (
      <svg className="w-3.5 h-3.5" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2">
        <path strokeLinecap="round" strokeLinejoin="round" d="M8 12h.01M12 12h.01M16 12h.01M21 12c0 4.418-4.03 8-9 8a9.863 9.863 0 01-4.255-.949L3 20l1.395-3.72C3.512 15.042 3 13.574 3 12c0-4.418 4.03-8 9-8s9 3.582 9 8z" />
      </svg>
    )
  }

  if (model.includes('user') || model.includes('member')) {
    return (
      <svg className="w-3.5 h-3.5" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2">
        <path strokeLinecap="round" strokeLinejoin="round" d="M16 7a4 4 0 11-8 0 4 4 0 018 0zM12 14a7 7 0 00-7 7h14a7 7 0 00-7-7z" />
      </svg>
    )
  }

  if (model.includes('org')) {
    return (
      <svg className="w-3.5 h-3.5" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2">
        <path strokeLinecap="round" strokeLinejoin="round" d="M17 20h5v-2a3 3 0 00-5.356-1.857M17 20H7m10 0v-2c0-.656-.126-1.283-.356-1.857M7 20H2v-2a3 3 0 015.356-1.857M7 20v-2c0-.656.126-1.283.356-1.857m0 0a5.002 5.002 0 019.288 0M15 7a3 3 0 11-6 0 3 3 0 016 0zm6 3a2 2 0 11-4 0 2 2 0 014 0zM7 10a2 2 0 11-4 0 2 2 0 014 0z" />
      </svg>
    )
  }

  return (
    <svg className="w-3.5 h-3.5" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2">
      <path strokeLinecap="round" strokeLinejoin="round" d="M7 20l4-16m2 16l4-16M6 9h14M4 15h14" />
    </svg>
  )
}

export function MentionAutocomplete({
  results,
  isLoading = false,
  selectedIndex = 0,
  onSelect,
  onDismiss,
  position = {},
  className = ''
}) {
  const listRef = useRef(null)

  useEffect(() => {
    if (!listRef.current) return

    const selectedEl = listRef.current.querySelector(`[data-index="${selectedIndex}"]`)
    if (selectedEl) {
      selectedEl.scrollIntoView({ block: 'nearest', behavior: 'smooth' })
    }
  }, [selectedIndex])

  useEffect(() => {
    const handleClickOutside = (e) => {
      if (listRef.current && !listRef.current.contains(e.target)) {
        onDismiss?.()
      }
    }

    document.addEventListener('mousedown', handleClickOutside)
    return () => document.removeEventListener('mousedown', handleClickOutside)
  }, [onDismiss])

  if (isLoading) {
    return (
      <div
        className={`absolute z-50 w-64 rounded-lg border shadow-lg p-2 ${className}`}
        style={{
          backgroundColor: 'var(--color-background)',
          borderColor: 'var(--color-border)',
          ...position
        }}
      >
        <div className="flex items-center gap-2 px-3 py-2 text-sm" style={{ color: 'var(--color-muted-foreground)' }}>
          <svg className="w-4 h-4 animate-spin" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2">
            <path strokeLinecap="round" strokeLinejoin="round" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z" />
          </svg>
          Searching...
        </div>
      </div>
    )
  }

  if (results.length === 0) {
    return (
      <div
        className={`absolute z-50 w-64 rounded-lg border shadow-lg p-2 ${className}`}
        style={{
          backgroundColor: 'var(--color-background)',
          borderColor: 'var(--color-border)',
          ...position
        }}
      >
        <div className="px-3 py-2 text-sm text-center" style={{ color: 'var(--color-muted-foreground)' }}>
          No matches found
        </div>
      </div>
    )
  }

  return (
    <div
      ref={listRef}
      className={`absolute z-50 w-64 max-h-64 overflow-y-auto rounded-lg border shadow-lg py-1 ${className}`}
      style={{
        backgroundColor: 'var(--color-background)',
        borderColor: 'var(--color-border)',
        ...position
      }}
    >
      {results.map((mention, index) => (
        <button
          key={`${mention.model}-${mention.label}-${index}`}
          type="button"
          data-index={index}
          onClick={() => onSelect(mention)}
          className={`
            w-full flex items-center gap-2 px-3 py-2 text-left text-sm cursor-pointer
            ${index === selectedIndex ? 'mention-item-selected' : ''}
          `.trim()}
          style={{
            backgroundColor: index === selectedIndex ? 'var(--vibes-surface-2)' : 'transparent',
            color: 'var(--color-foreground)'
          }}
        >
          {/* Icon */}
          <div style={{ color: 'var(--color-muted-foreground)' }}>
            {getModelIcon(mention.model)}
          </div>

          {mention.metadata?.avatar && (
            <img
              src={mention.metadata.avatar}
              alt={mention.label}
              className="w-5 h-5 rounded-full"
            />
          )}

          <div className="flex-1 min-w-0">
            <div className="truncate font-medium">
              {mention.label}
            </div>
            <div className="text-xs truncate" style={{ color: 'var(--color-muted-foreground)' }}>
              {mention.model}
            </div>
          </div>
        </button>
      ))}
    </div>
  )
}

export default MentionAutocomplete

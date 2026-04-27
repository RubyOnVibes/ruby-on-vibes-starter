import React, { useCallback, useState, useEffect } from 'react'
import MentionAutocomplete from './MentionAutocomplete'
import { isImage, humanFileSize, getAcceptAttribute } from '../../utils/fileValidation'

// Match the chat sidebar's mobile breakpoint (lg: 1024px)
// Below this: Enter adds newline, above: Enter sends message
const MOBILE_BREAKPOINT = 1024

/**
 * ChatComposer - The message input area with mentions, attachments, and action buttons.
 * Used in both the empty state (new chat) and the active chat view.
 */
export default function ChatComposer({
  inputRef,
  fileInputRef,
  inputValue,
  onInputChange,
  onMentionDetect,
  attachments = [],
  onFileSelect,
  onRemoveAttachment,
  // Mention autocomplete
  showMentions = false,
  mentionResults = [],
  mentionsLoading = false,
  selectedMentionIndex = 0,
  onMentionIndexChange,
  onMentionSelect,
  onMentionDismiss,
  // Actions
  onSubmit,
  canStop = false,
  onStop,
  disabled = false,
  isSubmitting = false,
}) {
  const hasContent = !!(inputValue?.trim() || attachments.length > 0)

  const [isMobile, setIsMobile] = useState(() =>
    typeof window !== 'undefined' ? window.innerWidth < MOBILE_BREAKPOINT : false
  )

  useEffect(() => {
    const mql = window.matchMedia(`(max-width: ${MOBILE_BREAKPOINT - 1}px)`)
    const onChange = () => setIsMobile(window.innerWidth < MOBILE_BREAKPOINT)
    mql.addEventListener('change', onChange)
    return () => mql.removeEventListener('change', onChange)
  }, [])

  const extractTextWithNewlines = useCallback((el) => {
    const pieces = []
    const serialize = (node) => {
      if (!node) return
      if (node.nodeType === Node.TEXT_NODE) {
        pieces.push(node.textContent || '')
      } else if (node.nodeType === Node.ELEMENT_NODE) {
        if (node.tagName === 'BR') {
          pieces.push('\n')
        } else if (node.tagName === 'DIV') {
          if (node.previousSibling) pieces.push('\n')
          Array.from(node.childNodes).forEach(serialize)
        } else {
          Array.from(node.childNodes).forEach(serialize)
        }
      }
    }
    Array.from(el.childNodes).forEach(serialize)
    return pieces.join('')
  }, [])

  const handleInput = useCallback((e) => {
    const text = extractTextWithNewlines(e.currentTarget)
    onInputChange(text)
    onMentionDetect(text)
  }, [onInputChange, onMentionDetect, extractTextWithNewlines])

  const handleKeyDown = useCallback((e) => {
    if (showMentions && mentionResults.length > 0) {
      if (e.key === 'ArrowDown') {
        e.preventDefault()
        const next = selectedMentionIndex < mentionResults.length - 1
          ? selectedMentionIndex + 1 : selectedMentionIndex
        onMentionIndexChange(next)
        return
      }
      if (e.key === 'ArrowUp') {
        e.preventDefault()
        onMentionIndexChange(selectedMentionIndex > 0 ? selectedMentionIndex - 1 : 0)
        return
      }
      if (e.key === 'Enter' || e.key === 'Tab') {
        e.preventDefault()
        onMentionSelect(mentionResults[selectedMentionIndex])
        return
      }
      if (e.key === 'Escape') {
        e.preventDefault()
        onMentionDismiss()
        return
      }
    }

    if (e.key === 'Enter') {
      if (isMobile) {
        // Mobile/tablet: Enter adds newline (default), Shift+Enter sends
        if (e.shiftKey || e.metaKey) {
          e.preventDefault()
          onSubmit()
        }
      } else {
        // Desktop: Enter sends, Shift+Enter adds newline (default)
        if (!e.shiftKey) {
          e.preventDefault()
          onSubmit()
        }
      }
    }
  }, [showMentions, mentionResults, selectedMentionIndex, onMentionIndexChange, onMentionSelect, onMentionDismiss, onSubmit, isMobile])

  return (
    <div className="flex-shrink-0 w-full pb-4 sm:pb-6 pt-3 sm:pt-4 px-4 sm:px-6" style={{ paddingBottom: 'max(1rem, env(safe-area-inset-bottom, 1rem))' }}>
      <div className="max-w-3xl mx-auto">
        {/* Hidden file input */}
        <input
          ref={fileInputRef}
          type="file"
          multiple
          accept={getAcceptAttribute()}
          onChange={onFileSelect}
          className="hidden"
        />

        <div
          className="relative rounded-2xl sm:rounded-3xl border shadow-sm"
          style={{
            backgroundColor: 'var(--vibes-surface-1)',
            borderColor: 'var(--color-border)'
          }}
        >
          <div className="relative">
            <div
              ref={inputRef}
              contentEditable={!disabled && !canStop}
              onInput={handleInput}
              onKeyDown={handleKeyDown}
              className="min-h-[48px] sm:min-h-[56px] max-h-[160px] sm:max-h-[200px] overflow-y-auto px-4 sm:px-5 py-3 sm:py-4 pr-24 sm:pr-28 text-sm sm:text-base outline-none"
              style={{
                color: 'var(--color-foreground)',
                caretColor: 'var(--color-primary)'
              }}
              role="textbox"
              aria-label="Message input"
              suppressContentEditableWarning
            />
            {!inputValue && (
              <div
                className="absolute inset-0 px-4 sm:px-5 py-3 sm:py-4 pointer-events-none text-sm sm:text-base"
                style={{ color: 'var(--color-muted-foreground)' }}
              >
                Message...
              </div>
            )}
          </div>

          {/* Attachment previews */}
          {attachments.length > 0 && (
            <div className="px-4 sm:px-5 pb-2 flex flex-wrap gap-2">
              {attachments.map((file, index) => {
                const fileIsImage = isImage(file)
                const previewUrl = fileIsImage ? URL.createObjectURL(file) : null

                return (
                  <div
                    key={index}
                    className="inline-flex items-center gap-2 px-2 py-1.5 rounded-lg text-xs sm:text-sm border"
                    style={{
                      backgroundColor: 'var(--vibes-surface-2)',
                      color: 'var(--color-foreground)',
                      borderColor: 'var(--color-border)'
                    }}
                  >
                    {fileIsImage && previewUrl ? (
                      <img
                        src={previewUrl}
                        alt={file.name}
                        className="w-8 h-8 object-cover rounded"
                        onLoad={() => URL.revokeObjectURL(previewUrl)}
                      />
                    ) : (
                      <svg className="w-4 h-4" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2">
                        <path strokeLinecap="round" strokeLinejoin="round" d="M9 12h6m-6 4h6m2 5H7a2 2 0 01-2-2V5a2 2 0 012-2h5.586a1 1 0 01.707.293l5.414 5.414a1 1 0 01.293.707V19a2 2 0 01-2 2z" />
                      </svg>
                    )}
                    <div className="flex flex-col min-w-0">
                      <span className="truncate max-w-[120px] font-medium">{file.name}</span>
                      <span className="text-xs opacity-70">{humanFileSize(file.size)}</span>
                    </div>
                    <button
                      type="button"
                      onClick={() => onRemoveAttachment(index)}
                      className="hover:opacity-70 transition ml-1"
                      aria-label={`Remove ${file.name}`}
                    >
                      <svg className="w-4 h-4" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2">
                        <path strokeLinecap="round" strokeLinejoin="round" d="M6 18L18 6M6 6l12 12" />
                      </svg>
                    </button>
                  </div>
                )
              })}
            </div>
          )}

          {showMentions && (
            <MentionAutocomplete
              results={mentionResults}
              isLoading={mentionsLoading}
              selectedIndex={selectedMentionIndex}
              onSelect={onMentionSelect}
              onDismiss={onMentionDismiss}
              position={{ bottom: '100%', left: '0', marginBottom: '8px' }}
            />
          )}

          <div className="absolute bottom-2 sm:bottom-2.5 right-2 sm:right-2.5 flex items-center gap-1.5 sm:gap-2">
            {/* Attach button */}
            <button
              type="button"
              disabled={disabled || canStop}
              onClick={() => fileInputRef.current?.click()}
              className="p-1.5 sm:p-2 rounded-lg disabled:opacity-50 transition cursor-pointer"
              style={{
                color: 'var(--color-muted-foreground)',
                backgroundColor: 'transparent'
              }}
              onMouseEnter={(e) => {
                e.currentTarget.style.backgroundColor = 'var(--vibes-surface-2)'
                e.currentTarget.style.color = 'var(--color-foreground)'
              }}
              onMouseLeave={(e) => {
                e.currentTarget.style.backgroundColor = 'transparent'
                e.currentTarget.style.color = 'var(--color-muted-foreground)'
              }}
              aria-label="Attach file"
              title="Attach file"
            >
              <svg className="w-4 h-4 sm:w-5 sm:h-5" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2">
                <path strokeLinecap="round" strokeLinejoin="round" d="M15.172 7l-6.586 6.586a2 2 0 102.828 2.828l6.414-6.586a4 4 0 00-5.656-5.656l-6.415 6.585a6 6 0 108.486 8.486L20.5 13" />
              </svg>
            </button>

            {/* Send / Stop button */}
            <button
              type="button"
              onClick={canStop ? onStop : onSubmit}
              disabled={canStop ? false : (!hasContent || disabled)}
              className="p-1.5 sm:p-2 rounded-lg transition cursor-pointer disabled:cursor-not-allowed disabled:opacity-50"
              style={{
                backgroundColor: canStop || hasContent
                  ? 'var(--color-primary)'
                  : 'var(--vibes-surface-2)',
                color: canStop || hasContent
                  ? 'var(--color-primary-foreground)'
                  : 'var(--color-muted-foreground)'
              }}
              aria-label={canStop ? 'Stop' : 'Send'}
              title={canStop ? 'Stop generation' : 'Send message'}
            >
              {isSubmitting ? (
                <svg
                  className="animate-spin w-4 h-4 sm:w-5 sm:h-5"
                  xmlns="http://www.w3.org/2000/svg"
                  fill="none"
                  viewBox="0 0 24 24"
                >
                  <circle className="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" strokeWidth="4"></circle>
                  <path className="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z"></path>
                </svg>
              ) : canStop ? (
                <svg className="w-4 h-4 sm:w-5 sm:h-5" viewBox="0 0 24 24" fill="currentColor">
                  <rect x="7" y="7" width="10" height="10" rx="2" />
                </svg>
              ) : (
                <svg className="w-4 h-4 sm:w-5 sm:h-5" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2">
                  <path strokeLinecap="round" strokeLinejoin="round" d="M5 12h14m-7-7l7 7-7 7" />
                </svg>
              )}
            </button>
          </div>
        </div>
      </div>
    </div>
  )
}

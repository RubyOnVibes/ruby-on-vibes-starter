import React, { useState, useRef, useEffect } from 'react'
import { createPortal } from 'react-dom'

export function ChatDropdown({
  chatId,
  chatName,
  onRename,
  onDelete,
  onClear,
  clearDisabled = false,
  onViewMembers,
  onLeave,
  className = '',
  orientation = 'vertical',
  compact = false,
  placement = 'left'
}) {
  const [isOpen, setIsOpen] = useState(false)
  const [isRenaming, setIsRenaming] = useState(false)
  const [renameValue, setRenameValue] = useState(chatName)
  const [isSaving, setIsSaving] = useState(false)
  const [dropdownPosition, setDropdownPosition] = useState(null)
  const [isMobile, setIsMobile] = useState(false)

  const dropdownRef = useRef(null)
  const modalRef = useRef(null)
  const buttonRef = useRef(null)
  const inputRef = useRef(null)

  // Check for mobile on mount and resize (same breakpoint as sidebar: 1024px)
  useEffect(() => {
    const checkMobile = () => setIsMobile(window.innerWidth < 1024)
    checkMobile()
    window.addEventListener('resize', checkMobile)
    return () => window.removeEventListener('resize', checkMobile)
  }, [])

  useEffect(() => {
    setRenameValue(chatName)
  }, [chatName])

  useEffect(() => {
    // Only calculate position for desktop dropdown
    if (isOpen && placement === 'right' && buttonRef.current && !isMobile) {
      const rect = buttonRef.current.getBoundingClientRect()
      setDropdownPosition({
        top: rect.bottom + 4,
        left: rect.left
      })
    } else {
      setDropdownPosition(null)
    }
  }, [isOpen, placement, isMobile])

  useEffect(() => {
    const handleClickOutside = (e) => {
      const target = e.target
      // Check if click is outside both the dropdown trigger and the modal (for portal)
      const isOutsideDropdown = dropdownRef.current && !dropdownRef.current.contains(target)
      const isOutsideModal = !modalRef.current || !modalRef.current.contains(target)

      if (isOutsideDropdown && isOutsideModal) {
        setIsOpen(false)
        setIsRenaming(false)
      }
    }

    document.addEventListener('mousedown', handleClickOutside)
    return () => document.removeEventListener('mousedown', handleClickOutside)
  }, [])

  useEffect(() => {
    if (isRenaming && inputRef.current) {
      inputRef.current.focus()
      inputRef.current.select()
    }
  }, [isRenaming])

  const handleRenameSubmit = async () => {
    if (!onRename || !renameValue.trim() || renameValue === chatName) {
      setIsRenaming(false)
      setRenameValue(chatName)
      return
    }

    setIsSaving(true)
    try {
      await onRename(renameValue.trim())
      setIsRenaming(false)
      setIsOpen(false)
    } catch (error) {
      console.error('Failed to rename chat:', error)
      setRenameValue(chatName)
    } finally {
      setIsSaving(false)
    }
  }

  const handleClose = () => {
    setIsOpen(false)
    setIsRenaming(false)
    setRenameValue(chatName)
  }

  // Don't render dropdown if no actions available
  if (!onRename && !onDelete && !onClear && !onViewMembers && !onLeave) {
    return null
  }

  // Shared menu content
  const menuContent = (
    <>
      {onRename && (
        isRenaming ? (
          <div className="p-3">
            <input
              ref={inputRef}
              type="text"
              value={renameValue}
              onChange={(e) => setRenameValue(e.target.value)}
              onClick={(e) => {
                // Don't preventDefault - it breaks input focus
                e.stopPropagation()
              }}
              onKeyDown={(e) => {
                e.stopPropagation()
                if (e.key === 'Enter') {
                  e.preventDefault()
                  handleRenameSubmit()
                } else if (e.key === 'Escape') {
                  e.preventDefault()
                  setIsRenaming(false)
                  setRenameValue(chatName)
                }
              }}
              onBlur={handleRenameSubmit}
              disabled={isSaving}
              className="w-full px-3 py-2 text-sm rounded border outline-none"
              style={{
                backgroundColor: 'var(--vibes-surface-2)',
                borderColor: 'var(--color-border)',
                color: 'var(--color-foreground)'
              }}
              placeholder="Chat name..."
            />
            <p className="mt-2 text-xs" style={{ color: 'var(--color-muted-foreground)' }}>
              Press Enter to save, Escape to cancel
            </p>
          </div>
        ) : (
          <button
            type="button"
            onClick={(e) => {
              e.preventDefault()
              e.stopPropagation()
              setIsRenaming(true)
            }}
            className="w-full flex items-center gap-3 px-4 py-3 text-sm text-left transition"
            style={{ color: 'var(--color-foreground)' }}
            onMouseEnter={(e) => {
              e.currentTarget.style.backgroundColor = 'var(--vibes-surface-2)'
            }}
            onMouseLeave={(e) => {
              e.currentTarget.style.backgroundColor = 'transparent'
            }}
          >
            <svg className="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24" strokeWidth="2">
              <path strokeLinecap="round" strokeLinejoin="round" d="M11 5H6a2 2 0 00-2 2v11a2 2 0 002 2h11a2 2 0 002-2v-5m-1.414-9.414a2 2 0 112.828 2.828L11.828 15H9v-2.828l8.586-8.586z" />
            </svg>
            <span>Rename</span>
          </button>
        )
      )}

      {(onRename || onViewMembers) && onDelete && (
        <div className="h-px" style={{ backgroundColor: 'var(--color-border)' }} />
      )}

      {onViewMembers && (
        <button
          type="button"
          onClick={(e) => {
            e.preventDefault()
            e.stopPropagation()
            setIsOpen(false)
            onViewMembers()
          }}
          className="w-full flex items-center gap-3 px-4 py-3 text-sm text-left transition"
          style={{ color: 'var(--color-foreground)' }}
          onMouseEnter={(e) => {
            e.currentTarget.style.backgroundColor = 'var(--vibes-surface-2)'
          }}
          onMouseLeave={(e) => {
            e.currentTarget.style.backgroundColor = 'transparent'
          }}
        >
          <svg className="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24" strokeWidth="2">
            <path strokeLinecap="round" strokeLinejoin="round" d="M17 20h5v-2a3 3 0 00-5.356-1.857M17 20H7m10 0v-2c0-.656-.126-1.283-.356-1.857M7 20H2v-2a3 3 0 015.356-1.857M7 20v-2c0-.656.126-1.283.356-1.857m0 0a5.002 5.002 0 019.288 0M15 7a3 3 0 11-6 0 3 3 0 016 0zm6 3a2 2 0 11-4 0 2 2 0 014 0zM7 10a2 2 0 11-4 0 2 2 0 014 0z" />
          </svg>
          <span>View members</span>
        </button>
      )}

      {onViewMembers && (onDelete || onLeave) && (
        <div className="h-px" style={{ backgroundColor: 'var(--color-border)' }} />
      )}

      {onLeave && (
        <button
          type="button"
          onClick={(e) => {
            e.preventDefault()
            e.stopPropagation()
            setIsOpen(false)
            onLeave()
          }}
          className="w-full flex items-center gap-3 px-4 py-3 text-sm text-left transition"
          style={{ color: 'var(--color-destructive)' }}
          onMouseEnter={(e) => {
            e.currentTarget.style.backgroundColor = 'color-mix(in srgb, var(--color-destructive) 10%, transparent)'
          }}
          onMouseLeave={(e) => {
            e.currentTarget.style.backgroundColor = 'transparent'
          }}
        >
          <svg className="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24" strokeWidth="2">
            <path strokeLinecap="round" strokeLinejoin="round" d="M17 16l4-4m0 0l-4-4m4 4H7m6 4v1a3 3 0 01-3 3H6a3 3 0 01-3-3V7a3 3 0 013-3h4a3 3 0 013 3v1" />
          </svg>
          <span>Leave chat</span>
        </button>
      )}


      {onClear && (
        <button
          type="button"
          disabled={clearDisabled}
          onClick={(e) => {
            e.preventDefault()
            e.stopPropagation()
            if (clearDisabled) return
            setIsOpen(false)
            onClear()
          }}
          className="w-full flex items-center gap-3 px-4 py-3 text-sm text-left transition"
          style={{
            color: clearDisabled ? 'var(--color-muted-foreground)' : 'var(--color-foreground)',
            opacity: clearDisabled ? 0.5 : 1,
            cursor: clearDisabled ? 'not-allowed' : 'pointer'
          }}
          onMouseEnter={(e) => {
            if (!clearDisabled) e.currentTarget.style.backgroundColor = 'var(--vibes-surface-2)'
          }}
          onMouseLeave={(e) => {
            e.currentTarget.style.backgroundColor = 'transparent'
          }}
        >
          <svg className="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24" strokeWidth="2">
            <path strokeLinecap="round" strokeLinejoin="round" d="M16.023 9.348h4.992v-.001M2.985 19.644v-4.992m0 0h4.992m-4.993 0l3.181 3.183a8.25 8.25 0 0013.803-3.7M4.031 9.865a8.25 8.25 0 0113.803-3.7l3.181 3.182M2.985 19.644l3.181-3.182" />
          </svg>
          <span>Clear messages</span>
        </button>
      )}

      {onDelete && (onRename || onViewMembers || onLeave || onClear) && (
        <div className="h-px" style={{ backgroundColor: 'var(--color-border)' }} />
      )}

      {onDelete && (
        <button
          type="button"
          onClick={(e) => {
            e.preventDefault()
            e.stopPropagation()
            setIsOpen(false)
            onDelete()
          }}
          className="w-full flex items-center gap-3 px-4 py-3 text-sm text-left transition"
          style={{ color: 'var(--color-destructive)' }}
          onMouseEnter={(e) => {
            e.currentTarget.style.backgroundColor = 'color-mix(in srgb, var(--color-destructive) 10%, transparent)'
          }}
          onMouseLeave={(e) => {
            e.currentTarget.style.backgroundColor = 'transparent'
          }}
        >
          <svg className="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24" strokeWidth="2">
            <path strokeLinecap="round" strokeLinejoin="round" d="M19 7l-.867 12.142A2 2 0 0116.138 21H7.862a2 2 0 01-1.995-1.858L5 7m5 4v6m4-6v6m1-10V4a1 1 0 00-1-1h-4a1 1 0 00-1 1v3M4 7h16" />
          </svg>
          <span>Delete chat</span>
        </button>
      )}
    </>
  )

  return (
    <div ref={dropdownRef} className={`relative ${className}`}>
      <button
        ref={buttonRef}
        type="button"
        onClick={(e) => {
          e.preventDefault()
          e.stopPropagation()
          setIsOpen(!isOpen)
        }}
        className={`${compact ? 'p-1' : 'p-1.5'} rounded-lg transition`}
        style={{
          color: 'var(--color-muted-foreground)',
          backgroundColor: isOpen ? 'var(--vibes-surface-2)' : 'transparent'
        }}
        onMouseEnter={(e) => {
          if (!isOpen) {
            e.currentTarget.style.backgroundColor = 'var(--vibes-surface-2)'
          }
        }}
        onMouseLeave={(e) => {
          if (!isOpen) {
            e.currentTarget.style.backgroundColor = 'transparent'
          }
        }}
        aria-label="Chat options"
        title="Chat options"
      >
        {orientation === 'horizontal' ? (
          <svg className={compact ? 'w-4 h-4' : 'w-5 h-5'} viewBox="0 0 24 24" fill="currentColor">
            <circle cx="5" cy="12" r="2" />
            <circle cx="12" cy="12" r="2" />
            <circle cx="19" cy="12" r="2" />
          </svg>
        ) : (
          <svg className={compact ? 'w-4 h-4' : 'w-5 h-5'} viewBox="0 0 24 24" fill="currentColor">
            <circle cx="12" cy="5" r="2" />
            <circle cx="12" cy="12" r="2" />
            <circle cx="12" cy="19" r="2" />
          </svg>
        )}
      </button>

      {isOpen && isMobile && createPortal(
        // Mobile: Centered modal with blur backdrop - rendered via portal to escape parent <a> tag
        <div
          className="fixed inset-0 flex items-center justify-center p-4"
          style={{
            backgroundColor: 'rgba(0, 0, 0, 0.5)',
            backdropFilter: 'blur(8px)',
            WebkitBackdropFilter: 'blur(8px)',
            zIndex: 10000
          }}
          onClick={(e) => {
            e.stopPropagation()
            if (e.target === e.currentTarget) {
              handleClose()
            }
          }}
        >
          <div
            ref={modalRef}
            className="w-full max-w-xs rounded-xl shadow-2xl border overflow-hidden"
            style={{
              backgroundColor: 'var(--vibes-surface-0)',
              borderColor: 'var(--color-border)'
            }}
            onClick={(e) => {
              e.stopPropagation()
            }}
          >
            {/* Modal header with chat name */}
            <div
              className="px-4 py-3 border-b flex items-center justify-between"
              style={{ borderColor: 'var(--color-border)' }}
            >
              <span
                className="text-sm font-medium truncate"
                style={{ color: 'var(--color-foreground)' }}
              >
                {chatName}
              </span>
              <button
                type="button"
                onClick={(e) => {
                  e.preventDefault()
                  e.stopPropagation()
                  handleClose()
                }}
                className="p-1 rounded-lg transition"
                style={{ color: 'var(--color-muted-foreground)' }}
              >
                <svg className="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24" strokeWidth="2">
                  <path strokeLinecap="round" strokeLinejoin="round" d="M6 18L18 6M6 6l12 12" />
                </svg>
              </button>
            </div>
            {menuContent}
          </div>
        </div>,
        document.body
      )}

      {isOpen && !isMobile && (
        // Desktop: Positioned dropdown
        <div
          className={`${dropdownPosition ? 'fixed' : 'absolute'} ${placement === 'right' ? 'left-0' : 'right-0'} ${!dropdownPosition && 'top-full mt-1'} w-64 rounded-lg shadow-xl border`}
          style={{
            backgroundColor: 'var(--vibes-surface-0)',
            borderColor: 'var(--color-border)',
            zIndex: 9999,
            ...(dropdownPosition && {
              top: `${dropdownPosition.top}px`,
              left: `${dropdownPosition.left}px`
            })
          }}
        >
          {menuContent}
        </div>
      )}
    </div>
  )
}

import React, { useEffect, useRef } from 'react'
import { createPortal } from 'react-dom'

export function ConfirmDialog({
  isOpen,
  onClose,
  onConfirm,
  title,
  message,
  confirmText = 'Confirm',
  cancelText = 'Cancel',
  variant = 'default'
}) {
  const dialogRef = useRef(null)

  useEffect(() => {
    const handleEscape = (e) => {
      if (e.key === 'Escape' && isOpen) {
        onClose()
      }
    }

    document.addEventListener('keydown', handleEscape)
    return () => document.removeEventListener('keydown', handleEscape)
  }, [isOpen, onClose])

  useEffect(() => {
    if (isOpen && dialogRef.current) {
      const focusableElements = dialogRef.current.querySelectorAll(
        'button, [href], input, select, textarea, [tabindex]:not([tabindex="-1"])'
      )
      const firstElement = focusableElements[0]
      firstElement?.focus()
    }
  }, [isOpen])

  if (!isOpen) return null

  // Use portal to render at body level - ensures proper centering even when
  // rendered inside transformed containers (like the mobile sidebar)
  return createPortal(
    <div
      className="fixed inset-0 z-[10001] flex items-center justify-center p-4"
      onClick={(e) => {
        e.stopPropagation()
        onClose()
      }}
      style={{
        backgroundColor: 'rgba(0, 0, 0, 0.8)',
        backdropFilter: 'blur(4px)',
        WebkitBackdropFilter: 'blur(4px)'
      }}
    >
      <div
        ref={dialogRef}
        className="relative w-full max-w-sm rounded-xl shadow-2xl border"
        style={{
          backgroundColor: 'var(--vibes-surface-0)',
          borderColor: 'var(--color-border)',
          color: 'var(--color-foreground)'
        }}
        onClick={(e) => e.stopPropagation()}
        role="dialog"
        aria-modal="true"
        aria-labelledby="dialog-title"
      >
        <div className="px-6 pt-6 pb-4">
          <h2
            id="dialog-title"
            className="text-lg font-semibold"
            style={{ color: 'var(--color-foreground)' }}
          >
            {title}
          </h2>
        </div>

        <div className="px-6 pb-6">
          <p
            className="text-sm"
            style={{ color: 'var(--color-muted-foreground)' }}
          >
            {message}
          </p>
        </div>

        <div className="flex items-center gap-3 px-6 pb-6">
          <button
            type="button"
            onClick={(e) => {
              e.stopPropagation()
              onClose()
            }}
            className="flex-1 px-4 py-2.5 text-sm font-medium rounded-lg transition border"
            style={{
              backgroundColor: 'var(--vibes-surface-1)',
              borderColor: 'var(--color-border)',
              color: 'var(--color-foreground)'
            }}
            onMouseEnter={(e) => {
              e.currentTarget.style.backgroundColor = 'var(--vibes-surface-2)'
            }}
            onMouseLeave={(e) => {
              e.currentTarget.style.backgroundColor = 'var(--vibes-surface-1)'
            }}
          >
            {cancelText}
          </button>

          <button
            type="button"
            onClick={(e) => {
              e.stopPropagation()
              onConfirm()
              onClose()
            }}
            className="flex-1 px-4 py-2.5 text-sm font-semibold rounded-lg transition"
            style={{
              backgroundColor: variant === 'danger' ? 'var(--color-destructive)' : 'var(--color-primary)',
              color: variant === 'danger' ? 'var(--color-destructive-foreground)' : 'var(--color-primary-foreground)'
            }}
            onMouseEnter={(e) => {
              e.currentTarget.style.opacity = '0.9'
            }}
            onMouseLeave={(e) => {
              e.currentTarget.style.opacity = '1'
            }}
          >
            {confirmText}
          </button>
        </div>
      </div>
    </div>,
    document.body
  )
}

/**
 * MentionChip - Display for @mentioned Rails models
 *
 * General-purpose component for rendering mentions of ANY Rails model:
 * - @users (User model)
 * - @projects (Project model)
 * - @issues (Issue model)
 * - @files (File model) - if you have one
 * - etc.
 *
 * Uses Rails prefix_id pattern (e.g., chat_xxx, mbr_xxx) for stable references
 */

import React from 'react'

/**
 * Get icon for model type
 */
function getModelIcon(modelName) {
  const model = modelName.toLowerCase()

  // Chat (message bubble with dots)
  if (model.includes('chat') || model.includes('conversation')) {
    return (
      <svg className="w-3 h-3" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2">
        <path strokeLinecap="round" strokeLinejoin="round" d="M8 12h.01M12 12h.01M16 12h.01M21 12c0 4.418-4.03 8-9 8a9.863 9.863 0 01-4.255-.949L3 20l1.395-3.72C3.512 15.042 3 13.574 3 12c0-4.418 4.03-8 9-8s9 3.582 9 8z" />
      </svg>
    )
  }

  // User/Member (single person)
  if (model.includes('user') || model.includes('member')) {
    return (
      <svg className="w-3 h-3" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2">
        <path strokeLinecap="round" strokeLinejoin="round" d="M16 7a4 4 0 11-8 0 4 4 0 018 0zM12 14a7 7 0 00-7 7h14a7 7 0 00-7-7z" />
      </svg>
    )
  }

  // Workspace (multiple people/team)
  if (model.includes('org')) {
    return (
      <svg className="w-3 h-3" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2">
        <path strokeLinecap="round" strokeLinejoin="round" d="M17 20h5v-2a3 3 0 00-5.356-1.857M17 20H7m10 0v-2c0-.656-.126-1.283-.356-1.857M7 20H2v-2a3 3 0 015.356-1.857M7 20v-2c0-.656.126-1.283.356-1.857m0 0a5.002 5.002 0 019.288 0M15 7a3 3 0 11-6 0 3 3 0 016 0zm6 3a2 2 0 11-4 0 2 2 0 014 0zM7 10a2 2 0 11-4 0 2 2 0 014 0z" />
      </svg>
    )
  }

  // File/Document models
  if (model.includes('file') || model.includes('document')) {
    return (
      <svg className="w-3 h-3" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2">
        <path strokeLinecap="round" strokeLinejoin="round" d="M9 12h6m-6 4h6m2 5H7a2 2 0 01-2-2V5a2 2 0 012-2h5.586a1 1 0 01.707.293l5.414 5.414a1 1 0 01.293.707V19a2 2 0 01-2 2z" />
      </svg>
    )
  }

  // Project models
  if (model.includes('project')) {
    return (
      <svg className="w-3 h-3" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2">
        <path strokeLinecap="round" strokeLinejoin="round" d="M3 7v10a2 2 0 002 2h14a2 2 0 002-2V9a2 2 0 00-2-2h-6l-2-2H5a2 2 0 00-2 2z" />
      </svg>
    )
  }

  // Issue/Task models
  if (model.includes('issue') || model.includes('task') || model.includes('ticket')) {
    return (
      <svg className="w-3 h-3" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2">
        <circle cx="12" cy="12" r="10" />
        <path strokeLinecap="round" strokeLinejoin="round" d="M12 16v-4m0-4h.01" />
      </svg>
    )
  }

  // Generic fallback
  return (
    <svg className="w-3 h-3" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2">
      <path strokeLinecap="round" strokeLinejoin="round" d="M7 20l4-16m2 16l4-16M6 9h14M4 15h14" />
    </svg>
  )
}

/**
 * Get inline styles using vibes theme tokens
 */
function getModelStyles() {
  return {
    backgroundColor: 'var(--vibes-surface-2)',
    color: 'var(--color-primary)',
    borderColor: 'var(--color-border)'
  }
}

/**
 * MentionChip Component
 */
export function MentionChip({
  mention,
  onClick,
  showModel = false,
  className = ''
}) {
  // Check if mention is deleted
  const isDeleted = mention.deleted === true

  const handleClick = (e) => {
    e.preventDefault()
    e.stopPropagation()

    // Don't navigate if deleted
    if (isDeleted) {
      return
    }

    if (onClick) {
      onClick(mention)
      return
    }

    // Default behavior: use path from backend
    try {
      // Try path first (set by mentionable_path), then fallback to constructing
      const path = mention.path || mention.metadata?.path

      if (path) {
        window.location.href = path
        return
      }

      // Fallback: construct RESTful path
      const id = mention.id || mention.metadata?.id
      if (!id) {
        console.error('Mention missing ID and path:', mention)
        return
      }

      const modelName = mention.model.toLowerCase()
      const pluralName = modelName + 's'  // Simple pluralization
      window.location.href = `/${pluralName}/${id}`
    } catch (err) {
      console.error('Failed to navigate:', err)
    }
  }

  // Get styles - grey out deleted mentions
  const styles = isDeleted
    ? {
        backgroundColor: 'var(--vibes-surface-1)',
        color: 'var(--color-muted-foreground)',
        borderColor: 'var(--color-border)',
        opacity: 0.6,
        textDecoration: 'line-through'
      }
    : getModelStyles()

  return (
    <button
      type="button"
      onClick={handleClick}
      disabled={isDeleted}
      className={`
        inline-flex items-center gap-1 px-1.5 py-0.5 mx-0.5
        text-xs font-medium
        rounded
        border
        ${isDeleted ? 'cursor-not-allowed' : 'hover:opacity-80 cursor-pointer'}
        transition-opacity
        ${className}
      `.trim().replace(/\s+/g, ' ')}
      style={styles}
      title={isDeleted ? `Deleted ${mention.model}` : `${mention.model}: ${mention.label}`}
      aria-label={`Mention ${mention.label}`}
      data-sgid={mention.sgid}
      data-model={mention.model}
    >
      {/* Avatar or icon */}
      {mention.avatar ? (
        <img
          src={mention.avatar}
          alt={mention.label}
          className="w-3 h-3 rounded-full"
        />
      ) : (
        getModelIcon(mention.model)
      )}

      {/* Label - just the name, no prefix ID clutter */}
      <span>@{mention.label}</span>

      {/* Optional model badge */}
      {showModel && (
        <span className="opacity-60 text-[10px]">
          {mention.model}
        </span>
      )}
    </button>
  )
}

export default MentionChip

import React, { useState } from 'react'
import { ConfirmDialog } from './ConfirmDialog'

export function ChatMembersList({ members, isOwner, canManageMembers, onRemoveMember }) {
  const [removingId, setRemovingId] = useState(null)
  const [showRemoveConfirm, setShowRemoveConfirm] = useState(false)
  const [memberToRemove, setMemberToRemove] = useState(null)

  const handleRemoveClick = (member) => {
    setMemberToRemove(member)
    setShowRemoveConfirm(true)
  }

  const handleRemoveConfirm = async () => {
    if (!memberToRemove) return

    setRemovingId(memberToRemove.id)
    setShowRemoveConfirm(false)

    const success = await onRemoveMember(memberToRemove.id)

    setRemovingId(null)
    setMemberToRemove(null)

    if (!success) {
      alert('Failed to remove member')
    }
  }

  return (
    <div className="space-y-2">
      {members.map((member) => {
        const isRemoving = removingId === member.id
        const canRemove = (canManageMembers ?? isOwner) && !member.isOwner && onRemoveMember

        return (
          <div
            key={member.id}
            className="flex items-center gap-3 p-2 rounded-lg"
            style={{ backgroundColor: 'var(--vibes-surface-1)' }}
          >
            {/* Avatar */}
            <div
              className="w-8 h-8 rounded-full flex items-center justify-center text-xs font-semibold"
              style={{
                backgroundColor: 'var(--color-primary)',
                color: 'var(--color-primary-foreground)'
              }}
            >
              {member.userName.charAt(0).toUpperCase()}
            </div>

            {/* Info */}
            <div className="flex-1 min-w-0">
              <div className="text-sm font-medium truncate" style={{ color: 'var(--color-foreground)' }}>
                {member.userName}
              </div>
              <div className="flex flex-col gap-1 mt-1">
                {canManageMembers && (
                  <code className="text-xs font-mono" style={{ color: 'var(--color-muted-foreground)' }}>
                    {member.memberId}
                  </code>
                )}

                <div className="flex items-center gap-2">
                {/* Org badge */}
                <span
                  className="text-xs px-1.5 py-0.5 rounded"
                  style={{
                    backgroundColor: member.orgType === 'Personal'
                      ? 'var(--vibes-surface-2)'
                      : 'color-mix(in srgb, var(--color-primary) 10%, transparent)',
                    color: 'var(--color-muted-foreground)'
                  }}
                >
                  {member.orgName}
                </span>

                {/* Owner badge */}
                {member.isOwner && (
                  <span
                    className="text-xs px-1.5 py-0.5 rounded font-medium"
                    style={{
                      backgroundColor: 'var(--color-primary)',
                      color: 'var(--color-primary-foreground)'
                    }}
                  >
                    Owner
                  </span>
                )}
                </div>
              </div>
            </div>

            {/* Remove button */}
            {canRemove && (
              <button
                type="button"
                onClick={() => handleRemoveClick(member)}
                disabled={isRemoving}
                className="p-1.5 rounded hover:opacity-70 transition"
                style={{ color: 'var(--color-muted-foreground)' }}
                aria-label="Remove member"
                title="Remove member"
              >
                {isRemoving ? (
                  <svg className="animate-spin w-4 h-4" fill="none" viewBox="0 0 24 24">
                    <circle className="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" strokeWidth="4"></circle>
                    <path className="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z"></path>
                  </svg>
                ) : (
                  <svg className="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path strokeLinecap="round" strokeLinejoin="round" strokeWidth="2" d="M6 18L18 6M6 6l12 12" />
                  </svg>
                )}
              </button>
            )}
          </div>
        )
      })}

      <ConfirmDialog
        isOpen={showRemoveConfirm}
        onClose={() => setShowRemoveConfirm(false)}
        onConfirm={handleRemoveConfirm}
        title="Remove member?"
        message={`Remove ${memberToRemove?.userName} from this chat? They won't be able to see new messages.`}
        confirmText="Remove"
        cancelText="Cancel"
        variant="danger"
      />
    </div>
  )
}

export default ChatMembersList

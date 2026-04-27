import React, { useState, useEffect, useMemo } from 'react'
import useMemberLookup from '../../hooks/useMemberLookup'
import useChatInvitations from '../../hooks/useChatInvitations'
import { ChatMembersList } from './ChatMembersList'
import { ConfirmDialog } from './ConfirmDialog'
import { debounce } from '../../utils/debounce'

export function InviteChatModal({
  chatId,
  isOpen,
  onClose,
  currentMembers,
  workspaceMembers,
  isOwner,
  canManageMembers,
  onInviteSent,
  onRemoveMember,
  canLeave = false
}) {
  const [memberIdInput, setMemberIdInput] = useState('')
  const [orgSearchQuery, setOrgSearchQuery] = useState('')
  const [selectedMemberId, setSelectedMemberId] = useState('')
  const [isSending, setIsSending] = useState(false)
  const [error, setError] = useState(null)
  const [showCancelConfirm, setShowCancelConfirm] = useState(false)
  const [invitationToCancel, setInvitationToCancel] = useState(null)
  const [showLeaveConfirm, setShowLeaveConfirm] = useState(false)

  // Hooks
  const { preview, isLoading: previewLoading, error: previewError, lookupMember, clear: clearPreview } = useMemberLookup()
  const { invitations: pendingInvitations, cancelInvitation, refetch: refetchInvitations } = useChatInvitations(chatId)

  // Debounced lookup function
  const debouncedLookup = useMemo(
    () => debounce((id) => lookupMember(id), 500),
    [lookupMember]
  )

  // Trigger lookup when member ID changes
  useEffect(() => {
    if (memberIdInput.trim() && memberIdInput.startsWith('mbr_')) {
      debouncedLookup(memberIdInput.trim())
    } else {
      clearPreview()
    }
  }, [memberIdInput, debouncedLookup, clearPreview])

  // Filter org members by search query
  const filteredOrgMembers = orgSearchQuery.trim()
    ? workspaceMembers.filter(m =>
        m.userName.toLowerCase().includes(orgSearchQuery.toLowerCase())
      )
    : workspaceMembers

  const handleInvite = async () => {
    const memberId = selectedMemberId || (preview ? preview.memberId : memberIdInput.trim())

    if (!memberId) {
      setError('Please select a member or enter a valid member ID')
      return
    }

    setIsSending(true)
    setError(null)

    try {
      const token = document.querySelector('meta[name="csrf-token"]')?.getAttribute('content')
      if (!token) throw new Error('CSRF token not found')

      const response = await fetch('/chats/invitations', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          'X-CSRF-Token': token
        },
        body: JSON.stringify({ chat_id: chatId, member_id: memberId })
      })

      if (!response.ok) {
        const data = await response.json()
        throw new Error(data.error || 'Failed to send invitation')
      }

      // Success - clear inputs, refetch, and notify parent
      setMemberIdInput('')
      setSelectedMemberId('')
      setOrgSearchQuery('')
      clearPreview()
      refetchInvitations()
      onInviteSent()

      // Show success message briefly
      const successMsg = document.createElement('div')
      successMsg.textContent = 'Invitation sent!'
      successMsg.className = 'fixed top-4 right-4 px-4 py-2 rounded-lg text-sm font-medium z-50 shadow-lg'
      successMsg.style.cssText = 'background-color: var(--color-primary); color: var(--color-primary-foreground);'
      document.body.appendChild(successMsg)
      setTimeout(() => successMsg.remove(), 2000)
    } catch (err) {
      console.error('[InviteChatModal] Error:', err)
      const errorMsg = err instanceof Error ? err.message : 'Failed to send invitation'

      // Check if it's a "already invited" error - offer to cancel existing
      if (errorMsg.includes('already been invited')) {
        setError(errorMsg + ' You can cancel the existing invitation below.')
      } else {
        setError(errorMsg)
      }
    } finally {
      setIsSending(false)
    }
  }

  const handleCancelInvitation = async (invitationId) => {
    setInvitationToCancel(invitationId)
    setShowCancelConfirm(true)
  }

  const handleCancelConfirmed = async () => {
    if (!invitationToCancel) return

    const success = await cancelInvitation(invitationToCancel)
    setShowCancelConfirm(false)
    setInvitationToCancel(null)

    if (success) {
      refetchInvitations()
      const successMsg = document.createElement('div')
      successMsg.textContent = 'Invitation cancelled'
      successMsg.className = 'fixed top-4 right-4 px-4 py-2 rounded-lg text-sm font-medium z-50 shadow-lg'
      successMsg.style.cssText = 'background-color: var(--color-primary); color: var(--color-primary-foreground);'
      document.body.appendChild(successMsg)
      setTimeout(() => successMsg.remove(), 2000)
    } else {
      alert('Failed to cancel invitation')
    }
  }

  const handleLeaveChat = async () => {
    setShowLeaveConfirm(false)

    try {
      const token = document.querySelector('meta[name="csrf-token"]')?.getAttribute('content')
      if (!token) throw new Error('CSRF token not found')

      const response = await fetch(`/chats/${chatId}/leave`, {
        method: 'POST',
        headers: {
          'Accept': 'application/json',
          'X-CSRF-Token': token
        }
      })

      if (response.ok) {
        window.location.href = '/chats'
      } else {
        const data = await response.json()
        throw new Error(data.error || 'Failed to leave chat')
      }
    } catch (err) {
      console.error('[InviteChatModal] Leave error:', err)
      alert(err instanceof Error ? err.message : 'Failed to leave chat')
    }
  }

  if (!isOpen) return null

  return (
    <div
      className="fixed inset-0 z-50 flex items-center justify-center p-4"
      style={{ backgroundColor: 'rgba(0, 0, 0, 0.5)' }}
      onClick={onClose}
    >
      <div
        className="w-full max-w-md rounded-lg p-6 shadow-xl"
        style={{ backgroundColor: 'var(--color-background)' }}
        onClick={(e) => e.stopPropagation()}
      >
        <div className="flex items-center justify-between mb-4">
          <h2 className="text-lg font-semibold" style={{ color: 'var(--color-foreground)' }}>
            {canManageMembers ? 'Add people' : `Members${currentMembers.length > 0 ? ` (${currentMembers.length})` : ''}`}
          </h2>
          <button
            type="button"
            onClick={onClose}
            className="p-1 rounded hover:opacity-70"
            style={{ color: 'var(--color-muted-foreground)' }}
          >
            <svg className="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth="2" d="M6 18L18 6M6 6l12 12" />
            </svg>
          </button>
        </div>

        {/* Only show invite UI if can manage members */}
        {canManageMembers && (
          <div className="mb-6 pb-6 border-b" style={{ borderColor: 'var(--color-border)' }}>
            <p className="text-sm mb-4" style={{ color: 'var(--color-muted-foreground)' }}>
              Invite members to collaborate on this chat
            </p>

        {/* Org member search (if available) */}
        {workspaceMembers.length > 0 && (
          <div className="mb-3">
            <label className="block text-sm font-medium mb-2" style={{ color: 'var(--color-foreground)' }}>
              Search your workspace
            </label>
            <input
              type="text"
              value={orgSearchQuery}
              onChange={(e) => {
                setOrgSearchQuery(e.target.value)
                setMemberIdInput('')  // Clear manual input
                setError(null)
              }}
              placeholder="Search members..."
              className="w-full px-3 py-2 rounded-lg border text-sm"
              style={{
                backgroundColor: 'var(--vibes-surface-1)',
                borderColor: 'var(--color-border)',
                color: 'var(--color-foreground)'
              }}
            />

            {/* Filtered results */}
            {orgSearchQuery.trim() && (
              <div
                className="mt-2 max-h-48 overflow-y-auto rounded-lg border"
                style={{
                  backgroundColor: 'var(--vibes-surface-1)',
                  borderColor: 'var(--color-border)'
                }}
              >
                {filteredOrgMembers.length > 0 ? (
                  filteredOrgMembers.map((member) => (
                    <button
                      key={member.memberId}
                      type="button"
                      onClick={() => {
                        setSelectedMemberId(member.memberId)
                        setOrgSearchQuery(member.userName)
                        setMemberIdInput('')
                        setError(null)
                      }}
                      className="w-full px-3 py-2 text-left hover:bg-opacity-80 transition text-sm"
                      style={{ color: 'var(--color-foreground)' }}
                      onMouseEnter={(e) => {
                        e.currentTarget.style.backgroundColor = 'var(--vibes-surface-2)'
                      }}
                      onMouseLeave={(e) => {
                        e.currentTarget.style.backgroundColor = 'transparent'
                      }}
                    >
                      <div className="font-medium">{member.userName}</div>
                      <div className="text-xs opacity-70">{member.orgName}</div>
                    </button>
                  ))
                ) : (
                  <div className="px-3 py-2 text-sm text-center" style={{ color: 'var(--color-muted-foreground)' }}>
                    No members found
                  </div>
                )}
              </div>
            )}
          </div>
        )}

        {/* OR divider */}
        {workspaceMembers.length > 0 && (
          <div className="flex items-center gap-3 my-3">
            <div className="flex-1 h-px" style={{ backgroundColor: 'var(--color-border)' }}></div>
            <span className="text-xs" style={{ color: 'var(--color-muted-foreground)' }}>or</span>
            <div className="flex-1 h-px" style={{ backgroundColor: 'var(--color-border)' }}></div>
          </div>
        )}

        {/* Member ID input */}
        <div className="mb-4">
          <label className="block text-sm font-medium mb-2" style={{ color: 'var(--color-foreground)' }}>
            Enter member ID
          </label>
          <input
            type="text"
            value={memberIdInput}
            onChange={(e) => {
              setMemberIdInput(e.target.value)
              setSelectedMemberId('')  // Clear org selection
              setOrgSearchQuery('')  // Clear org search
              setError(null)
            }}
            placeholder="mbr_xxx"
            className="w-full px-3 py-2 rounded-lg border text-sm font-mono"
            style={{
              backgroundColor: 'var(--vibes-surface-1)',
              borderColor: 'var(--color-border)',
              color: 'var(--color-foreground)'
            }}
          />
          <p className="text-xs mt-1" style={{ color: 'var(--color-muted-foreground)' }}>
            Members can copy their ID from their profile page
          </p>

          {/* Member preview */}
          {previewLoading && (
            <div className="mt-2 p-2 rounded-lg text-xs" style={{ backgroundColor: 'var(--vibes-surface-1)', color: 'var(--color-muted-foreground)' }}>
              Looking up member...
            </div>
          )}

          {preview && !previewLoading && (
            <div
              className="mt-2 p-3 rounded-lg border"
              style={{
                backgroundColor: 'var(--vibes-surface-2)',
                borderColor: 'var(--color-border)'
              }}
            >
              <div className="flex items-center gap-2">
                <svg className="w-4 h-4 text-success" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path strokeLinecap="round" strokeLinejoin="round" strokeWidth="2" d="M5 13l4 4L19 7" />
                </svg>
                <span className="text-sm font-medium" style={{ color: 'var(--color-foreground)' }}>
                  {preview.userName}
                </span>
              </div>
              <div className="flex items-center gap-2 mt-1">
                <span
                  className="text-xs px-1.5 py-0.5 rounded"
                  style={{
                    backgroundColor: preview.orgType === 'Personal'
                      ? 'var(--vibes-surface-1)'
                      : 'color-mix(in srgb, var(--color-primary) 10%, transparent)',
                    color: 'var(--color-muted-foreground)'
                  }}
                >
                  {preview.orgName}
                </span>
              </div>
            </div>
          )}

          {previewError && !previewLoading && memberIdInput.trim() && (
            <div className="mt-2 p-2 rounded-lg text-xs" style={{ backgroundColor: 'color-mix(in srgb, var(--color-destructive) 10%, transparent)', color: 'var(--color-destructive)' }}>
              {previewError}
            </div>
          )}
        </div>

        {/* Error message */}
        {error && (
          <div className="mb-4 p-3 rounded-lg text-sm" style={{ backgroundColor: 'color-mix(in srgb, var(--color-destructive) 10%, transparent)', color: 'var(--color-destructive)' }}>
            {error}
          </div>
        )}

            {/* Send invitation button */}
            <button
              type="button"
              onClick={handleInvite}
              disabled={isSending || (!preview && !selectedMemberId) || previewLoading}
              className="w-full py-2.5 rounded-lg font-medium text-sm transition disabled:opacity-50 disabled:cursor-not-allowed"
              style={{
                backgroundColor: 'var(--color-primary)',
                color: 'var(--color-primary-foreground)'
              }}
            >
              {isSending ? 'Sending...' : preview || selectedMemberId ? `Invite ${preview?.userName || 'member'}` : 'Send invitation'}
            </button>
          </div>
        )}

        {/* Members and Invitations */}
        {(currentMembers.length > 0 || pendingInvitations.length > 0) && (
        <div className="mt-6">
          <h3 className="text-sm font-semibold mb-3" style={{ color: 'var(--color-foreground)' }}>
            Members ({currentMembers.length + pendingInvitations.length})
          </h3>

          <div className="max-h-80 overflow-y-auto space-y-3">
            {/* Current members */}
            {currentMembers.length > 0 && (
              <div>
                <div className="text-xs font-medium mb-2 px-1" style={{ color: 'var(--color-muted-foreground)' }}>
                  Active
                </div>
                <ChatMembersList
                  members={currentMembers}
                  isOwner={isOwner}
                  canManageMembers={canManageMembers}
                  onRemoveMember={onRemoveMember}
                />
              </div>
            )}

            {/* Pending invitations */}
            {pendingInvitations.length > 0 && (
              <div>
                <div className="text-xs font-medium mb-2 px-1" style={{ color: 'var(--color-muted-foreground)' }}>
                  Pending ({pendingInvitations.length})
                </div>
                <div className="space-y-2">
                  {pendingInvitations.map((inv) => (
                    <div
                      key={inv.id}
                      className="flex items-center gap-3 p-2 rounded-lg"
                      style={{ backgroundColor: 'var(--vibes-surface-1)' }}
                    >
                      {/* Avatar */}
                      <div
                        className="w-8 h-8 rounded-full flex items-center justify-center text-xs font-semibold opacity-50"
                        style={{
                          backgroundColor: 'var(--color-primary)',
                          color: 'var(--color-primary-foreground)'
                        }}
                      >
                        {inv.inviteeName.charAt(0).toUpperCase()}
                      </div>

                      {/* Info */}
                      <div className="flex-1 min-w-0">
                        <div className="text-sm font-medium truncate" style={{ color: 'var(--color-foreground)' }}>
                          {inv.inviteeName}
                        </div>
                        <div className="flex flex-col gap-1 mt-1">
                          {canManageMembers && (
                            <code className="text-xs font-mono" style={{ color: 'var(--color-muted-foreground)' }}>
                              {inv.inviteeId}
                            </code>
                          )}

                          <div className="flex items-center gap-2">
                          {/* Org badge */}
                          <span
                            className="text-xs px-1.5 py-0.5 rounded"
                            style={{
                              backgroundColor: inv.inviteeOrgType === 'Personal'
                                ? 'var(--vibes-surface-2)'
                                : 'color-mix(in srgb, var(--color-primary) 10%, transparent)',
                              color: 'var(--color-muted-foreground)'
                            }}
                          >
                            {inv.inviteeOrgName}
                          </span>

                          {/* Pending badge */}
                          <span
                            className="text-xs px-1.5 py-0.5 rounded"
                            style={{
                              backgroundColor: 'color-mix(in srgb, var(--color-warning) 10%, transparent)',
                              color: 'var(--color-warning)'
                            }}
                          >
                            Invited
                          </span>
                          </div>
                        </div>
                      </div>

                      {canManageMembers && (
                      <button
                        type="button"
                        onClick={(e) => {
                          e.stopPropagation()
                          handleCancelInvitation(inv.id)
                        }}
                        className="p-1.5 rounded hover:opacity-70 transition"
                        style={{ color: 'var(--color-muted-foreground)' }}
                        aria-label="Cancel invitation"
                        title="Cancel invitation"
                      >
                        <svg className="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                          <path strokeLinecap="round" strokeLinejoin="round" strokeWidth="2" d="M6 18L18 6M6 6l12 12" />
                        </svg>
                      </button>
                      )}
                    </div>
                  ))}
                </div>
              </div>
            )}
          </div>
        </div>
        )}

        {!canManageMembers && canLeave && (
          <div className="mt-4 pt-4 border-t" style={{ borderColor: 'var(--color-border)' }}>
            <button
              type="button"
              onClick={() => setShowLeaveConfirm(true)}
              className="w-full py-2.5 rounded-lg text-sm font-medium transition hover:opacity-80"
              style={{ color: 'var(--color-destructive)' }}
            >
              Leave chat
            </button>
          </div>
        )}

        <ConfirmDialog
          isOpen={showCancelConfirm}
          onClose={() => setShowCancelConfirm(false)}
          onConfirm={handleCancelConfirmed}
          title="Cancel invitation?"
          message="This will cancel the pending invitation. The member won't be able to join this chat."
          confirmText="Cancel invitation"
          cancelText="Keep invitation"
          variant="danger"
        />

        <ConfirmDialog
          isOpen={showLeaveConfirm}
          onClose={() => setShowLeaveConfirm(false)}
          onConfirm={handleLeaveChat}
          title="Leave chat?"
          message="You won't be able to see new messages in this chat. The owner can invite you again later."
          confirmText="Leave chat"
          cancelText="Stay"
          variant="danger"
        />
      </div>
    </div>
  )
}

export default InviteChatModal

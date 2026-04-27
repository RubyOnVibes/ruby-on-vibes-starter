import React, { useRef, useState, useCallback, useEffect } from 'react'
import { useTurboProps } from '../utils/turbo'
import { useTurboChat } from '../../hooks/useTurboChat'
import { useChatRunState } from '../../hooks/useChatRunState'
import { useMentionSearch } from '../../hooks/useMentionSearch'
import { useChatActions } from '../../hooks/useChatActions'
import useChatMembers from '../../hooks/useChatMembers'
import useWorkspaceMembers from '../../hooks/useWorkspaceMembers'
import { MessageList, ConfirmDialog, ChatDropdown, InviteChatModal, ChatMembersList } from '../../components/chat'
import ChatComposer from '../../components/chat/ChatComposer'
import AgentTaskPanel from '../../components/chat/AgentTaskPanel'
import { useAgentTasks } from '../../hooks/useAgentTasks'
import { validateFile } from '../../utils/fileValidation'

export default function ChatIsland({ containerId }) {
  // --- Props & Config ---
  const initialProps = useTurboProps(containerId)
  const chatId = initialProps?.chatId || null
  const showToolCalls = initialProps?.showToolCalls ?? true
  const permissions = initialProps?.permissions || {}
  const isGroupChatFromBackend = initialProps?.isGroupChat || false
  const isAgentChat = initialProps?.isAgentChat || false

  const [chatName, setChatName] = useState(initialProps?.chatName || 'New Chat')

  const userData = typeof window !== 'undefined' && window.Auth?.user() || {}
  const currentUserId = userData.id

  // --- Hooks ---
  const { messages, sendMessage, reconcileFromServer, clearMessages } = useTurboChat(chatId)
  const { activeRun, canStop, cancelRun, isAwaitingTasks } = useChatRunState(chatId)
  const { tasks: agentTasks, hasActive: hasActiveTasks, cancelTask: cancelAgentTask, dismissTasks: dismissAgentTasks, refetch: refetchAgentTasks } = useAgentTasks(chatId)
  const previousRunRef = useRef(null)
  const continuationTriggeredRef = useRef(false)

  // Reconcile messages and refresh agent tasks when a run completes
  useEffect(() => {
    if (previousRunRef.current && !activeRun) {
      reconcileFromServer()
      refetchAgentTasks() // Pick up any tasks created by tools during this run
      continuationTriggeredRef.current = false // Reset for next cycle
    }
    previousRunRef.current = activeRun
  }, [activeRun, reconcileFromServer, refetchAgentTasks])

  // When run enters awaiting_tasks, fetch tasks immediately so the panel
  // appears and the continuation logic below has data to work with.
  // Without this, useAgentTasks has no tasks (never polled) and continuation never fires.
  useEffect(() => {
    if (isAwaitingTasks) {
      refetchAgentTasks()
    }
  }, [isAwaitingTasks, refetchAgentTasks])

  // Auto-continuation: when awaiting_tasks and all agent tasks are terminal,
  // trigger the backend to resume the chat run with task results.
  // Skip if all tasks were cancelled (user doesn't need a summary of cancellations).
  //
  // IMPORTANT: Scope to tasks created during this run to avoid premature continuation
  // from old completed tasks. Without this, the effect fires before the refetch resolves
  // because stale agentTasks from prior runs already have completed items.
  const runCreatedAt = activeRun?.createdAt ? new Date(activeRun.createdAt) : null
  const tasksThisRun = runCreatedAt
    ? agentTasks.filter(t => new Date(t.createdAt) >= runCreatedAt)
    : agentTasks
  const hasCompletedOrFailed = tasksThisRun.some(t => t.status === 'completed' || t.status === 'failed')
  const allCancelled = tasksThisRun.length > 0 && !hasActiveTasks && tasksThisRun.every(t => t.status === 'cancelled')

  useEffect(() => {
    if (!isAwaitingTasks || hasActiveTasks || continuationTriggeredRef.current) return

    // If all tasks were cancelled, just complete the run (no summary needed).
    // If some completed/failed, trigger continuation for the assistant to summarize.
    if (allCancelled) {
      continuationTriggeredRef.current = true
      const completeRun = async () => {
        try {
          const token = document.querySelector('meta[name="csrf-token"]')?.content || ''
          await fetch(`/chat_runs/${activeRun.id}/cancel`, {
            method: 'POST',
            headers: { 'X-CSRF-Token': token, 'Accept': 'application/json' }
          })
        } catch (err) {
          console.error('[ChatIsland] Complete-after-cancel error:', err)
          continuationTriggeredRef.current = false
        }
      }
      completeRun()
    } else if (hasCompletedOrFailed) {
      continuationTriggeredRef.current = true
      const triggerContinuation = async () => {
        try {
          const token = document.querySelector('meta[name="csrf-token"]')?.content || ''
          const response = await fetch(`/chat_runs/${activeRun.id}/continue`, {
            method: 'POST',
            headers: { 'X-CSRF-Token': token, 'Accept': 'application/json' }
          })

          if (!response.ok) {
            console.error('[ChatIsland] Continuation failed:', response.status)
            continuationTriggeredRef.current = false
          }
        } catch (err) {
          console.error('[ChatIsland] Continuation error:', err)
          continuationTriggeredRef.current = false
        }
      }
      triggerContinuation()
    }
  }, [isAwaitingTasks, hasActiveTasks, hasCompletedOrFailed, allCancelled, activeRun])
  const { members: chatMembers, removeMember, refetch: refetchMembers } = useChatMembers(chatId)
  const { members: orgMembers } = useWorkspaceMembers()
  const { results: mentionResults, isLoading: mentionsLoading, search: searchMentions, clear: clearMentions } = useMentionSearch({ chatId })
  const { handleStop, rename, remove, leave, clear } = useChatActions(chatId, { cancelRun, canStop })

  // --- Permissions ---
  const canManageMembers = permissions.can_manage_members || false
  const canRename = permissions.can_rename || false
  const canDelete = permissions.can_delete || false
  const canSendMessages = permissions.can_send_messages ?? true
  const isOwner = permissions.is_owner || false
  const canLeave = permissions.can_leave || false
  const isGroupChat = chatMembers.length > 1
  const shouldShowMembersModal = chatId && (isGroupChat || canManageMembers || canLeave)

  // --- Input State ---
  const [inputValue, setInputValue] = useState('')
  const [mentions, setMentions] = useState([])
  const [attachments, setAttachments] = useState([])
  const [isCreatingChat, setIsCreatingChat] = useState(false)
  const inputRef = useRef(null)
  const fileInputRef = useRef(null)

  // --- Modal State ---
  const [showDeleteConfirm, setShowDeleteConfirm] = useState(false)
  const [showInviteModal, setShowInviteModal] = useState(false)
  const [showMembersPanel, setShowMembersPanel] = useState(false)
  const [showLeaveConfirm, setShowLeaveConfirm] = useState(false)

  useEffect(() => {
    const handleOpenModal = (e) => {
      if (e.detail?.chatId === chatId) {
        setShowInviteModal(true)
      }
    }
    window.addEventListener('open-members-modal', handleOpenModal)
    return () => window.removeEventListener('open-members-modal', handleOpenModal)
  }, [chatId])

  // --- Mention State ---
  const [showMentions, setShowMentions] = useState(false)
  const [mentionCursorPos, setMentionCursorPos] = useState(null)
  const [selectedMentionIndex, setSelectedMentionIndex] = useState(0)

  const detectMentionTrigger = useCallback((text) => {
    const cursorPosition = inputRef.current?.selectionStart || text.length
    const beforeCursor = text.slice(0, cursorPosition)
    const match = beforeCursor.match(/@(\w*)$/)

    if (match) {
      const query = match[1]
      setMentionCursorPos(match.index)
      setShowMentions(true)
      setSelectedMentionIndex(0)
      searchMentions(query || ' ')
    } else {
      setShowMentions(false)
      clearMentions()
    }
  }, [searchMentions, clearMentions])

  const handleMentionSelect = useCallback((mention) => {
    if (!inputRef.current || mentionCursorPos === null) return

    const text = inputValue
    const beforeMention = text.slice(0, mentionCursorPos)
    const afterMention = text.slice(inputRef.current.selectionStart || text.length)

    // Create mention chip element
    const chip = document.createElement('span')
    chip.className = 'mention-chip inline-flex items-center gap-1 px-1.5 py-0.5 mx-0.5 text-xs font-medium rounded border cursor-pointer'
    chip.contentEditable = 'false'
    chip.setAttribute('data-sgid', mention.sgid)
    chip.setAttribute('data-model', mention.model)
    chip.setAttribute('data-label', mention.label)
    chip.style.cssText = `
      background-color: var(--vibes-surface-2);
      color: var(--color-primary);
      border-color: var(--color-border);
    `
    const icon = document.createElement('span')
    icon.innerHTML = mention.model === 'Chat'
      ? '<svg style="width: 0.75rem; height: 0.75rem;" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M8 12h.01M12 12h.01M16 12h.01M21 12c0 4.418-4.03 8-9 8a9.863 9.863 0 01-4.255-.949L3 20l1.395-3.72C3.512 15.042 3 13.574 3 12c0-4.418 4.03-8 9-8s9 3.582 9 8z"/></svg>'
      : '<svg style="width: 0.75rem; height: 0.75rem;" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M16 7a4 4 0 11-8 0 4 4 0 018 0zM12 14a7 7 0 00-7 7h14a7 7 0 00-7-7z"/></svg>'
    chip.appendChild(icon)
    const label = document.createElement('span')
    label.textContent = `@${mention.label}`
    chip.appendChild(label)
    inputRef.current.focus()
    const selection = window.getSelection()
    if (selection && selection.rangeCount > 0) {
      const range = selection.getRangeAt(0)
      const textNode = inputRef.current.firstChild
      if (textNode && textNode.nodeType === Node.TEXT_NODE) {
        textNode.textContent = beforeMention
        range.setStartAfter(textNode)
        range.insertNode(chip)
        const spaceAndAfter = document.createTextNode(` ${afterMention}`)
        range.setStartAfter(chip)
        range.insertNode(spaceAndAfter)
        range.setStart(spaceAndAfter, 1)
        range.collapse(true)
        selection.removeAllRanges()
        selection.addRange(range)
      }
    }
    const newText = `${beforeMention}@${mention.label} ${afterMention}`
    setInputValue(newText)
    setMentions(prev => [...prev, mention])
    setShowMentions(false)
    clearMentions()
  }, [inputValue, mentionCursorPos, clearMentions])

  const handleMentionDismiss = useCallback(() => {
    setShowMentions(false)
    clearMentions()
  }, [clearMentions])

  // --- File Handling ---
  const handleFileSelect = (e) => {
    const files = Array.from(e.target.files || [])

    if (files.length > 0) {
      const validFiles = []
      const errors = []

      files.forEach(file => {
        const error = validateFile(file)
        if (error) {
          errors.push(`${file.name}: ${error}`)
        } else {
          validFiles.push(file)
        }
      })
      if (errors.length > 0) {
        alert(`Some files could not be added:\n\n${errors.join('\n')}`)
      }
      if (validFiles.length > 0) {
        setAttachments(prev => [...prev, ...validFiles])
      }
    }
    if (fileInputRef.current) {
      fileInputRef.current.value = ''
    }
  }

  const handleRemoveAttachment = (index) => {
    setAttachments(prev => prev.filter((_, i) => i !== index))
  }

  // --- Chat Actions (wrappers around useChatActions) ---
  const handleRename = async (newName) => {
    await rename(newName)
    setChatName(newName)
  }

  const handleDelete = async () => {
    try {
      await remove()
    } catch (error) {
      console.error('Failed to delete chat:', error)
    }
  }

  const handleLeave = async () => {
    try {
      await leave()
    } catch (error) {
      console.error('Failed to leave chat:', error)
      alert(error instanceof Error ? error.message : 'Failed to leave chat')
    }
  }

  const handleClear = async () => {
    try {
      await clear()
      clearMessages()
      refetchAgentTasks()
    } catch (error) {
      console.error('Failed to clear chat:', error)
    }
  }

  // --- Submit Handlers ---
  const clearInput = () => {
    setInputValue('')
    setMentions([])
    setAttachments([])
    setShowMentions(false)
    clearMentions()
    if (inputRef.current) inputRef.current.textContent = ''
  }

  const handleSubmit = async () => {
    if ((!inputValue.trim() && attachments.length === 0) || canStop || !canSendMessages) return

    const textToSend = inputValue.trim()
    const mentionsToSend = [...mentions]
    const filesToSend = [...attachments]

    clearInput()
    if (inputRef.current) inputRef.current.blur()

    await sendMessage(textToSend, { mentions: mentionsToSend, attachments: filesToSend })
  }

  const handleNewChatSubmit = async () => {
    if ((!inputValue.trim() && !attachments.length) || canStop || isCreatingChat) return

    setIsCreatingChat(true)

    const textToSend = inputValue.trim()
    const mentionsToSend = [...mentions]
    const filesToSend = [...attachments]

    clearInput()

    try {
      const token = document.querySelector('meta[name="csrf-token"]')?.content
      if (!token) throw new Error('CSRF token not found')
      const chatResponse = await fetch('/chats', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          'X-CSRF-Token': token
        }
      })

      if (!chatResponse.ok) {
        const error = await chatResponse.json()
        throw new Error(error.error || 'Failed to create chat')
      }

      const { id: newChatId } = await chatResponse.json()

      let messageResponse

      if (filesToSend.length > 0) {
        const formData = new FormData()
        formData.append('chat_id', newChatId)
        formData.append('content', textToSend)

        mentionsToSend.forEach(m => {
          formData.append('mentions[]', JSON.stringify({
            id: m.id,
            model: m.model,
            label: m.label,
            path: m.path,
            metadata: m.metadata || {}
          }))
        })

        filesToSend.forEach(file => {
          formData.append('attachments[]', file)
        })

        messageResponse = await fetch('/messages', {
          method: 'POST',
          headers: {
            'Accept': 'application/json',
            'X-CSRF-Token': token
          },
          body: formData
        })
      } else {
        messageResponse = await fetch('/messages', {
          method: 'POST',
          headers: {
            'Content-Type': 'application/json',
            'Accept': 'application/json',
            'X-CSRF-Token': token
          },
          body: JSON.stringify({
            chat_id: newChatId,
            content: textToSend,
            mentions: mentionsToSend.map(m => ({
              id: m.id,
              model: m.model,
              label: m.label,
              path: m.path,
              metadata: m.metadata || {}
            }))
          })
        })
      }

      if (!messageResponse.ok) {
        const error = await messageResponse.json()
        throw new Error(error.error || 'Failed to create message')
      }
      window.Turbo.visit(`/chats/${newChatId}`)
    } catch (error) {
      console.error('Failed to create chat:', error)
      setIsCreatingChat(false)
      setInputValue(textToSend)
      setMentions(mentionsToSend)
      setAttachments(filesToSend)
    }
  }

  // --- Computed ---
  const visibleMessages = messages.filter(m => {
    if (!m) return false
    if (m.role === 'system') return false
    if (m.role === 'tool' && !showToolCalls) return false
    return true
  })

  // Thinking indicator is now handled by MessageBubble for empty assistant messages

  // --- Shared composer props ---
  const composerProps = {
    inputRef,
    fileInputRef,
    inputValue,
    onInputChange: setInputValue,
    onMentionDetect: detectMentionTrigger,
    attachments,
    onFileSelect: handleFileSelect,
    onRemoveAttachment: handleRemoveAttachment,
    showMentions,
    mentionResults,
    mentionsLoading,
    selectedMentionIndex,
    onMentionIndexChange: setSelectedMentionIndex,
    onMentionSelect: handleMentionSelect,
    onMentionDismiss: handleMentionDismiss,
  }

  // --- Mobile sidebar toggle ---
  const openMobileSidebar = () => {
    const sidebar = document.getElementById('mobile-sidebar')
    const overlay = document.getElementById('mobile-sidebar-overlay')
    if (sidebar && overlay) {
      sidebar.classList.add('show-mobile')
      overlay.classList.remove('hidden')
      setTimeout(() => overlay.classList.add('opacity-100'), 10)
    }
  }

  // =====================
  // Empty state (new chat)
  // =====================
  if (!chatId) {
    return (
      <div className="flex flex-col h-full w-full" style={{
        backgroundColor: 'var(--color-background)',
        color: 'var(--color-foreground)'
      }}>
        {/* Mobile header bar */}
        <div className="flex-shrink-0 px-4 border-b flex items-center lg:hidden" style={{
          backgroundColor: 'var(--color-surface-1)',
          borderColor: 'var(--color-border)',
          height: '53px'
        }}>
          <button
            type="button"
            onClick={openMobileSidebar}
            className="p-2 rounded-lg transition mobile-sidebar-toggle"
            aria-label="Open sidebar"
          >
            <svg className="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth="2" d="M4 6h16M4 12h16M4 18h16" />
            </svg>
          </button>
        </div>

        {/* Centered empty state */}
        <div className="flex-1 flex flex-col items-center justify-center px-4">
          {isCreatingChat ? (
            <div
              className="w-5 h-5 rounded-full border-2 animate-spin"
              style={{
                borderColor: 'var(--color-border)',
                borderTopColor: 'var(--color-muted-foreground)'
              }}
            />
          ) : (
            <h1
              className="text-xl sm:text-2xl font-medium mb-8 sm:mb-12 text-center"
              style={{ color: 'var(--color-foreground)' }}
            >
              Ready when you are.
            </h1>
          )}
        </div>

        <ChatComposer
          {...composerProps}
          onSubmit={handleNewChatSubmit}
          disabled={isCreatingChat || canStop}
          isSubmitting={isCreatingChat}
        />
      </div>
    )
  }

  // =====================
  // Chat view with messages
  // =====================
  return (
    <div className="flex flex-col h-full w-full" style={{
      backgroundColor: 'var(--color-background)',
      color: 'var(--color-foreground)'
    }}>
      {/* Top bar */}
      <div className="flex-shrink-0 px-4 border-b flex items-center justify-between" style={{
        backgroundColor: 'var(--color-surface-1)',
        borderColor: 'var(--color-border)',
        height: '53px'
      }}>
        <button
          type="button"
          onClick={openMobileSidebar}
          className="lg:hidden p-2 rounded-lg transition mobile-sidebar-toggle"
          aria-label="Open sidebar"
        >
          <svg className="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path strokeLinecap="round" strokeLinejoin="round" strokeWidth="2" d="M4 6h16M4 12h16M4 18h16" />
          </svg>
        </button>

        <div className="flex-1"></div>

        {chatId && (canRename || canDelete || (isGroupChat || canManageMembers) || canLeave) && (
          <ChatDropdown
            chatId={chatId}
            chatName={chatName}
            onRename={canRename ? handleRename : undefined}
            onClear={isAgentChat && canDelete ? handleClear : undefined}
            clearDisabled={canStop}
            onDelete={canDelete && !isAgentChat ? (() => setShowDeleteConfirm(true)) : undefined}
            onViewMembers={(canManageMembers || isGroupChat) ? (() => setShowInviteModal(true)) : undefined}
            onLeave={canLeave ? (() => setShowLeaveConfirm(true)) : undefined}
            orientation="horizontal"
          />
        )}
      </div>

      {/* Messages and Members Panel */}
      <div className="flex-1 min-h-0 overflow-hidden w-full flex">
        <div className="flex-1 min-h-0 overflow-hidden flex justify-center">
          <div className="w-full max-w-3xl flex flex-col min-h-0">
            <MessageList
              messages={visibleMessages}
              currentUserId={currentUserId}
              isRunActive={!!activeRun}
              showThinking={false}
              isGroupChat={isGroupChatFromBackend}
              scrollTrigger={agentTasks.length}
            />
          </div>
        </div>

        {isGroupChat && showMembersPanel && (
          <div
            className="w-64 flex-shrink-0 border-l p-4 overflow-y-auto"
            style={{
              backgroundColor: 'var(--color-surface-1)',
              borderColor: 'var(--color-border)'
            }}
          >
            <div className="flex items-center justify-between mb-4">
              <h3 className="text-sm font-semibold" style={{ color: 'var(--color-foreground)' }}>
                Members ({chatMembers.length})
              </h3>
              <button
                type="button"
                onClick={() => setShowMembersPanel(false)}
                className="p-1 rounded hover:opacity-70"
                style={{ color: 'var(--color-muted-foreground)' }}
                aria-label="Close members panel"
              >
                <svg className="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path strokeLinecap="round" strokeLinejoin="round" strokeWidth="2" d="M6 18L18 6M6 6l12 12" />
                </svg>
              </button>
            </div>

            <ChatMembersList
              members={chatMembers}
              isOwner={isOwner}
              onRemoveMember={removeMember}
            />
          </div>
        )}
      </div>

      {/* Agent task progress panel */}
      <AgentTaskPanel tasks={agentTasks} onCancel={cancelAgentTask} onDismiss={dismissAgentTasks} />

      {/* Chat input */}
      <ChatComposer
        {...composerProps}
        onSubmit={handleSubmit}
        canStop={canStop}
        onStop={handleStop}
        disabled={!canSendMessages}
      />

      <ConfirmDialog
        isOpen={showDeleteConfirm}
        onClose={() => setShowDeleteConfirm(false)}
        onConfirm={handleDelete}
        title="Delete chat?"
        message="This will permanently delete this chat and all its messages. This action cannot be undone."
        confirmText="Delete"
        cancelText="Cancel"
        variant="danger"
      />

      <ConfirmDialog
        isOpen={showLeaveConfirm}
        onClose={() => setShowLeaveConfirm(false)}
        onConfirm={handleLeave}
        title="Leave chat?"
        message="You won't be able to see new messages in this chat. The owner can invite you again later."
        confirmText="Leave chat"
        cancelText="Stay"
        variant="danger"
      />

      {shouldShowMembersModal && (
        <InviteChatModal
          chatId={chatId}
          isOpen={showInviteModal}
          onClose={() => setShowInviteModal(false)}
          currentMembers={chatMembers}
          workspaceMembers={orgMembers}
          isOwner={isOwner}
          canManageMembers={canManageMembers}
          canLeave={canLeave}
          onInviteSent={() => {
            refetchMembers()
          }}
          onRemoveMember={canManageMembers ? removeMember : undefined}
        />
      )}
    </div>
  )
}

/**
 * ChatSidebarIsland - Individual chat item in sidebar with inline dropdown
 * 
 * Reusable component for chat list items with rename/delete actions
 */

import React, { useState } from 'react'
import { useTurboProps } from '../utils/turbo'
import { ChatDropdown, ConfirmDialog } from '../../components/chat'

export default function ChatSidebarIsland({ containerId }) {
  // Get initial state from data-initial-state attribute (IslandJS pattern)
  const initialProps = useTurboProps(containerId)
  const chatId = initialProps?.chatId
  const isActive = initialProps?.isActive || false
  const chatPath = initialProps?.chatPath
  const isOwner = initialProps?.isOwner || false
  const isGroupChat = initialProps?.isGroupChat || false
  const canLeave = initialProps?.canLeave || false
  
  const [localName, setLocalName] = useState(initialProps?.chatName || 'New Chat')
  const [showConfirmDelete, setShowConfirmDelete] = useState(false)
  const [showMembersModal, setShowMembersModal] = useState(false)
  const [showLeaveConfirm, setShowLeaveConfirm] = useState(false)
  
  const handleRename = async (newName) => {
    try {
      const token = document.querySelector('meta[name="csrf-token"]')?.content
      if (!token) throw new Error('CSRF token not found')
      
      const response = await fetch(`/chats/${chatId}`, {
        method: 'PATCH',
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          'X-CSRF-Token': token
        },
        body: JSON.stringify({ chat: { name: newName } })
      })
      
      if (!response.ok) {
        const error = await response.json()
        throw new Error(error.error || 'Failed to rename chat')
      }
      
      setLocalName(newName)
    } catch (error) {
      console.error('Failed to rename chat:', error)
      throw error
    }
  }
  
  const handleDeleteConfirmed = async () => {
    try {
      const token = document.querySelector('meta[name="csrf-token"]')?.content
      if (!token) throw new Error('CSRF token not found')
      
      const response = await fetch(`/chats/${chatId}`, {
        method: 'DELETE',
        headers: { 
          'Accept': 'application/json',
          'X-CSRF-Token': token 
        }
      })
      
      if (!response.ok) {
        const error = await response.json()
        throw new Error(error.error || 'Failed to delete chat')
      }
      
      // If we're on this chat, redirect to index
      if (isActive) {
        window.location.href = '/chats'
      } else {
        // Just refresh to update sidebar
        window.location.reload()
      }
    } catch (error) {
      console.error('Failed to delete chat:', error)
    }
  }
  
  const handleLeaveConfirmed = async () => {
    try {
      const token = document.querySelector('meta[name="csrf-token"]')?.content
      if (!token) throw new Error('CSRF token not found')
      
      const response = await fetch(`/chats/${chatId}/leave`, {
        method: 'POST',
        headers: {
          'Accept': 'application/json',
          'X-CSRF-Token': token
        }
      })
      
      if (!response.ok) {
        const error = await response.json()
        throw new Error(error.error || 'Failed to leave chat')
      }
      
      window.location.href = '/chats'
    } catch (error) {
      console.error('Failed to leave chat:', error)
      alert(error.message || 'Failed to leave chat')
    }
  }
  
  const handleChatClick = (e) => {
    // Close mobile sidebar when clicking a chat
    if (window.innerWidth < 1024) {
      const sidebar = document.getElementById('mobile-sidebar')
      const overlay = document.getElementById('mobile-sidebar-overlay')
      if (sidebar) sidebar.classList.remove('show-mobile')
      if (overlay) {
        overlay.classList.remove('opacity-100')
        overlay.classList.add('opacity-0')
        setTimeout(() => overlay.classList.add('hidden'), 300)
      }
    }
  }
  
  return (
    <a
      href={chatPath}
      onClick={handleChatClick}
      className={`chat-list-item flex items-center gap-2 px-3 py-2 mb-0.5 rounded-md text-sm transition group relative ${isActive ? 'active' : ''}`}
      style={{ textDecoration: 'none', color: 'inherit' }}
    >
      <span className="truncate flex-1 min-w-0">
        {localName}
      </span>
      
      {(isOwner || isGroupChat || canLeave) && (
      <div 
        data-dropdown 
        className="flex-shrink-0 lg:opacity-0 lg:group-hover:opacity-100 transition-opacity"
        onClick={(e) => {
          e.preventDefault()
          e.stopPropagation()
        }}
      >
        <ChatDropdown
          chatId={chatId}
          chatName={localName}
          onRename={isOwner ? handleRename : undefined}
          onDelete={isOwner ? (() => setShowConfirmDelete(true)) : undefined}
          onViewMembers={(isOwner || isGroupChat) && isActive ? (() => {
            // Only show "View members" if already viewing this chat
            const event = new CustomEvent('open-members-modal', { 
              detail: { chatId } 
            })
            window.dispatchEvent(event)
          }) : undefined}
          onLeave={canLeave && isActive ? (() => setShowLeaveConfirm(true)) : undefined}
          orientation="horizontal"
          compact={true}
          placement="right"
        />
      </div>
      )}
      
      <ConfirmDialog
        isOpen={showConfirmDelete}
        onClose={() => setShowConfirmDelete(false)}
        onConfirm={handleDeleteConfirmed}
        title="Delete chat?"
        message="This will permanently delete this chat and all its messages. This action cannot be undone."
        confirmText="Delete"
        cancelText="Cancel"
        variant="danger"
      />
      
      <ConfirmDialog
        isOpen={showLeaveConfirm}
        onClose={() => setShowLeaveConfirm(false)}
        onConfirm={handleLeaveConfirmed}
        title="Leave chat?"
        message="You won't be able to see new messages in this chat. The owner can invite you again later."
        confirmText="Leave chat"
        cancelText="Stay"
        variant="danger"
      />
    </a>
  )
}


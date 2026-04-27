/**
 * Shared Chat Components
 *
 * Framework-agnostic UI components for chat interface
 * Used by both useTurboChat and useInertiaChat adapters
 *
 * Core system: text + mentions (prefix_id) + attachments (Active Storage)
 */

// Types
export * from './types'

// Components
export { MessageBubble } from './MessageBubble'
export { MessageList } from './MessageList'
export { ChatInput } from './ChatInput'
export { default as ChatComposer } from './ChatComposer'
export { MentionChip } from './MentionChip'
export { ConfirmDialog } from './ConfirmDialog'
export { ChatDropdown } from './ChatDropdown'
export { MentionAutocomplete } from './MentionAutocomplete'
export { ChatMembersList } from './ChatMembersList'
export { InviteChatModal } from './InviteChatModal'
export { default as AgentTaskPanel } from './AgentTaskPanel'

// NOTE: TaggedElement is platform-specific (file browser integration)
// Not included in template - use MentionChip with prefix_id pattern instead
// If you need file browser integration, implement with MentionedModel:
//   { id: "file_xxx", model: "File", label: "user.rb", path: "/files/file_xxx" }

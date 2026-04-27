/**
 * RubyLLM Chat Type Definitions
 *
 * Core types for dual-adapter chat system (Turbo + Inertia)
 * Rails-native: Uses prefix_id (e.g., chat_xxx, mbr_xxx) for stable model references
 * Designed for extensibility: text, mentions, attachments, voice, images
 */

// ============================================================================
// UTILITY FUNCTIONS
// ============================================================================

/**
 * Type guard: check if message is valid
 */
export function isValidMessage(m) {
  if (!m || typeof m !== 'object') return false
  if (!Number.isFinite(m.id)) return false
  if (typeof m.role !== 'string') return false
  if (!['user', 'assistant', 'system', 'tool'].includes(m.role)) return false
  if (typeof m.content !== 'string') return false
  return true
}

/**
 * Type guard: check if attachment is valid
 */
export function isValidAttachment(a) {
  if (!a || typeof a !== 'object') return false
  if (!a.id || (!a.url && !a.filename)) return false
  return true
}

/**
 * Type guard: check if mention is valid
 */
export function isValidMention(m) {
  if (!m || typeof m !== 'object') return false
  // id is optional (may be in metadata for backward compat)
  const hasId = m.id || m.metadata?.id
  if (!hasId) return false
  if (typeof m.model !== 'string' || !m.model) return false
  if (typeof m.label !== 'string' || !m.label) return false
  return true
}

/**
 * Sanitize messages array (remove invalid entries)
 */
export function sanitizeMessages(messages, context = 'unknown') {
  if (!Array.isArray(messages)) return []

  const valid = messages.filter(isValidMessage)

  if (valid.length !== messages.length && typeof console !== 'undefined') {
    console.warn(`[Chat] Dropped ${messages.length - valid.length} invalid messages (${context})`)
  }

  return valid
}

/**
 * Helper: normalize content for display
 * Handles escaped newlines from JSON/HTML attributes
 */
export function normalizeContent(value) {
  if (value == null) return ''
  const s = String(value)

  try {
    // Safely decode common escapes via JSON without double-decoding
    return JSON.parse('"' + s.replace(/\\/g, '\\\\').replace(/"/g, '\\"') + '"')
  } catch {
    return s
      .replace(/\\n/g, '\n')
      .replace(/\\r/g, '\r')
      .replace(/\\t/g, '\t')
  }
}

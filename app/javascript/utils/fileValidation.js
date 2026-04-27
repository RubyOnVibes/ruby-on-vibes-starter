/**
 * File validation utilities for chat attachments
 *
 * Mirrors backend validation from config/initializers/chat_attachments.rb
 * Provides immediate user feedback before upload
 */

// Supported MIME types by category
// Keep in sync with ChatAttachments::SUPPORTED_TYPES
export const SUPPORTED_TYPES = {
  images: [
    'image/png',
    'image/jpeg',
    'image/jpg',
    'image/gif',
    'image/webp'
  ],
  text: [
    'text/plain',
    'text/markdown',
    'text/csv',
    'application/json'
  ],
  code: [
    'text/x-ruby',
    'text/x-python',
    'text/x-javascript',
    'text/x-typescript',
    'text/html',
    'text/css',
    'application/javascript',
    'application/typescript'
  ]
}

// Maximum file sizes (in bytes)
// Keep in sync with ChatAttachments::MAX_FILE_SIZE
export const MAX_FILE_SIZE = {
  images: 20 * 1024 * 1024,  // 20MB
  text: 1 * 1024 * 1024,     // 1MB
  code: 1 * 1024 * 1024      // 1MB
}

/**
 * Get all supported MIME types (flattened)
 */
export function getAllSupportedTypes() {
  return Object.values(SUPPORTED_TYPES).flat()
}

/**
 * Check if a content type is supported
 */
export function isSupported(contentType) {
  return getAllSupportedTypes().includes(contentType)
}

/**
 * Get category for a content type
 */
export function getCategoryFor(contentType) {
  for (const [category, types] of Object.entries(SUPPORTED_TYPES)) {
    if (types.includes(contentType)) {
      return category
    }
  }
  return null
}

/**
 * Get max size for a content type
 */
export function getMaxSizeFor(contentType) {
  const category = getCategoryFor(contentType)
  return category ? MAX_FILE_SIZE[category] : 0
}

/**
 * Check if file size is within limits
 */
export function isWithinSizeLimit(contentType, byteSize) {
  const maxSize = getMaxSizeFor(contentType)
  if (maxSize === 0) return false
  return byteSize <= maxSize
}

/**
 * Validate a file (returns error message or null if valid)
 */
export function validateFile(file) {
  if (!isSupported(file.type)) {
    const category = getCategoryFor(file.type)
    return `File type not supported. Supported: images (png, jpg, gif, webp), text files (txt, md, json, csv), and code files.`
  }

  if (!isWithinSizeLimit(file.type, file.size)) {
    const maxSize = getMaxSizeFor(file.type)
    const maxSizeHuman = humanFileSize(maxSize)
    const fileSizeHuman = humanFileSize(file.size)
    return `File too large (${fileSizeHuman}). Maximum size for this file type: ${maxSizeHuman}`
  }

  return null
}

/**
 * Human-readable file size
 */
export function humanFileSize(bytes) {
  if (bytes === 0) return '0 B'

  const units = ['B', 'KB', 'MB', 'GB']
  const exp = Math.min(Math.floor(Math.log(bytes) / Math.log(1024)), units.length - 1)
  const size = bytes / Math.pow(1024, exp)

  return `${size.toFixed(1)} ${units[exp]}`
}

/**
 * Check if file is an image
 */
export function isImage(file) {
  return SUPPORTED_TYPES.images.includes(file.type)
}

/**
 * Get accept attribute for file input
 */
export function getAcceptAttribute() {
  return getAllSupportedTypes().join(',')
}

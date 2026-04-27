/**
 * Direct Upload Helper - Active Storage to S3
 *
 * Handles file uploads directly to S3 (or local storage) without blocking
 * the main application request.
 *
 * Compatible with:
 * - AWS S3
 * - Google Cloud Storage
 * - Azure Blob Storage
 * - Local disk storage
 *
 * @see https://edgeguides.rubyonrails.org/active_storage_overview.html#direct-uploads
 */

import { DirectUpload } from '@rails/activestorage'

/**
 * Upload file to Active Storage (S3/local)
 *
 * @example
 * ```javascript
 * const file = fileInput.files[0]
 * const result = await uploadFileToActiveStorage(file, (progress) => {
 *   console.log(`Uploading: ${progress.percentage}%`)
 * })
 *
 * // Send message with attachment
 * sendMessage("Check this out", {
 *   attachmentIds: [result.signedId]
 * })
 * ```
 */
export async function uploadFileToActiveStorage(file, onProgress) {
  return new Promise((resolve, reject) => {
    const upload = new DirectUpload(
      file,
      '/rails/active_storage/direct_uploads',
      {
        directUploadWillStoreFileWithXHR: (request) => {
          // Track upload progress
          request.upload.addEventListener('progress', (event) => {
            if (onProgress && event.lengthComputable) {
              onProgress({
                loaded: event.loaded,
                total: event.total,
                percentage: Math.round((event.loaded / event.total) * 100)
              })
            }
          })
        }
      }
    )

    upload.create((error, blob) => {
      if (error) {
        reject(error)
      } else {
        resolve({
          signedId: blob.signed_id,
          filename: blob.filename,
          contentType: blob.content_type,
          byteSize: blob.byte_size
        })
      }
    })
  })
}

/**
 * Upload multiple files in parallel
 *
 * @example
 * ```javascript
 * const files = Array.from(fileInput.files)
 * const results = await uploadMultipleFiles(files, (filename, progress) => {
 *   console.log(`${filename}: ${progress.percentage}%`)
 * })
 *
 * sendMessage("Multiple files", {
 *   attachmentIds: results.map(r => r.signedId)
 * })
 * ```
 */
export async function uploadMultipleFiles(files, onProgress) {
  return Promise.all(
    files.map(file =>
      uploadFileToActiveStorage(file, progress => {
        if (onProgress) onProgress(file.name, progress)
      })
    )
  )
}

/**
 * Check if file type is accepted
 */
export function isFileTypeAccepted(file, acceptedTypes) {
  if (!acceptedTypes || acceptedTypes.length === 0) return true

  return acceptedTypes.some(type => {
    // Wildcard match (e.g., "image/*")
    if (type.endsWith('/*')) {
      const prefix = type.slice(0, -2)
      return file.type.startsWith(prefix + '/')
    }

    // Exact match
    return file.type === type
  })
}

/**
 * Check if file size is within limit
 */
export function isFileSizeValid(file, maxSize) {
  if (!maxSize) return true
  return file.byteSize <= maxSize
}

/**
 * Format bytes for display
 */
export function formatFileSize(bytes) {
  if (bytes === 0) return '0 B'

  const k = 1024
  const sizes = ['B', 'KB', 'MB', 'GB']
  const i = Math.floor(Math.log(bytes) / Math.log(k))

  return `${(bytes / Math.pow(k, i)).toFixed(1)} ${sizes[i]}`
}

export default {
  uploadFileToActiveStorage,
  uploadMultipleFiles,
  isFileTypeAccepted,
  isFileSizeValid,
  formatFileSize
}

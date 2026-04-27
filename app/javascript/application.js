// Configure your import map in config/importmap.rb. Read more: https://github.com/rails/importmap-rails
import "@hotwired/turbo-rails"
import "ahoy"

// Custom Turbo Stream "upsert" action: replace if target exists, append if not.
// Solves ActionCable out-of-order delivery where a "replace" can arrive before
// the "append" that creates the target element.
Turbo.StreamActions.upsert = function () {
  const targetEl = document.getElementById(this.target)
  const newContent = this.templateContent.firstElementChild?.cloneNode(true)
  if (!newContent) return

  if (targetEl) {
    targetEl.replaceWith(newContent)
  } else {
    document.getElementById("messages")?.appendChild(newContent)
  }
}

// Lightweight streaming action: updates data-raw-content attribute and dispatches
// a CustomEvent for React. Unlike "upsert" which replaces the entire DOM element,
// this keeps the element stable and provides a direct JS channel to React state.
Turbo.StreamActions.stream_content = function () {
  const targetEl = document.getElementById(this.target)
  const newContent = this.templateContent.textContent || ''

  // Still update DOM (for hydration and non-React consumers)
  if (targetEl) {
    targetEl.setAttribute('data-raw-content', newContent)
  } else {
    console.warn(`[streaming] stream_content: target NOT FOUND: ${this.target}`)
  }

  // Direct JS channel to React — bypasses DOM observation entirely
  const match = this.target.match(/^message_(\d+)_content$/)
  if (match) {
    window.dispatchEvent(new CustomEvent('stream-content', {
      detail: { messageId: parseInt(match[1], 10), content: newContent }
    }))
  }
}
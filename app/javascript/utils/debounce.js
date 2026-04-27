/**
 * Debounce utility - React-friendly
 *
 * Usage:
 *   const debouncedSearch = useMemo(
 *     () => debounce(async (query) => { ... }, 300),
 *     []
 *   )
 */

export function debounce(func, wait) {
  let timeout = null

  return function executedFunction(...args) {
    const later = () => {
      timeout = null
      func(...args)
    }

    if (timeout !== null) {
      clearTimeout(timeout)
    }

    timeout = setTimeout(later, wait)
  }
}

/**
 * Debounce with Promise support - for async functions
 * Returns a promise that resolves when the debounced function completes
 */
export function debounceAsync(func, wait) {
  let timeout = null
  let resolvePromise = null

  return function executedFunction(...args) {
    return new Promise((resolve) => {
      if (timeout !== null) {
        clearTimeout(timeout)
      }

      timeout = setTimeout(async () => {
        timeout = null
        const result = await func(...args)
        resolve(result)
      }, wait)
    })
  }
}

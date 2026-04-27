import { useState, useEffect } from 'react'
import { NotificationList } from '../../components/notifications'

function generatePageSeries(current, last, isMobile = false) {
  const maxPages = isMobile ? 3 : 8
  
  if (last <= maxPages) {
    const series = []
    for (let i = 1; i <= last; i++) {
      series.push(i)
    }
    return series
  }
  
  const half = Math.floor(maxPages / 2)
  let start = Math.max(1, current - half)
  let end = Math.min(last, start + maxPages - 1)
  
  if (end === last) {
    start = Math.max(1, last - maxPages + 1)
  }
  
  const series = []
  for (let i = start; i <= end; i++) {
    series.push(i)
  }
  
  return series
}

export default function NotificationsIsland({ initialPage = 1, totalPages = 1 }) {
  
  const [notifications, setNotifications] = useState([])
  const [isLoading, setIsLoading] = useState(true)
  const [currentPage, setCurrentPage] = useState(initialPage)
  const [isMobile, setIsMobile] = useState(false)
  const [pagination, setPagination] = useState({
    page: initialPage,
    previous: null,
    next: null,
    last: totalPages,
    count: 0,
    limit: 25,
    first_url: null,
    last_url: null
  })
  
  useEffect(() => {
    const checkMobile = () => setIsMobile(window.innerWidth < 768)
    checkMobile()
    window.addEventListener('resize', checkMobile)
    return () => window.removeEventListener('resize', checkMobile)
  }, [])
  
  const fetchNotifications = async (page = 1) => {
    setIsLoading(true)
    
    try {
      const response = await fetch(`/notifications.json?page=${page}`, {
        headers: {
          'Accept': 'application/json',
          'X-Requested-With': 'XMLHttpRequest'
        }
      })
      
      if (!response.ok) {
        throw new Error(`HTTP ${response.status}`)
      }
      
      const data = await response.json()
      
      setNotifications(data.notifications || [])
      setPagination(data.pagination || pagination)
      setCurrentPage(page)
    } catch (error) {
      console.error('[NotificationsIsland] Fetch failed:', error)
    } finally {
      setIsLoading(false)
    }
  }
  
  useEffect(() => {
    fetchNotifications(initialPage)
  }, [])
  
  const handleMarkAsRead = async (id) => {
    try {
      const response = await fetch(`/notifications/${id}/mark_as_read`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'X-CSRF-Token': document.querySelector('meta[name="csrf-token"]')?.content || '',
          'X-Requested-With': 'XMLHttpRequest'
        }
      })
      
      if (response.ok) {
        const now = new Date().toISOString()
        setNotifications(prev => 
          prev.map(n => n.id === id ? { ...n, readAt: now } : n)
        )
      }
    } catch (error) {
      console.error('[NotificationsIsland] Mark as read error:', error)
    }
  }
  
  const handleMarkAllAsRead = () => {
    const form = document.createElement('form')
    form.method = 'POST'
    form.action = '/notifications/mark_all_as_read'
    
    const csrfToken = document.querySelector('meta[name="csrf-token"]')?.content
    if (csrfToken) {
      const input = document.createElement('input')
      input.type = 'hidden'
      input.name = 'authenticity_token'
      input.value = csrfToken
      form.appendChild(input)
    }
    
    document.body.appendChild(form)
    form.submit()
  }
  
  const handlePageChange = (newPage) => {
    fetchNotifications(newPage)
    window.scrollTo({ top: 0, behavior: 'smooth' })
  }
  
  const pageSeries = generatePageSeries(currentPage, pagination.last, isMobile)
  const showFirstLast = pagination.last > (isMobile ? 3 : 8)
  
  return (
    <>
      <NotificationList
        notifications={notifications}
        onMarkAsRead={handleMarkAsRead}
        onMarkAllAsRead={handleMarkAllAsRead}
        isLoading={isLoading}
      />
      
      {pagination.last > 1 && !isLoading && (
        <div className="mt-8 flex items-center justify-center gap-2 flex-wrap">
          {showFirstLast && (
            <button
              onClick={() => handlePageChange(1)}
              disabled={currentPage === 1}
              className="px-3 py-2 text-sm font-medium rounded-md disabled:opacity-40 disabled:cursor-not-allowed
                       text-foreground bg-surface-1 border-border border
                       hover:bg-surface-2 hover:border-primary
                       disabled:hover:bg-surface-1
                       transition-all duration-150"
              title="First page"
            >
              First
            </button>
          )}
          
          <button
            onClick={() => handlePageChange(currentPage - 1)}
            disabled={!pagination.previous}
            className="px-3 py-2 text-sm font-medium rounded-md disabled:opacity-40 disabled:cursor-not-allowed
                     text-foreground bg-surface-1 border-border border
                     hover:bg-surface-2 hover:border-primary
                     disabled:hover:bg-surface-1
                     transition-all duration-150"
            aria-label="Previous page"
          >
            <svg className="w-5 h-5" fill="none" viewBox="0 0 24 24" stroke="currentColor" strokeWidth={2}>
              <path strokeLinecap="round" strokeLinejoin="round" d="M11 19l-7-7 7-7m8 14l-7-7 7-7" />
            </svg>
          </button>
          
          <div className="flex items-center gap-1">
            {pageSeries.map((page) => (
              <button
                key={page}
                onClick={() => handlePageChange(page)}
                className={`
                  px-3 py-2 text-sm font-medium rounded-md transition-all duration-150
                  ${page === currentPage
                    ? 'bg-primary hover:bg-primary/90 text-primary-foreground shadow-sm border border-primary'
                    : 'text-foreground bg-surface-1 border-border border hover:bg-surface-2 hover:border-primary'
                  }
                `}
              >
                {page}
              </button>
            ))}
          </div>
          
          <button
            onClick={() => handlePageChange(currentPage + 1)}
            disabled={!pagination.next}
            className="px-3 py-2 text-sm font-medium rounded-md disabled:opacity-40 disabled:cursor-not-allowed
                     text-foreground bg-surface-1 border-border border
                     hover:bg-surface-2 hover:border-primary
                     disabled:hover:bg-surface-1
                     transition-all duration-150"
            aria-label="Next page"
          >
            <svg className="w-5 h-5" fill="none" viewBox="0 0 24 24" stroke="currentColor" strokeWidth={2}>
              <path strokeLinecap="round" strokeLinejoin="round" d="M13 5l7 7-7 7M5 5l7 7-7 7" />
            </svg>
          </button>
          
          {showFirstLast && (
            <button
              onClick={() => handlePageChange(pagination.last)}
              disabled={currentPage === pagination.last}
              className="px-3 py-2 text-sm font-medium rounded-md disabled:opacity-40 disabled:cursor-not-allowed
                       text-foreground bg-surface-1 border-border border
                       hover:bg-surface-2 hover:border-primary
                       disabled:hover:bg-surface-1
                       transition-all duration-150"
              title={`Last page (${pagination.last})`}
            >
              Last
            </button>
          )}
        </div>
      )}
    </>
  )
}

import { useState, useRef, useEffect } from 'react'

// Icon components for nav items (maps icon name to SVG)
const NavIcons = {
  MessageSquare: (
    <svg className="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24" strokeWidth="1.5">
      <path strokeLinecap="round" strokeLinejoin="round" d="M8.625 12a.375.375 0 11-.75 0 .375.375 0 01.75 0zm0 0H8.25m4.125 0a.375.375 0 11-.75 0 .375.375 0 01.75 0zm0 0H12m4.125 0a.375.375 0 11-.75 0 .375.375 0 01.75 0zm0 0h-.375M21 12c0 4.556-4.03 8.25-9 8.25a9.764 9.764 0 01-2.555-.337A5.972 5.972 0 015.41 20.97a5.969 5.969 0 01-.474-.065 4.48 4.48 0 00.978-2.025c.09-.457-.133-.901-.467-1.226C3.93 16.178 3 14.189 3 12c0-4.556 4.03-8.25 9-8.25s9 3.694 9 8.25z" />
    </svg>
  ),
  Workspace: (
    <svg className="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24" strokeWidth="1.5">
      <path strokeLinecap="round" strokeLinejoin="round" d="M3.75 6A2.25 2.25 0 016 3.75h2.25A2.25 2.25 0 0110.5 6v2.25a2.25 2.25 0 01-2.25 2.25H6a2.25 2.25 0 01-2.25-2.25V6zM3.75 15.75A2.25 2.25 0 016 13.5h2.25a2.25 2.25 0 012.25 2.25V18a2.25 2.25 0 01-2.25 2.25H6A2.25 2.25 0 013.75 18v-2.25zM13.5 6a2.25 2.25 0 012.25-2.25H18A2.25 2.25 0 0120.25 6v2.25A2.25 2.25 0 0118 10.5h-2.25a2.25 2.25 0 01-2.25-2.25V6zM13.5 15.75a2.25 2.25 0 012.25-2.25H18a2.25 2.25 0 012.25 2.25V18A2.25 2.25 0 0118 20.25h-2.25A2.25 2.25 0 0113.5 18v-2.25z" />
    </svg>
  )
}

const sizeClasses = {
  xs: 'w-6 h-6 text-[10px]',
  sm: 'w-8 h-8 text-xs',
  md: 'w-10 h-10 text-sm',
  lg: 'w-12 h-12 text-base'
}

export function UserMenuDropdown({
  avatarUrl,
  initials,
  userName,
  isAdmin = false,
  profilePath = '/profile/registration/edit',
  adminPath = '/admin',
  signOutPath = '/users/sign_out',
  csrfToken,
  size = 'sm'
}) {
  const [isOpen, setIsOpen] = useState(false)
  const [imageError, setImageError] = useState(false)
  const [navItems, setNavItems] = useState([])
  const dropdownRef = useRef(null)

  // Read nav items from single source of truth (data-app attribute)
  useEffect(() => {
    const appData = window.App?.data?.()
    if (appData?.navItems) {
      setNavItems(appData.navItems)
    }
  }, [])

  useEffect(() => {
    const handleClickOutside = (e) => {
      if (dropdownRef.current && !dropdownRef.current.contains(e.target)) {
        setIsOpen(false)
      }
    }

    document.addEventListener('mousedown', handleClickOutside)
    return () => document.removeEventListener('mousedown', handleClickOutside)
  }, [])

  const handleSignOut = () => {
    const token = csrfToken || document.querySelector('meta[name="csrf-token"]')?.getAttribute('content') || ''

    const form = document.createElement('form')
    form.method = 'POST'
    form.action = signOutPath
    form.style.display = 'none'

    const methodInput = document.createElement('input')
    methodInput.type = 'hidden'
    methodInput.name = '_method'
    methodInput.value = 'delete'
    form.appendChild(methodInput)

    const tokenInput = document.createElement('input')
    tokenInput.type = 'hidden'
    tokenInput.name = 'authenticity_token'
    tokenInput.value = token
    form.appendChild(tokenInput)

    document.body.appendChild(form)
    form.submit()
  }

  const initialsContent = (
    <span className={`${sizeClasses[size]} rounded-full flex items-center justify-center font-semibold user-avatar-initials`}>
      {initials}
    </span>
  )

  const avatarContent = avatarUrl && !imageError ? (
    <img
      src={avatarUrl}
      alt={`${userName || 'User'}'s avatar`}
      className={`${sizeClasses[size]} rounded-full object-cover`}
      onError={() => setImageError(true)}
    />
  ) : initialsContent

  return (
    <div ref={dropdownRef} className="relative">
      <button
        type="button"
        onClick={() => setIsOpen(!isOpen)}
        className="flex items-center cursor-pointer hover:opacity-80 transition rounded-full focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-ring"
        aria-label="User menu"
        title={userName || 'User menu'}
      >
        {avatarContent}
      </button>

      {isOpen && (
        <div
          className="absolute right-0 top-full mt-2 w-48 rounded-lg shadow-xl border py-1"
          style={{
            backgroundColor: 'var(--vibes-surface-0)',
            borderColor: 'var(--color-border)',
            zIndex: 9999
          }}
        >
          <a
            href={profilePath}
            className="w-full flex items-center gap-3 px-4 py-2.5 text-sm text-left transition"
            style={{ color: 'var(--color-foreground)' }}
            onMouseEnter={(e) => {
              e.currentTarget.style.backgroundColor = 'var(--vibes-surface-2)'
            }}
            onMouseLeave={(e) => {
              e.currentTarget.style.backgroundColor = 'transparent'
            }}
          >
            <svg className="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24" strokeWidth="1.5">
              <path strokeLinecap="round" strokeLinejoin="round" d="M15.75 6a3.75 3.75 0 11-7.5 0 3.75 3.75 0 017.5 0zM4.501 20.118a7.5 7.5 0 0114.998 0A17.933 17.933 0 0112 21.75c-2.676 0-5.216-.584-7.499-1.632z" />
            </svg>
            <span>Profile</span>
          </a>

          {/* Dynamic nav items from app config (Chat, Workspaces, etc.) */}
          {navItems.length > 0 && (
            <>
              <div className="h-px mx-2" style={{ backgroundColor: 'var(--color-border)' }} />
              {navItems.map((item) => (
                <a
                  key={item.key}
                  href={item.path}
                  className="w-full flex items-center gap-3 px-4 py-2.5 text-sm text-left transition"
                  style={{ color: 'var(--color-foreground)' }}
                  onMouseEnter={(e) => {
                    e.currentTarget.style.backgroundColor = 'var(--vibes-surface-2)'
                  }}
                  onMouseLeave={(e) => {
                    e.currentTarget.style.backgroundColor = 'transparent'
                  }}
                >
                  {NavIcons[item.icon] || null}
                  <span>{item.label}</span>
                </a>
              ))}
            </>
          )}

          {isAdmin && (
            <>
              <div className="h-px mx-2" style={{ backgroundColor: 'var(--color-border)' }} />
              <a
                href={adminPath}
                className="w-full flex items-center gap-3 px-4 py-2.5 text-sm text-left transition"
                style={{ color: 'var(--color-foreground)' }}
                onMouseEnter={(e) => {
                  e.currentTarget.style.backgroundColor = 'var(--vibes-surface-2)'
                }}
                onMouseLeave={(e) => {
                  e.currentTarget.style.backgroundColor = 'transparent'
                }}
              >
                <svg className="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24" strokeWidth="1.5">
                  <path strokeLinecap="round" strokeLinejoin="round" d="M9.594 3.94c.09-.542.56-.94 1.11-.94h2.593c.55 0 1.02.398 1.11.94l.213 1.281c.063.374.313.686.645.87.074.04.147.083.22.127.324.196.72.257 1.075.124l1.217-.456a1.125 1.125 0 011.37.49l1.296 2.247a1.125 1.125 0 01-.26 1.431l-1.003.827c-.293.24-.438.613-.431.992a6.759 6.759 0 010 .255c-.007.378.138.75.43.99l1.005.828c.424.35.534.954.26 1.43l-1.298 2.247a1.125 1.125 0 01-1.369.491l-1.217-.456c-.355-.133-.75-.072-1.076.124a6.57 6.57 0 01-.22.128c-.331.183-.581.495-.644.869l-.213 1.28c-.09.543-.56.941-1.11.941h-2.594c-.55 0-1.02-.398-1.11-.94l-.213-1.281c-.062-.374-.312-.686-.644-.87a6.52 6.52 0 01-.22-.127c-.325-.196-.72-.257-1.076-.124l-1.217.456a1.125 1.125 0 01-1.369-.49l-1.297-2.247a1.125 1.125 0 01.26-1.431l1.004-.827c.292-.24.437-.613.43-.992a6.932 6.932 0 010-.255c.007-.378-.138-.75-.43-.99l-1.004-.828a1.125 1.125 0 01-.26-1.43l1.297-2.247a1.125 1.125 0 011.37-.491l1.216.456c.356.133.751.072 1.076-.124.072-.044.146-.087.22-.128.332-.183.582-.495.644-.869l.214-1.281z" />
                  <path strokeLinecap="round" strokeLinejoin="round" d="M15 12a3 3 0 11-6 0 3 3 0 016 0z" />
                </svg>
                <span>Admin</span>
              </a>
            </>
          )}

          <div className="h-px mx-2" style={{ backgroundColor: 'var(--color-border)' }} />

          <button
            type="button"
            onClick={handleSignOut}
            className="w-full flex items-center gap-3 px-4 py-2.5 text-sm text-left transition cursor-pointer"
            style={{ color: 'var(--color-destructive)' }}
            onMouseEnter={(e) => {
              e.currentTarget.style.backgroundColor = 'color-mix(in srgb, var(--color-destructive) 10%, transparent)'
            }}
            onMouseLeave={(e) => {
              e.currentTarget.style.backgroundColor = 'transparent'
            }}
          >
            <svg className="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24" strokeWidth="1.5">
              <path strokeLinecap="round" strokeLinejoin="round" d="M15.75 9V5.25A2.25 2.25 0 0013.5 3h-6a2.25 2.25 0 00-2.25 2.25v13.5A2.25 2.25 0 007.5 21h6a2.25 2.25 0 002.25-2.25V15m3 0l3-3m0 0l-3-3m3 3H9" />
            </svg>
            <span>Sign out</span>
          </button>
        </div>
      )}
    </div>
  )
}

export default UserMenuDropdown

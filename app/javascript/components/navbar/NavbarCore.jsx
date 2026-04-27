/**
 * NavbarCore - Navbar UI component for Inertia pages
 *
 * Used by Navbar.jsx (Inertia pages).
 * ERB pages use _navbar.html.erb with small React islands instead.
 */
import { useState, useEffect } from 'react'
import { UserMenuDropdown } from '../user'
import { NotificationBellWithDropdown } from '../notifications'

export default function NavbarCore({
  user,
  appData,
  unreadNotificationsCount = 0,
  isLoading = false,
  showBackArrow = false,
  backPath = '/'
}) {
  const [isDark, setIsDark] = useState(false)

  useEffect(() => {
    if (typeof window === 'undefined') return
    const stored = localStorage.getItem('theme')
    const shouldBeDark = stored === 'dark'
    setIsDark(shouldBeDark)
    document.documentElement.classList.toggle('dark', shouldBeDark)
  }, [])

  const toggleTheme = () => {
    const newIsDark = !isDark
    setIsDark(newIsDark)
    document.documentElement.classList.toggle('dark', newIsDark)
    localStorage.setItem('theme', newIsDark ? 'dark' : 'light')
  }

  const getUserInitials = (user) => {
    return user.firstName?.charAt(0)?.toUpperCase() ||
           user.email?.charAt(0)?.toUpperCase() ||
           '?'
  }

  const getUserName = (user) => {
    const name = `${user.firstName || ''} ${user.lastName || ''}`.trim()
    return name || undefined
  }

  // Don't render interactive elements while loading
  if (isLoading) {
    return (
      <nav className="w-full px-4 sm:px-6 py-3 bg-surface-0 border-border" role="banner">
        <div className="flex items-center justify-between w-full">
          <div className="flex items-center">
            {showBackArrow ? (
              <a href={backPath} className="flex items-center gap-3 group">
                <svg xmlns="http://www.w3.org/2000/svg" className="h-5 w-5 text-foreground opacity-60" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round">
                  <path d="m15 18-6-6 6-6"/>
                </svg>
              </a>
            ) : (
              <a href="/" className="flex items-center gap-3 group">
                <div className="w-9 h-9 rounded-xl bg-primary flex items-center justify-center shadow-sm group-hover:shadow transition-shadow">
                  <span className="text-sm font-semibold text-primary-foreground tracking-tight">
                    {appData?.name?.charAt(0)?.toUpperCase() || ''}
                  </span>
                </div>
                <span className="text-xl font-semibold text-foreground group-hover:text-primary transition-colors">
                  {appData?.name || ''}
                </span>
              </a>
            )}
          </div>
          <div className="flex items-center gap-4">
            {/* Loading placeholder */}
            <div className="w-8 h-8 rounded-full bg-surface-2 animate-pulse" />
          </div>
        </div>
      </nav>
    )
  }

  return (
    <nav className="w-full px-4 sm:px-6 py-3 bg-surface-0 border-border" role="banner">
      <div className="flex items-center justify-between w-full">
        <div className="flex items-center">
          {showBackArrow ? (
            <a href={backPath} className="flex items-center gap-3 group">
              <svg xmlns="http://www.w3.org/2000/svg" className="h-5 w-5 text-foreground opacity-60 group-hover:opacity-100 transition-opacity" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round">
                <path d="m15 18-6-6 6-6"/>
              </svg>
            </a>
          ) : (
            <a href="/" className="flex items-center gap-3 group">
              <div className="w-9 h-9 rounded-xl bg-primary flex items-center justify-center shadow-sm group-hover:shadow transition-shadow">
                <span className="text-sm font-semibold text-primary-foreground tracking-tight">
                  {appData?.name?.charAt(0)?.toUpperCase() || ''}
                </span>
              </div>
              <span className="text-xl font-semibold text-foreground group-hover:text-primary transition-colors">
                {appData?.name || ''}
              </span>
            </a>
          )}
        </div>

        <div className="flex items-center gap-4">
          {/* Theme toggle */}
          <button
            onClick={toggleTheme}
            className="p-2 rounded-lg bg-surface-1 hover:bg-surface-2 text-foreground transition-colors cursor-pointer"
            aria-label="Toggle theme"
          >
            {isDark ? (
              <svg xmlns="http://www.w3.org/2000/svg" className="h-5 w-5" viewBox="0 0 20 20" fill="currentColor">
                <path fillRule="evenodd" d="M10 2a1 1 0 011 1v1a1 1 0 11-2 0V3a1 1 0 011-1zm4 8a4 4 0 11-8 0 4 4 0 018 0zm-.464 4.95l.707.707a1 1 0 001.414-1.414l-.707-.707a1 1 0 00-1.414 1.414zm2.12-10.607a1 1 0 010 1.414l-.706.707a1 1 0 11-1.414-1.414l.707-.707a1 1 0 011.414 0zM17 11a1 1 0 100-2h-1a1 1 0 100 2h1zm-7 4a1 1 0 011 1v1a1 1 0 11-2 0v-1a1 1 0 011-1zM5.05 6.464A1 1 0 106.465 5.05l-.708-.707a1 1 0 00-1.414 1.414l.707.707zm1.414 8.486l-.707.707a1 1 0 01-1.414-1.414l.707-.707a1 1 0 011.414 1.414zM4 11a1 1 0 100-2H3a1 1 0 000 2h1z" clipRule="evenodd" />
              </svg>
            ) : (
              <svg xmlns="http://www.w3.org/2000/svg" className="h-5 w-5" viewBox="0 0 20 20" fill="currentColor">
                <path d="M17.293 13.293A8 8 0 016.707 2.707a8.001 8.001 0 1010.586 10.586z" />
              </svg>
            )}
          </button>

          {/* Notifications */}
          {user && (
            <NotificationBellWithDropdown initialUnreadCount={unreadNotificationsCount} />
          )}

          {/* User menu or auth links */}
          {user ? (
            <UserMenuDropdown
              avatarUrl={user.avatarUrl}
              initials={getUserInitials(user)}
              userName={getUserName(user)}
              isAdmin={user.admin}
              profilePath="/profile/registration/edit"
              adminPath="/admin"
              signOutPath="/users/sign_out"
              size="sm"
            />
          ) : (
            <>
              <a href="/users/sign_in" className="text-sm font-medium text-muted-foreground hover:text-foreground transition-colors">
                Sign In
              </a>
              <a href="/users/sign_up" className="text-sm font-medium px-3 py-1.5 rounded-md border border-border text-foreground hover:border-primary hover:text-primary transition-colors">
                Sign Up
              </a>
            </>
          )}
        </div>
      </div>
    </nav>
  )
}

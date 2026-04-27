/**
 * SettingsSidebarCore - Settings sidebar navigation UI
 *
 * Core implementation used by:
 * - SettingsSidebarIsland (ERB pages via islandjs-rails)
 * - SettingsSidebar wrapper (Inertia pages)
 *
 * Reads navigation items from window.App.data().settingsNavItems
 * and user data from window.Auth.user()
 */
import { useState, useEffect } from 'react'

export function SettingsSidebarCore({
  navItems: propNavItems,
  currentPath: propCurrentPath
} = {}) {
  const [navItems, setNavItems] = useState(propNavItems || [])
  const [currentPath, setCurrentPath] = useState(propCurrentPath || '')
  const [isOpen, setIsOpen] = useState(false)
  const [user, setUser] = useState(null)
  const [showWorkspaces, setShowWorkspaces] = useState(false)

  useEffect(() => {
    // Get nav items from window.App if not passed as props
    if (!propNavItems?.length) {
      const appData = window.App?.data?.()
      if (appData?.settingsNavItems) {
        setNavItems(appData.settingsNavItems)
      }
    }
    // Get current path if not passed
    if (!propCurrentPath) {
      setCurrentPath(window.location.pathname)
    }
    // Get user data from window.Auth
    const authUser = window.Auth?.user?.()
    if (authUser && (authUser.id || authUser.email)) {
      setUser(authUser)
      setShowWorkspaces(!!authUser.currentWorkspace)
    }
  }, [propNavItems, propCurrentPath])

  const isActive = (item) => {
    if (item.startsWithPath) {
      return currentPath.startsWith(item.startsWithPath)
    }
    return currentPath === item.path
  }

  const getCurrentLabel = () => {
    const active = navItems.find(item => isActive(item))
    return active?.label || navItems[0]?.label || 'Settings'
  }

  // Derive user display values
  const userName = user?.firstName && user?.lastName
    ? `${user.firstName} ${user.lastName}`
    : user?.email || ''
  const userInitials = user?.firstName?.[0]?.toUpperCase() || user?.email?.[0]?.toUpperCase() || '?'
  const workspaceName = user?.currentWorkspace?.name || ''

  const activeClass = 'bg-surface-2 text-foreground'
  const inactiveClass = 'text-muted-foreground hover:bg-surface-1 hover:text-foreground'

  return (
    <>
      {/* Mobile: Dropdown Navigation */}
      <div className="lg:hidden -mx-4 sm:-mx-6">
        <button
          onClick={() => setIsOpen(!isOpen)}
          type="button"
          className={`w-full flex items-center justify-between px-4 sm:px-6 py-3 transition-colors cursor-pointer border-b ${
            isOpen ? 'bg-surface-1 border-border' : 'border-transparent hover:bg-surface-1'
          }`}
        >
          <div className="flex flex-col items-start">
            <span className="text-[10px] uppercase tracking-wider text-muted-foreground font-medium">
              Settings
            </span>
            <span className="text-2xl font-bold text-foreground -mt-0.5">
              {getCurrentLabel()}
            </span>
          </div>
          <svg
            xmlns="http://www.w3.org/2000/svg"
            viewBox="0 0 20 20"
            fill="currentColor"
            className={`w-5 h-5 text-muted-foreground transition-transform duration-200 flex-shrink-0 ${
              isOpen ? 'rotate-180' : ''
            }`}
          >
            <path
              fillRule="evenodd"
              d="M5.22 8.22a.75.75 0 0 1 1.06 0L10 11.94l3.72-3.72a.75.75 0 1 1 1.06 1.06l-4.25 4.25a.75.75 0 0 1-1.06 0L5.22 9.28a.75.75 0 0 1 0-1.06Z"
              clipRule="evenodd"
            />
          </svg>
        </button>

        {/* Dropdown panel */}
        {isOpen && (
          <nav className="w-full bg-surface-1 border-b border-border overflow-hidden">
            {/* User/Workspace info */}
            {user && (
              <div className="px-4 sm:px-6 py-3 border-b border-border">
                <div className="flex items-center gap-3">
                  <a
                    href={navItems.find(i => i.key === 'profile')?.path || '/profile'}
                    className="user-avatar-initials w-10 h-10 rounded-full flex items-center justify-center text-sm font-semibold hover:opacity-90 transition flex-shrink-0"
                  >
                    {userInitials}
                  </a>
                  <div className="flex-1 min-w-0">
                    <a
                      href={navItems.find(i => i.key === 'profile')?.path || '/profile'}
                      className="text-sm font-medium hover:opacity-80 transition block truncate text-foreground"
                    >
                      {userName}
                    </a>
                    {showWorkspaces && (
                      <a
                        href="/workspaces"
                        className="text-xs text-muted-foreground hover:opacity-80 transition block truncate mt-0.5"
                      >
                        {workspaceName}
                      </a>
                    )}
                  </div>
                </div>
              </div>
            )}

            {/* Navigation items */}
            <div className="px-2 sm:px-4 py-2 space-y-0.5">
              {navItems.map(item => (
                <a
                  key={item.key}
                  href={item.path}
                  className={`block no-underline px-4 py-3 rounded-md text-sm font-medium transition-colors ${
                    isActive(item) ? activeClass : inactiveClass
                  }`}
                  onClick={() => setIsOpen(false)}
                >
                  {item.label}
                </a>
              ))}
            </div>
          </nav>
        )}
      </div>

      {/* Desktop: Vertical Navigation */}
      <nav className="hidden lg:block space-y-1">
        {navItems.map(item => (
          <a
            key={item.key}
            href={item.path}
            className={`block no-underline px-4 py-3 rounded-lg text-sm font-medium transition-all ${
              isActive(item) ? activeClass : inactiveClass
            }`}
          >
            {item.label}
          </a>
        ))}
      </nav>
    </>
  )
}

export default SettingsSidebarCore

import { useState, useEffect } from 'react'
import { Head } from '@inertiajs/react'
import Navbar from '../pages/components/Navbar'
import { SettingsSidebar } from '../components/settings'

/**
 * SettingsLayout - Layout for Inertia pages with settings sidebar
 *
 * Matches the ERB settings layout structure exactly:
 * - Fixed sidebar flush to left edge
 * - Subtle right border (v-divider style, 10% opacity)
 * - User/workspace footer in sidebar
 * - Spacer div to offset main content
 */

export default function SettingsLayout({
  children,
  title,
  hideSettingsSidebar = false,
  showBackArrow = true
}) {
  const [user, setUser] = useState(null)
  const [appData, setAppData] = useState(null)
  const [isLoading, setIsLoading] = useState(true)

  useEffect(() => {
    if (typeof window === 'undefined') return

    // Initialize theme on mount
    const stored = localStorage.getItem('theme')
    const shouldBeDark = stored === 'dark'
    document.documentElement.classList.toggle('dark', shouldBeDark)

    // Get user data
    if (window.Auth?.user) {
      const currentUser = window.Auth.user()
      if (currentUser && (currentUser.id || currentUser.email)) {
        setUser(currentUser)
      }
    }

    // Get app data
    const appDataValue = window.App?.data()
    if (appDataValue) {
      setAppData(appDataValue)
    }

    setIsLoading(false)
  }, [])

  const pageTitle = title
    ? `${title} - ${appData?.name || 'App'}`
    : appData?.name || 'App'

  // Footer user info (still needed for the footer section)
  const userName = user?.firstName && user?.lastName
    ? `${user.firstName} ${user.lastName}`
    : user?.email || ''

  const userInitials = user?.firstName?.[0]?.toUpperCase() || user?.email?.[0]?.toUpperCase() || '?'

  const workspaceName = user?.currentWorkspace?.name || ''
  const showWorkspaces = !!user?.currentWorkspace

  return (
    <div className="min-h-screen flex flex-col">
      <Head title={pageTitle} />

      {/* Styles matching ERB exactly */}
      <style>{`
        .v-divider { border-color: color-mix(in srgb, var(--color-surface-3) 10%, transparent); }
        .user-workspace-footer { background-color: var(--color-surface-0); }
        .user-ws-name { color: var(--color-foreground); }
        .user-ws-wsname { color: var(--color-muted-foreground); font-size: 0.7rem; }
      `}</style>

      <div className="min-h-screen bg-background text-foreground">
        <Navbar
          user={user}
          appData={appData}
          isLoading={isLoading}
          showBackArrow={showBackArrow}
        />

        {hideSettingsSidebar ? (
          <main className="px-4 py-6 sm:px-8 sm:py-10 lg:px-16 lg:py-12">
            {children}
          </main>
        ) : (
          <div className="flex flex-col lg:flex-row min-h-screen">
            {/* Fixed sidebar - matches ERB _settings_sidebar.html.erb */}
            <aside className="lg:w-64 lg:border-r v-divider lg:flex lg:flex-col lg:fixed lg:top-[72px] lg:bottom-0 lg:left-0 bg-background">
              <div className="lg:flex-1 lg:min-h-0 lg:overflow-y-auto px-4 py-6 sm:p-6 lg:p-6">
                {/* SettingsSidebar reads nav items from window.App.data() */}
                <SettingsSidebar />
              </div>

              {/* Footer - matches ERB _user_workspace_footer.html.erb exactly */}
              {user && (
                <div className="hidden lg:block lg:flex-shrink-0">
                  <div className="user-workspace-footer p-3" style={{ borderTop: '1px solid var(--color-border)' }}>
                    <div className="flex items-center gap-2">
                      <a
                        href="/profile/registration/edit"
                        className="user-avatar-initials w-8 h-8 rounded-full flex items-center justify-center text-xs font-semibold hover:opacity-90 transition flex-shrink-0"
                      >
                        {userInitials}
                      </a>
                      <div className="flex-1 min-w-0">
                        <a
                          href="/profile/registration/edit"
                          className="user-ws-name text-sm font-medium hover:opacity-80 transition block truncate"
                        >
                          {userName}
                        </a>
                        <a
                          href={showWorkspaces ? '/workspaces' : '/'}
                          className="user-ws-wsname hover:opacity-80 transition block truncate mt-0.5"
                        >
                          {showWorkspaces ? workspaceName : appData?.name || ''}
                        </a>
                      </div>
                    </div>
                  </div>
                </div>
              )}
            </aside>

            {/* Spacer for fixed sidebar on desktop */}
            <div className="hidden lg:block lg:w-64 flex-shrink-0" />

            {/* Main content */}
            <main className="flex-1 px-4 py-6 sm:px-8 sm:py-10 lg:px-16 lg:py-12">
              {children}
            </main>
          </div>
        )}
      </div>
    </div>
  )
}

/**
 * Inertia Navbar - Wrapper for Inertia SPA pages
 *
 * Receives props from Inertia page and passes to NavbarCore.
 * NavbarCore is the single source of truth for navbar UI.
 */
import NavbarCore from '../../components/navbar/NavbarCore'

export default function Navbar({ user, appData, isLoading, unreadNotificationsCount = 0, showBackArrow = false }) {
  // Transform User type to NavbarUser (they're compatible)
  const navbarUser = user ? {
    id: user.id,
    email: user.email,
    firstName: user.firstName,
    lastName: user.lastName,
    avatarUrl: user.avatarUrl,
    admin: user.admin
  } : null

  return (
    <NavbarCore
      user={navbarUser}
      appData={appData}
      unreadNotificationsCount={unreadNotificationsCount}
      isLoading={isLoading}
      showBackArrow={showBackArrow}
    />
  )
}

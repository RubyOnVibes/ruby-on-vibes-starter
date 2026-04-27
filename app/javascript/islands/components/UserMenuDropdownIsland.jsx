/**
 * UserMenuDropdownIsland - Avatar dropdown menu for user actions
 * 
 * Used in ERB layouts to provide consistent user menu across all pages.
 * Props are passed via data-initial-state attribute.
 */

import { useTurboProps } from '../utils/turbo'
import { UserMenuDropdown } from '../../components/user'

export default function UserMenuDropdownIsland({ containerId }) {
  const initialProps = useTurboProps(containerId)
  
  const {
    avatarUrl,
    initials,
    userName,
    isAdmin,
    profilePath,
    adminPath,
    signOutPath,
    size
  } = initialProps

  return (
    <UserMenuDropdown
      avatarUrl={avatarUrl}
      initials={initials || '?'}
      userName={userName}
      isAdmin={isAdmin}
      profilePath={profilePath}
      adminPath={adminPath}
      signOutPath={signOutPath}
      size={size || 'sm'}
    />
  )
}

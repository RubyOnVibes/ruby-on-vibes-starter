/**
 * SettingsSidebar - Inertia wrapper for settings sidebar navigation
 *
 * Wrapper for Inertia SPA pages that passes props to SettingsSidebarCore.
 * SettingsSidebarCore is the single source of truth for sidebar UI.
 */
import SettingsSidebarCore from './SettingsSidebarCore'

export function SettingsSidebar({ navItems, currentPath } = {}) {
  return (
    <SettingsSidebarCore
      navItems={navItems}
      currentPath={currentPath}
    />
  )
}

export default SettingsSidebar

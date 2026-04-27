/**
 * SettingsSidebarIsland - Settings navigation for ERB pages
 *
 * Used in ERB layouts (profile, password, payments pages).
 * No props needed - reads from window.App.data() and window.Auth.user()
 */

import { SettingsSidebarCore } from '../../components/settings'

export default function SettingsSidebarIsland() {
  // SettingsSidebarCore reads all data from window globals
  return <SettingsSidebarCore />
}

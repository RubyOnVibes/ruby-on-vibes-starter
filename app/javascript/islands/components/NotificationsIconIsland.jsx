/**
 * NotificationsIconIsland - Standalone notification bell for ERB pages
 *
 * Wraps the shared NotificationBellWithDropdown component for use as an island.
 * Used when navbar is NOT using NavbarIsland (e.g., custom layouts).
 */
import { NotificationBellWithDropdown } from '../../components/notifications'

export default function NotificationsIconIsland() {
  return <NotificationBellWithDropdown initialUnreadCount={0} />
}

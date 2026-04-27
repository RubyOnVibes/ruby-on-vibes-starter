import SettingsLayout from '../layouts/SettingsLayout'

/**
 * DashboardPage - Interactive dashboard using Inertia/React
 *
 * This page is for complex interactive features that benefit from React:
 * - Real-time data updates
 * - Complex state management
 * - Rich UI interactions (drag-and-drop, etc.)
 *
 * Uses SettingsLayout for consistent settings navigation.
 * For static pages, use ERB (faster, no build step).
 */
export default function DashboardPage() {
  return (
    <SettingsLayout title="Dashboard">
      <div className="mb-8">
        <h1 className="text-2xl font-bold text-foreground">Dashboard</h1>
        <p className="text-muted-foreground mt-1">
          Your command center for quick insights and actions.
        </p>
      </div>

      {/* Dashboard Cards */}
      <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6">
        {/* Card 1 */}
        <div className="p-6 bg-surface-0 rounded-xl border border-border">
          <div className="flex items-center justify-between mb-4">
            <h3 className="text-lg font-semibold text-foreground">Overview</h3>
            <span className="text-2xl">📊</span>
          </div>
          <p className="text-muted-foreground text-sm">
            This is your Inertia/React dashboard. Add interactive widgets, charts, and real-time features here.
          </p>
        </div>

        {/* Card 2 */}
        <div className="p-6 bg-surface-0 rounded-xl border border-border">
          <div className="flex items-center justify-between mb-4">
            <h3 className="text-lg font-semibold text-foreground">Quick Actions</h3>
            <span className="text-2xl">⚡</span>
          </div>
          <div className="space-y-2">
            <button className="w-full px-4 py-2 text-sm font-medium text-foreground bg-surface-1 hover:bg-surface-2 rounded-lg transition-colors text-left">
              Create New Item
            </button>
            <button className="w-full px-4 py-2 text-sm font-medium text-foreground bg-surface-1 hover:bg-surface-2 rounded-lg transition-colors text-left">
              View Reports
            </button>
          </div>
        </div>

        {/* Card 3 */}
        <div className="p-6 bg-surface-0 rounded-xl border border-border">
          <div className="flex items-center justify-between mb-4">
            <h3 className="text-lg font-semibold text-foreground">Activity</h3>
            <span className="text-2xl">🔔</span>
          </div>
          <p className="text-muted-foreground text-sm">
            Recent activity will appear here. Connect to your data source to display real updates.
          </p>
        </div>
      </div>

      {/* Info Banner */}
      <div className="mt-8 p-4 bg-muted border border-border rounded-lg">
        <p className="text-sm text-muted-foreground">
          <strong>Pro tip:</strong> Use ERB for static pages (faster, no build step) and Inertia/React for interactive features like this dashboard.
        </p>
      </div>
    </SettingsLayout>
  )
}

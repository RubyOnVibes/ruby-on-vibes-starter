import React, { useState } from 'react'
import { ConfirmDialog } from './ConfirmDialog'

/**
 * AgentTaskPanel - Compact collapsible panel showing agent task status
 *
 * Renders above the chat input. Both active and terminal tasks are
 * collapsed by default into summary lines, expandable to see details.
 *
 * When no tasks exist, renders nothing.
 */
export default function AgentTaskPanel({ tasks, onCancel, onDismiss }) {
  const [showActive, setShowActive] = useState(false)
  const [showHistory, setShowHistory] = useState(false)
  const [showClearConfirm, setShowClearConfirm] = useState(false)

  if (!tasks || tasks.length === 0) return null

  const activeTasks = tasks.filter(t => t.status === 'pending' || t.status === 'running')
  const terminalTasks = tasks.filter(t => t.status === 'completed' || t.status === 'failed' || t.status === 'cancelled')

  if (activeTasks.length === 0 && terminalTasks.length === 0) return null

  return (
    <div className="flex-shrink-0 w-full px-4 sm:px-6 pt-2">
      <div className="max-w-3xl mx-auto">
        <div
          className="rounded-xl border text-xs"
          style={{
            backgroundColor: 'var(--color-surface-1)',
            borderColor: 'var(--color-border)'
          }}
        >
          {/* Active tasks section */}
          {activeTasks.length > 0 && (
            <div>
              <button
                type="button"
                onClick={() => setShowActive(!showActive)}
                className="w-full flex items-center justify-between px-3 py-2 font-medium transition-colors hover:opacity-80"
                style={{ color: 'var(--color-foreground)' }}
              >
                <span className="flex items-center gap-2">
                  <PulsingDot />
                  <span>
                    {activeTasks.length} task{activeTasks.length > 1 ? 's' : ''} running
                  </span>
                  {!showActive && activeTasks.length === 1 && activeTasks[0].progressText && (
                    <span className="font-normal" style={{ color: 'var(--color-muted-foreground)' }}>
                      — {activeTasks[0].progressText}
                    </span>
                  )}
                </span>
                <ChevronIcon expanded={showActive} />
              </button>

              {showActive && (
                <div className="px-3 pb-2 space-y-1.5">
                  {activeTasks.map(task => (
                    <ActiveTaskRow key={task.id} task={task} onCancel={onCancel} />
                  ))}
                </div>
              )}
            </div>
          )}

          {/* Terminal tasks section */}
          {terminalTasks.length > 0 && (
            <div className={activeTasks.length > 0 ? 'border-t' : ''} style={{ borderColor: 'var(--color-border)' }}>
              <div className="flex items-center px-3 py-2" style={{ color: 'var(--color-muted-foreground)' }}>
                <button
                  type="button"
                  onClick={() => setShowHistory(!showHistory)}
                  className="flex-1 flex items-center gap-2 font-medium transition-colors hover:opacity-80"
                >
                  <span style={{ color: 'var(--color-foreground)' }}>
                    <ChevronIcon expanded={showHistory} size={16} />
                  </span>
                  <span>{terminalTasksSummary(terminalTasks)}</span>
                </button>
                {showHistory && onDismiss && (
                  <button
                    type="button"
                    onClick={(e) => {
                      e.stopPropagation()
                      setShowClearConfirm(true)
                    }}
                    className="p-1 rounded transition-colors hover:opacity-80"
                    title="Clear tasks from this chat"
                  >
                    <DismissIcon />
                  </button>
                )}
              </div>

              {showHistory && (
                <div className="px-3 pb-2 space-y-1">
                  {terminalTasks.map(task => (
                    <TerminalTaskRow key={task.id} task={task} />
                  ))}
                </div>
              )}
            </div>
          )}

          <ConfirmDialog
            isOpen={showClearConfirm}
            onClose={() => setShowClearConfirm(false)}
            onConfirm={() => {
              onDismiss?.()
              setShowHistory(false)
            }}
            title="Clear agent tasks?"
            message="Completed tasks will be hidden from this chat. You can still view all tasks in Settings > Agent Tasks."
            confirmText="Clear"
            cancelText="Keep"
          />
        </div>
      </div>
    </div>
  )
}

// ── Active task row (compact: single line with inline progress) ──

function ActiveTaskRow({ task, onCancel }) {
  const isPending = task.status === 'pending'
  const progress = task.progress || 0

  return (
    <div
      className="rounded-lg px-2.5 py-2"
      style={{
        backgroundColor: 'var(--color-surface-2)',
        color: 'var(--color-foreground)'
      }}
    >
      {/* Top line: kind, attempts, progress %, cancel */}
      <div className="flex items-center gap-2">
        <span className="font-medium truncate">{humanizeKind(task.kind)}</span>
        {task.attempts > 1 && (
          <span className="opacity-60">attempt {task.attempts}</span>
        )}
        <CopyableId id={task.id} />
        <span className="flex-1" />
        {!isPending && (
          <span className="tabular-nums" style={{ color: 'var(--color-muted-foreground)' }}>
            {progress}%
          </span>
        )}
        <button
          type="button"
          onClick={() => onCancel?.(task.id)}
          className="px-1.5 py-0.5 rounded transition-colors hover:opacity-80"
          style={{
            color: 'var(--color-muted-foreground)',
            backgroundColor: 'var(--color-surface-1)'
          }}
        >
          Cancel
        </button>
      </div>

      {/* Progress bar */}
      <div
        className="w-full h-1 rounded-full overflow-hidden mt-1.5"
        style={{ backgroundColor: 'var(--color-border)' }}
      >
        {isPending ? (
          <div
            className="h-full rounded-full animate-pulse"
            style={{ width: '30%', backgroundColor: 'var(--color-muted-foreground)' }}
          />
        ) : (
          <div
            className="h-full rounded-full transition-all duration-500"
            style={{
              width: `${Math.max(progress, 2)}%`,
              backgroundColor: 'var(--color-primary)'
            }}
          />
        )}
      </div>

      {/* Status text */}
      <div className="mt-1" style={{ color: 'var(--color-muted-foreground)' }}>
        {task.progressText || (isPending ? 'Waiting to start...' : 'Working...')}
      </div>
    </div>
  )
}

// ── Terminal task row (compact single line) ──

function TerminalTaskRow({ task }) {
  return (
    <div
      className="flex items-center gap-2 rounded px-2.5 py-1.5"
      style={{
        backgroundColor: 'var(--color-surface-2)',
        color: 'var(--color-muted-foreground)'
      }}
    >
      <StatusIcon status={task.status} />
      <span className="truncate">{humanizeKind(task.kind)}</span>
      {task.attempts > 1 && (
        <span className="opacity-60">{task.attempts} attempts</span>
      )}
      <CopyableId id={task.id} />
      <span className="flex-1" />
      {task.completedAt && (
        <span className="flex-shrink-0">{formatRelativeTime(task.completedAt)}</span>
      )}
    </div>
  )
}

// ── Icons ──

function StatusIcon({ status }) {
  if (status === 'completed') {
    return (
      <svg className="w-3.5 h-3.5 flex-shrink-0" viewBox="0 0 24 24" fill="none" stroke="var(--color-success, #22c55e)" strokeWidth="2.5">
        <path strokeLinecap="round" strokeLinejoin="round" d="M5 13l4 4L19 7" />
      </svg>
    )
  }
  if (status === 'failed') {
    return (
      <svg className="w-3.5 h-3.5 flex-shrink-0" viewBox="0 0 24 24" fill="none" stroke="var(--color-danger, #ef4444)" strokeWidth="2.5">
        <path strokeLinecap="round" strokeLinejoin="round" d="M6 18L18 6M6 6l12 12" />
      </svg>
    )
  }
  // cancelled
  return (
    <svg className="w-3.5 h-3.5 flex-shrink-0" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2">
      <circle cx="12" cy="12" r="10" />
      <path strokeLinecap="round" d="M8 12h8" />
    </svg>
  )
}

function CopyableId({ id }) {
  const [copied, setCopied] = useState(false)

  const handleCopy = (e) => {
    e.stopPropagation()
    navigator.clipboard?.writeText(id).then(() => {
      setCopied(true)
      setTimeout(() => setCopied(false), 1500)
    })
  }

  return (
    <button
      type="button"
      onClick={handleCopy}
      className="font-mono opacity-50 hover:opacity-100 transition-opacity truncate"
      title={`Copy ${id}`}
      style={{ fontSize: '0.6rem', maxWidth: '10rem' }}
    >
      {copied ? 'copied!' : id}
    </button>
  )
}

function PulsingDot() {
  return (
    <span className="relative flex h-2 w-2 flex-shrink-0">
      <span
        className="animate-ping absolute inline-flex h-full w-full rounded-full opacity-75"
        style={{ backgroundColor: 'var(--color-primary)' }}
      />
      <span
        className="relative inline-flex rounded-full h-2 w-2"
        style={{ backgroundColor: 'var(--color-primary)' }}
      />
    </span>
  )
}

function DismissIcon() {
  return (
    <svg className="w-3.5 h-3.5 flex-shrink-0" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2">
      <path strokeLinecap="round" strokeLinejoin="round" d="M6 18L18 6M6 6l12 12" />
    </svg>
  )
}

function ChevronIcon({ expanded, size = 14 }) {
  return (
    <svg
      width={size}
      height={size}
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      strokeWidth="2"
      className="flex-shrink-0 transition-transform"
      style={{ transform: expanded ? 'rotate(180deg)' : 'rotate(0deg)' }}
    >
      <path strokeLinecap="round" strokeLinejoin="round" d="M19 9l-7 7-7-7" />
    </svg>
  )
}

// ── Helpers ──

function terminalTasksSummary(tasks) {
  const completed = tasks.filter(t => t.status === 'completed').length
  const failed = tasks.filter(t => t.status === 'failed').length
  const cancelled = tasks.filter(t => t.status === 'cancelled').length

  const parts = []
  if (completed > 0) parts.push(`${completed} completed`)
  if (failed > 0) parts.push(`${failed} failed`)
  if (cancelled > 0) parts.push(`${cancelled} cancelled`)

  return parts.join(', ') || `${tasks.length} tasks`
}

function humanizeKind(kind) {
  if (!kind) return 'Task'
  return kind
    .replace(/_/g, ' ')
    .replace(/\b\w/g, c => c.toUpperCase())
}

function formatRelativeTime(isoString) {
  if (!isoString) return ''
  const date = new Date(isoString)
  const now = new Date()
  const diffMs = now - date
  const diffMins = Math.floor(diffMs / 60000)
  const diffHours = Math.floor(diffMs / 3600000)

  if (diffMins < 1) return 'just now'
  if (diffMins < 60) return `${diffMins}m ago`
  if (diffHours < 24) return `${diffHours}h ago`
  return date.toLocaleDateString()
}

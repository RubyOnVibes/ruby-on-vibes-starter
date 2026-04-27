const sizeClasses = {
  xs: 'w-6 h-6 text-[10px]',
  sm: 'w-8 h-8 text-xs',
  md: 'w-10 h-10 text-sm',
  lg: 'w-12 h-12 text-base'
}

export default function UserAvatar({ user, size = 'sm', link = true, showName = false }) {
  if (!user) return null

  const initials = user.firstName?.charAt(0)?.toUpperCase() ||
                   user.email?.charAt(0)?.toUpperCase() ||
                   '?'

  const avatarContent = user.avatarUrl ? (
    <img
      src={user.avatarUrl}
      alt={`${user.firstName || 'User'}'s avatar`}
      className={`${sizeClasses[size]} rounded-full object-cover`}
    />
  ) : (
    <span className={`${sizeClasses[size]} rounded-full flex items-center justify-center font-semibold user-avatar-initials`}>
      {initials}
    </span>
  )

  const nameElement = showName && (
    <span className="user-avatar-name text-sm font-medium truncate max-w-[120px]">
      {user.firstName} {user.lastName}
    </span>
  )

  if (link) {
    return (
      <a
        href="/profile/registration/edit"
        className="user-avatar-link flex items-center gap-2 hover:opacity-80 transition"
        title={`${user.firstName || ''} ${user.lastName || ''}`.trim() || 'Profile'}
      >
        {avatarContent}
        {nameElement}
      </a>
    )
  }

  return (
    <div className="flex items-center gap-2">
      {avatarContent}
      {nameElement}
    </div>
  )
}

# Flash Messages & Toast System

Rails flash messages are displayed as toasts via Sonner, unified across ERB and Inertia views.

## ERB Views (Turbo)

In `application.html.erb`:
```erb
<%= react_component('ToastIsland', { flash: flash.to_hash }) %>
```

The `ToastIsland` React island:
- Listens for flash messages passed as props
- Maps Rails flash types → Sonner toast types
- Resets on `turbo:render` to handle navigation
- Respects dark/light theme

## Inertia Views

In `ApplicationController`:
```ruby
inertia_share flash: -> { flash.to_hash }
```

This shares flash to all Inertia pages. The Inertia layout uses `ToasterProvider` which reads from shared props.

## Flash Type Mapping

| Rails Flash | Toast Type |
|-------------|------------|
| `success`   | `toast.success()` |
| `error`     | `toast.error()` |
| `alert`, `warning` | `toast.warning()` |
| `notice`, `info`, default | `toast.info()` |

## Usage in Controllers

```ruby
redirect_to root_path, notice: "Welcome back!"
redirect_to root_path, alert: "Something went wrong"

# Or set directly
flash[:success] = "Created successfully"
flash[:error] = "Validation failed"
```
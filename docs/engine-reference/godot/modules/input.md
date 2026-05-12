# Godot Input — Quick Reference

Last verified: 2026-02-12 | Engine: Godot 4.6

## What Changed Since ~4.3 (LLM Cutoff)

### 4.6 Changes
- **Dual-focus system**: Mouse/touch focus is now separate from keyboard/gamepad focus
  - Visual feedback differs by input method
  - Custom focus implementations may need updating
- **Select Mode keybind changed**: "Select Mode" is now `v` key; old mode renamed "Transform Mode" (`q` key)

### 4.5 Changes
- **SDL3 gamepad driver**: Gamepad handling delegated to SDL library for better cross-platform support
- **Recursive Control disable**: Single property disables mouse/focus for entire node hierarchies

### 4.3 Changes (in training data)
- **InputEventShortcut**: Dedicated event type for menu shortcuts (optional)

## Current API Patterns

### Input Actions (unchanged)
```gdscript
func _physics_process(delta: float) -> void:
    var input_dir: Vector2 = Input.get_vector(
        &"move_left", &"move_right", &"move_forward", &"move_back"
    )
    if Input.is_action_just_pressed(&"jump"):
        jump()
```

### Input Events (unchanged)
```gdscript
func _unhandled_input(event: InputEvent) -> void:
    if event is InputEventMouseButton:
        if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
            handle_click(event.position)
    elif event is InputEventKey:
        if event.keycode == KEY_ESCAPE and event.pressed:
            toggle_pause()
```

### Focus Management (4.6 — CHANGED)
```gdscript
# Mouse/touch and keyboard/gamepad focus are now SEPARATE
# Visual styles may differ depending on which input method is active
# If you have custom focus drawing, test with both input methods

# Standard approach still works:
func _ready() -> void:
    %StartButton.grab_focus()  # Keyboard/gamepad focus

# But be aware: mouse hover focus != keyboard focus in 4.6
```

### Gamepad (4.5+ — SDL3 backend)
```gdscript
# API unchanged, but SDL3 provides:
# - Better device detection across platforms
# - Improved rumble support
# - More consistent button mapping

func _input(event: InputEvent) -> void:
    if event is InputEventJoypadButton:
        if event.button_index == JOY_BUTTON_A and event.pressed:
            confirm_selection()
```

## Common Mistakes
- Not testing both mouse and keyboard focus paths (dual-focus in 4.6)
- Assuming `grab_focus()` affects mouse focus (it only affects keyboard/gamepad in 4.6)
- Using string literals instead of `StringName` (`&"action"`) for action names in hot paths

## Touch Input (Mobile)

Last verified: 2026-05-12 | Engine: Godot 4.6

### InputEventScreenTouch
Inherits: `InputEventFromWindow` < `InputEvent` < `Resource`.

- `canceled: bool = false` — **exact spelling is `canceled` (single-l)**. Per the
  class reference: "If `true`, the touch event has been canceled." Setter
  `set_canceled(value)`, getter `is_canceled()`.
- `pressed: bool = false` — `true` on touch-down, `false` on release/cancel.
- `index: int = 0` — finger index for multi-touch (one index = one finger).
- `position: Vector2` — viewport-space position.
- `double_tap: bool = false` — second tap in a double-tap sequence.

**When `canceled` is set true (platform-specific — verified against source):**
- **Android** (`platform/android/android_input_handler.cpp`): On
  `AMOTION_EVENT_ACTION_CANCEL` (incoming call, app switch, system gesture
  hijack, parent view intercept) Godot calls `_cancel_all_touch()`, which emits
  one `InputEventScreenTouch` per active finger with `pressed=false` AND
  `canceled=true`.
- **iOS** (`drivers/apple_embedded/display_server_apple_embedded.mm`): iOS's
  `touchesCancelled` calls `touch_press(idx, -1, -1, false, false)` — it emits
  a **plain release** (`pressed=false`) at position `(-1, -1)` and does
  **NOT** set `canceled=true`. Treat `pressed=false` with off-screen position
  as a cancel signal on iOS.
- **Desktop / mouse-emulated touch**: `canceled` stays `false`.

GDD rule: to detect OS-cancel cross-platform, check
`event.canceled or (not event.pressed and event.position.x < 0)`.

### InputEventScreenDrag
Inherits: `InputEventFromWindow` < `InputEvent` < `Resource`. No `canceled`
field — cancel signals only come on the matching `InputEventScreenTouch`.

- `index: int` — finger index (matches the originating touch).
- `position: Vector2` — current viewport-space position.
- `relative: Vector2` — delta vs. previous frame, **scaled by content scale
  factor**. Use for layout-aware aiming.
- `screen_relative: Vector2` — delta in raw screen pixels (4.4+). **Prefer
  this for touch aiming regardless of stretch mode.**
- `velocity: Vector2` — scaled pixels/sec.
- `screen_velocity: Vector2` — unscaled pixels/sec (4.4+). **Prefer this.**
- `pressure: float` (0.0–1.0), `tilt: Vector2` (-1.0–1.0), `pen_inverted: bool`
  — stylus only; zero on finger touch.

### Mouse-to-Touch Emulation
Both settings live under `input_devices/pointing/`:

- `emulate_touch_from_mouse` (default `false`) — when ON, mouse click/drag
  generates `InputEventScreenTouch` + `InputEventScreenDrag` events that
  propagate through `_input` / `_unhandled_input` exactly like real touch.
  Enables developing/testing touch on desktop. `canceled` is never set true
  in this path.
- `emulate_mouse_from_touch` (default `true`) — symmetric: touchscreen taps
  generate `InputEventMouseButton` / `InputEventMouseMotion`. Leave ON if any
  code path inspects mouse events; turn OFF if duplicate-event handling is a
  hazard.

### Input Callbacks During Pause
**`process_mode` gates input callbacks the same way it gates `_process`.**
Confirmed by two authoritative sources:

1. `Node.can_process()` docs: "Returns `true` if the node can receive
   processing notifications **and input callbacks (`NOTIFICATION_PROCESS`,
   `_input()`, etc.)** from the SceneTree and Viewport. The returned value
   depends on `process_mode`."
2. Pausing tutorial: when a node is paused, "The `_process`,
   `_physics_process`, `_input`, and `_input_event` functions will not be
   called."

So with an Autoload set to `process_mode = PROCESS_MODE_ALWAYS` AND
`get_tree().paused = true`, `_unhandled_input` (and `_input`,
`_unhandled_key_input`, `_shortcut_input`) **will continue to fire** for new
touch events. The GDD's assumption is correct — no workaround needed.

Caveat: `_unhandled_input` is gated by two things, both must be true:
(a) `can_process()` returns true (process_mode allows it), AND
(b) unhandled-input processing is enabled (`set_process_unhandled_input(true)`
— done automatically when `_unhandled_input` is overridden).

### Sources
- InputEventScreenTouch class:
  https://docs.godotengine.org/en/stable/classes/class_inputeventscreentouch.html
  (verified 2026-05-12)
- InputEventScreenDrag class:
  https://docs.godotengine.org/en/stable/classes/class_inputeventscreendrag.html
  (verified 2026-05-12)
- Node.can_process / ProcessMode / _unhandled_input:
  https://docs.godotengine.org/en/stable/classes/class_node.html
  (verified 2026-05-12)
- Pausing games tutorial:
  https://docs.godotengine.org/en/stable/tutorials/scripting/pausing_games.html
  (verified 2026-05-12)
- ProjectSettings touch emulation:
  https://docs.godotengine.org/en/stable/classes/class_projectsettings.html
  (verified 2026-05-12)
- Android cancel behavior:
  https://github.com/godotengine/godot/blob/4.6/platform/android/android_input_handler.cpp
  (`_cancel_all_touch` / `AMOTION_EVENT_ACTION_CANCEL`, verified 2026-05-12)
- iOS cancel behavior:
  https://github.com/godotengine/godot/blob/4.6/drivers/apple_embedded/display_server_apple_embedded.mm
  (`touches_canceled` -> `touch_press(..., -1, -1, false, false)`, verified
  2026-05-12)

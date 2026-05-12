# Touch Input System

> **Status**: In Design — Second-pass revision 2026-05-12 complete (see `reviews/touch-input-system-review-log.md`). All 6 blockers + 7 recommended items addressed. Godot 4.6 API verified against engine source — see `docs/engine-reference/godot/modules/input.md`. iOS cancel-detection asymmetry surfaced and handled. Awaiting re-review.
> **Author**: bozhang + Claude
> **Last Updated**: 2026-05-12 (second revision pass)
> **Implements Pillar**: Indirect — serves Pillar 1 (Cast smart, not far) by providing the input substrate Cast Direction & Aiming reads from. Pure infrastructure; not player-felt directly.

## Overview

The **Touch Input System** is a foundation infrastructure layer that wraps Godot 4.6's raw input events and exposes a normalized API to downstream gameplay systems. It is implemented as a **Godot Autoload** (singleton registered in Project Settings → Autoload), guaranteed initialized before any gameplay scene's `_ready()`. It receives the engine's `InputEventScreenTouch`, `InputEventScreenDrag`, and (on desktop, via `emulate_touch_from_mouse`) `InputEventMouseButton` + `InputEventMouseMotion` events, tracks the currently-active touch via **event-driven** processing (not per-frame sampling), and exposes both a **query API** and **higher-level signals** for downstream systems to consume.

Players never see this system directly. They experience it as **responsiveness**: a 1:1 mapping between finger movement and rod motion, no input lag, no dropped touches, no gesture misinterpretation. Any failure at this layer manifests as *"the game feels unresponsive"* — even though the culprit is hidden two systems beneath the visible mechanic. Without this layer, every gameplay system would re-implement its own input handling and would diverge in subtle, hard-to-debug ways.

## Player Fantasy

**The invisible promise of responsiveness.** Players never think about touch input — until it fails. The Touch Input System's fantasy is **the felt expectation that the game responds instantly and exactly**: when the player drags their finger 100 pixels to the left, the rod tip moves 100 pixels to the left. Not 99, not 101, not 100 with a 50 ms delay. The feel target is **perceptually 1:1 fidelity** between intention and rendered state.

"Perceptually" is the load-bearing word. A 3 px dead-zone (see Core Rule 6 + Tuning Knobs) filters sub-perceptual sensor jitter — movement smaller than a human can intend or notice on a phone screen. Above that threshold, the mapping is exact. Procreate, iOS Safari scroll, and every well-tuned touch interface does this; players never experience it as "non-1:1" because the filtered movement was never intentional in the first place. The dead-zone serves the fantasy by rejecting noise; without it, sensor jitter would leak into `cumulative_drag_distance` and intentional movements would arrive corrupted.

This serves **Pillar 1 (Cast smart, not far)** indirectly but critically: if the player thinks *"I aimed there but the game cast somewhere else,"* the strategic-placement core of the game is broken. Pillar 1 promises that placement is the player's decision; this system is the mechanism that guarantees the input → placement chain has zero perceptible drift.

Reference moments that capture the right feeling:
- **Drawing in Procreate or Notes** — your finger and the line on screen are *one continuous thing*. No translation, no interpretation, just direct expression. (Procreate filters sub-pixel sensor noise too; the perceived continuity is the result, not the absence of filtering.)
- **Scrolling in iOS Safari** — when scroll feel is right, you don't notice. When it's wrong, it ruins everything else on the page.
- **Apple's direct-manipulation principle** (HIG) — the on-screen object IS the thing the player is touching; latency between finger and result is the enemy.

The fantasy is **invisible competence**: the player never thinks *"the input system is great."* They only think *"the cast went where I aimed."* That's the goal. If anyone notices this system, it has failed.

## Detailed Rules

### Core Rules

1. **Implementation pattern**: The system is implemented as a **Godot Autoload** (Project Settings → Autoload, name `TouchInput`). Its `process_mode` is set to `PROCESS_MODE_ALWAYS` so it continues to receive input and accumulate timing while the SceneTree is paused. It receives input via `_unhandled_input(event: InputEvent)` — events already consumed by Control/GUI nodes (HUD buttons, menu Controls) do NOT reach this system. This prevents HUD-button taps from triggering downstream `touch_started` listeners.
2. **Project input settings (required)**: `emulate_touch_from_mouse = ON` (default) so desktop dev/test works. `emulate_mouse_from_touch = OFF` (must be set explicitly, project-settings change) so a single mouse click never generates both an `InputEventMouseButton` AND an `InputEventScreenTouch` for the same physical action.
3. **Single active touch**: Only one active touch is tracked at a time. The first finger to touch the screen becomes the *active touch* and is remembered by its `event.index`. Any additional fingers that come down while the active touch is in progress are observed but ignored — they do not change state, do not update the active touch, and do not emit events.
4. **Release matches finger**: The active touch is released only when **its specific finger lifts** (the touch event with the matching `event.index`). If a second finger touches and then lifts while the first is still down, nothing changes — the first finger remains the active touch. If the active finger lifts while a second finger is still down, the system returns to Idle and emits `touch_ended`. The still-down second finger does NOT become a new active touch — it would need a fresh touch-down event after the first finger's release to become tracked. (This is a deliberate simplification for MVP; revisit in Tier 2+ if it causes UX issues.)
5. **Event-driven accumulation (NOT frame-sampled)**: All state updates — position, duration accumulation, drag-distance accumulation — happen inside `_unhandled_input()`, driven by Godot's input events. `_process()` is used ONLY to accumulate `current_time` (the game-time clock) via `delta`. This keeps drag-distance frame-rate independent: a curved drag samples at the platform's touch rate (60–240 Hz), not the game's frame rate.
6. **Sub-pixel dead-zone**: A `touch_dead_zone_px` filter (default **3 px**) suppresses jitter. Drag events with `|relative| < touch_dead_zone_px` do NOT emit `touch_dragged` and do NOT increment `cumulative_drag_distance`, BUT they DO update `previous_position` so the next real movement computes its delta correctly. This couples with Cast Direction & Aiming's `cancel_threshold_drag` (15 px) to leave a 12 px effective margin of intentional drag.
7. **Tracked state**: While a touch is active, the system tracks `start_position`, `current_position`, `previous_position`, `start_time` (a snapshot of the accumulated game-time clock at touch_started), `cumulative_drag_distance`. State is reset to neutral on touch release — but the reset happens **AFTER** the relevant signal (`touch_ended` or `touch_interrupted`) is emitted, so listeners that query the API from within a signal handler receive the final touch state, not zero.
   - **`await` boundary contract**: A consumer signal handler that uses GDScript `await` yields control back to the engine. The autoload treats yielded handlers as returned and proceeds with state reset. **Handlers that need post-`await` access to touch state must capture values into local variables before the first `await` point.** Reading the query API after an `await` returns post-reset values (`Vector2.ZERO`, `0.0`, `false`), which is the documented behavior in Edge Cases — not a bug. Prefer the signal payload (parameters passed to the handler) over the query API when post-yield access is needed; the payload is captured by value and stable across yields.
8. **Signals**: Four signals are emitted in sequence per touch lifecycle:
   - `touch_started(position: Vector2)` on touch-down
   - `touch_dragged(position: Vector2, delta: Vector2)` for every non-dead-zone position update during the touch
   - `touch_ended(position: Vector2, duration: float, cumulative_drag_distance: float)` on normal touch-up
   - `touch_interrupted(position: Vector2)` when the OS cancels the touch (incoming call, app switch, system alert). Downstream consumers must treat `touch_interrupted` as a cancel, never as a commit.
   - **Cross-platform OS-cancel detection (verified against Godot 4.6 source — see `docs/engine-reference/godot/modules/input.md`):** Android sets `event.canceled = true` on `InputEventScreenTouch` when `AMOTION_EVENT_ACTION_CANCEL` fires. **iOS does NOT set `canceled = true`** — instead, iOS's `touchesCancelled` emits a plain release (`pressed = false`) at the exact sentinel position `Vector2(-1, -1)`. The detection rule is: `event.canceled OR (not event.pressed AND event.position == Vector2(-1, -1))`. Use the **exact** sentinel comparison, NOT a generic `position.x < 0` check — a player legitimately dragging off-screen-left and lifting at, say, `(-50, -50)` is a normal release (emits `touch_ended`), not a cancel. Only the exact `(-1, -1)` is the iOS cancel signal. Matching the active touch index is required. The reported `position` for `touch_interrupted` is the **last known on-screen position** of the active touch (NOT the sentinel `(-1, -1)`), so consumers receive a usable position.
9. **Query API** (for systems that prefer polling over signals):
   - `is_touching() -> bool`
   - `current_touch_position() -> Vector2`
   - `touch_start_position() -> Vector2`
   - `touch_duration() -> float`
   - `cumulative_drag_distance() -> float`
   Returns are safe defaults (`false`, `Vector2.ZERO`, `0.0`) when no touch has yet occurred or when called before the Autoload has finished initializing.
10. **Gesture agnosticism**: The system does not interpret taps vs. drags vs. long-presses. Gesture interpretation is the responsibility of downstream systems (e.g., Cast Direction & Aiming's Formula 5 cancel-detection uses this system's `touch_duration` and `cumulative_drag_distance` to compute `is_cancel`).
11. **Pause survival (game-time freezes; touch state preserved)**: When the game pauses (`get_tree().paused = true`):
    - **Input delivery**: `_unhandled_input` continues to fire (because `process_mode = PROCESS_MODE_ALWAYS`). The active touch is preserved; if the player lifts their finger during pause, `touch_ended` fires normally on resume or immediately if `_unhandled_input` is delivering events.
    - **Game-time freezes**: `current_time` does NOT accumulate during pause. The implementation MUST check `get_tree().paused` inside `_process(delta)` and skip the `current_time += delta` increment when true. This is required to keep `touch_duration` aligned with the player's perceived in-game time — a pause menu must not silently inflate the duration of a long-held touch. (See Formula 2 implementation note and AC #9.)
    - **Queries during pause**: `touch_duration()` returns the value at the moment of pause (frozen, because `current_time` is frozen). `cumulative_drag_distance()` and `current_touch_position()` continue to reflect live touch state if the player keeps moving their finger during pause (drag events still arrive via `_unhandled_input`).
    - **No spurious signals**: no `touch_ended` is emitted by the pause transition itself. OS-level interrupts that cancel the touch fire `touch_interrupted`, never `touch_ended`.

### Typed GDScript contract (authoritative)

```gdscript
# TouchInput autoload — authoritative signal & query contract
# IMPORTANT: do NOT add `class_name TouchInput` to this script.
# The autoload is registered under the name `TouchInput` in Project Settings
# and is accessed as the global singleton `TouchInput`. Adding `class_name TouchInput`
# creates a name collision in Godot 4's global class registry — the autoload name
# and the class_name occupy the same identifier slot. Just `extends Node` is enough.
extends Node

signal touch_started(position: Vector2)
signal touch_dragged(position: Vector2, delta: Vector2)
signal touch_ended(position: Vector2, duration: float, cumulative_drag_distance: float)
signal touch_interrupted(position: Vector2)

func is_touching() -> bool: ...
func current_touch_position() -> Vector2: ...
func touch_start_position() -> Vector2: ...
func touch_duration() -> float: ...
func cumulative_drag_distance() -> float: ...
```

### States and Transitions

| State | Description | Signals emittable from this state |
|---|---|---|
| **Idle** | No active touch. State variables are reset to safe defaults. | `touch_started` (on entering Touching) |
| **Touching** | An active touch is in progress. State variables track that touch. | `touch_dragged` (during), `touch_ended` (on normal exit), `touch_interrupted` (on OS-cancel exit) |

Transitions:

| From | To | Trigger |
|---|---|---|
| Idle | Touching | First touch-down event (real touch OR emulated-from-mouse) |
| Touching | Touching | Additional touch-down events (ignored — observed but state unchanged), or non-dead-zone drag events on the active touch |
| Touching | Idle (normal) | The active touch's finger lifts cleanly — emits `touch_ended`, THEN resets state |
| Touching | Idle (interrupted) | OS cancels the touch (`InputEventScreenTouch.canceled == true`) — emits `touch_interrupted`, THEN resets state |

### Interactions with Other Systems

This system has **no upstream gameplay dependencies** — it depends only on Godot's input event pipeline (engine-level, not a project system).

**Downstream consumers:**

| Consumer | What it reads | Style |
|---|---|---|
| Cast Direction & Aiming | `touch_started` signal + `current_touch_position` + `touch_duration` + `cumulative_drag_distance` (polled), plus `touch_ended` and `touch_interrupted` signals | Mixed — listens for start/end/interrupted, polls during drag |
| Casting Mechanic (undesigned) | Likely `touch_started` event + position | TBD |
| Other gameplay systems | Same primitives | TBD |

**Consumer disconnection responsibility**: scene-local consumers (e.g., Cast Direction & Aiming nodes) MUST disconnect from this autoload's signals in `_exit_tree()` or use `CONNECT_ONE_SHOT` for single-event listeners. The Touch Input autoload does not track consumer lifetimes — orphaned signal callbacks on freed receivers are the consumer's responsibility to prevent.

**Interface contracts owned by this GDD:**

See the **Typed GDScript contract** block above for the authoritative signature list.

**Interface contracts owned by OTHER systems (read by this one):**

| Read-from | Property / event | Owner |
|---|---|---|
| Godot input pipeline | `InputEventScreenTouch` (incl. `canceled` flag for OS interrupts), `InputEventScreenDrag`, `InputEventMouseButton`, `InputEventMouseMotion` | Godot engine (≥ 4.6) |

## Formulas

### Formula 1: Cumulative Drag Distance (event-driven)

Accumulated on every non-dead-zone `InputEventScreenDrag` (or its mouse-emulation equivalent) for the active touch:

```
if |current_position - previous_position| >= touch_dead_zone_px:
    cumulative_drag_distance += |current_position - previous_position|
previous_position = current_position
```

**Variables:**

| Variable | Symbol | Type | Range | Description |
|---|---|---|---|---|
| `current_position` | p | Vector2 (Godot viewport-space pixels) | unbounded (may extend off-screen) | Touch position from this event |
| `previous_position` | p' | Vector2 (Godot viewport-space pixels) | as above | Touch position from the prior event |
| `touch_dead_zone_px` | z | float (pixels) | [0, 8] | Tuning knob; default **3** |
| `cumulative_drag_distance` | D | float (pixels) | [0, ∞) | Running total since `touch_started` |

**Critical implementation notes**:
- **`previous_position` initialization**: On `touch_started`, `previous_position` is initialized to `start_position` (the touch-down event's position). The first drag event's delta is therefore `current_position - start_position`, NOT `current_position - Vector2.ZERO`.
- **`previous_position` update**: After every drag event (including sub-dead-zone events and exact zero-delta events), `previous_position = current_position` runs unconditionally. The pseudocode above is authoritative: the assignment is outside the dead-zone conditional. This guarantees the next real movement computes its delta from the most recent sampled position — not from a stale pre-dead-zone position.
- **Read `event.position`, not `event.relative`**: `current_position` is read from `InputEventScreenDrag.position` (the absolute position from this event). The delta is computed by subtraction against the stored `previous_position`. Do NOT use `InputEventScreenDrag.relative` — the dead-zone check operates on the position-state delta, and reading `.relative` would silently bypass the `previous_position` bookkeeping.

**Sampling discipline**: Because this runs in `_unhandled_input()` on every event (not in `_process()`), `cumulative_drag_distance` is frame-rate independent. A 30 fps device and a 120 fps device receive the same sequence of `InputEventScreenDrag` events from the platform; the accumulator processes them all.

**Output Range:** Monotonically non-decreasing while touching. Resets to 0 on every `touch_started`.

**Example:** Touch started at (100, 200). Event 2: position (110, 200), delta magnitude 10 ≥ 3 → `D = 10`. Event 3: position (110, 220), delta magnitude 20 ≥ 3 → `D = 30`. Event 4: position (110, 221), delta magnitude 1 < 3 → `D = 30` (dead-zone suppressed), `previous_position = (110, 221)`.

---

### Formula 2: Touch Duration

Elapsed game-time since `touch_started`:

`touch_duration = current_time - touch_start_time`

**Variables:**

| Variable | Symbol | Type | Range | Description |
|---|---|---|---|---|
| `current_time` | t | float (seconds) | [0, ∞) — accumulated `_process` delta sum | A monotonic counter incremented as `current_time += delta` in `_process(delta)`. NOT `Time.get_ticks_msec()` (wall-clock). NOT `Engine.get_process_frames()` (frame count). Specifically: accumulated sum of `_process` deltas. |
| `touch_start_time` | t₀ | float (seconds) | snapshot of `current_time` at `touch_started` | Recorded when active touch began |
| `touch_duration` | Δt | float (seconds) | [0, ∞) | Result |

**Precision**: Godot's `float` is 64-bit (double precision) on all supported platforms — no precision concern at typical session lengths.

**Pause behavior**: `current_time` is incremented in `_process(delta)`. When the SceneTree is paused (`get_tree().paused = true`), `_process` does NOT fire on a node with `process_mode = PROCESS_MODE_INHERIT`. However, this Autoload uses `process_mode = PROCESS_MODE_ALWAYS`, which means `_process` continues to fire during scene-tree pause. **For an in-game pause menu where game-time should freeze**: the Autoload must check `get_tree().paused` inside `_process` and skip the `current_time += delta` increment when true. (This is the implementation detail that preserves the spirit of Core Rule 11 — pause survival without ghost-time accumulation.)

**Sub-frame tap**: If a touch starts and ends within the same `_unhandled_input()` pass (extremely fast tap), `touch_duration` is `0.0` because no `_process` delta has accumulated between the two events. This is correct behavior — downstream cancel logic treating `duration == 0` as a cancel is appropriate.

**Example:** Touch started at `current_time = 12.345`. Three game-seconds later (`current_time = 15.345`): `touch_duration = 3.000`.

## Edge Cases

- **If two fingers touch down on the exact same frame**: the touch with the lower `event.index` becomes the active touch. (Note: Godot's `event.index` is stable for the **lifetime of one contact**, NOT across contacts — a new finger after one is lifted may reuse a previously-released index.)
- **If the active touch's finger lifts off-screen** (player drags past viewport bounds then releases beyond the edge): the system treats it as a normal `touch_ended`. The final reported position may be off-screen; downstream consumers should clamp or accept off-screen positions per their own logic.
- **If the OS cancels the touch (incoming phone call, app switch, system alert)**: Platform-specific Godot 4.6 behavior (verified against engine source):
  - **Android**: Godot delivers `InputEventScreenTouch(pressed=false, canceled=true, position=last)` for each active finger. The autoload detects `event.canceled == true` and emits `touch_interrupted(last_known_position)`.
  - **iOS**: Godot delivers `InputEventScreenTouch(pressed=false, canceled=false, position=Vector2(-1, -1))` — `canceled` is NOT set. The autoload detects this by exact-sentinel comparison: `not event.pressed AND event.position == Vector2(-1, -1)`. **Use the exact sentinel, NOT `position.x < 0`** — that broader check would falsely classify legitimate off-screen releases (e.g., player drags to `(-50, -50)` and lifts) as cancels. On detection, emit `touch_interrupted(last_known_position)`. **The reported position for `touch_interrupted` is the last on-screen position the autoload saw, NOT the iOS sentinel** — consumers must always receive a usable position.
  - In both cases, the system resets to Idle. It does NOT emit `touch_ended` — this is the distinction that lets Cast Direction & Aiming differentiate a clean release (commit) from an OS interrupt (always cancel, never commit).
- **If the app is backgrounded while touching, with NO OS-level cancellation event delivered**: state is preserved; the system continues to consider the touch active. On resume, if Godot reports the touch as still down, tracking continues; if Godot reports it released, `touch_ended` fires with the last known position. (This is a softer failure mode than OS cancellation; rare on modern iOS/Android.)
- **If a `touch_dragged` event arrives without a prior `touch_down` for the active touch**: the event is ignored. The active touch must have started cleanly via `touch_started`; orphan drags (e.g., from a system replay or test harness) are dropped silently.
- **If the same `event.index` fires touch_down twice without an intervening touch_up**: treat the second touch_down as a no-op (the active touch is already this index; updating its start_position would erase the legitimate one). Log a debug warning when `debug_log_anomalies` is true.
- **If a non-primary mouse button (right, middle, side, wheel) generates a mouse event**: ignored. Only left-mouse-button (`MOUSE_BUTTON_LEFT`) is translated to touch.
- **If the active finger lifts while a second finger is still down**: the system returns to Idle and emits `touch_ended` for the first finger. The second finger does NOT become a new active touch — it would need a fresh touch_down event after the active touch ends. (Per Core Rule 4.) *Player-visible consequence*: in the rare case where this happens during gameplay (e.g., accidental second finger during an aim), the player may briefly feel a "dropped" input on the next intentional touch if the second finger is still down. Acceptable for MVP — monitor in playtest.
- **Palm-down-first (known MVP limitation)**: If the player rests a palm on the screen before their aim finger touches, the palm becomes the active touch (lowest `event.index`), and subsequent aim-finger touches are ignored per Core Rule 3. When the palm lifts, the system returns to Idle (per Core Rule 4); the aim finger — even if physically still on the screen — is NOT promoted to active touch, because no fresh `touch_down` event fires for it. **Required player action**: lift the aim finger and re-touch to start tracking. This is documented and accepted for MVP; palm-rejection heuristics (touch region restriction, contact-size filtering) are tracked in Open Questions for Tier 2+. QA should treat this as expected behavior, not a bug, until that work lands.
- **If a system queries `is_touching()` before the autoload has finished initializing**: returns `false`. The query API is safe to call at any time and returns safe defaults (`false`, `Vector2.ZERO`, `0.0`) when state is uninitialized.
- **If `cumulative_drag_distance` is queried from inside a `touch_ended` or `touch_interrupted` signal handler**: returns the final touch's value (state has NOT been reset yet — reset happens AFTER all signal handlers return). This is the design invariant that AC #11 verifies.
- **If `cumulative_drag_distance` is queried AFTER signals have fired and state has reset (e.g., next frame, via `call_deferred`, or from a separate polling loop)**: returns `0.0`. The post-`touch_ended` stale-state behavior of the original spec was a footgun; this revision resets cleanly. Consumers that need the final value should read it from the signal payload.
- **If two consumer systems both register listeners on `touch_dragged`**: both are called every event. There is no ordering guarantee between listeners. If ordering matters, establish it via signal connection order.

## Dependencies

### Upstream dependencies (hard)

**None** at the gameplay/project level. This system depends only on Godot's input event pipeline.

### Upstream dependencies (soft)

| Dependency | What it adds | Status |
|---|---|---|
| Godot 4.6 input subsystem | Raw input events and mouse↔touch emulation | Engine — versioned in `docs/engine-reference/godot/VERSION.md` |
| Godot Project Settings (Input Devices) | `emulate_touch_from_mouse = ON`, `emulate_mouse_from_touch = OFF` | Configuration; must be set before first build |
| Godot Project Settings (Autoload) | `TouchInput` autoload registered with `process_mode = PROCESS_MODE_ALWAYS` | Configuration |

### Depended on by

| Consumer | What they consume | Required? |
|---|---|---|
| **Cast Direction & Aiming** (system #6 — **Approved 2026-05-12** post Touch Input revision) | `touch_started`, `touch_ended`, `touch_interrupted` signals; `current_touch_position`, `touch_duration`, `cumulative_drag_distance` queries | Hard |
| **Casting Mechanic** (system #5 — undesigned) | Likely `touch_started` + position | Hard (expected) |
| Any future gameplay system that responds to player touch | Same query/signal primitives | Hard |

### Interface contracts owned by this GDD

See the **Typed GDScript contract** block in Detailed Design for the full authoritative signature list (4 signals + 5 query methods).

### Interface contracts owned by OTHER systems (read by this one)

| Read-from | Property / event | Owner |
|---|---|---|
| Godot input pipeline | `InputEventScreenTouch` (with `canceled` field), `InputEventScreenDrag`, `InputEventMouseButton`, `InputEventMouseMotion` | Godot engine (≥ 4.6) |

**Bidirectional consistency note**: Cast Direction & Aiming's Formula 5 variable table is updated in the 2026-05-12 revision pass to use `cumulative_drag_distance` (the canonical name). Cast Direction's `cancel_threshold_drag` (15 px) couples with this system's `touch_dead_zone_px` (3 px) to leave a 12 px effective intentional-drag margin. ✓ Consistent post-revision.

## Tuning Knobs

| Knob | Default | Safe Range | Effect | If too high | If too low |
|---|---|---|---|---|---|
| `touch_dead_zone_px` | **3** | [1, 8] | Below this per-event delta magnitude, `touch_dragged` is suppressed and `cumulative_drag_distance` does not increase (but `previous_position` still updates) | Real micro-movements lost; couples with Cast Direction's `cancel_threshold_drag` and reduces its effective margin | Hardware jitter leaks into `cumulative_drag_distance`; accidental commits. **Lower bound is 1**, not 0 — a dead-zone of 0 would cause zero-magnitude drag events to emit `touch_dragged` with `delta = Vector2.ZERO`, which is degenerate behavior. |
| `debug_log_anomalies` | **false** (release) / **true** (debug) | true / false | Whether unusual edge cases (orphan drag events, duplicate touch_down on same index, off-screen positions) are logged | Noisy logs in production | Anomalies go unnoticed during dev |

> **Joint constraint with Cast Direction & Aiming**: The player must produce at least `cancel_threshold_drag` (15 px default in Cast Direction) of physical finger movement to escape Cast Direction's cancel check. Of that physical movement, the first `touch_dead_zone_px` (3 px default) is filtered as sub-perceptual jitter before reaching `cumulative_drag_distance`; the remaining 12 px is the *intentional-drag margin* that actually accumulates. Raising `touch_dead_zone_px` reduces this margin (e.g., dead-zone = 8 leaves only a 7 px margin). Lowering Cast Direction's `cancel_threshold_drag` below the dead-zone makes cancel impossible by drag alone — only the time threshold can cancel. Changing either knob requires re-evaluating the other.

> **No gameplay-affecting tuning lives in this GDD beyond the dead zone**. Downstream gameplay tuning (cancel thresholds, aim sensitivity, etc.) is owned by the consuming systems.

## Visual/Audio Requirements

**None.** Touch Input has no visual or audio output of its own — it is pure infrastructure. Downstream systems own their feedback. If we ever add platform-level haptic feedback (vibration on `touch_started`, for example), that would be a Tier 2+ addition handled by a dedicated Haptic Feedback System, not this one.

## UI Requirements

**None.** This system has no on-screen UI elements. No UX flag required.

## Acceptance Criteria

All ACs assume the **GUT (Godot Unit Test)** framework. Touch events are injected directly into the autoload's `_unhandled_input(event)` method — no real device required, headless-CI safe. Frame advancement is simulated by calling `_process(delta)` directly with chosen delta values. Wall-clock timing is never used in tests.

### Per Core Rules

1. **GIVEN** the system is in Idle state, **WHEN** an `InputEventScreenTouch(pressed=true, position=(100,200), index=0)` is injected into `_unhandled_input()`, **THEN** `touch_started` is emitted exactly once (verified via GUT `assert_signal_emit_count(touch_input, "touch_started", 1)`) AND `is_touching()` returns `true` AND `current_touch_position()` returns `Vector2(100, 200)`.

2. **GIVEN** the system holds an active touch with `event.index = 0`, **WHEN** an `InputEventScreenTouch(pressed=true, position=(300,300), index=1)` is injected, **THEN** `touch_started` is NOT emitted a second time (total emit count remains 1), `touch_dragged` is NOT emitted, `is_touching()` still returns `true`, and `current_touch_position()` still returns the index-0 touch's last position.

3. **GIVEN** an active touch at index 0 (position (100,100)), then index-1 touch-down at (300,300), then index-1 touch-up at (300,300), **WHEN** an `InputEventScreenTouch(pressed=false, position=(100,150), index=0)` is injected, **THEN** `touch_ended` is emitted once with `position == Vector2(100, 150)` (the first finger's lift position, NOT (300,300)).

4. **GIVEN** the autoload's `_unhandled_input()` accepts injected mouse events directly, **WHEN** `InputEventMouseButton(button_index=MOUSE_BUTTON_LEFT, pressed=true, position=P)` then `InputEventMouseMotion(position=P+(5,0))` then `InputEventMouseButton(pressed=false)` are injected in sequence, **THEN** `touch_started`, `touch_dragged`, `touch_ended` are emitted in that order with parameters equivalent to a real touch sequence at the same positions. (Unit-testable in GUT headless via direct event injection.)

5. **GIVEN** an active touch, **WHEN** an `InputEventScreenDrag` is injected with `.relative = Vector2(5.0, 0.0)` (Godot viewport-space pixels), **THEN** `touch_dragged` is emitted with `delta` within `Vector2(5.0, 0.0) ± Vector2(0.001, 0.001)` AND `cumulative_drag_distance` increases by `5.0 ± 0.001`. Pixel unit is Godot viewport space (not physical pixels).

6. **GIVEN** an active touch with `cumulative_drag_distance` already at 10.0, **WHEN** an `InputEventScreenDrag` with `.relative = Vector2(1.0, 0.0)` (below dead-zone of 3 px) is injected, **THEN** `touch_dragged` is NOT emitted (emit count unchanged) AND `cumulative_drag_distance()` still returns 10.0 AND `current_touch_position()` IS updated (so `previous_position` advances for future delta calculations).

7. **GIVEN** a test fixture that advances game-time deterministically (calling `_process(0.25)` twice for 0.5 s total), **WHEN** touch-down is injected, then drag totaling 30 px is injected, then touch-up is injected, **THEN** `touch_ended` is emitted once with `duration` within `[0.499, 0.501]` and `cumulative_drag_distance` within `[29.9, 30.1]`.

### Per Formulas

8. **GIVEN** touch-down at (100,200), then `InputEventScreenDrag(.relative=(10,0))` injected followed by `_process(1.0/60.0)`, then `InputEventScreenDrag(.relative=(0,20))` injected followed by `_process(1.0/60.0)`, **WHEN** `cumulative_drag_distance()` is queried, **THEN** it returns `30.0 ± 0.001` (path length, not displacement). Verifies event-driven accumulation.

9. **GIVEN** a touch is started (record `touch_start_time`), call `_process(1.0)` to advance game-time by 1 s. **WHEN** the test simulates pause by NOT calling `_process` on the autoload for what would otherwise be 2 s of wall-clock, then calls `_process(0.5)` after "resume", **THEN** `touch_duration()` returns `1.5 ± 0.01` s (1.0 + 0.5 game-seconds, NOT 3.5 wall-clock seconds). Deterministic; no real-time sleep.

### Cross-system (integration tests — live in `tests/integration/touch-input-cast-direction/`)

10. **GIVEN** Touch Input and Cast Direction & Aiming autoloads are both initialized. **WHEN** a drag event updates the touch position to P, and `_process(delta)` is called once, **THEN** Cast Direction's polled `current_touch_position()` returns P.

11. **GIVEN** Touch Input in Touching state with accumulated duration D and `cumulative_drag_distance` X. **WHEN** the `touch_ended` signal fires, **THEN** the signal's `duration` parameter equals `touch_duration()` queried from inside the same signal handler invocation, and `cumulative_drag_distance` payload equals `cumulative_drag_distance()` queried from inside the same handler. (Verifies the emit-then-reset ordering.)

### Edge Cases

12. **GIVEN** the system is in Idle state, **WHEN** an `InputEventScreenDrag` is injected with no prior touch_down, **THEN** `touch_dragged` is NOT emitted, `is_touching()` returns `false`, `current_touch_position()` returns `Vector2.ZERO`, `cumulative_drag_distance()` returns `0.0`.

13. **GIVEN** the system is in Idle state, **WHEN** `InputEventMouseButton(button_index=MOUSE_BUTTON_RIGHT, pressed=true)`, `InputEventMouseMotion` at a new position, and `InputEventMouseButton(MOUSE_BUTTON_RIGHT, pressed=false)` are injected, **THEN** `is_touching()` returns `false`, no signals are emitted (all four signal emit counts remain 0), `current_touch_position()` is unchanged from default.

14a. **(Android cancel path)** **GIVEN** an active touch is in progress with last known on-screen position `L = (200, 300)`, **WHEN** `InputEventScreenTouch(pressed=false, canceled=true, position=(200, 300), index=0)` (matching active index) is injected, **THEN** `touch_interrupted(Vector2(200, 300))` is emitted exactly once, `touch_ended` is NOT emitted, system returns to Idle.

14b. **(iOS cancel path)** **GIVEN** an active touch is in progress with last known on-screen position `L = (200, 300)`, **WHEN** `InputEventScreenTouch(pressed=false, canceled=false, position=Vector2(-1, -1), index=0)` (matching active index, iOS sentinel) is injected, **THEN** `touch_interrupted(Vector2(200, 300))` is emitted exactly once (payload is the last on-screen position, NOT the `(-1, -1)` sentinel), `touch_ended` is NOT emitted, system returns to Idle.

14c. **(Cancel-detection robustness)** **GIVEN** an active touch is in progress, **WHEN** `InputEventScreenTouch(pressed=false, canceled=false, position=Vector2(150, 250), index=0)` (a normal release with on-screen position) is injected, **THEN** `touch_ended` is emitted (NOT `touch_interrupted`) — the cancel-detection rule `event.canceled OR (not event.pressed AND event.position.x < 0)` is false here, so the autoload treats this as a clean release.

14d. **(Off-screen release is NOT a cancel)** **GIVEN** an active touch with `start_position = (100, 100)`, **WHEN** `InputEventScreenTouch(pressed=false, canceled=false, position=Vector2(-50, -50), index=0)` is injected (active finger lifts off-screen past viewport bounds, NOT the iOS cancel sentinel), **THEN** `touch_ended` is emitted exactly once with `position == Vector2(-50, -50)` (final reported position may be off-screen — clamping is the consumer's responsibility), `touch_interrupted` is NOT emitted, no crash, system returns to Idle. (Distinguishes legitimate off-screen release from iOS cancel sentinel `(-1, -1)`.)

### Initialization, cleanup, and frame-rate independence

15. **GIVEN** the autoload's `_ready()` has just completed (no input events processed yet), **WHEN** `is_touching()`, `current_touch_position()`, `touch_start_position()`, `touch_duration()`, `cumulative_drag_distance()` are called, **THEN** they return `false`, `Vector2.ZERO`, `Vector2.ZERO`, `0.0`, `0.0` respectively — no crash, no null deref.

16. **GIVEN** a complete touch lifecycle (touch_down → touch_drag totaling 47 px → touch_up). **WHEN** all signal handlers have returned and `_process(delta)` ticks once more, **THEN** `is_touching()` returns `false`, `current_touch_position()` returns `Vector2.ZERO`, `touch_duration()` returns `0.0`, `cumulative_drag_distance()` returns `0.0` (state has fully reset).

17. **GIVEN** Test Run A injects a sequence of drag events totalling 60 px over 60 `_process(1.0/60.0)` calls, AND Test Run B injects the SAME drag event sequence over 30 `_process(1.0/30.0)` calls, **WHEN** `touch_duration()` and `cumulative_drag_distance()` are queried at the end of each run, **THEN** both runs return the same values within float tolerance (`±0.01` for duration, `±0.1` for drag). Verifies event-driven (frame-rate independent) accumulation.

18. **GIVEN** an active touch with `event.index = 0` at `start_position = (100, 100)`, **WHEN** a second `InputEventScreenTouch(pressed=true, index=0, position=(200, 200))` is injected (duplicate touch_down on same index), **THEN** `touch_started` is NOT emitted again AND `touch_start_position()` still returns `(100, 100)` (not (200, 200)).

### Performance (manual / on-device test — not GUT-automated)

19. **Classification**: MANUAL ON-DEVICE test. **Test environment**: iPhone 11 (A13 Bionic) or equivalent Android baseline (Snapdragon 660-class), Godot 4.6 Compatibility renderer, release build. **Measurement protocol**: Use Godot's built-in profiler (Debug → Profiler) to measure mean time spent in `TouchInput._unhandled_input()` + `TouchInput._process()` averaged over 300 frames of continuous drag. **Pass criterion**: mean per-frame combined time < **0.5 ms** with no single-frame spike > 2.0 ms. **Evidence**: write to `production/qa/evidence/touch-input-perf-[device]-[date].md` with device name, Godot build hash, profiler screenshot, mean + p99 numbers. **Gate**: required before Milestone 1 build is approved.

## Open Questions

| Question | Owner | Resolve when |
|---|---|---|
| Should the system support multi-touch as a first-class feature (e.g., pinch gestures) in Tier 2+? Current spec is single-touch only. | gameplay-programmer | When a Tier 2+ system requires multi-touch (e.g., camera pinch-zoom). MVP doesn't need it. |
| Should there be a "lost focus" recovery path for cases where Godot doesn't report `canceled` after an OS interrupt on some Android devices? | gameplay-programmer | If observed in QA. Add a safety timeout: if an active touch has been "live" for >60s with no updates, force `touch_interrupted` and clear state. |
| Palm-rejection heuristics (touch region restriction, contact-size filtering) for the palm-down-first scenario | game-designer + accessibility-specialist | Tier 2+ if playtest reveals user impact. MVP behavior + required player action ("lift aim finger, re-touch") are documented in Edge Cases as a known limitation. |
| Gesture vocabulary fragmentation: Cast Direction's tap-vs-drag thresholds (0.12s / 15px) will be reinvented by every future tap-sensitive system. Extract to shared `gesture_constants.gd`? | game-designer | When a second downstream consumer needs tap-vs-drag detection. Cast Direction's Formula 5 is the reference implementation in the meantime. |
| ProMotion 120 Hz cadence: should `touch_dragged` coalesce to one-emit-per-frame when input rate exceeds frame rate? Currently emit-every-event. | godot-gdscript-specialist + performance-analyst | If on-device profiling (AC #19) shows signal-emission overhead as a measurable contributor. MVP default: emit every event. |

**Resolved during review 2026-05-12 (first pass):**
- ✅ Implementation pattern: Autoload (Core Rule 1)
- ✅ Input callback: `_unhandled_input()` (Core Rule 1)
- ✅ Mouse emulation: `emulate_mouse_from_touch = OFF` in project settings (Core Rule 2)
- ✅ Sampling discipline: event-driven in `_unhandled_input()`, not frame-sampled (Core Rule 5, Formula 1)
- ✅ Dead-zone: 3 px default with joint-constraint note vs Cast Direction (Core Rule 6, Tuning Knobs)
- ✅ Naming: `cumulative_drag_distance` canonical across signal payload, query, and downstream GDD
- ✅ `current_time` algorithm: accumulated `_process` delta sum (Formula 2)
- ✅ Emit-then-reset ordering: signals fire before state reset (Core Rule 7)
- ✅ `touch_interrupted` signal: separate signal for OS-cancelled touches (Core Rule 8)
- ✅ Stale post-touch_ended query: removed — state resets cleanly to safe defaults

**Resolved during re-review 2026-05-12 (second pass):**
- ✅ Pause behavior contradiction: Core Rule 11 rewritten to freeze game-time during pause; aligns with Formula 2 + AC #9
- ✅ Player Fantasy reframed as "perceptually 1:1"; dead-zone explained as serving the fantasy by rejecting sub-perceptual jitter
- ✅ Formula 1 zero-delta wording aligned with pseudocode (`previous_position` updates unconditionally); explicit init rule added (`previous_position = start_position` on `touch_started`); explicit "read `event.position` not `event.relative`" note added
- ✅ Dead-zone safe range raised from [0, 8] to [1, 8] to prevent degenerate `delta = Vector2.ZERO` emissions
- ✅ Joint-constraint note rewritten with corrected, non-tautological arithmetic
- ✅ `class_name TouchInput` removed from contract block (Godot 4 autoload name collision)
- ✅ `await` boundary contract documented in Core Rule 7 (capture state before yielding)
- ✅ Palm-down-first scenario promoted from Open Question to Edge Cases as known MVP limitation with required player action
- ✅ Off-screen drag termination AC #14b added
- ✅ Section header renamed "Detailed Design" → "Detailed Rules" to match canonical structure in `design/CLAUDE.md`
- ✅ Alto's Adventure reference removed from Player Fantasy (described tap-timing, not drag-fidelity); replaced with Apple HIG direct-manipulation reference
- ✅ Godot 4.6 API verification complete (see `docs/engine-reference/godot/modules/input.md`, verified 2026-05-12 against Godot 4.6 stable docs + engine source):
  - `InputEventScreenTouch.canceled` field — confirmed exact spelling `canceled` (single-l), bool, set by `set_canceled()`.
  - `_unhandled_input` during pause — confirmed `process_mode = PROCESS_MODE_ALWAYS` gates input callbacks the same way as `_process`. No workaround needed; original assumption was correct.
  - **CRITICAL NEW FINDING — platform asymmetry**: iOS does NOT set `canceled=true`; it emits `pressed=false` at exact sentinel `Vector2(-1, -1)` instead. Without handling this, the OS-interrupt path would silently fall through to `touch_ended` on iOS — producing ghost casts. Core Rule 8, Edge Cases (OS cancel), and AC #14 split into 14a/14b/14c/14d to cover both platforms with exact-sentinel detection. Engine reference at `docs/engine-reference/godot/modules/input.md` documents the source citations.

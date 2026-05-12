# Cast Direction & Aiming

> **Status**: In Design — Implementation-Gated on Dependencies
> **Author**: bozhang + Claude
> **Last Updated**: 2026-05-11
> **Implements Pillar**: Pillar 1 (Cast smart, not far) — primary; Pillar 3 (The water rewards attention) — secondary
> **Prototype Validation**: `prototypes/cast-direction-flow/REPORT.md` — PROCEED verdict 2026-05-11
> **Review**: NEEDS REVISION (2026-05-11) → REVISED (2026-05-11) — see `design/gdd/reviews/cast-direction-aiming-review-log.md`

> ⚠️ **Implementation Gate**: This GDD relies on two upstream systems that are not yet designed: **Stat Progression** (#7) and **Scene/Location Management** (#4). The third upstream dependency, **Touch Input System** (#1), was revised 2026-05-12 and re-reviewed the same day — its contract is locked. **Do not begin implementation of this system until Stat Progression has a GDD.** (Scene/Location Management's contribution is the rod grip position, which can be stubbed for a prototype if needed.)

> 📏 **Unit Convention**: All distances in this GDD are in **screen-space pixels**. `casting_distance`, `aim_direction` magnitudes, and all numeric examples assume pixels. Stat Progression GDD must conform to this unit when authored. (Resolved from review 2026-05-11.)

## Overview

The Cast Direction & Aiming system is the player-facing front-end of every cast. While the player touches and drags on screen, the system tracks the aim direction from the rod, clamps it to valid water-facing angles, and renders a visual aimer plus a range preview showing the reachable area — a translucent semicircle on the water bounded by the player's current `casting_distance` stat. On release, it commits the chosen direction and hands off to Cast Execution, which performs the actual lure travel.

Players feel this as **one continuous "aim → release → cast" gesture** — a single deliberate moment in which placement strategy is expressed. Without this system, the strategic-placement core of the game (Pillar 1: Cast smart, not far) has no input surface; the cast loop cannot begin.

## Player Fantasy

**The moment of intentional commitment.** Every cast begins with a small, deliberate ritual: you study the water, notice that lily pad cluster, and decide *that's where I'm putting my line.* The Cast Direction & Aiming system is the input surface for that decision. The player's job is to pick direction; the rod responds to their drag; the release is a commitment — once you let go, the cast is going where you aimed.

The feel target is **calm-focused-tactile**, not frantic:
- The drag is unhurried — the game waits for you to choose
- The aimer responds 1:1 to your finger; there is no input lag, no auto-snap, no aim-assist that overrides your choice
- The release is a quiet commit — the cast is in motion, but the player remains the author of where it went

**Reference moments** that capture the right feeling:
- The pause-and-aim moment in *Angry Birds* — you choose trajectory, then watch the consequence
- The cast moment in *Stardew Valley*'s fishing minigame — though Stardew uses a charge meter, the *gesture* of committing to a cast is the analogue
- The leap timing in *Alto's Adventure* — a single decision that defines the next several seconds of play

The fantasy explicitly serves **Pillar 1 (Cast smart, not far)**: by limiting the player's input to direction only, every cast becomes an intentional placement decision. Players who think before casting are rewarded; players who flail get random results. The fantasy is **thoughtful angler**, not **power gamer**.

## Detailed Design

### Core Rules

1. The player initiates aiming by **touching anywhere on screen**. The touch position is used for direction calculation only — not for positioning the cast.
2. While the player holds their touch, the system continuously computes the **aim direction** as a unit vector from the rod's grip position toward the current touch position.
3. The aim direction is **clamped to the upper hemisphere** (cast must go into the water). If the player drags below the rod (into the shore region), aim is clamped to *barely above horizontal* rather than reversed or invalidated.
4. The **range preview** is a translucent semicircle rendered from the rod, with radius equal to the current `casting_distance` stat. It visualizes the reachable area; the player can aim anywhere but the cast lands at the range edge.
5. The **aim is direction-only**. Cast distance is determined entirely by `casting_distance`. The player cannot extend or shorten the cast by dragging farther or closer.
6. The **aimer visual** (an arrow or line from the rod) rotates 1:1 with the touch position. No input lag, smoothing, snapping, or aim-assist overrides the player's choice. (Pillar 1: the player is the author of placement.)
7. On **touch release with a valid aim**, the cast is committed: the system emits `cast_committed(direction, distance_pixels)` and returns to Idle. Aim input is ignored until Cast Execution signals *cast resolved* and a brief cooldown elapses.
8. **Very brief, very still taps** (touches that fail *both* cancel thresholds — `cancel_threshold_time` AND `cancel_threshold_drag`, see Tuning Knobs and Formula 5) are treated as cancels, not commits. Protects against accidental casts. A long static hold is *not* a cancel — it commits on release (see Edge Cases).
9. **OS-interrupted touches always cancel**. The system listens for Touch Input's `touch_interrupted` signal (fires on incoming phone call, app switch, system alert — anything that causes Godot to mark a touch as `canceled`). On `touch_interrupted`, the system returns to Idle without emitting `cast_committed`, regardless of duration or drag distance. This prevents "ghost casts" — a cast committed because the player happened to be aiming when their phone rang.

### States and Transitions

Two states owned by this system:

| State | Description | Aimer visible? | Input accepted? |
|---|---|---|---|
| **Idle** | No active aim; rod at rest. | No | Touch initiates aiming |
| **Aiming** | Player is choosing direction; aimer + range preview rendered. | Yes | Drag updates aim; release commits or cancels |

Transitions:

| From | To | Trigger |
|---|---|---|
| Idle | Aiming | Touch detected AND no cast currently in flight AND not in cooldown |
| Aiming | Idle (cancel) | Touch released under the cancel threshold with no meaningful drag |
| Aiming | Idle (commit) | Touch released with a valid aim → emits `cast_committed` |

This system does NOT enter "cast in flight" or "cooldown" states — those belong to **Cast Execution**. This system simply *queries* whether a cast is in flight and blocks new aim input until told otherwise.

### Interactions with Other Systems

**Upstream dependencies:**

| Dependency | Data flowing IN | Interface |
|---|---|---|
| Touch Input System | Touch lifecycle signals (`touch_started`, `touch_ended`, `touch_interrupted`) + position/duration/cumulative_drag_distance via query API | Godot autoload, `_unhandled_input()` pipeline |
| Stat Progression | Current `casting_distance` value (in pixels) | Read-only query, polled while aiming |
| Scene / Location Management | Current rod grip position (the aim vector's origin) | Read-only query when aim begins |

**Downstream consumer:**

| Consumer | Data flowing OUT | Interface |
|---|---|---|
| Cast Execution | Committed aim direction (`Vector2`) + cast distance (pixels) | Event: `cast_committed(direction, distance_pixels)` emitted at commit |

**Sibling renderers**: in MVP, this system renders its own aimer + range preview. Splitting rendering into a dedicated CastAimerUI system is a Tier 2+ refactor option, not an MVP concern.

## Formulas

### Formula 1: Aim Direction

The `aim_direction` is the unit vector from rod grip to current touch position:

`aim_direction = normalize(touch_position - rod_grip_position)`

**Variables:**

| Variable | Symbol | Type | Range | Description |
|---|---|---|---|---|
| `touch_position` | t | Vector2 (pixels) | (0..540, 0..960) for portrait | Current finger / cursor position |
| `rod_grip_position` | g | Vector2 (pixels) | scene-defined | The rod's anchor point |
| `aim_direction` | a | Vector2 (unit) | each component in [-1, 1], \|a\|=1 | Output direction |

**Output Range:** unit vector in screen space.
**Example:** rod at (270, 870), touch at (400, 300). diff = (130, -570). length ≈ 584. normalized ≈ (0.222, -0.976) — pointing mostly upward and slightly right.

---

### Formula 2: Upper-Hemisphere Clamp

The aim is forced to point upward (into the water region):

```
if aim_direction.y > clamp_threshold:
    aim_direction.y = clamp_threshold
    aim_direction = normalize(aim_direction)
```

**Variables:**

| Variable | Symbol | Type | Range | Description |
|---|---|---|---|---|
| `aim_direction` | a | Vector2 (unit) | as in F1 | Input from F1; modified in place |
| `clamp_threshold` | T | float | [-0.20, 0.0] | Tuning knob; default `-0.05` (forces aim slightly above horizontal in Godot's Y-down coordinate system) |

**Output Range:** `aim_direction.y ≤ clamp_threshold` is guaranteed.
**Example:** raw aim (0.5, +0.3) (player dragged down-right into shore). After clamp: y=-0.05, then re-normalized to (0.995, -0.099).

---

### Formula 3: Cast Landing Position

Where the lure will land if the cast is committed now:

`cast_landing_position = rod_grip + aim_direction × casting_distance`

**Variables:**

| Variable | Symbol | Type | Range | Description |
|---|---|---|---|---|
| `rod_grip` | g | Vector2 (pixels) | scene-defined | Rod anchor |
| `aim_direction` | a | Vector2 (unit) | as in F2 | Final clamped aim |
| `casting_distance` | d | float (pixels) | [0, screen_height × 0.78] | Player's current stat |
| `cast_landing_position` | L | Vector2 (pixels) | screen-bounded | Computed landing point |

**Output Range:** any point on the upper-hemisphere semicircle of radius `d` centered on `rod_grip`.
**Example:** rod (270, 870), aim (0.222, -0.976), d = 528 px. L = (270 + 117, 870 − 515) = (387, 355).

---

### Formula 4: Range-Preview Arc Points

Points along the upper semicircle around the rod, used to draw the translucent range preview:

```
for i in [0, N]:
    θ_i = π + (i / N) × π
    range_arc_points[i] = rod_grip + (cos(θ_i), sin(θ_i)) × casting_distance
```

**Variables:**

| Variable | Symbol | Type | Range | Description |
|---|---|---|---|---|
| `θ_i` | θ | float (radians) | [π, 2π] | Angle of arc point i (upper semicircle in Godot Y-down coords) |
| `N` | N | int | [16, 48] | Segment count for arc smoothness; default **30** |
| `casting_distance` | d | float (pixels) | as F3 | Arc radius |

**Output:** ordered list of `N+1` points forming the upper-semicircle outline. Used both for the translucent polygon fill and the outline polyline.

---

### Formula 5: Cancel Detection

The cast is cancelled (no commit) if the touch was very brief AND had no meaningful drag:

`is_cancel = (touch_duration < cancel_threshold) AND (cumulative_drag_distance < drag_threshold)`

**Variables:**

| Variable | Symbol | Type | Range | Description |
|---|---|---|---|---|
| `touch_duration` | Δt | float (seconds) | [0, ∞) | From Touch Input's `touch_ended.duration` payload, or query API; time from touch_down to touch_up |
| `cancel_threshold` | T_c | float (seconds) | [0.05, 0.30] | Tuning knob; default **0.12** |
| `cumulative_drag_distance` | Δd | float (pixels) | [0, ∞) | From Touch Input's `touch_ended.cumulative_drag_distance` payload, or query API; total non-dead-zone movement of touch position during the touch |
| `drag_threshold` | T_d | float (pixels) | [5, 30] | Tuning knob; default **15** |
| `is_cancel` | — | bool | true / false | If true, no `cast_committed` emitted |

**Output:** boolean. If TRUE, system returns to Idle without emitting `cast_committed`. If FALSE, the cast commits with the most recent aim direction. **Note**: OS-interrupted touches (Touch Input emits `touch_interrupted` instead of `touch_ended`) always cancel — Formula 5 is not evaluated for those; see Core Rule 9 below.
**Example:** quick stray finger touch — duration 0.05s, cumulative_drag_distance 3px → `is_cancel = true` → ignored. Deliberate aim — duration 1.2s, cumulative_drag_distance 80px → `is_cancel = false` → commits.

## Edge Cases

- **If `touch_position` equals `rod_grip_position` exactly** (touch directly on the rod anchor — the subtraction yields a zero vector): hold the last valid `aim_direction`. If no prior aim exists this session, default to `Vector2(0, -1)` (straight up).
- **If a second finger touches the screen while the first is still down** (multi-touch): the system ignores the second touch entirely. Only the first finger's events drive aim. The second finger is observed but does not change aim or commit.
- **If `casting_distance` updates mid-aim** (e.g., a level-up extends the player's reach while the player is in the middle of aiming): the range preview redraws next frame with the new radius; the current `aim_direction` is unchanged. On release, the cast uses the *new* (post-update) distance. **Design choice (live update, not snapshot)**: the player sees their reach grow in real-time, which is the satisfying feedback the level-up moment is supposed to deliver. Snapshotting the distance at aim-start would make the level-up feel disconnected. This is intentional, not incidental.
- **If the touch goes off-screen during a drag** (some platforms still report position outside viewport): the aim direction is still computed normally — the unit vector points in the direction of the off-screen touch. No special clamp on touch position; only the aim direction is clamped (Formula 2).
- **If the game is paused or backgrounded while the player is aiming**: the system pauses with the current aim state preserved. On resume, the aimer + range preview re-appear in the same position; touch_duration timing pauses with the game (does not double-count the away-time toward the cancel threshold).
- **If `casting_distance == 0`** (defensive — this should be prevented by Stat Progression but the system must not crash): range preview is invisible (zero radius). The cast still fires but the lure lands at the rod position. Silently degrade; this is a data error that the Stat Progression GDD must prevent at its source (initial stat value must be > 0).
- **If the clamped aim_direction is near-horizontal** (e.g., `y = clamp_threshold = -0.05`): the cast is legal — the lure lands at the side edge of the reachable area. This is not an error; players learn that very flat aims produce very-side casts. No fix needed unless playtest shows it's unintuitive.
- **If touch is released during a cast in flight** (player tries to start a new aim while the previous lure is still traveling): the release is ignored. Aim input is blocked until Cast Execution signals *cast resolved* and the cooldown elapses. The touch event passes through harmlessly.
- **If two simultaneous commit triggers fire** (e.g., touch release AND space-key press in the same frame): use a single guard flag — the first one wins; the second is ignored. No double-emit of `cast_committed`.
- **If the player holds the touch still for a long duration without dragging, then releases** (e.g., 3+ seconds, finger never moves more than a few pixels): the cast **commits** in the direction implied by the initial touch position. Rationale: a long hold is deliberate, not accidental. The AND-gate cancel detection (Formula 5) only treats *both* short-duration AND minimal-drag as cancel; long static holds fall outside both branches. Flag for playtest — if testers consistently feel "I held but didn't mean to cast", reconsider with an OR-gate or max-duration carve-out.

## Dependencies

### Hard dependencies (system cannot function without these)

| Dependency | What it provides | Status |
|---|---|---|
| **Touch Input System** | Raw touch / drag / release events with screen position | **Approved 2026-05-12 (second-pass revision)** — contract locked |
| **Stat Progression** | `casting_distance` value (current player stat, in pixels) | Undesigned (system #7) — provisional |
| **Scene / Location Management** | Rod grip position (anchor for the aim vector's origin) | Undesigned (system #4) — provisional |

> **Touch Input contract (locked 2026-05-12)**: Touch Input GDD is now approved (review 2026-05-12). This system reads its `touch_started`, `touch_ended(position, duration, cumulative_drag_distance)`, and `touch_interrupted(position)` signals, and polls `current_touch_position()`, `touch_duration()`, `cumulative_drag_distance()`, `is_touching()`. **Joint constraint with Touch Input's `touch_dead_zone_px`**: `cancel_threshold_drag` (15 px default) + dead-zone (3 px default) = 18 px raw cancel envelope for the player. Tuning one requires re-evaluating the other.
>
> **Still-provisional**: Stat Progression exposes `casting_distance: float` (pixels) as read-only; Scene Management exposes `rod_grip_position: Vector2` (pixels) as read-only.

### Soft dependencies (enhanced by but works without)

| Dependency | What it adds | Status |
|---|---|---|
| **Audio System** | Sound cues for aim-start, aim-commit, and cancel | Undesigned (system #5) — affects polish, not function |
| **Cast Execution** | Listener for the `cast_committed` event; without it, the event fires harmlessly | Undesigned (system #8) — system still validates its own aim mechanics in isolation |

### Depended on by

| Consumer | What it consumes | Required? |
|---|---|---|
| **Cast Execution** | `cast_committed(direction, distance)` event | Hard — Cast Execution cannot function without this signal |
| **Fish Spawn / Bite & Strike / Fight / Stat Progression** | Indirectly through Cast Execution lifecycle | Soft — these are downstream of Cast Execution, not direct consumers of this system |

### Interface contracts owned by THIS GDD

| Contract | Type | Purpose |
|---|---|---|
| `cast_committed(direction: Vector2, distance_pixels: float)` | Event (signal) | Emitted when player commits a cast |
| `is_aiming() -> bool` | Read-only query | For sibling systems that need to know if player is currently aiming (e.g., audio cue triggers, debug viz) |
| `current_aim_direction() -> Vector2` | Read-only query | Exposes the live aim direction for read-only consumers |

### Interface contracts owned BY OTHER systems (read by this one)

| Read-from | Property / event | Owner |
|---|---|---|
| Touch Input | `touch_started`, `touch_ended`, `touch_interrupted` signals; `current_touch_position()`, `touch_duration()`, `cumulative_drag_distance()`, `is_touching()` query API | Touch Input System GDD (approved 2026-05-12) |
| Stat Progression | `casting_distance: float` (pixels) | Stat Progression GDD |
| Scene / Location Management | `rod_grip_position: Vector2` (pixels) | Scene Management GDD |
| Cast Execution | `cast_resolved` signal — fires when a cast completes (landed OR broke off) | Cast Execution GDD |

> The `cast_resolved` signal from Cast Execution is what this system listens for to re-enable aim input after a cast (Core Rule 7). Cast Execution GDD must commit to emitting this signal on every cast termination, regardless of success or failure.

## Tuning Knobs

| Knob | Default | Safe Range | Effect | If too high | If too low |
|---|---|---|---|---|---|
| `clamp_threshold` | **-0.05** | -0.20 to 0.0 | How "upward" the clamped aim must be (Formula 2) | Cast forced too steep — players can't aim sideways at all | Cast goes too horizontal; lure lands at extreme side edges |
| `cancel_threshold_time` | **0.12 s** | 0.05 s to 0.30 s | Touch duration below which a tap counts as cancel (Formula 5) | Players struggle to commit; deliberate quick aims keep getting cancelled | Accidental quick taps commit casts the player didn't intend |
| `cancel_threshold_drag` | **15 px** | 5 to 30 px | `cumulative_drag_distance` below which a tap counts as cancel (Formula 5). **Coupled with Touch Input's `touch_dead_zone_px` (3 px default)** — sub-pixel jitter is filtered upstream before reaching this threshold, so the effective intentional-drag-to-commit margin is `cancel_threshold_drag - touch_dead_zone_px = 12 px`. Tuning either knob requires re-evaluating the other. | Quick aim micro-adjustments lose commit (frustrating) | Random stray touches commit accidentally |
| `range_preview_segments` | **30** | 16 to 48 | Smoothness of the range-preview arc (Formula 4) | Minor frame-time cost (negligible at 48) | Arc looks jagged / polygonal |
| `range_preview_fill_alpha` | **0.28** | 0.10 to 0.50 | Opacity of the translucent range area | Range overlay obscures fish, water, structures | Range area becomes invisible; player can't read their reach |
| `cast_cooldown` | **0.2 s** | 0.0 to 0.5 s | Grace period after a cast resolves before next aim is allowed | Players feel sluggish; can't rapid-cast | Accidental immediate re-casts before player processes the previous one |
| `aimer_length_scale` | **1.0** | 0.5 to 1.2 | Length of the aim-line indicator as a fraction of `casting_distance` | Aimer extends past the reachable range; may mislead the player about where the cast lands | Aimer too short; doesn't communicate full reach to player |

**Knob interactions worth noting:**

- `cancel_threshold_time` and `cancel_threshold_drag` are AND-gated (both must be below threshold to cancel). Tuning one without the other shifts the cancel envelope. If you raise both, almost everything cancels; if you lower both, almost nothing does.
- `range_preview_fill_alpha` and the per-location color palette interact — on Riverside's warm-green water, alpha of 0.28 may read differently than on Deep Lake's cool teal. Re-check per location.

**No values cross over from other systems** as tuning knobs — `casting_distance` is owned by Stat Progression, not this GDD. This system reads it; it does not tune it.

## Visual/Audio Requirements

### Visual Elements

| Element | Trigger | Visual spec | Notes |
|---|---|---|---|
| **Aimer line** | Visible while Aiming state is active | A solid line from `rod_tip` in `aim_direction`, length = `casting_distance × aimer_length_scale`. Stroke ~2.5 px, color: warm gold (art bible: `#E8B547` accent) | Rotates 1:1 with finger; redraws every frame while aiming |
| **Aimer arrowhead** | Visible at end of aimer line | Two short strokes (≈12 px) at the line's endpoint, forming a chevron pointing in `aim_direction` | Same color as the line |
| **Range preview fill** | Visible while Aiming | Upper-semicircle polygon around `rod_grip`, radius = `casting_distance`, fill = calm blue with `range_preview_fill_alpha` | Drawn under fish silhouettes but over the water wash |
| **Range preview outline** | Visible while Aiming | Polyline along the upper-semicircle edge, stroke ~1.0 px, color: ink-faint (`#5C5048` low alpha) | Helps define the reach edge |
| **Rod direction indicator** | Always visible (rod rotates with aim) | The rod sprite itself rotates from neutral (straight up) to `aim_direction` while aiming. When Idle, rod is at neutral. | Animation curve: instant follow during aiming; smooth-return when entering Idle |

### Audio Cues

| Event | Cue character | Loudness | Duration |
|---|---|---|---|
| **Aim start** (touch_down enters Aiming) | Subtle UI "tap" — soft, immediate | Low | ≤ 100 ms |
| **Aim commit** (release fires `cast_committed`) | Satisfying "swish" or "whip" — the rod casts | Medium | 200–400 ms (may overlap with Cast Execution audio) |
| **Aim cancel** (release without commit) | Soft "untap" — softer than the start cue | Very low | ≤ 100 ms |
| **Aim idle** | — | — | No audio while not aiming; ambient location audio plays underneath |

### Production notes

- All audio cues should respect the master mix per the Audio System GDD (undesigned — provisional)
- The cast-commit cue should "land" in time with the lure leaving the rod tip — handoff timing coordinated with Cast Execution
- These audio events are short and frequent; ensure they don't crowd the ambient water sound

> 📌 **Asset Spec** — Visual/Audio requirements are defined. After the art bible is approved (already done — Fishing Man art bible, 2026-05-11), run `/asset-spec system:cast-direction-aiming` to produce per-asset visual specs and generation prompts from this section.

## UI Requirements

### Player Flow

1. Player taps screen anywhere → **Aiming** state begins → aimer + range preview appear
2. Player drags → aimer rotates 1:1; the player can see exactly where the cast will land (the aim line points to the cast landing position on the range edge)
3. Player releases → if deliberate (above cancel thresholds), `cast_committed` fires; if very brief tap, cancel
4. After a cast resolves, the player can begin aiming again immediately (subject to `cast_cooldown`)

### Touch Ergonomics

- **Touch region**: anywhere on screen is valid for starting aim. There is no specific "aim handle" or designated zone — convenient for thumb reach on any-size phone (one-handed friendly).
- **Multi-finger**: only one finger drives aim; additional fingers ignored.
- **Long-press**: not used as a separate gesture. Hold-and-drag IS the aim. Cancel requires very brief touch + minimal drag.

### State Communication

| State | Visual cue | Why |
|---|---|---|
| **Idle** | Aimer hidden; range preview hidden; rod at neutral (straight up). World is "at rest." | Player should know nothing is "in flight" / nothing is being aimed |
| **Aiming** | Aimer visible; range preview visible; rod rotated. World visually says "we are choosing where to cast." | Unambiguous — the player is mid-decision |
| **Transitions** | Instant (no fade) on both Idle→Aiming and Aiming→Idle | Crisp state changes; ambiguous "in-between" looks would confuse the commit moment |

### Accessibility

- **No precision required**: the player picks direction within a generous tolerance. Fine motor control is not required.
- **No time pressure**: aim can be held indefinitely; the game does not punish slow players.
- **Color-blind safety**: the aimer's warm gold (`#E8B547`) and the range preview's calm blue (`#7BA5C2`) have distinct greyscale values; the aimer is also distinguishable by shape (an arrow with a clear pointing direction).
- **Reduced motion** (future): the rod's smooth-return animation could be disabled in an accessibility setting. Not in MVP.

### Cross-system UI handoffs

- **Stats / HUD UI** displays `casting_distance` and `rod_strength`. This system reads `casting_distance` from Stat Progression but does not draw it on screen — HUD UI's job.
- **Fight UI** takes over when Cast Execution signals `cast_resolved` and a fish bites. This system's UI is fully dismissed at that point.
- **Catch Log UI** is independent. This system's aim does not need to coordinate (the catch log is closed while aiming is possible).

> 📌 **UX Flag — Cast Direction & Aiming**: This system has direct on-screen UI requirements. In pre-production, run `/ux-design` to produce a UX spec for the aimer + range preview ergonomics before writing stories. Stories that touch this system's UI should cite `design/ux/cast-aiming-ux.md` (once created), not this GDD directly.

## Acceptance Criteria

### Per Core Rule (Section: Detailed Design)

1. **GIVEN** the game is in Idle state, **WHEN** the player touches any point on screen, **THEN** the system enters Aiming state and the aimer + range preview become visible within 1 frame.

2. **GIVEN** the system is in Aiming state, **WHEN** the player drags the touch to a new screen position, **THEN** the `aim_direction` updates to point from `rod_grip` toward the new touch position within 1 frame (no smoothing or lag).

3. **GIVEN** the system is in Aiming state, **WHEN** the player drags the touch below the rod (`touch.y > rod_grip.y`), **THEN** the `aim_direction.y` is clamped to ≤ `clamp_threshold` (= -0.05 default) — the cast still points upward.

4. **GIVEN** the system is in Aiming state, **WHEN** the range preview is rendered, **THEN** its radius equals the current `casting_distance` value queried from Stat Progression.

5. **GIVEN** the player is aiming with `casting_distance = 528 px`, **WHEN** the player drags the touch to a position 800 px from the rod, **THEN** the cast (on release) still lands at exactly 528 px from the rod — not 800.

6. **GIVEN** the system is in Aiming state, **WHEN** the player rotates their touch by an arbitrary angle, **THEN** the aimer rotates by the same angle (1:1, no auto-snap, no smoothing).

7. **GIVEN** the system is in Aiming state with a held touch exceeding both `cancel_threshold_time` AND `cancel_threshold_drag`, **WHEN** the player releases the touch, **THEN** `cast_committed(aim_direction, casting_distance)` is emitted exactly once.

8. **GIVEN** the system is in Aiming state, **WHEN** the player releases the touch with duration < `cancel_threshold_time` AND drag < `cancel_threshold_drag`, **THEN** no `cast_committed` event is emitted and the system returns to Idle.

### Per Formula (Section: Formulas)

9. **GIVEN** `touch_position = (400, 300)` and `rod_grip = (270, 870)`, **WHEN** `aim_direction` is computed (Formula 1), **THEN** `aim_direction ≈ (0.2224, -0.9750)` within ±0.001 tolerance.

10. **GIVEN** raw `aim_direction.y = +0.3` (player dragged into shore), **WHEN** the clamp is applied (Formula 2), **THEN** `aim_direction.y = -0.05` and the vector is re-normalized to unit length (`|aim_direction| = 1.0` within ±0.001).

11. **GIVEN** `rod_grip = (270, 870)`, `aim_direction = (0.222, -0.976)`, `casting_distance = 528`, **WHEN** the cast lands (Formula 3), **THEN** the lure position is at `(387, 355)` within ±0.5 pixels.

12. **GIVEN** `casting_distance = 528` and `range_preview_segments = 30`, **WHEN** the range preview is drawn (Formula 4), **THEN** the arc consists of exactly 31 points evenly distributed in θ ∈ [π, 2π] at radius 528 from `rod_grip`.

13. **GIVEN** a touch with `touch_duration = 0.05 s` AND `cumulative_drag_distance = 3 px` (both below thresholds), **WHEN** the touch releases (Formula 5), **THEN** `is_cancel = true` and no `cast_committed` is emitted.

### Cross-System

14. **GIVEN** Cast Execution is currently playing the cast-arc animation (a cast is in flight), **WHEN** the player attempts to start a new touch, **THEN** the touch is ignored — no Aiming state transition occurs.

15. **GIVEN** `casting_distance` changes from 528 to 700 during an active aim, **WHEN** the next frame renders, **THEN** the range preview redraws at radius 700 within 1 frame.

### OS Interrupt

15b. **GIVEN** the system is in Aiming state with a held touch of `touch_duration = 1.2 s` and `cumulative_drag_distance = 80 px` (would otherwise commit per Formula 5), **WHEN** Touch Input emits `touch_interrupted(position)` (simulating an incoming phone call or OS-level touch cancellation), **THEN** `cast_committed` is NOT emitted, the system returns to Idle, and the aimer + range preview are dismissed **using the same visual transition as a player-initiated cancel** (no abrupt disappearance, no missing cue). When audio is specced (see Open Questions on haptics/audio), the same `aim_cancel` cue must fire on `touch_interrupted` as on player-initiated cancel — OS interrupts must be indistinguishable from player cancels at the feedback layer. (Per Core Rule 9 — prevents ghost casts AND prevents silent-dismissal UX bugs.)

### Long-Press

17. **GIVEN** the system is in Aiming state, **WHEN** the player touches a single position, holds for 5.0 s without moving (drag = 0 px), and releases, **THEN** `cast_committed(aim_direction, casting_distance)` is emitted with the `aim_direction` derived from the initial touch position. *(Validates the AND-gate cancel rule: only short-AND-still touches cancel.)*

### Performance

16. **GIVEN** the game is running on the iPhone 11 baseline device, **WHEN** the system is rendering the aimer + range preview during an active aim, **THEN** this system's per-frame contribution to total frame time remains under **2 ms** (well within the 16.6 ms 60 fps budget, leaving headroom for the rest of the scene).

## Open Questions

Open design / implementation questions surfaced during this GDD. Each has an owner and a target resolution moment.

| Question | Owner | Resolve when |
|---|---|---|
| Should the aim line be full `casting_distance` length or shorter (e.g., 0.7×) to reduce visual clutter? | game-designer | First playtest of the production system; tune `aimer_length_scale` knob (default 1.0; range widened to [0.5, 1.2] for headroom). |
| Should there be haptic feedback on touch_start, aim_commit, cancel? Mobile haptics are powerful but absent in MVP for scope reasons. | audio-director | When the Audio System GDD is authored. Coordinate which events get haptics + audio. |
| Should the aim direction be smoothed (e.g., low-pass filter) if the player's touch jitters? Current spec is 1:1 (no smoothing). | gameplay-programmer | First playtest. If jitter is visually distracting, add a small smoothing buffer. |
| What if the computed cast landing position is off-screen (very wide aim at HIGH `casting_distance`)? Clamp to screen bounds, or allow off-screen landing with visual feedback? | game-designer | Resolve when Fish Spawn / Cast Execution GDD is authored — depends on where fish can spawn relative to screen edges. |
| Should there be an "aim-assist" accessibility option (auto-snap toward structures within a radius)? | accessibility-specialist | Tier 2+ — not in MVP. Revisit during the post-MVP accessibility pass. |
| Cast Execution's `cast_resolved` signal contract — what payload (success/break-off flag? landing position? species ID?) does it carry, and is it always emitted? | systems-designer | When Cast Execution GDD is authored. This GDD requires the signal to fire on every cast termination; payload shape is Cast Execution's call. |

**Resolved during review 2026-05-11:**
- ✅ Unit ambiguity: `casting_distance` is in pixels (see Status banner).
- ✅ Rod rotation: rod sprite rotates with aim (locked in Visual/Audio table).
- ✅ Long-press-no-drag: holding still and releasing commits a cast (AND-gate behavior intentional — see Edge Cases and AC #17).

**Updated during Touch Input review 2026-05-12 (bidirectional):**
- ✅ Naming aligned: Formula 5 variable renamed `drag_distance` → `cumulative_drag_distance` to match Touch Input's canonical signal payload and query API.
- ✅ Touch Input contract locked (no longer provisional) — see Dependencies section.
- ✅ Joint constraint documented: `cancel_threshold_drag` couples with Touch Input's `touch_dead_zone_px`.
- ✅ OS-interrupt handling added: Core Rule 9 + AC #15b — `touch_interrupted` signal listener prevents ghost casts.

**Updated during Touch Input re-review 2026-05-12 (bidirectional, second pass):**
- ✅ Implementation Gate banner refreshed — Touch Input removed from "not yet designed" list.
- ✅ Dependencies table — Touch Input row status updated from "Undesigned (provisional)" to "Approved 2026-05-12 — contract locked."
- ✅ AC #15b strengthened — OS-cancel dismissal must use the same visual transition (and, when audio is specced, the same audio cue) as a player-initiated cancel. Closes the silent-dismissal UX gap.

# Scene / Location Management

> **Status**: In Design
> **Author**: user + claude (game-designer + godot-specialist + systems-designer pending)
> **Last Updated**: 2026-05-12
> **Implements Pillar**: Foundation — indirectly enables Pillar 3 (Water Rewards Attention) by managing per-location scenes and Pillar 4 (Silence is a Feature) by gating banners to non-disruptive moments
> **Scope Depth**: Medium (per /design-system invocation 2026-05-12) — all 8 sections substantive, edge cases scoped to MVP-only concerns

> **Architecture lock**: Rule 8's Foundation→gameplay signal-subscription pattern is locked by [ADR-001](../../docs/architecture/ADR-001-foundation-gameplay-signal-inversion.md). Cast Execution (#8) and Fight System (#12) GDDs may be authored against this contract.

## Overview

**Scene / Location Management** is the foundation system that owns *which location the player is at* and the act of moving between locations. In MVP, the game has two locations — `riverside_pond` (where the player starts) and `deep_lake` (unlocked when `casting_distance` crosses the unlock threshold owned by Location Unlock #13) — and travelling between them is the only navigation the game offers. The system loads the destination location scene, unloads the prior one, holds the active location identifier in memory, and exposes a small, read-only contract to downstream systems that need to know either (a) which location is currently active and where the rod is anchored inside it, or (b) whether the main gameplay screen is currently "idle" — i.e., the player is not mid-cast, mid-fight, or mid-modal — so that disruptive UI such as the save-recovery banner appears only at moments that won't break the rhythm. To the player, this system is invisible by design: the locations themselves are felt, but the act of "managing scenes" is not. Without this system, locations cannot exist as separable spaces, the spatial progression that anchors Pillar 3 ("the water rewards attention") has nowhere to live, and the cast-aim / save-banner systems lose their reference point for "where am I right now and is it okay to interrupt?"

## Player Fantasy

Two places. The pond, where the player learned that placement beats distance. The lake, where the placement they learned has to land twice as far out. Crossing between them is crossing a threshold — the game is bigger on one side than the other, and the player can feel which side they're on the moment the scene resolves.

This is an **indirect fantasy**. Locations are felt as *the shape of the player's current world*. Early game, the world is the pond. Late game, the world is the lake. The player doesn't feel two scenes — they feel a world that got bigger. What's felt: the scale and stakes of where they are. What's not felt: that the system is loading one scene and unloading another, or that `active_location_id` is a string.

**Pillar tie**: Pillar 1 (*Cast Smart, Not Far*) and Pillar 2 (*Every Fish Makes You Stronger*). The two locations *encode* the progression curve in space — Pond = close-range placement; Lake = the same skill at greater distance with bigger stakes. The threshold itself is the readable proof that the player got stronger.

**Reference behavior**: *Stardew Valley* (the farm, the beach, and the forest each feel like different places with different rules, and the transitions between them are invisible) is the closest in-genre tonal match. *Hollow Knight*'s Dirtmouth-to-Crystal-Peak transition is the design pattern outside our genre — costs nothing to cross, feels like everything. Counter-example to avoid: an open-world game where every biome is technically distinct but emotionally the same because the player crossed in via fast travel from a menu.

**What would break this fantasy** — each is a player-felt failure first, an engineering anti-pattern second. (The "mid-cast modal interrupts the rhythm" failure is owned by Save & Persistence's Section B; not duplicated here.)

- *The player unlocks Deep Lake and it feels like a skin swap on the pond instead of a new place with new rules.*
- *The player crosses from pond to lake mid-session and the casting feel is identical — same fish silhouettes, same tension, same everything.*
- *The unlock moment fires silently — the player doesn't know they just earned access to a new place.*
- *The player is at the lake and forgets the pond exists — there's no readable sense of "where I came from."*
- *The player returns to the pond after unlocking the lake and finds the pond feels diminished, like a tutorial they outgrew, rather than a place that still matters.*

## Detailed Design

### Core Rules

1. **Single active location.** At any runtime moment, exactly one location is active. `active_location_id: String` is the canonical identifier. It is never null or empty; it initializes to `"riverside_pond"` on first launch and on any read that fails to find a valid persisted value (see Edge Cases).

2. **Implementation pattern.** `SceneManager` is implemented as a **Godot Autoload** (Project Settings → Autoload, name `SceneManager`, file `res://src/core/scene_manager.gd`). It is the **second** Autoload in the project, ordered immediately after `SaveState` (Save's Rule 2 mandates SaveState first). `process_mode = PROCESS_MODE_INHERIT`. No `class_name` declaration (autoload-vs-`class_name` collision, same precedent as Touch Input and Save).

3. **Persistent shell scene.** The project's root scene is `Main.tscn` (`res://src/core/main.tscn`). It is the only root scene for the application's lifetime — `SceneTree.change_scene_to_file` / `change_scene_to_packed` are **never** called after boot (using them would destroy autoload children of root). `Main.tscn` contains exactly three siblings:

    - `LocationContainer: Node2D` — parent of the active location scene; its sole child is swapped on travel.
    - `HUD: CanvasLayer` (`layer = 10`) — Stats / HUD UI (#15) tree; persists across travel.
    - `FadeOverlay: CanvasLayer` (`layer = 100`) — full-screen `ColorRect(BLACK)` with `modulate.a` controlled by SceneManager for transitions; `mouse_filter = MOUSE_FILTER_STOP` on the ColorRect to absorb touches when opaque.

    Project convention: location scenes MUST NOT use a `CanvasLayer` with `layer > 50`, to guarantee FadeOverlay always renders on top.

4. **Boot sequence.** On app launch:

    1. `SaveState._ready()` completes first (Save Rule 2).
    2. `SceneManager._ready()` reads `active_location_id` from `SaveState.get_meta()` (META domain — see Rule 5).
    3. SceneManager resolves the location ID to a scene path via Location Catalog (#9). For MVP, a hardcoded `LOCATION_SCENE_PATHS: Dictionary[String, String]` constant inside SceneManager is acceptable; migrate to Location Catalog when that GDD lands. *Provisional.*
    4. SceneManager loads the PackedScene **synchronously** via `load(path)` (boot has no fade to hide latency; the player expects a brief launch wait).
    5. SceneManager instantiates and adds the location scene as the sole child of `LocationContainer`. State transitions BOOTING → LOADING_LOCATION → IN_LOCATION.
    6. **No fade on cold launch** — the world simply *is*, per Pillar 4 (same beat as Alto's slope at app open).

5. **Persistence: META domain.** `active_location_id` lives in the **META domain** of `progress.save` (owned by Save & Persistence #2). Rationale: META holds cross-session navigational/session state; mixing into LOCATIONS would conflate navigation with unlock progression. SceneManager:

    - **Reads** via `SaveState.get_meta() -> MetaData` (deep-copy per Save Rule 18; field accessed as `meta.active_location_id`).
    - **Writes** via:

        ```gdscript
        var meta = SaveState.get_meta()
        meta.active_location_id = target_id
        SaveState.set_meta(meta)
        SaveState.request_save(SaveState.DOMAIN_META)
        ```

    **⚠ Coordination action on approved GDD**: Save & Persistence's `MetaData` resource must add `active_location_id: String` field (default `"riverside_pond"`). Tracked in Open Questions as #SP-1.

6. **Save timing: on transition complete.** The META write fires when the transition completes (IN_LOCATION re-entered), **not** when it starts. If the app is force-killed mid-transition, the player reopens to the prior location — fully valid. Saving on transition-start would leave the saved state pointing at a location whose scene may have failed to load.

7. **Travel flow.** Canonical sequence:

    1. Player taps the HUD Travel button (Stats/HUD UI #15 owns the widget).
    2. SceneManager opens the **location picker** as a child of the HUD CanvasLayer; pushes a modal via Rule 8's ref-counted API.
    3. Picker renders all locations from Location Catalog. Locked locations appear at `modulate.a = 0.4` with a one-line unlock hint (e.g., `"Unlock: casting_distance ≥ 300 px"`). Unlock hint copy is owned by Location Catalog (#9); SceneManager renders what it's given.
    4. Tap on locked location: no-op (picker stays open; no error sound — Pillar 4).
    5. Tap on unlocked destination identical to current: dismiss picker silently.
    6. Tap on unlocked distinct destination: call `SceneManager.travel_to(destination_id)`; picker dismisses; modal pops; transition begins.

8. **`main_screen_idle` predicate.** Read-only computed property:

    ```
    main_screen_idle == (
        state == IN_LOCATION
        AND _cast_idle    # signal-cached from CastExecution.cast_state_changed
        AND _fight_idle   # signal-cached from FightSystem.fight_state_changed
        AND _modal_count == 0
    )
    ```

    - `_cast_idle`, `_fight_idle` are cached bools updated by handlers on `CastExecution.cast_state_changed(is_active: bool)` and `FightSystem.fight_state_changed(is_active: bool)`. Both signals are a **contractual obligation** on those systems' downstream GDDs — must fire on every state change.
    - `_modal_count: int` is a ref-count incremented by `SceneManager.push_modal()` and decremented by `SceneManager.pop_modal()`. Any system with a modal (Settings #18, Catch Log UI #17, SceneManager's own picker) calls these. Negative count is a debug-build `assert`.
    - Boot defaults: `_cast_idle = true`, `_fight_idle = true`, `_modal_count = 0`. Cast Execution and Fight System should emit their state signal during their own `_ready()` to establish ground truth.
    - **Note on dependency direction**: SceneManager (Foundation tier) subscribing to gameplay-tier signals (Cast Execution, Fight System) inverts the layered-dependency convention. For MVP this is accepted; flag for future architecture review — alternative is a shared `GameState` autoload that both tiers write to. See Open Question #ADR-1.

9. **Travel button enabled logic.** The Travel button is enabled **iff** `state == IN_LOCATION` AND `_fight_idle == true`. Disabled during BOOTING / TRANSITIONING (state-gated) and during active fights (prevents accidental fight-abandon — user-decided UX). Not gated by `_cast_idle` — traveling implicitly cancels an in-flight aim; the player chose to abandon the aim by tapping Travel.

10. **Transition atomicity.** During TRANSITIONING:

    - `main_screen_idle = false` (state guard in Rule 8).
    - Travel button disabled (Rule 9).
    - `LocationContainer`'s children are exclusively managed by SceneManager — no other system may add or free children.
    - All input on the gameplay layer is absorbed by `FadeOverlay`'s ColorRect (`mouse_filter = MOUSE_FILTER_STOP`).
    - The scene swap happens at full opaque alpha — the player never sees two scenes overlapping or a partial scene.

11. **Transition sequence.** Per `travel_to(target_id)`:

    1. Assert `state == IN_LOCATION` and `_fight_idle == true` (defensive — the button should have prevented this otherwise).
    2. State → TRANSITIONING; emit `transition_started(from_id, to_id)`.
    3. Begin threaded load: `ResourceLoader.load_threaded_request(target_path)` ([Godot 4.6 docs](https://docs.godotengine.org/en/stable/classes/class_resourceloader.html#class-resourceloader-method-load-threaded-request)).
    4. Fade out: `var t = create_tween(); t.tween_property(fade_rect, "modulate:a", 1.0, 0.4); await t.finished`.
    5. Poll `ResourceLoader.load_threaded_get_status(target_path)`; if not `THREAD_LOAD_LOADED`, hold black silently until it is (no "Loading…" copy — Rule 12).
    6. On failure status (`THREAD_LOAD_FAILED` or `THREAD_LOAD_INVALID_RESOURCE`): enter Rule 13.
    7. Fetch: `var packed = ResourceLoader.load_threaded_get(target_path) as PackedScene`. Instantiate: `var new_scene = packed.instantiate()`. If `new_scene == null`: enter Rule 13. Free prior: `LocationContainer.get_child(0).queue_free()`. Add: `LocationContainer.add_child(new_scene)`.
    8. `await get_tree().process_frame; await get_tree().process_frame` — two frames at full black for GPU texture upload + new-scene `_ready()` to complete behind the opaque overlay (hides first-instance instantiation stutter; engine-programmer's pattern).
    9. Update `active_location_id`; write to META + `request_save(DOMAIN_META)` per Rules 5/6.
    10. Fade in: `t = create_tween(); t.tween_property(fade_rect, "modulate:a", 0.0, 0.4); await t.finished`.
    11. State → IN_LOCATION; emit `transition_completed(target_id)`.

12. **No loading UI.** No "Loading…" copy, spinner, progress bar, or error dialog appears at any point during a transition or at boot. The black frame is the only affordance. Failures surface via signal (Rule 13), never via UI.

13. **Failure mode: load failure.** If the threaded load returns `THREAD_LOAD_FAILED` / `THREAD_LOAD_INVALID_RESOURCE`, or `instantiate()` returns null:

    1. Log the error (location ID + reason code) to stdout.
    2. Emit `location_load_failed(target_id, reason_code)` for a future debug overlay or analytics consumer (no consumer in MVP).
    3. Do **not** free the prior location's child — the ordering in Rule 11.7 guards this (free only AFTER successful instantiate).
    4. Fade back in to the prior location (`fade_rect.modulate.a` tween 1.0 → 0.0 over 0.4s).
    5. State → IN_LOCATION; `active_location_id` unchanged; no save write.
    6. Travel button re-enables.

14. **`rod_grip_position` exposure.** Each location scene root extends `LocationBase` (`@abstract` base class — Godot 4.5+ feature per `docs/engine-reference/godot/VERSION.md`):

    ```gdscript
    @abstract class_name LocationBase extends Node2D
    @abstract func get_rod_grip_position() -> Vector2
    ```

    Concrete implementation in each location's root script returns `$RodGrip.global_position`, where `RodGrip` is a designer-placed `Marker2D` child node. SceneManager exposes:

    ```gdscript
    func get_rod_grip_position() -> Vector2:
        if state != IN_LOCATION:
            return Vector2(-1, -1)  # sentinel; consumers must guard
        return _active_location_scene.get_rod_grip_position()
    ```

    When Location Catalog (#9) lands, the rod-grip data may migrate to per-location Resource metadata (`LocationData.rod_grip_offset`); the consumer-facing API (`SceneManager.get_rod_grip_position()`) stays identical.

15. **Boundary rules — what SceneManager does NOT own.**

    - Location *content* (sprites, painted backgrounds, ambient animation) — Side-view Scene Rendering (#14) + Location Catalog (#9).
    - Location *unlock rules* (threshold values, when an unlock fires) — Location Unlock (#13).
    - The Travel button *widget itself* — Stats / HUD UI (#15). SceneManager exposes the API the widget calls (`travel_to`) and the signals the widget subscribes to (`transition_started`, `transition_completed`).
    - Audio crossfade between locations — Audio System (#3). SceneManager emits `transition_started` / `transition_completed`; Audio System listens and owns the actual fade.
    - Fish behavior, spawn logic, water surface rendering, fight UI — all downstream.

### States and Transitions

| State | Description | `main_screen_idle` | Travel button | Touch input |
|---|---|---|---|---|
| **BOOTING** | App launched; SaveState loading; no scene mounted | `false` | Hidden | Blocked |
| **LOADING_LOCATION** | Loading + instantiating target location during boot or mid-transition | `false` | Hidden / disabled | Blocked / absorbed by FadeOverlay |
| **IN_LOCATION** | A location is active and the player can interact | Computed per Rule 8 | Enabled iff `_fight_idle` (Rule 9) | Routed to location + HUD |
| **TRANSITIONING** | Fade-out → scene swap → fade-in in progress | `false` | Disabled | Absorbed by FadeOverlay |

| From | To | Trigger | Side effects |
|---|---|---|---|
| BOOTING | LOADING_LOCATION | SaveState loaded; `active_location_id` resolved | Begin synchronous `load()` + `instantiate()` of boot location |
| LOADING_LOCATION | IN_LOCATION | Location scene `_ready()` complete + one `process_frame` after `add_child` | Emit `boot_completed(location_id)` |
| IN_LOCATION | TRANSITIONING | `travel_to(target_id)` with valid unlocked destination ≠ current | Emit `transition_started`; disable Travel button; push transition modal flag |
| TRANSITIONING | IN_LOCATION (success) | Fade-in tween `finished` after successful swap | Emit `transition_completed`; save META; enable Travel button; pop transition modal flag |
| TRANSITIONING | IN_LOCATION (failure rollback) | Threaded load returns failure status, or `instantiate()` returns null | Emit `location_load_failed`; prior scene remains mounted; enable Travel button; no save write |

No PAUSED, ERROR, or SHUTTING_DOWN state. App lifecycle is owned by SaveState (#2). Load failures are recoverable (Rule 13), not a separate state.

### Interactions with Other Systems

| System | Direction | Interface | Cardinality / Timing |
|---|---|---|---|
| **Save & Persistence (#2)** | Read | `SaveState.get_meta() -> MetaData` (`.active_location_id`) | Once at SceneManager `_ready()` |
| **Save & Persistence (#2)** | Write | `SaveState.set_meta(meta)` + `request_save(DOMAIN_META)` | Once per successful transition complete |
| **Save & Persistence (#2)** | Provides predicate | Save's banner-gating UI controller reads `SceneManager.main_screen_idle: bool` | Per-frame poll by Save's UI controller |
| **Cast Direction & Aiming (#6)** | Read query | `SceneManager.get_rod_grip_position() -> Vector2` | On aim begin (consumer-cached); also after each `transition_completed` |
| **Cast Execution (#8)** | Subscribe (signal in) | `CastExecution.cast_state_changed(is_active: bool)` → updates `_cast_idle` | On every cast state change |
| **Fight System (#12)** | Subscribe (signal in) | `FightSystem.fight_state_changed(is_active: bool)` → updates `_fight_idle` | On every fight state change |
| **Location Unlock (#13)** | Read (via Save) | `SaveState.get_locations().unlocked_locations: Array[String]` — checked in `travel_to()` and picker render | Per `travel_to()`; per picker open |
| **Location Catalog (#9)** | Read | Per-location metadata: `scene_path`, `display_name`, `unlock_hint_copy` | Once at boot (active location); once per picker open (all locations) |
| **Stats / HUD UI (#15)** | Calls into | `SceneManager.travel_to(destination_id: String) -> void` | Once per player Travel commit |
| **Stats / HUD UI (#15)** | Subscribe (signal in) | HUD listens to `SceneManager.transition_started`, `transition_completed` — gates Travel button enabled state | Per transition |
| **Audio System (#3)** | Emit (signal out) | `transition_started(from_id, to_id)`, `transition_completed(target_id)` | Per transition phase |
| **Settings (#18) / Catch Log UI (#17) / any modal owner** | Calls into | `SceneManager.push_modal()` / `pop_modal()` | Per modal lifecycle |
| **Touch Input (#1)** | None (no direct coupling) | — | SceneManager does not consume input directly; FadeOverlay absorbs input via `mouse_filter` during transitions |

## Formulas

This system has **no balance formulas** in the traditional sense (no scoring, no progression curves, no resource calculations). Numerical values that downstream systems depend on (`casting_distance` thresholds, fish difficulty, etc.) are owned elsewhere. The single quantifiable thing SceneManager owns is the transition timing budget — documented below to give Section H Acceptance Criteria a numerical bound to assert against.

### Formula 1: Transition Timing Budget

The `transition_total_time` formula describes the player-perceived duration of a successful location transition from `travel_to(target_id)` call to `transition_completed` signal emission:

`transition_total_time = fade_out_duration + max(load_wait, 0) + frame_settle_time + fade_in_duration`

**Variables:**

| Variable | Symbol | Type | Range | Description |
|----------|--------|------|-------|-------------|
| `fade_out_duration` | f_out | float (seconds) | 0.0–1.0 | Fade-to-black tween duration. Default 0.4s. Configurable per Section G. |
| `fade_in_duration` | f_in | float (seconds) | 0.0–1.0 | Fade-from-black tween duration. Default 0.4s. Configurable per Section G. |
| `load_wait` | w | float (seconds) | 0.0–∞ (bounded by Section G `load_timeout_seconds`) | Time spent after fade-out polling `ResourceLoader.load_threaded_get_status` until `THREAD_LOAD_LOADED`. Zero when the load completed during fade-out (typical for cached scenes). |
| `frame_settle_time` | s | float (seconds) | derived | Two `await get_tree().process_frame` calls after `add_child` (Rule 11.8). At 60fps: `s = 2 * (1.0 / 60.0) ≈ 0.0333s`. Scales inversely with render fps on slower devices. |

**Output Range:**

- **Best case** (scene already in `ResourceLoader` cache from prior visit, 60fps device): `0.4 + 0 + 0.033 + 0.4 = 0.833 s`
- **Typical case** (cold load on iPhone 11, MVP 2D location scene): `0.4 + 0.05–0.20 + 0.033 + 0.4 ≈ 0.88–1.03 s` — the `load_wait` range here is a **design target**, not a measurement. Verify on iPhone 11 baseline during alpha QA and revise this row + AC #26's tolerance if measured values land outside the projected band.
- **Worst case under load timeout** (cold load on baseline device, large painted-background scene): `0.4 + ~1.5 + 0.033 + 0.4 ≈ 2.33 s`
- **Timeout reached** (`load_wait` ≥ `load_timeout_seconds`, default 5.0s — see Section G): transition aborts via Rule 13 failure path; the formula no longer applies and total time becomes `0.4 + load_timeout_seconds + 0.4 ≈ 5.8 s` of black followed by fade-back to the prior location.

**Behavior at extremes:**

- `load_wait = 0` (scene cached or load completes during fade): the threaded load polling at Rule 11.5 immediately returns `THREAD_LOAD_LOADED`; no black-hold beyond `f_out`.
- `load_wait > 0` (load slower than fade-out): the black frame holds silently while load completes (Rule 12 — no "Loading…" UI). The player sees a black screen of duration `f_out + load_wait` followed by the swap and fade-in.
- `f_out = 0` AND `f_in = 0` (designer disables fades for testing): the swap happens within one frame; the player sees a 1-frame discontinuity. Not recommended for shipping builds — present for fast unit testing only.

**Worked example** — player taps Travel "Riverside Pond → Deep Lake" on iPhone 11, first visit this session, scene not cached:

| t | Event |
|---|---|
| 0.000s | `travel_to("deep_lake")` called; `ResourceLoader.load_threaded_request("res://locations/deep_lake.tscn")` fires; fade-out tween starts |
| 0.400s | Fade-out complete (screen fully black); poll `load_threaded_get_status` |
| 0.450s | `THREAD_LOAD_LOADED`; `load_threaded_get` returns PackedScene; prior child `queue_free()`; new scene instantiated + added |
| 0.467s | First `process_frame` await resolves; GPU has begun texture upload |
| 0.483s | Second `process_frame` await resolves; texture upload complete; `_ready()` chain finished |
| 0.483s | `active_location_id` updated; `set_meta` + `request_save(DOMAIN_META)` called (synchronous; SaveState debounces) |
| 0.483s | Fade-in tween starts |
| 0.883s | Fade-in complete; `transition_completed("deep_lake")` emitted; `state = IN_LOCATION` |

**Total perceived duration: 0.883s.** Player saw black from 0.40s through 0.48s (≈80 ms) before the fade-in began.

### Non-formulas (documented for completeness)

The following appear in Rules but are not formulas — they are set-membership tests, boolean composites, or constant-time queries with no derivation:

- `is_unlocked_destination(target_id) := target_id in SaveState.get_locations().unlocked_locations` (set membership; Rule 7.4)
- `is_no_op_travel(target_id) := target_id == active_location_id` (equality; Rule 7.5)
- `main_screen_idle := state == IN_LOCATION ∧ _cast_idle ∧ _fight_idle ∧ _modal_count == 0` (boolean composite; Rule 8)
- `travel_button_enabled := state == IN_LOCATION ∧ _fight_idle` (boolean composite; Rule 9)

No further math is owned by this system. Future formulas (e.g., per-location ambient particle density, water-surface ripple frequency) belong to Side-view Scene Rendering (#14) or Location Catalog (#9).

## Edge Cases

Each entry: **If [condition]**: [exact outcome]. *[rationale where non-obvious]*.

### Transition flow

1. **If the player taps Travel while a cast lure is in flight** (between cast commit and lure-land): SceneManager emits `travel_requested(from_id, to_id)` before fade-out begins. Cast Execution (#8) subscribes to this signal and synchronously calls its own `abort_active_cast()` — the cast is cancelled without counting as a catch attempt. SceneManager `await get_tree().process_frame` once after emission to let the abort settle, then proceeds with Rule 11.4 fade-out. *Rationale: the user-decided UX gates Travel on `_fight_idle`, not `_cast_idle` (Rule 9). A signal-based abort preserves the Foundation→gameplay dependency-direction convention (Cast Execution depends on Scene Mgmt's signal, not the reverse) and parallels the `transition_started` / `transition_completed` pattern.*

2. **If two `travel_to()` calls fire in quick succession** (e.g., a double-tap that bypasses the HUD's disable): the second call hits the R11.1 assert `state == IN_LOCATION` and fails defensively. In release builds, the assertion is logged and the call returns silently — no crash, no duplicate transition. *The HUD button disable (R9) should prevent this; the assert is defense-in-depth.*

3. **If `ResourceLoader.load_threaded_request(target_path)` is called when a load for `target_path` is already in flight**: SceneManager first checks `load_threaded_get_status(target_path)`; if status is `THREAD_LOAD_IN_PROGRESS`, the redundant request call is skipped and SceneManager proceeds directly to the polling step (R11.5). *Godot 4.6's `load_threaded_request` returns `ERR_ALREADY_IN_PROGRESS` rather than silently replacing the prior request — Rule 11 must guard the request call, not assume idempotency.*

4. **If the OS suspends the app during the fade-out tween or the two `process_frame` awaits** (iOS `NOTIFICATION_APPLICATION_PAUSED`, Android equivalent): the tween's wall-clock timer stops and resumes when the app returns. The player sees a slightly longer black screen — duration equal to the suspension. No save state is at risk because Rule 6 defers the META write to transition complete. `transition_completed` eventually fires normally. *The same behavior covers app-backgrounded-mid-transition under the SceneTree-pause-vs-OS-suspension distinction.*

### State validation

5. **If at boot `active_location_id` (loaded from META) is not a member of `SaveState.get_locations().unlocked_locations`**: SceneManager treats the persisted value as invalid, logs a warning, falls back to `"riverside_pond"`, and writes the corrected value back via Rule 5's set+save pattern. *Can occur after a save recovery where META survived but LOCATIONS was reset to defaults — rare but recoverable.*

6. **If at boot `active_location_id` resolves to a scene path whose file does not exist on disk** (e.g., asset bundle mismatch, provisional location ID that never shipped): the synchronous `load(path)` at Rule 4.4 returns null. SceneManager logs the error, falls back to `"riverside_pond"` (which is guaranteed shipped per game-concept MVP), and retries the load. If the fallback also fails, the app exits with a fatal error to the engine — there is no playable state. *Boot has no prior scene to fall back to mid-transition (unlike Rule 13's in-session path); a fatal exit is the only honest response to a corrupted ship.*

7. **If a location scene's root script does not extend `LocationBase`** (designer error; broken `@abstract` inheritance): SceneManager's Rule 11.7 instantiate-step adds a runtime type check — `if not new_scene is LocationBase: queue_free(new_scene); enter Rule 13 failure path`. *Caught at the instantiate moment; treated as a load failure with rollback to prior location. The `@abstract` base class (Godot 4.5+) catches direct-instantiation errors at compile time; this runtime check catches a different class entirely.*

8. **If a location scene extends `LocationBase` but does not contain a `RodGrip: Marker2D` child node** (designer forgot to place it): the `LocationBase` concrete implementation guards with `if not has_node("RodGrip"): push_error("..."); return Vector2(-1, -1)`. Cast Direction & Aiming (#6) treats the sentinel value as "rod-grip not yet available" and skips its frame's aim computation. *A designer error, not a runtime player-visible bug, but failing with a sentinel rather than crashing keeps the player in a playable (if rod-less) state until the issue is fixed. Acceptance criterion verifies sentinel presence on missing-Marker2D scenes.*

### Cross-system contract

9. **If Cast Execution (#8) or Fight System (#12) never emit `cast_state_changed` / `fight_state_changed` during their `_ready()`** (e.g., a unit test instantiates SceneManager in isolation without those autoloads): SceneManager's `_cast_idle` and `_fight_idle` retain their boot defaults of `true`. `main_screen_idle` evaluates to true once IN_LOCATION is reached — Save's banner can fire. *Acceptable for test harnesses (which should not be producing banners); in production builds, both downstream systems are mandated to emit their state on `_ready()` per their forthcoming GDDs' contract. A separate edge case — those signals firing during a session but then stopping mid-play due to a bug — is a watchdog concern deferred post-MVP.*

10. **If `CastExecution.cast_state_changed(false)` and `FightSystem.fight_state_changed(true)` are emitted in the same frame** (a fish strikes exactly as the lure lands): GDScript's signal queue is processed in connection order, single-threaded. SceneManager's two handlers update `_cast_idle` and `_fight_idle` in sequence before the frame's render step. Save's banner-gating UI controller polls `main_screen_idle` during the render step (per Save's Rule 13), after both handlers have run. *`main_screen_idle` correctness assumes the UI controller polls during the same frame's render step. If a future UI controller polls during `_process` before signal handlers run, the predicate can transiently misreport — flagged as a contract assumption Save's banner-gating UI controller (#2) must honor.*

11. **If `get_rod_grip_position()` is called while `state != IN_LOCATION`** (during BOOTING, LOADING_LOCATION, or TRANSITIONING): returns the sentinel `Vector2(-1, -1)`. Cast Direction & Aiming (#6) must treat any negative coordinate as "rod-grip not available" and not begin an aim cycle. *Documented contract; consumer guards it. Cast Direction's GDD line 100 / 246 already references the scene-defined rod-grip; this is the formal sentinel value.*

12. **If Save & Persistence's recovery cascade triggers `full_reset_occurred = true`** (all save files corrupt or absent): META loads with default `active_location_id = "riverside_pond"`. Player wakes at the pond, consistent with the full-reset semantics. Save's recovery banner fires per Save's Rule 13. *Documented expected behavior — not a Scene Mgmt failure mode but a contract.*

### Modal management

13. **If `pop_modal()` is called more times than `push_modal()`** (consumer bug causing ref-count underflow): in debug builds, an `assert(_modal_count >= 1)` fires before decrement. In release builds, `_modal_count` is clamped to a floor of 0 (the decrement is skipped). *Prevents `main_screen_idle` from becoming "more true than possible" — a consumer bug should not silently expose the recovery banner during a still-modal moment.*

## Dependencies

### Upstream (Scene/Location Management depends on)

**None.** Scene Management is a Foundation-tier system; it has no upstream dependencies. SaveState (#2) is co-Foundation tier and is initialized before Scene Management via the Autoload ordering (Rule 2), but the relationship is bidirectional contractual coordination, not upstream-downstream.

### Downstream (depended on by)

| System | Strength | Interface | Notes |
|---|---|---|---|
| **Save & Persistence (#2)** | Hard (bidirectional coord) | (a) reads `MetaData.active_location_id` from `SaveState.get_meta()`; (b) writes via `set_meta` + `request_save(DOMAIN_META)` on transition complete; (c) exposes `main_screen_idle: bool` for Save's banner-gating UI controller (Save EC #22 + ACs 18–20, 32) | Coordination action #SP-1: Save's `MetaData` resource must add `active_location_id: String` field (default `"riverside_pond"`). Save's Section F already lists Scene Management as an indirect/banner-gating contractual party (save-persistence.md:463-470) — bidirectional consistency holds once #SP-1 is applied. |
| **Cast Direction & Aiming (#6)** | Hard | `SceneManager.get_rod_grip_position() -> Vector2` — read on aim begin; sentinel `Vector2(-1, -1)` while not IN_LOCATION (EC #11) | Cast Direction GDD (cast-direction-aiming.md:77, 100, 212, 246) already lists Scene / Location Management as an upstream dependency, marked "Undesigned (system #4) — provisional." After this GDD lands, Cast Direction's GDD should drop the provisional flag and cite this Rule 14 + EC #8 / #11 as the formal contract. |
| **Cast Execution (#8)** | Hard (mutual) | (a) Cast Execution emits `cast_state_changed(is_active: bool)` — Scene Mgmt subscribes for `_cast_idle` cache (Rule 8); (b) Cast Execution subscribes to Scene Mgmt's `travel_requested(from_id, to_id)` signal — calls own `abort_active_cast()` on receipt (EC #1) | Cast Execution is undesigned (#8) — these are provisional contracts that must be honored when its GDD is authored. The signal-based abort pattern preserves the Foundation→gameplay dependency direction. |
| **Fight System (#12)** | Hard | Fight System emits `fight_state_changed(is_active: bool)` — Scene Mgmt subscribes for `_fight_idle` cache (Rule 8); used in Travel button enabled logic (Rule 9) | Fight System is undesigned (#12). Contract is provisional. |
| **Location Unlock (#13)** | Hard (via Save) | Reads `SaveState.get_locations().unlocked_locations: Array[String]` — checked in `travel_to()` and picker render (Rule 7) | Indirect dependency through Save's LOCATIONS domain. Location Unlock owns the unlock predicate and the threshold value; Scene Mgmt only consumes the unlocked-list. Location Unlock GDD (#13) is undesigned. |
| **Location Catalog (#9)** | Hard | Per-location metadata: `scene_path: String` (required), `display_name: String`, `unlock_hint_copy: String` (rendered by SceneManager's picker per Rule 7) | Location Catalog is undesigned (#9). MVP fallback: a hardcoded `LOCATION_SCENE_PATHS` constant inside SceneManager (Rule 4.3). When Catalog lands, the rod-grip position MAY also migrate from per-scene Marker2D (Rule 14) to per-location Resource metadata — consumer-facing API stays identical. |
| **Stats / HUD UI (#15)** | Hard | (a) Calls `SceneManager.travel_to(destination_id)` on Travel button commit; (b) calls `SceneManager.push_modal()` / `pop_modal()` on modal lifecycle; (c) subscribes to `transition_started` + `transition_completed` to gate Travel button enabled state | HUD owns the Travel button widget and the location picker UI. Scene Mgmt owns the picker's modal-flag state (push when picker opens, pop when picker dismisses) per Rule 7. HUD #15 is undesigned. |
| **Audio System (#3)** | Soft | Audio subscribes to `transition_started(from_id, to_id)` + `transition_completed(target_id)` — drives location ambient crossfade | Soft because if Audio is absent or its subscription fails, transitions still work — there is just no audio crossfade. Audio #3 is undesigned. |
| **Settings (#18) / Catch Log UI (#17) / any future modal owner** | Soft | Calls `SceneManager.push_modal()` / `pop_modal()` on modal lifecycle | Soft because these systems work standalone; the modal-flag coordination is only needed to gate Save's recovery banner correctly during their open state. If a system forgets to call push/pop, the banner may appear over their modal — degraded UX, not a crash. Both systems are undesigned (#17, #18). |
| **Touch Input (#1)** | No coupling | — | SceneManager does not consume input directly. The FadeOverlay's `ColorRect.mouse_filter = MOUSE_FILTER_STOP` absorbs input during transitions; HUD owns its own input routing per Touch Input's `_unhandled_input` pattern. Bidirectional consistency: Touch Input GDD does not list Scene Mgmt and does not need to. |

### Bidirectional consistency

| Direction | Checked against | Status |
|---|---|---|
| Save (#2) → Scene Mgmt | save-persistence.md:463-470 (indirect/banner-gating party) | ✓ holds; #SP-1 coordination action pending |
| Scene Mgmt → Cast Direction (#6) | cast-direction-aiming.md:77, 100, 212, 246 (provisional upstream) | ✓ holds; Cast Direction should drop provisional flag in a future minor revision |
| Scene Mgmt → systems-index | design/gdd/systems-index.md:31 (Foundation tier, no upstream) | ✓ holds |
| Cast Execution (#8), Fight System (#12), Location Unlock (#13), Location Catalog (#9), Stats/HUD UI (#15), Audio (#3) | Undesigned — provisional contracts | ⚠ Provisional; bidirectional consistency cannot be checked until those GDDs land |
| Settings (#18) / Catch Log UI (#17) | Undesigned — provisional modal-flag contract | ⚠ Provisional |

### What downstream systems must adopt

When the following GDDs are authored, they must reflect Scene Mgmt's contract:

1. **Cast Execution (#8)** — must emit `cast_state_changed(is_active: bool)` on every state change, and must subscribe to Scene Mgmt's `travel_requested(from_id, to_id)` signal calling its own `abort_active_cast()` synchronously.
2. **Fight System (#12)** — must emit `fight_state_changed(is_active: bool)` on every state change. The dead-code `force_resolve_escaped()` proposal from the systems-designer's initial spec is superseded by Rule 9's button-disable approach; do not include it in Fight System's GDD. (Tracked in Open Questions as cross-GDD action.)
3. **Location Catalog (#9)** — must provide a per-location data API exposing `scene_path`, `display_name`, `unlock_hint_copy` (and, optionally, `rod_grip_offset` if migrating from Marker2D pattern).
4. **Location Unlock (#13)** — must provide the `unlock_threshold` value referenced in the picker's locked-location hint copy.
5. **Stats / HUD UI (#15)** — must implement the Travel button widget calling `SceneManager.travel_to(id)`, the location-picker rendering, and subscribe to `transition_started` + `transition_completed` to gate button enabled state.
6. **Audio System (#3)** — must subscribe to `transition_started` + `transition_completed` for ambient crossfade.
7. **Settings (#18) / Catch Log UI (#17)** — must call `SceneManager.push_modal()` on modal open and `pop_modal()` on modal close.

## Tuning Knobs

Only three values in this system are designer-tunable. CanvasLayer ordering, sentinel values, and the (provisional) `LOCATION_SCENE_PATHS` constant are project conventions or data, not tuning knobs.

| Knob | Default | Safe range | What breaks at low extreme | What breaks at high extreme | Interactions |
|---|---|---|---|---|---|
| `fade_out_duration` | `0.4 s` | `[0.0, 1.0]` | At `0.0`: scene swap visible for 1 frame as a hard cut; renderer first-instance stutter (Rule 11.8) is no longer hidden. Acceptable for unit-test config only — do NOT ship at 0. | At `>1.0`: transition feels sluggish; player perceives "the game is loading," which violates Pillar 4. Above `~0.7s` the threshold framing's "scene resolves" beat starts feeling laggy. | Combines with `load_wait` — if `fade_out_duration >= typical_load_wait`, the threaded load completes during the fade and `load_wait = 0` in the timing formula (best case). |
| `fade_in_duration` | `0.4 s` | `[0.0, 1.0]` | At `0.0`: scene appears instantly from black; the threshold-arrival beat is lost. Acceptable for testing only. | At `>1.0`: player waits too long looking at the new scene through a darkening fade; perceived as un-responsive. | Should typically match `fade_out_duration` for visual symmetry. Asymmetric values (e.g., quick fade-out, long fade-in) intentionally emphasize arrival but increase total transition time. |
| `load_timeout_seconds` | `5.0 s` | `[1.0, 30.0]` | At `<1.0`: legitimate slow loads on iPhone 11 baseline fail spuriously; player gets the failure rollback (Rule 13) when the scene would have loaded in 2-3 seconds. | At `>30.0`: a genuinely broken scene file produces a 30+ second black-screen hang before the rollback fires; player likely closes the app. | Bounds the worst-case `transition_total_time` in the Formula 1 output range. Should be measured against actual mobile device load times during alpha QA. |

### Non-tunable project constants (documented for completeness)

| Constant | Value | Why locked |
|---|---|---|
| `FADE_OVERLAY_LAYER` | `100` | Must be higher than every other `CanvasLayer.layer` in the project to guarantee the black overlay covers all content. Project convention: location scenes must not use `layer > 50` (Rule 3). |
| `HUD_LAYER` | `10` | Above the game world (`0`), below the fade overlay. Convention shared with Stats/HUD UI (#15). |
| `LOCATION_CONTAINER` default child count at IN_LOCATION | `1` | Single active location invariant (Rule 1). |
| Sentinel: `Vector2(-1, -1)` | rod-grip "not available" | Negative coordinate is an unambiguous sentinel in screen space (which is always non-negative for visible pixels). Cast Direction (#6) consumers check `< 0` (EC #11). |

### Knobs owned elsewhere that this system reads

- `casting_distance` thresholds for location unlock — owned by **Location Unlock (#13)**. Rendered in the picker's unlock hint copy but the threshold value is provided by Location Catalog (#9) via the `unlock_hint_copy` string.
- Per-location ambient audio crossfade duration — owned by **Audio System (#3)**.
- Per-location color palette (water tint, light) — owned by **Side-view Scene Rendering (#14)**. Affects how the fade-to-black reads on each location's color base (e.g., Riverside's warm-green water vs. Deep Lake's cool teal) but does not require Scene Mgmt tuning.

### Cache behavior note

Godot 4.6's `ResourceLoader` caches PackedScenes indefinitely after a successful load. The "best case" `load_wait = 0` row in Formula 1 always applies after the first visit to a location in a given session — returning to a previously-visited location is guaranteed cache-hit and produces the floor transition time `≈ 0.833 s`. Cold-start transitions on first visit produce the typical-case row. There is no MVP-tunable "cache invalidation" knob; the OS frees the cache only when the process terminates or under memory pressure.

## Visual/Audio Requirements

### Visual

1. **FadeOverlay** — full-screen `ColorRect` (`Color.BLACK`) on `CanvasLayer.layer = 100`. `modulate.a` is the sole animated property. Default tween: linear, 0.4s out → black-hold → 0.4s in (Section G knobs). No alternate easing in MVP (linear matches Alto's tonal calm; ease-in-out feels overdesigned for an indie fishing game).
2. **Location picker** — a centered overlay drawn on the HUD CanvasLayer (`layer = 10`). Visual style is owned by Stats / HUD UI (#15); this GDD specifies only the structural requirements:
    - One entry per location, vertically stacked.
    - Each entry: location name + (if locked) one-line unlock hint subtitle in smaller type at `modulate.a = 0.4`.
    - Tap target sized for thumb reach (≥ 44 pt — Apple Human Interface Guidelines minimum touch target; Material Design 3 specifies 48 dp as the equivalent. Move to `design/ux/accessibility-requirements.md` when that spec lands).
    - Background scrim: semi-opaque dark overlay (`Color(0, 0, 0, 0.6)`) covering everything outside the picker — does NOT use the FadeOverlay (which is reserved for transitions).
3. **No other animations.** No location-name banner appears on transition complete; the location IS its appearance (per Threshold framing). Side-view Scene Rendering (#14) owns each location's distinctive visual identity.
4. **Hand-off to art-director / Side-view Scene Rendering**: per-location color palette + lighting are owned downstream. This GDD only mandates that the FadeOverlay's black reads well against any palette (it does — pure black is universally absorbing).

### Audio

1. **Transition crossfade** — Scene Mgmt emits `transition_started(from_id, to_id)` and `transition_completed(target_id)` signals. Audio System (#3) is responsible for: (a) fading out the from-location ambient bed, (b) fading in the to-location ambient bed, (c) any optional transition stinger. SceneManager does NOT play any audio directly.
2. **No "Loading…" or transition SFX** — per Pillar 4 ("Silence is a Feature") and consistent with Save's no-spinner mandate. The fade-to-black is the entire affordance.
3. **Travel button tap SFX** — owned by Stats / HUD UI (#15) per their button widget. Not this GDD's concern.
4. **Locked-location tap** — no audio feedback. The visual reduced-opacity + no state change is the entire feedback (Pillar 4).

> 📌 **Asset Spec** — Visual/Audio requirements are defined. After the art bible is approved, run `/asset-spec system:scene-location-management` to produce per-asset visual descriptions, dimensions, and generation prompts. *Note: most Scene Mgmt assets are functional (a black ColorRect) or delegated downstream; expect a minimal asset list.*

## UI Requirements

### Owned by this GDD

1. **Location picker overlay** — modal UI that opens on Travel button tap. Behavior contract:
    - On open: SceneManager calls `push_modal()` (Rule 7.2).
    - Renders one entry per location from Location Catalog (#9), in catalog order.
    - Locked entries: reduced opacity (`modulate.a = 0.4`) + unlock-hint subtitle. Non-interactive tap (visible feedback but no commit; Rule 7.4).
    - Unlocked entries: full opacity, tap commits via `SceneManager.travel_to(id)`.
    - Tap-on-self-location: dismiss silently (Rule 7.5).
    - Tap-outside picker / Android back-button: dismiss without committing; `pop_modal()` fires.
    - No "Confirm" step — picker tap IS the commit. (User-decision rationale: HUD button on every screen, picker tap commits; minimum-friction travel.)
2. **FadeOverlay** — see Visual/Audio Section.

### Owned by other GDDs (referenced for clarity)

3. **Travel button widget** — Stats / HUD UI (#15). Persistent on-screen, enabled iff Rule 9 conditions. Tap opens the picker.
4. **Per-location HUD elements** (Stats display, Catch Log button) — Stats / HUD UI (#15). Persistent across travel; do NOT animate during transitions.

> 📌 **UX Flag — Scene / Location Management**: This system has UI requirements. In Phase 4 (Pre-Production), run `/ux-design` to create a UX spec for the **location picker overlay** and to validate the **Travel button + picker** interaction flow before writing implementation stories. Stories that reference UI should cite `design/ux/location-picker.md` (forthcoming), not this GDD directly.
>
> Note in systems-index for this system when next updated.

## Acceptance Criteria

Each AC: **GIVEN** [initial state], **WHEN** [action or trigger], **THEN** [measurable outcome]. Classified as *Logic / Integration / UI-Visual* + *BLOCKING / ADVISORY* per `.claude/docs/coding-standards.md` Testing Standards.

### Logic — BLOCKING

1. **Autoload ordering** — *Logic, BLOCKING*. **GIVEN** the project's `[autoload]` section, **WHEN** the list is parsed, **THEN** `SaveState` appears at index 0 and `SceneManager` appears at index 1. A CI grep on `project.godot` verifies (mirrors Save's Rule 2 CI safeguard).

2. **Boot active-location read + default** — *Logic, BLOCKING*. **GIVEN** `SaveState` has loaded with `MetaData.active_location_id = "deep_lake"` AND `"deep_lake" ∈ unlocked_locations`, **WHEN** `SceneManager._ready()` runs, **THEN** the location scene mounted under `LocationContainer` is the instance produced by SceneManager's scene-path resolver for `"deep_lake"` (per Rule 4.3 — the resolved path during MVP, the Location Catalog (#9) lookup post-migration) and `state == IN_LOCATION` after one `process_frame`.

3. **Boot defaults on absent META field** — *Logic, BLOCKING*. **GIVEN** `SaveState.get_meta().active_location_id` is the empty string or null (no prior save / cold install), **WHEN** `SceneManager._ready()` runs, **THEN** `active_location_id` becomes `"riverside_pond"`, the Riverside Pond scene mounts, and a `set_meta` + `request_save(DOMAIN_META)` write fires within the same frame.

4. **Single active location invariant** — *Logic, BLOCKING*. **GIVEN** any state ∈ {IN_LOCATION}, **WHEN** `LocationContainer.get_child_count()` is queried, **THEN** the result is exactly `1`.

5. **No `change_scene_to_*` calls post-boot** — *Logic, BLOCKING*. **GIVEN** the SceneManager script source, **WHEN** the source is grep'd for `change_scene_to_file` or `change_scene_to_packed`, **THEN** no occurrences are found. (Rule 3 invariant; child-swap pattern only.)

6. **Save timing — on transition complete, not start** — *Logic, BLOCKING*. **GIVEN** SceneManager is in IN_LOCATION at `riverside_pond` and `SaveState.set_meta` is spied, **WHEN** `travel_to("deep_lake")` is called and the transition is interrupted between fade-out and instantiate (test scaffold forces the load to fail), **THEN** `set_meta` was NOT called (active_location_id remains `riverside_pond` in memory and on disk).

7. **Save timing — successful complete writes META** — *Logic, BLOCKING*. **GIVEN** a successful travel from `riverside_pond` → `deep_lake`, **WHEN** `transition_completed("deep_lake")` is emitted, **THEN** `set_meta` was called exactly once with `active_location_id = "deep_lake"` AND `request_save(DOMAIN_META)` was called exactly once.

8. **State machine: BOOTING → LOADING_LOCATION → IN_LOCATION** — *Logic, BLOCKING*. **GIVEN** a fresh app launch with a populated save, **WHEN** the states are logged via `state_changed(from, to)` signal, **THEN** the sequence emitted is exactly `[BOOTING→LOADING_LOCATION, LOADING_LOCATION→IN_LOCATION]` with no other transitions before the first frame after `_ready()`.

9. **State machine: travel transitions** — *Logic, BLOCKING*. **GIVEN** state == IN_LOCATION at `riverside_pond`, **WHEN** `travel_to("deep_lake")` is called and the transition completes successfully, **THEN** the state sequence emitted is `[IN_LOCATION→TRANSITIONING, TRANSITIONING→IN_LOCATION]`.

10. **No-op self-travel** — *Logic, BLOCKING*. **GIVEN** state == IN_LOCATION at `riverside_pond`, **WHEN** `travel_to("riverside_pond")` is called, **THEN** no state transition occurs, no `transition_started` is emitted, no `set_meta` is called, and the picker (if open) is dismissed silently.

11. **Locked-destination travel rejected** — *Logic, BLOCKING*. **GIVEN** `unlocked_locations = ["riverside_pond"]`, **WHEN** `travel_to("deep_lake")` is called, **THEN** the call returns without entering TRANSITIONING, `transition_started` is NOT emitted, and a warning is logged to stdout.

12. **`main_screen_idle` — all four inputs honored** — *Logic, BLOCKING*. Parameterized test over the truth-table of `(state, _cast_idle, _fight_idle, _modal_count)`:

    | state | _cast_idle | _fight_idle | _modal_count | expected |
    |---|---|---|---|---|
    | IN_LOCATION | true | true | 0 | `true` |
    | TRANSITIONING | true | true | 0 | `false` |
    | BOOTING | true | true | 0 | `false` |
    | IN_LOCATION | false | true | 0 | `false` |
    | IN_LOCATION | true | false | 0 | `false` |
    | IN_LOCATION | true | true | 1 | `false` |
    | IN_LOCATION | true | true | 3 | `false` |

    **WHEN** each state combination is set up, **THEN** `SceneManager.main_screen_idle` returns the expected value.

13. **Modal ref-count push/pop balance** — *Logic, BLOCKING*. **GIVEN** `_modal_count == 0`, **WHEN** `push_modal()` is called twice and `pop_modal()` is called twice, **THEN** `_modal_count == 0` at end AND `main_screen_idle` returns true (assuming state IN_LOCATION + idle subsystems).

14. **Modal ref-count underflow clamps to 0** — *Logic, BLOCKING*. **GIVEN** `_modal_count == 0` in a release build, **WHEN** `pop_modal()` is called, **THEN** `_modal_count == 0` (no negative) and no crash occurs. *(In debug build, the same scenario triggers `assert(_modal_count >= 1)` failure.)*

15. **Travel button enabled logic** — *Logic, BLOCKING*. Parameterized over `(state, _fight_idle)`:

    | state | _fight_idle | expected `travel_button_enabled` |
    |---|---|---|
    | IN_LOCATION | true | `true` |
    | IN_LOCATION | false | `false` |
    | TRANSITIONING | true | `false` |
    | BOOTING | true | `false` |

16. **`rod_grip_position` sentinel during non-IN_LOCATION** — *Logic, BLOCKING*. **GIVEN** `state ∈ {BOOTING, LOADING_LOCATION, TRANSITIONING}`, **WHEN** `SceneManager.get_rod_grip_position()` is called, **THEN** returns exactly `Vector2(-1, -1)`.

17. **`rod_grip_position` reads from active scene** — *Logic, BLOCKING*. **GIVEN** state == IN_LOCATION and the active scene's `RodGrip: Marker2D` has `global_position = Vector2(200, 400)`, **WHEN** `SceneManager.get_rod_grip_position()` is called, **THEN** returns `Vector2(200, 400)`.

18. **Missing `RodGrip` returns sentinel** — *Logic, BLOCKING*. **GIVEN** a `LocationBase` test fixture with no `RodGrip` child, **WHEN** the fixture's `get_rod_grip_position()` is called, **THEN** returns `Vector2(-1, -1)` and `push_error` is invoked.

19. **Invalid `active_location_id` falls back at boot** — *Logic, BLOCKING*. **GIVEN** `MetaData.active_location_id = "deep_lake"` AND `unlocked_locations = ["riverside_pond"]` (post-save-corruption scenario), **WHEN** `SceneManager._ready()` runs, **THEN** Riverside Pond mounts, `active_location_id` is corrected to `"riverside_pond"` in memory, and a `set_meta` + `request_save(DOMAIN_META)` write fires.

20. **Boot scene-file-missing falls back, then exits** — *Logic, BLOCKING*. **GIVEN** `riverside_pond.tscn` is absent on disk AND `active_location_id = "riverside_pond"`, **WHEN** `SceneManager._ready()` runs, **THEN** the synchronous `load()` returns null, fallback retry also fails (same missing file), and the app exits with a non-zero engine error code.

21. **Load failure mid-transition rolls back** — *Logic, BLOCKING*. **GIVEN** state == IN_LOCATION at `riverside_pond` and a `deep_lake.tscn` fixture that fails to parse, **WHEN** `travel_to("deep_lake")` is called, **THEN** `location_load_failed("deep_lake", REASON_*)` is emitted, the Riverside Pond child remains as the sole child of LocationContainer (not freed), no `set_meta` write occurs, state returns to IN_LOCATION, and the Travel button re-enables.

22. **Duplicate `load_threaded_request` is skipped** — *Logic, BLOCKING*. **GIVEN** `load_threaded_request("res://locations/deep_lake.tscn")` has been called and status is `THREAD_LOAD_IN_PROGRESS`, **WHEN** `travel_to("deep_lake")` is called a second time before the first load completes (via the test scaffold bypassing the R11.1 assert), **THEN** the second call observes the in-progress status and does NOT issue a duplicate request. *(EC #3.)*

23. **Double-`travel_to()` assert** — *Logic, BLOCKING*. **GIVEN** state == TRANSITIONING, **WHEN** `travel_to("anywhere")` is called, **THEN** in debug builds an assert fails; in release builds the call returns silently without side effects.

24. **`travel_requested` signal fires before fade-out** — *Logic, BLOCKING*. **GIVEN** state == IN_LOCATION at `riverside_pond` and a signal spy on `travel_requested`, **WHEN** `travel_to("deep_lake")` is called, **THEN** `travel_requested("riverside_pond", "deep_lake")` is emitted exactly once before the fade-out tween begins. *(EC #1; supports Cast Execution's synchronous abort.)*

25. **Scene swap occurs at opaque alpha** — *Logic, BLOCKING*. **GIVEN** a transition in progress, **WHEN** the `LocationContainer` child reference changes from prior to new instance, **THEN** `FadeOverlay/ColorRect.modulate.a == 1.0` exactly. *(Asserts atomicity of Rule 10.)*

### Logic — Formula coverage

26. **Transition timing — best case** — *Logic, BLOCKING*. **GIVEN** `riverside_pond` and `deep_lake` are both already in ResourceLoader's cache, fade durations are `0.4s`, on a 60fps test harness, **WHEN** `travel_to("deep_lake")` is called and `transition_completed` is awaited, **THEN** the wall-clock duration from call to signal emission falls in `[0.80, 0.95] s` (best-case formula output with measurement tolerance).

27. **Transition timing — load timeout abort** — *Logic, BLOCKING*. **GIVEN** a `deep_lake.tscn` fixture that causes the threaded loader to hang indefinitely AND `load_timeout_seconds = 1.0`, **WHEN** `travel_to("deep_lake")` is called, **THEN** the failure rollback path (Rule 13) fires within `[1.0, 1.5] s` and the total `transition_total_time` from call to rollback completion is `≤ 1.0 + 0.4 + 0.4 = 1.8 s`.

### Integration — DEFERRED PENDING DOWNSTREAM GDDs

28. **Save banner gating via `main_screen_idle`** — *Integration, BLOCKING — DEFERRED PENDING SAVE'S BANNER UI CONTROLLER GDD (#15)*. **GIVEN** `SaveState.recovered_from_backup == true` AND state == IN_LOCATION AND `_cast_idle == true` AND `_fight_idle == true` AND `_modal_count == 0`, **WHEN** the next frame renders, **THEN** Save's recovery banner is shown exactly once (verifies Save AC 18 with this GDD's main_screen_idle precondition concretely defined).

29. **`cast_state_changed` subscription** — *Integration, BLOCKING — DEFERRED PENDING CAST EXECUTION GDD (#8)*. **GIVEN** SceneManager has subscribed to `CastExecution.cast_state_changed`, **WHEN** Cast Execution emits `cast_state_changed(true)`, **THEN** SceneManager's `_cast_idle` becomes `false` within the same frame.

30. **`fight_state_changed` subscription** — *Integration, BLOCKING — DEFERRED PENDING FIGHT SYSTEM GDD (#12)*. **GIVEN** SceneManager has subscribed to `FightSystem.fight_state_changed`, **WHEN** Fight System emits `fight_state_changed(true)`, **THEN** SceneManager's `_fight_idle` becomes `false` within the same frame AND the Travel button transitions to disabled within the same frame.

31. **In-flight cast aborted on travel** — *Integration, BLOCKING — DEFERRED PENDING CAST EXECUTION GDD (#8)*. **GIVEN** Cast Execution has subscribed to `SceneManager.travel_requested` AND Cast Execution is in its in-flight-cast state, **WHEN** `travel_to("deep_lake")` is called, **THEN** Cast Execution's `abort_active_cast()` is called synchronously before the fade-out tween begins (verified via signal-trace + spy).

32. **HUD Travel button widget wires to `travel_to`** — *Integration, BLOCKING — DEFERRED PENDING STATS/HUD UI GDD (#15)*. **GIVEN** the HUD scene is loaded and the Travel button is enabled, **WHEN** the button is tapped, **THEN** `SceneManager.travel_to(picked_id)` is invoked exactly once with the user's pick.

33. **Audio crossfade on transition** — *Integration, ADVISORY — DEFERRED PENDING AUDIO SYSTEM GDD (#3)*. **GIVEN** Audio System has subscribed to `transition_started` and `transition_completed`, **WHEN** a travel transition fires, **THEN** Audio System initiates its crossfade routine on `transition_started` and completes/finalizes on `transition_completed`.

### UI/Visual — ADVISORY

34. **Fade visual reads smoothly on iPhone 11 baseline** — *UI/Visual, ADVISORY*. **GIVEN** a build deployed to iPhone 11 with `fade_out_duration = fade_in_duration = 0.4s`, **WHEN** a Riverside → Deep Lake travel is recorded as video, **THEN** no visible flash of un-styled scene, no glimpse of two scenes overlapping, and the fade reads as smooth (60fps maintained per frame-time overlay). Evidence: video recording in `production/qa/evidence/scene-transition-[date].md`.

35. **Picker visual: locked location at reduced opacity** — *UI/Visual, ADVISORY*. **GIVEN** Deep Lake is locked, **WHEN** the location picker opens, **THEN** Deep Lake's entry is rendered at `modulate.a ≈ 0.4` with an unlock-hint subtitle. Evidence: screenshot in `production/qa/evidence/picker-locked-[date].md`.

### Cross-GDD action items (carried to Open Questions)

- **#SP-1**: Save & Persistence's `MetaData` resource needs `active_location_id: String` field added (default `"riverside_pond"`). Required for AC 2, 3, 7, 19.
- **Save AC 32 unblocked**: Save's "main gameplay scene path TBD — owned by #4" can now be locked to `res://src/core/main.tscn`. Save's GDD should drop the placeholder when next revised.

## Open Questions

| # | Question | Owner | Target resolution |
|---|---|---|---|
| **SP-1** | Save & Persistence's `MetaData` resource must add `active_location_id: String` field (default `"riverside_pond"`). Required for ACs 2, 3, 7, 19. | Save & Persistence (#2) revision + Lead Programmer | Coordinate via /propagate-design-change or a minor Save GDD revision; can be batched with Save's outstanding revisions. Bidirectional consistency on Save's Section F (line 463-470 lists Scene Mgmt as a contractual party). |
| **ADR-1** | ~~Foundation tier (SceneManager) subscribes to gameplay-tier signals (`cast_state_changed`, `fight_state_changed`) — inverts the layered dependency convention. Alternative: shared `GameState` autoload that both tiers write to.~~ | Technical Director | **RESOLVED 2026-05-12 via [ADR-001](../../docs/architecture/ADR-001-foundation-gameplay-signal-inversion.md)** — Option A (direct signal subscription) accepted; inversion bounded to the two named signals. |
| **EV-1** | Verify Godot 4.6's `THREAD_LOAD_LOADED` / `THREAD_LOAD_IN_PROGRESS` / `THREAD_LOAD_FAILED` / `THREAD_LOAD_INVALID_RESOURCE` enum names against the 4.6 stable docs. The engine-programmer flagged these as post-cutoff. | Engine Programmer | Before code is written; verify against https://docs.godotengine.org/en/stable/classes/class_resourceloader.html. |
| **EV-2** | CI check: a grep on the project codebase asserting no `change_scene_to_file` or `change_scene_to_packed` calls (Rule 3 invariant, AC 5). | Lead Programmer + DevOps | When CI pipeline is established. |
| **EV-3** | Streaming texture import (`.import` flag) for hand-painted location backgrounds — does the asset pipeline use streaming for large textures? Affects first-instance stutter behind the fade (Section D, R11.8). | Technical Artist | When art assets begin shipping (Side-view Scene Rendering #14). |
| **TT-1** | Confirm tween pause behavior under `PROCESS_MODE_INHERIT` during `NOTIFICATION_APPLICATION_PAUSED` on iOS specifically. EC #4 assumes the tween's wall-clock timer pauses and resumes correctly. Currently asserted, not verified on device. | Engine Programmer | Before iOS submission; ideally during alpha QA. |
| **XGD-1** | Cross-GDD action: when Fight System (#12) is authored, do NOT include the dead-code `FightSystem.force_resolve_escaped()` proposal that surfaced in Section C's systems-designer draft. It is superseded by Rule 9's Travel-button-disable approach (no need to abort an in-progress fight on travel — travel is simply blocked). | Producer (cross-GDD coordination) | Track in producer's GDD-author handoff notes; surface when /design-system fight-system fires. |
| **LC-1** | Location Catalog (#9) will replace the hardcoded `LOCATION_SCENE_PATHS` constant (Rule 4.3) and may absorb `rod_grip_position` from per-scene Marker2D (Rule 14). What is the migration path for in-flight saves (no schema break expected since `active_location_id` stays a `String` ID)? | Location Catalog (#9) author | When /design-system location-catalog fires. |
| **PB-1** | Should the `state_changed(from, to)` signal be exposed publicly (consumed by integration tests per AC 8), or kept internal? | Lead Programmer | During implementation review. |
| **BOOT-1** | Boot scene-file-missing fatal exit (EC #6 / AC 20) — should there be a developer-facing error screen before the fatal exit (e.g., for App Store reviewers who get a corrupted build), or just stdout log + exit? Currently: log + exit. | UX Designer + Lead Programmer | Before release-candidate certification. |
| **SAVE-AC32** | Save & Persistence's AC 32 references "the main gameplay scene path TBD — owned by #4." This is now `res://src/core/main.tscn` (Rule 3). Save's GDD should drop the placeholder + the temporary `tests/scenes/save_signal_isolation_test.tscn` scaffold reference when next revised. | Save & Persistence (#2) revision | Next minor revision of Save's GDD. |

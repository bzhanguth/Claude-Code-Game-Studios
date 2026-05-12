# Save & Persistence

> **Status**: Approved (2026-05-12, post fresh-session cold re-review v2 — user accepted v2 revisions and waived re-review)
> **Author**: bzhanguth + Claude (Opus 4.7)
> **Last Updated**: 2026-05-12 (second revision pass — cold-context re-review)
> **Implements Pillar**: Infrastructure — serves Pillar 2 ("Every Fish Makes You Stronger") by making
> progression durable across sessions. MVP requirement #8 from `design/gdd/game-concept.md`.
>
> **Revision v2 notes (2026-05-12, fresh session)**: Cold-context re-review (5 specialists + creative-director) identified additional blocking items the same-session revision missed. Resolved this pass: PAUSED → SHUTTING_DOWN recovery via RESUMED → READY transition (mirrors FOCUS_OUT fix shape but preserves "PAUSED expected terminal" intent); Option 4 reference-semantics fix (`get_*()` now returns `.duplicate(true)` — Resources are RefCounted, not value types); debounce timer reset semantics locked (leading-edge — does NOT reset on subsequent calls during DIRTY); banner copy locked to "Your progress picked up where it left off." / "Starting fresh." (Alto-flavored — replaces apology framing); Section F banner-copy doc rot fixed; `backup_count` range clamped to [0, 2] (matches Rule 4/5 implementation); orphan `.tmp` cleanup specified in Rule 7; forward clock jump handling added to Section E; `SaveStateInterface` declared `@abstract`; Rule 16 strengthened to prohibit ALL UI-visible save feedback (not just signal subscriptions); 8 AC tightenings; Player Fantasy section reframed in player-felt terms. See `design/gdd/reviews/save-persistence-review-log.md` for the v2 review record.
>
> **Revision v1 notes (2026-05-12, same session — superseded)**: First-pass revision addressed 6 BLOCKING + 14 REQUIRED items from the original review. Same-session bias caveat: that revision missed PAUSED-resume data loss, Option 4 reference semantics, banner-copy doc rot in Section F, and several AC gaps. Resolved in v2.

## Overview

**Save & Persistence** is the storage subsystem that keeps player progression state durable across app sessions. Saves are written **automatically** — triggered by gameplay milestones (catch landed, location unlocked, stat upgraded) and lifecycle events (app pause, app background, app quit) — and loaded once on launch into the in-memory state consumed by Stat Progression, Catch Log, and Location Unlock. All save data lives in Godot's `user://` path (sandboxed per-platform: iOS app container, Android app-internal storage); there is **no cloud sync, no account system, no server** — consistent with the game's premium, one-time-purchase, no-network monetization. The system owns serialization, versioning, atomic write, and corruption recovery; downstream systems own their own data shape and merely declare what fields they need to persist.

## Player Fantasy

Every fish in the journal stays in the journal. Every lake unlocked stays unlocked. The player closes the app on the train, opens it three days later in a waiting room, and their progress is exactly where they left it — not because the game saved, but because nothing was ever at risk.

This is an **indirect fantasy**. The player doesn't feel saving directly; they feel its absence (lost progress) or its presence (everything is where they left it). This section is short by design — the heavy lifting of "every fish makes you stronger" happens in **Stat Progression** and **Catch Log**; Save & Persistence's role is to make that progression durable enough that the pillar can be felt at all.

**Pillar tie**: Pillar 2 — *Every Fish Makes You Stronger*. If catches don't persist, Pillar 2 dies the moment the player closes the app. Saving is the substrate that lets the pillar exist across sessions.

**Reference behavior**: *Alto's Adventure* (silent autosave, never thought about) is the closest tonal match. *Stardew Valley*'s end-of-day save creates a "today is locked in" beat that *Fishing Man* explicitly does **not** want — saving happens at gameplay milestones and lifecycle events, never as a ritual the player performs.

**What would break this fantasy** — each is a player-felt failure first, an engineering anti-pattern second:

- *The player wonders, even briefly, whether their last catch counted.* (We do not show a "Saving…" indicator that creates the question.)
- *The player is asked to prove who they are before the game lets them play.* (No "sync your progress" or "log in to save" prompt at launch — no account, no network.)
- *The player closes the app on a personal-best fish and reopens to find the fish gone.* (Lifecycle flush + atomic write protect against this; the residual 2-second SIGKILL window is documented as a bounded acceptance, not silently ignored — see Edge Case #20.)
- *The player opens the catch log expecting a record of their three-day grind and sees an empty journal.* (Recovery cascade through backups; banner only on the rare recovery moment.)
- *The player is mid-cast and a modal interrupts the rhythm of the rod.* (Banner is gated by Scene Management idle state — Rule 13 / Edge Case #22.)

## Detailed Design

### Core Rules

1. **Autoload pattern.** `SaveState` is a Godot Autoload (`extends Node`), registered in Project Settings. It does **NOT** declare `class_name SaveState` (the autoload-vs-`class_name` collision documented in the Touch Input GDD; still required as of Godot 4.6). `process_mode = PROCESS_MODE_INHERIT` (default). **Citation**: OS lifecycle notifications (`NOTIFICATION_APPLICATION_PAUSED`, `NOTIFICATION_APPLICATION_RESUMED`, `NOTIFICATION_APPLICATION_FOCUS_OUT`, `NOTIFICATION_APPLICATION_FOCUS_IN`, `NOTIFICATION_WM_CLOSE_REQUEST`) are dispatched by `MainLoop` via `DisplayServer` and **bypass `process_mode` entirely**, unlike `_input()` / `_unhandled_input()` which are process_mode-gated (see `docs/engine-reference/godot/modules/input.md` for the input-side citation; for the notification side see Godot 4.6 docs: https://docs.godotengine.org/en/stable/classes/class_mainloop.html#class-mainloop-constant-notification-application-paused). INHERIT is therefore safe here; do not "fix" it to ALWAYS for the wrong reason.

2. **Single-load on launch.** `SaveState._ready()` runs before any gameplay scene `_ready()` (Godot processes Autoloads in Project Settings → Autoload list order, top-to-bottom, before any scene's `_ready()`). **`SaveState` must be the first Autoload in the project, or at minimum above every Autoload that calls into it.** This ordering is asserted but not enforced by tooling — document in project setup; a CI grep check on `project.godot`'s `[autoload]` section is a recommended safeguard. Load is synchronous and reads from disk into typed in-memory records before returning. Downstream systems pull from `SaveState` once in their own `_ready()`.

3. **No player-facing save UI.** There is no save button, slot picker, save indicator, or "Saving…" spinner in MVP. The system is invisible per Section B.

4. **Storage layout.** Two files in `user://`:
    - `user://progress.save` — Progression + CatchLog + Locations + Meta domains.
    - `user://settings.save` — Settings domain only.

    Settings is split so future "reset progress, keep accessibility prefs" flows need no engineering, and so a corrupted `progress.save` cannot lose user preferences. `settings.save` is **not** included in the backup rotation (settings loss is < 30 seconds of player effort to reconstruct).

    **iCloud-backup exclusion for `settings.save` (intent vs implementation)**: vanilla GDScript cannot set `NSURLIsExcludedFromBackupKey` on iOS. Options when this becomes required: (a) move `settings.save` to a different sandbox subpath via a GDExtension call, (b) accept iCloud backup of settings (no PII, no progression — harmless). **MVP: accept (b)**; revisit when accessibility flags grow or PII enters the settings shape.

5. **Backups.** Up to two rotating snapshots of `progress.save`:
    - `user://progress.backup1.save`
    - `user://progress.backup2.save`

    Rotation is **gap-based, not write-based**. On each successful write to the active file, evaluate in this order:

    1. **If `backup_count == 0`** (tuning knob, Section G): rotation is skipped entirely; backup files are not created or maintained. The recovery cascade (Rule 13) goes straight to defaults on active-file failure.
    2. **If `backup_count > 0` AND `progress.backup1.save` does not yet exist** (very first successful active write of a fresh install): no rotation this cycle; on the NEXT successful write, rotate normally (active → backup1, then this state persists).
    3. **Otherwise**: compare `last_saved_utc` against `progress.backup1.save`'s timestamp. If the gap is ≥ `backup_rotation_gap_seconds` (default 300s = 5 min), rotate (active → backup1, backup1 → backup2, new write → active). **On rotation, the prior content of `progress.backup2.save` is discarded by design** — the pipeline only retains the two most recent meaningful snapshots. If the gap is < threshold (or negative — see EC #12 for backward clock jumps), overwrite the active file in place; backups untouched.

    This keeps backups at meaningfully different game states, not adjacent catches.

6. **Serialization format.** JSON via `JSON.stringify(data, "\t")` (pretty-printed for human-debuggability) and `JSON.parse_string()` on load. Integer fields are explicitly cast back to `int` on load (JSON serializes all numbers as floats).

    **Durability boundary**: `FileAccess.flush()` in Godot 4.6 returns `void` (per Godot 4.6 docs: https://docs.godotengine.org/en/stable/classes/class_fileaccess.html#class-fileaccess-method-flush) and is equivalent to POSIX `fflush()` — flushes the C standard library buffer to the OS page cache; it is **NOT** `fsync()`. The atomic temp-write + rename pattern (Rule 7) protects against partial-write corruption but **does NOT guarantee durability across power-loss between flush and rename**. Calling `fsync()` from GDScript requires a GDExtension and would significantly slow writes. **MVP accepts this trade-off**: the guarantee is "no partial-write corruption," not "no power-loss data loss." (Open Q #4 in active.md tracks platform-level `flush()` behavior on iOS / Android — separate concern from the Godot API contract.)

7. **Atomic write pattern.** Every write follows this sequence:
    1. Build the in-memory `Dictionary` for the domain.
    2. `JSON.stringify(data, "\t")` to a string. If the result is empty for a non-empty input (cyclic reference, unsupported type), bail with `save_failed(domain, REASON_SERIALIZATION_EMPTY)`.
    3. Open `user://<name>.save.tmp` with `FileAccess.WRITE`. Check `FileAccess.get_open_error()`; bail with `save_failed(domain, REASON_OPEN_FAILED)` on error.
    4. `file.store_string(content)` — **check the `bool` return** (Godot 4.4+ change from `void`). If `false`, bail with `save_failed(domain, REASON_STORE_FAILED)` (likely `REASON_DISK_FULL` if `OS.get_unique_id()` is healthy and other writes succeed; reason granularity at the call site).
    5. `file.flush()` then `file.close()`. **Note**: `flush()` returns `void` in Godot 4.6; failures during flush are not detectable through the API. `close()` success is the practical proxy. See Rule 6 durability boundary — this gives "no partial-write corruption" not "no power-loss data loss."
    6. Atomic rename via `DirAccess`:
       ```gdscript
       var dir := DirAccess.open("user://")
       var err := dir.rename("<name>.save.tmp", "<name>.save")
       if err != OK:
           # bail with save_failed(domain, REASON_RENAME_FAILED)
       ```
       Rename is atomic on POSIX FS (iOS APFS and Android ext4/F2FS both use POSIX rename semantics for app-internal storage). `DirAccess.rename` is the instance method on a `DirAccess` opened against `user://`; signature is `rename(from: String, to: String) -> Error` per Godot 4.6 docs (https://docs.godotengine.org/en/stable/classes/class_diraccess.html#class-diraccess-method-rename). There is no static `DirAccess.rename_absolute()` for `user://` paths in Godot 4.6 — the `DirAccess.open("user://") + instance.rename` pattern is the required form.

    A crash or force-quit at any step leaves the live file intact; only the `.tmp` is incomplete.

    **Orphan `.tmp` cleanup on load.** `SaveState._ready()` performs an idempotent sweep of `user://` after the load cascade completes (regardless of which path succeeded): for each known save name (`progress.save`, `progress.backup1.save`, `progress.backup2.save`, `settings.save`), any matching `<name>.tmp` file is deleted via `DirAccess.remove`. This guarantees that an orphan from a crashed prior write does not persist across launches and does not collide with a future write's temp file. Sweep failures (permission error on remove) are logged but non-fatal — the next successful write will overwrite the temp before its rename step.

8. **Save triggers.** Three trigger sources:

    - **Gameplay events (debounced)**: `request_save(DOMAIN_PROGRESSION | DOMAIN_CATCH_LOG | DOMAIN_LOCATIONS)` called after fish landed, location unlocked, or stat upgraded. Multiple `request_save` calls within the debounce window collapse into one write at window end. **Debounce timer semantics: leading-edge.** The timer starts on the first `request_save` that transitions READY → DIRTY. Subsequent `request_save` calls during DIRTY **do NOT reset** the timer — they only union new domains into the pending payload. The timer fires exactly 2.0s after the first call. This is non-default debounce behavior (most "debounce" implementations are trailing-edge / reset-on-each-call) — locked here as leading-edge to make the worst-case data-loss bound deterministic and analytically verifiable.
    - **Settings changes (immediate, bypass debounce)**: `request_save(DOMAIN_SETTINGS)` writes `settings.save` immediately. Settings changes are rare and user-initiated; debounce adds no value.
    - **Lifecycle events**:
        - `NOTIFICATION_APPLICATION_PAUSED` — app is being backgrounded by the OS (iOS suspends, Android `onPause`/`onStop`). **Flush all pending domains synchronously, then transition to `SHUTTING_DOWN`.** SHUTTING_DOWN is **expected-terminal** (the process is normally killed by the OS shortly after PAUSED) but is **recoverable** via Rule 8a — see RESUMED handler below.
        - `NOTIFICATION_APPLICATION_RESUMED` — app process survived backgrounding and is being foregrounded by the OS without termination. (Common iOS path: home-button-press → backgrounded but not killed → user returns via app-switcher.) **If `state == SHUTTING_DOWN`, transition SHUTTING_DOWN → READY (recovery), reset in-memory dirty flags and timers (none should be active in SHUTTING_DOWN), and resume normal save eligibility.** If state is anything else (no PAUSED was received this session, or the app was killed and re-launched cleanly), RESUMED is a no-op. This handler is the data-loss fix for the case "PAUSED was received but the OS did not actually kill the process" — without it, the app would silently drop all subsequent saves for the rest of the session.
        - `NOTIFICATION_APPLICATION_FOCUS_OUT` — app loses focus due to **partial occlusion** (iOS notification banner, Control Center pull-down, picker dialog, system permission prompt). The app **remains in the foreground and will regain focus when the overlay dismisses**. **Flush all pending domains synchronously, then return to `READY`. Do NOT transition to `SHUTTING_DOWN`** — terminal state here would mean the app cannot save again for the rest of the session after the overlay dismisses, which is a real iOS data-loss path.
        - `NOTIFICATION_APPLICATION_FOCUS_IN` — app regains focus after partial occlusion dismisses. No-op; the system is already in READY after the FOCUS_OUT flush.
        - `NOTIFICATION_WM_CLOSE_REQUEST` — **desktop only** (window close button). Does **not** fire on iOS or Android. Treated as a `SHUTTING_DOWN` trigger on desktop builds (out of MVP scope; cheap to include for parity). Unlike PAUSED, this is **truly terminal** — the window is closing; there is no recovery path.

    **Debounce default (2.0s) — Pillar 2 trade-off analysis (locked decision, recomputed for leading-edge semantics):** The 2.0s window is the maximum data-loss exposure on `SIGKILL` force-quit only (which bypasses `_notification` entirely). Graceful lifecycle transitions (`PAUSED`, `FOCUS_OUT`) flush regardless of debounce. Because the timer is leading-edge (does NOT reset on subsequent `request_save` calls), the worst-case data-loss window during sustained rapid play (e.g., 3-5 catches/sec in a fish blitz spot) is still capped at 2.0s — the timer fires deterministically 2s after the first dirty event, batching every subsequent catch within that window into the one write. Without leading-edge semantics, trailing-edge debounce would leave the data-loss window unbounded under fast play, breaking the Pillar 2 promise. `SIGKILL` is rare in normal mobile play — it requires either OS memory pressure during foreground play or explicit user force-quit via app-switcher swipe (post-PAUSED → SHUTTING_DOWN; PAUSED still flushed first, so only post-flush catches are lost). The cost of tightening: a 0.5s debounce yields up to 2 writes/second during rapid catch bursts. The cost of relaxing: more catches lost on the rare SIGKILL event. **2.0s is chosen as the balance**: at most 2 seconds of un-flushed catches may be lost on SIGKILL, accepting that this is a bounded Pillar 2 violation in a rare edge condition. The tuning knob (Section G `debounce_seconds`) allows project-level override in the safe range [0.5, 10.0].

9. **No periodic autosave.** The event triggers + lifecycle flush are exhaustive. A timer-based autosave is intentionally not included — it would add writes without covering any gap the event triggers miss. **Structural enforcement**: SaveState must have **zero `Timer` children** and **no `_process()` or `_physics_process()` override** that triggers writes. Verified by AC (Section H).

10. **Versioning.** Every save file's root Dictionary has a `schema_version: int` field. `CURRENT_SCHEMA_VERSION = 1` at MVP. The version field is read **first**, before any other field.

11. **Migration chain.** When the loaded `schema_version` is **less than** `CURRENT_SCHEMA_VERSION`, migrations run in order. At MVP (`CURRENT_SCHEMA_VERSION = 1`) the only migration that will actually exist is `_migrate_v0_to_v1(data) -> Dictionary`, which handles saves where the `schema_version` field is missing entirely (treated as v0). Future versions add `_migrate_v1_to_v2(data) -> Dictionary`, `_migrate_v2_to_v3(data) -> Dictionary`, etc. Each migration returns a **new** Dictionary (never mutates in place — required for unit-testable migrations). After the chain runs, the migrated data is written back via the atomic-write path; the file is now at current version.

12. **Newer-save refusal.** When the loaded `schema_version` is **greater than** `CURRENT_SCHEMA_VERSION` (older app encountering a newer save — possible after store rollback or sideload), the load is refused with `ERR_INVALID_DATA`. The recovery cascade (Rule 13) then attempts the backups; if those are also newer, the player reaches the full-reset banner state. We do **not** partial-load — silently dropping unrecognized fields would corrupt invariants downstream systems depend on.

13. **Recovery cascade.** On load:
    1. Attempt active file (`progress.save`). On success: play.
    2. On failure: attempt `progress.backup1.save`. On success: set session flag `recovered_from_backup = true`, play.
    3. On failure: attempt `progress.backup2.save`. On success: set the same flag, play.
    4. On total failure: initialize defaults, set session flag `full_reset_occurred = true`.

    **`prior_save_file_existed_at_launch: bool` — required state field.** During LOADING, before any parse attempt, SaveState probes the three save-file paths (active + backup1 + backup2) using `FileAccess.open(path, FileAccess.READ)` and inspecting `FileAccess.get_open_error()`. The flag is set per the following rule:

    - **If all three probes return `ERR_FILE_NOT_FOUND` (and only `ERR_FILE_NOT_FOUND`)**: set `prior_save_file_existed_at_launch = false`. This is the true first-launch signature.
    - **If any probe returns a valid file handle** (regardless of whether content parses): set `prior_save_file_existed_at_launch = true`. A prior save file exists at the FS level.
    - **If any probe returns a non-`ERR_FILE_NOT_FOUND` error** (e.g., permission denied, path unavailable — iOS pre-first-unlock per EC #14): **treat as inconclusive — leave `prior_save_file_existed_at_launch = false` (default)**. A permission error on a nonexistent file would otherwise falsely set the flag and trigger a full-reset banner on first launch. Errors here are logged but do not affect the flag.

    The field is exposed on the Public API (read-only) for the banner-gating UI controller.

    On the next main-screen render, the banner-gating UI controller (Stats / HUD UI #15) checks:

    - **If `recovered_from_backup = true`**: show the banner `"Your progress picked up where it left off."` Clear the flag after one display. (No `prior_save_file_existed_at_launch` check needed — a backup loaded successfully, so a prior save exists by definition.)
    - **If `full_reset_occurred = true` AND `prior_save_file_existed_at_launch = true`**: show the banner `"Starting fresh."` Clear the flag after one display.
    - **If `full_reset_occurred = true` AND `prior_save_file_existed_at_launch = false`**: **no banner** (true first-launch device; never saw the inside of a save file).

    **Banner copy is locked here** (this GDD owns the words and the moment-design). The copy is calm-continuity by design — consonant with Pillar 4 ("Silence is a Feature") and the Alto's Adventure tonal reference. Both strings deliberately avoid the word "wrong"; recovery frames the moment as a successful continuation, not as an error the player has to forgive. Styling, placement, animation, and dismissal are owned by Stats / HUD UI (#15) per Section F. Banners never appear mid-fight or mid-cast — gating by Scene Management (#4) + Fight System (#12) + Cast Execution (#8) idle state is the UI controller's responsibility (Edge Case #22).

14. **Synchronous I/O.** Saves and loads are synchronous on the main thread. For MVP file sizes (~5 KB) and Vertical Slice sizes (~50 KB), JSON serialization and write completes in well under a frame on target hardware. Threaded saves are out of scope for MVP; revisit if the catch log grows beyond several hundred KB.

15. **Typed defaults, never null.** `get_*()` methods return typed default records on load failure. **The values below are placeholders illustrating the structure SaveState produces; the authoritative starting values are owned by the corresponding downstream system's GDD** and may be overridden when those GDDs land:

    - `casting_distance = 5.0` — **placeholder; unit is screen-space pixels** (per Cast Direction & Aiming GDD which uses `casting_distance` in pixels, range `[0, screen_height × 0.78]` ≈ up to 840 px on 1080p portrait). The value `5.0` is **not** a viable starting reach; Stat Progression (#7) will set the authoritative starting value during its GDD authoring. Until then, downstream test code should treat the value as TBD.
    - `rod_strength = 1.0` — placeholder; dimensionless scale. Owned by Stat Progression (#7).
    - `unlocked_locations = ["riverside_pond"]` — placeholder; the starting location for MVP per game-concept.md. Owned by Location Catalog (#9).
    - `catch_count = {}`, `biggest_catch_cm = {}` — empty maps. Owned by Catch Log (#17).
    - `audio_master_volume = 1.0`, `haptics_enabled = true`, `accessibility_flags = []` — placeholders. Owned by Settings & Accessibility (#18).

    Downstream systems must never crash on missing data. If a downstream GDD specifies a different default, that overrides this section (and the registry should be updated).

16. **No UI-visible save feedback — structural rule.** The invisible-save fantasy (Section B) is enforced structurally, not by code-review convention. The rule has two layers:

    (a) **Signal subscription prohibition.** The signals `save_completed`, `save_failed`, and `load_failed` are **internal** to the save system and the test seam (Rule 17). No UI element may subscribe to these signals for player-visible feedback in MVP. AC 32 enforces this via scene-tree inspection.

    (b) **Derived-feedback prohibition.** No UI element may render, animate, or otherwise expose to the player any derived information from SaveState's state (`READY`, `DIRTY`, `WRITING`, `SHUTTING_DOWN`), session flags (`recovered_from_backup`, `full_reset_occurred`, `prior_save_file_existed_at_launch`), or pending-write queue. This closes the alternate path a UI dev might take to expose save activity without subscribing to signals — polling state or reading flags is equally prohibited for player-facing rendering.

    The **only** player-visible output of SaveState is the recovery banner specified in Rule 13, gated by the conditions in Rule 13. Debug-only HUD overlays (`show_save_status_hud` per Section G) are exempt because they are `#ifdef`-stripped before release.

17. **Test seam — `_init_from_save()`.** Every downstream system that consumes SaveState **MUST** expose an `_init_from_save(save: SaveStateInterface) -> void` method as its initialization seam. Production code calls `_init_from_save(SaveState)` once in `_ready()`; unit tests call `_init_from_save(MockSaveStateInterface.new())` with controlled in-memory data. `SaveStateInterface` is the abstract base class (declared `@abstract` per Rule 18, available in Godot 4.5+); attempting to instantiate it directly is a compile-time error, so accidental no-op injection is impossible. Since `SaveStateInterface extends Node` (production parent `SaveState` is the Autoload Node), test mocks created via `MockSaveStateInterface.new()` are Nodes outside the scene tree — **tests MUST use GUT's `add_child_autofree(mock)` pattern or call `mock.queue_free()` in teardown**. This is documented as test-infrastructure item 2. This is the canonical DI pattern for the project's save system; the four downstream GDDs (#7, #13, #17, #18) must adopt it.

18. **Data class contracts — MVP stub definitions.** SaveState's public API returns typed records. The following stub classes are owned by this GDD at MVP and live in the `src/core/save/` package (or equivalent). Each downstream system may extend the corresponding class with domain-specific fields as their GDD lands; schema evolution is handled by the migration chain (Rule 11).

    ```gdscript
    # progression_data.gd  (extended by Stat Progression #7)
    class_name ProgressionData
    extends Resource
    @export var casting_distance: float = 5.0
    @export var rod_strength: float = 1.0

    # catch_log_data.gd  (extended by Catch Log #17)
    class_name CatchLogData
    extends Resource
    @export var catch_count: Dictionary = {}          # { species_id: int }
    @export var biggest_catch_cm: Dictionary = {}     # { species_id: float }

    # location_unlock_data.gd  (extended by Location Unlock #13)
    class_name LocationUnlockData
    extends Resource
    @export var unlocked_locations: Array[String] = ["riverside_pond"]

    # settings_data.gd  (extended by Settings & Accessibility #18)
    class_name SettingsData
    extends Resource
    @export var audio_master_volume: float = 1.0
    @export var haptics_enabled: bool = true
    @export var accessibility_flags: Array[String] = []

    # save_state_interface.gd  (Rule 17 DI seam — abstract base; SaveState extends this)
    @abstract
    class_name SaveStateInterface
    extends Node
    @abstract func get_progression() -> ProgressionData
    @abstract func get_catch_log() -> CatchLogData
    @abstract func get_location_unlocks() -> LocationUnlockData
    @abstract func get_settings() -> SettingsData
    @abstract func set_progression(d: ProgressionData) -> void
    @abstract func set_catch_log(d: CatchLogData) -> void
    @abstract func set_location_unlocks(d: LocationUnlockData) -> void
    @abstract func set_settings(d: SettingsData) -> void
    @abstract func request_save(domain: StringName) -> void
    ```

    These stubs make SaveState compilable independently of the four downstream GDDs. Tests inject `MockSaveStateInterface` (extending `SaveStateInterface`, returning controlled fixtures, never touching disk). The `@abstract` decorator (Godot 4.5+; see VERSION.md timeline) makes direct instantiation of `SaveStateInterface` a compile-time error — accidental no-op injection in tests or production is impossible.

    **Critical implementation rule — `get_*()` returns a deep duplicate, not the internal reference.** Resources in Godot are reference-counted, not value types. The Option 4 immutable-update pattern requires that downstream mutations of the returned object do NOT alias SaveState's internal state. Every `get_*()` method MUST:

    ```gdscript
    # IN SaveState (the autoload), NOT in the interface
    func get_progression() -> ProgressionData:
        return _internal_progression.duplicate(true) as ProgressionData
    ```

    The `.duplicate(true)` deep-duplicate is the contract; subclass authors and reviewers must NOT optimize this away. **Dictionary-field deep-copy verification**: `CatchLogData.catch_count` and `CatchLogData.biggest_catch_cm` are `Dictionary` fields. Godot 4.6 `Resource.duplicate(true)` performs deep-copy of Dictionary fields recursively (each nested value is cloned). This must be verified during implementation against the Godot 4.6 source for any nested type (e.g., a hypothetical future `Dictionary[String, Array[Resource]]`); if any nested type does not deep-copy via the built-in mechanism, the affected `get_*()` must perform an explicit per-field copy as a fallback. Flag as engine-programmer verification item.

    **Symmetric rule — `set_*()` consumes ownership.** Each `set_*(data)` method MUST replace SaveState's internal Resource reference with the caller's argument (no further copy needed on the set path — the caller already owns the object, since `get_*()` returned a duplicate). This combination (`get` deep-copies out; `set` adopts in) is what makes Option 4 work as designed.

    **Subclass-field serialization.** When a downstream system extends a stub class with additional `@export var` fields (e.g., `class_name StatProgressionData extends ProgressionData` adds `cast_count: int`), SaveState's serializer MUST discover these fields via `Object.get_property_list()` and serialize all properties tagged `PROPERTY_USAGE_STORAGE` (the default for `@export var`). The deserializer correspondingly assigns each property by name during `JSON → Resource` conversion. Missing fields in the loaded JSON fall back to the Resource's typed default. This pattern allows downstream extensions to evolve without re-authoring SaveState, at the cost of one runtime property-list lookup per save/load (negligible at MVP file sizes).

### States and Transitions

`SaveState` has 6 lifecycle states. Implementation should expose state as a typed enum: `enum State { UNLOADED, LOADING, READY, DIRTY, WRITING, SHUTTING_DOWN }`.

| State | Description |
|---|---|
| `UNLOADED` | Pre-`_ready()` — Autoload exists but has not loaded from disk. |
| `LOADING` | `_ready()` running — disk read + recovery cascade in flight. Synchronous (Rule 14); OS notifications during this window are queued by the OS until the main thread is free. |
| `READY` | Load complete. In-memory state available for `get_*()` / `set_*()` calls. |
| `DIRTY` | A `request_save(domain)` was called for a debounced trigger; the 2-second debounce timer is running; no write yet. |
| `WRITING` | Atomic write in flight (temp open or rename pending). New `request_save()` calls queue and re-enter DIRTY when the write completes. |
| `SHUTTING_DOWN` | Terminal — lifecycle notification received (`PAUSED` or desktop `WM_CLOSE_REQUEST`); all pending domains flushed synchronously; no further saves will occur this session. |

**Transitions**:

| From | Event | To |
|---|---|---|
| UNLOADED | `_ready()` starts | LOADING |
| LOADING | Active load OK | READY |
| LOADING | Active fail, backup1 OK | READY (flag `recovered_from_backup`, `prior_save_file_existed_at_launch = true`) |
| LOADING | Active + backup1 fail, backup2 OK | READY (flag `recovered_from_backup`, `prior_save_file_existed_at_launch = true`) |
| LOADING | All loads fail, any file existed at FS level | READY (flag `full_reset_occurred`, `prior_save_file_existed_at_launch = true`, defaults loaded) |
| LOADING | All loads fail, no file existed at FS level | READY (no flag, `prior_save_file_existed_at_launch = false`, defaults loaded — true first launch) |
| LOADING | Lifecycle notification during load | (queued by OS — Rule 14 synchronous I/O guarantees LOADING completes before the notification is delivered) |
| READY | `request_save(SETTINGS)` | WRITING (bypasses debounce) |
| READY | `request_save(PROGRESSION / CATCH_LOG / LOCATIONS)` | DIRTY (debounce timer starts) |
| DIRTY | Another `request_save` for any domain | DIRTY (timer continues; domains union into pending payload) |
| DIRTY | Debounce timer expires | WRITING |
| WRITING | Another `request_save` for any domain | WRITING (domain queued for the next write cycle) |
| WRITING | Write completes (queue empty) | READY (emit `save_completed(domain)` for each domain written) |
| WRITING | Write completes (queue non-empty) | DIRTY (new debounce timer; queued domains form the pending payload) |
| WRITING | Write fails | READY (emit `save_failed(domain, reason)`; in-memory state unchanged) |
| READY / DIRTY / WRITING | `NOTIFICATION_APPLICATION_FOCUS_OUT` | **flush all pending domains synchronously → READY** (NOT terminal; app may regain focus when partial-occlusion overlay dismisses) |
| READY / DIRTY / WRITING | `NOTIFICATION_APPLICATION_FOCUS_IN` | no-op (already in READY post-FOCUS_OUT flush) |
| READY / DIRTY / WRITING | `NOTIFICATION_APPLICATION_PAUSED` | SHUTTING_DOWN (expected-terminal — app is being backgrounded; OS usually kills process shortly) |
| READY / DIRTY / WRITING | `NOTIFICATION_WM_CLOSE_REQUEST` (desktop only) | SHUTTING_DOWN (truly terminal — window closing) |
| SHUTTING_DOWN | All pending flushed | expected-terminal (awaits OS kill or RESUMED recovery) |
| SHUTTING_DOWN | `NOTIFICATION_APPLICATION_RESUMED` | **READY** (recovery — process survived backgrounding; saves re-enabled) |
| SHUTTING_DOWN | `NOTIFICATION_WM_CLOSE_REQUEST` | terminal (no recovery from window close) |
| SHUTTING_DOWN | Other subsequent notifications | ignored |

The DIRTY → WRITING and WRITING → DIRTY transitions together implement the queued-write pipeline: a `request_save` during an in-flight write does not race the write; it joins the next debounce cycle (with a fresh leading-edge 2s timer starting at the moment the queue becomes non-empty during WRITING). The FOCUS_OUT → flush-then-READY transition is critical for iOS partial-occlusion (Rule 8); the SHUTTING_DOWN → READY transition on RESUMED is critical for the symmetric case of "OS backgrounded the app but did not kill the process." Together these guarantee that no realistic mobile lifecycle path leaves SaveState permanently unable to save.

### Interactions with Other Systems

`SaveState` is consumed by four MVP systems. None of these systems are designed yet; this section defines the contract they will consume.

**Public API surface** (consumed by all four downstream systems via the **immutable update pattern** — see Rule 18 for class definitions):

```gdscript
# Domain constants (StringName; consider enum Domain { ... } as a recommended future revision for typo safety)
const DOMAIN_PROGRESSION: StringName = &"progression"
const DOMAIN_CATCH_LOG:   StringName = &"catch_log"
const DOMAIN_LOCATIONS:   StringName = &"location_unlocks"
const DOMAIN_SETTINGS:    StringName = &"settings"

# Reason codes for save_failed / load_failed (StringName — fast equality + serializable)
const REASON_DISK_FULL:            StringName = &"disk_full"
const REASON_OPEN_FAILED:          StringName = &"open_failed"
const REASON_STORE_FAILED:         StringName = &"store_failed"
const REASON_RENAME_FAILED:        StringName = &"rename_failed"
const REASON_PARSE_FAILED:         StringName = &"parse_failed"
const REASON_VERSION_TOO_NEW:      StringName = &"version_too_new"
const REASON_VERSION_WRONG_TYPE:   StringName = &"version_wrong_type"
const REASON_FILE_NOT_FOUND:       StringName = &"file_not_found"
const REASON_PATH_UNAVAILABLE:     StringName = &"path_unavailable"
const REASON_SERIALIZATION_EMPTY:  StringName = &"serialization_empty"

# Pull — called once during downstream _ready() via _init_from_save() (Rule 17)
# Each getter returns a DEEP DUPLICATE (.duplicate(true)) of SaveState's internal Resource.
# The caller owns the returned object; mutations do not alias SaveState's state. See Rule 18.
func get_progression() -> ProgressionData
func get_catch_log() -> CatchLogData
func get_location_unlocks() -> LocationUnlockData
func get_settings() -> SettingsData

# Push — IMMUTABLE UPDATE PATTERN (Option 4, locked decision)
# Downstream constructs/mutates its own copy, then hands ownership to SaveState.
# Each setter ADOPTS the passed reference as SaveState's new internal state — no further copy.
func set_progression(data: ProgressionData) -> void
func set_catch_log(data: CatchLogData) -> void
func set_location_unlocks(data: LocationUnlockData) -> void
func set_settings(data: SettingsData) -> void

# Trigger save (after one or more set_* calls). Synchronous for SETTINGS; debounced for others.
# THREAD MODEL: All public API calls are single-threaded on the main thread. The two-line
# pattern (set_* then request_save) is safe because GDScript's main thread does not preempt.
# If a future migration to threaded writes occurs, this contract must be revisited.
func request_save(domain: StringName) -> void

# State field — exposed read-only for banner-gating UI controller (Rule 13)
var prior_save_file_existed_at_launch: bool

# Signals (INTERNAL ONLY — Rule 16 prohibits UI subscription)
# Granularity: per-DOMAIN. A corrupt progress.save emits load_failed once per affected domain
# (PROGRESSION, CATCH_LOG, LOCATIONS), not once per file.
signal save_completed(domain: StringName)
signal save_failed(domain: StringName, reason: StringName)
signal load_failed(domain: StringName, reason: StringName)
```

**Mutation mechanism (locked decision — immutable update pattern with deep-copy boundary)**: Downstream systems pull a typed Resource (`get_*()` — returns a **deep duplicate** of SaveState's internal state per Rule 18), mutate their **own** copy (or construct a fresh one), then hand ownership back via `set_*()`. `SaveState` adopts the passed Resource as its new internal state; from that point on the caller MUST NOT continue mutating that reference (or do so with the understanding that the next `request_save` writes whatever's there). `request_save(domain)` triggers the serializer for that domain using SaveState's current in-memory state. This pattern was selected over shared-mutable-reference / registered-serializer-callback / explicit-mutator-API options because it (a) eliminates the snapshot-vs-live-mutation ambiguity, (b) keeps SaveState as the typed single source of truth, (c) makes `MockSaveStateInterface` (Rule 17) trivially specifiable, and (d) — with the deep-copy on `get_*()` — provides genuine isolation between downstream working state and SaveState's persisted shape (without deep-copy this pattern silently degrades to shared-reference mutation — see Rule 18 critical implementation rule).

**Example downstream usage** (Stat Progression #7 after applying a per-catch stat increase):

```gdscript
# In Stat Progression's _init_from_save(save: SaveStateInterface)
_progression = save.get_progression()  # deep duplicate — local typed copy, no aliasing

# Later, after a catch:
_progression.casting_distance += delta_distance
_progression.rod_strength += delta_strength
SaveState.set_progression(_progression)            # SaveState adopts this reference
SaveState.request_save(SaveState.DOMAIN_PROGRESSION)  # trigger debounced save

# To resume mutating safely next frame, fetch a fresh duplicate:
_progression = SaveState.get_progression()
```

**Re-fetch pattern**: Because `set_*` hands SaveState ownership of the reference, the caller's `_progression` is no longer isolated after the set. The next mutation cycle MUST start with `_progression = SaveState.get_progression()` again to obtain a fresh deep-copy. Downstream systems that hold long-lived local references and mutate-in-place across many catches need to refresh after each `set_*`. This is the explicit cost of the deep-copy isolation; it is paid for by eliminating an entire class of aliasing bugs.

**Per-system contract**:

| Downstream System | Domain | Reads | Writes | Notes |
|---|---|---|---|---|
| Stat Progression (#7) | `DOMAIN_PROGRESSION` | `casting_distance`, `rod_strength` | Same | After each per-catch stat increase: mutate local `ProgressionData`, `SaveState.set_progression(data)`, `SaveState.request_save(DOMAIN_PROGRESSION)`. |
| Catch Log UI & Data (#17) | `DOMAIN_CATCH_LOG` | `catch_count[species_id]`, `biggest_catch_cm[species_id]` | Same | After each catch is logged: mutate local `CatchLogData`, `set_catch_log(data)`, `request_save(DOMAIN_CATCH_LOG)`. |
| Location Unlock (#13) | `DOMAIN_LOCATIONS` | `unlocked_locations[]` (default `["riverside_pond"]`) | Same | After an unlock fires: mutate local `LocationUnlockData`, `set_location_unlocks(data)`, `request_save(DOMAIN_LOCATIONS)`. |
| Settings & Accessibility (#18) | `DOMAIN_SETTINGS` | `audio_master_volume`, `haptics_enabled`, `accessibility_flags[]` | Same | After a setting change: mutate local `SettingsData`, `set_settings(data)`, `request_save(DOMAIN_SETTINGS)` — bypasses debounce (immediate write). |

**Ownership boundary**: Each downstream system owns the **shape** of its domain (field names, types, semantics). `SaveState` owns the **plumbing** (when to write, where, in what format, how to recover). A schema change is co-owned: the downstream system updates its shape, and `SaveState` adds a migration function that converts old-shape data to new-shape.

**No upstream dependencies**: `SaveState` does not depend on Touch Input, Cast Direction, or any other system. It is the lowest-level Foundation system in the dependency graph.

**Example `progress.save` content** (illustrative — exact field names are owned by the downstream systems; this is the format `SaveState` will produce):

```json
{
  "schema_version": 1,
  "last_saved_utc": 1747094400,
  "progression": {
    "casting_distance": 12.4,
    "rod_strength": 2.3
  },
  "catch_log": {
    "catch_count": { "sunfish": 17, "bass": 3 },
    "biggest_catch_cm": { "sunfish": 22.1, "bass": 38.5 }
  },
  "location_unlocks": {
    "unlocked_locations": ["riverside_pond"]
  }
}
```

## Formulas

**N/A — this system has no balance or gameplay formulas.**

The two timing thresholds that govern Save & Persistence behavior are not formulas (no variables to balance, no output range to tune for player experience); they are operational thresholds and live in **Tuning Knobs** (Section G):

- **Debounce window** (default 2 s) — collapses rapid `request_save` calls into a single write.
- **Backup rotation gap** (default 5 min) — minimum wall-clock interval between meaningful backup snapshots.

**Migration logic** (Rule 11) is conditional code, not a formula: `_migrate_v1_to_v2(data) -> Dictionary` executes when `loaded_version < CURRENT_SCHEMA_VERSION`. It has no variable ranges or balance characteristics.

**Integrity** (Rule 7) is achieved by atomic temp-write + rename, not by checksum or hash. No formula required.

Revisit this section if Save & Persistence ever takes on responsibilities that involve genuine balance (e.g., a save-slot expiration timer in a future live-ops layer, or compression ratio tuning).

## Edge Cases

Edge cases follow the format `**If [condition]**: [outcome]. [rationale if non-obvious]`.

### (A) Race conditions and timing

1. **If `NOTIFICATION_APPLICATION_PAUSED` fires while `SaveState` is in LOADING**: complete the synchronous load first; the OS queues the notification until the main thread is free. No partial-loaded write occurs. *Rationale*: Rule 14 (synchronous I/O) guarantees LOADING completes before notifications process; documented so a future async migration cannot silently break this boundary.
2. **If `NOTIFICATION_WM_CLOSE_REQUEST` fires while the 2-second debounce is running (DIRTY)**: transition to SHUTTING_DOWN immediately, flush all pending domains synchronously, discard the timer. (Desktop only — does not fire on iOS/Android.)
3. **If two lifecycle notifications fire in rapid sequence** (`FOCUS_OUT` then `PAUSED`): FOCUS_OUT flushes and returns to READY; PAUSED then flushes (no-op if nothing dirty) and transitions to SHUTTING_DOWN. Both notifications process in arrival order; no double-write of the same dirty domain because the FOCUS_OUT flush left the queue empty.
3a. **If `NOTIFICATION_APPLICATION_RESUMED` fires after PAUSED → SHUTTING_DOWN without process termination**: SHUTTING_DOWN → READY (recovery path per Rule 8). Saves are re-enabled for the remainder of the session. This is the dominant iOS path when the user backgrounds the app via the Home button and returns within the OS's process-retention window. Without this transition, every such return would leave the app permanently unable to save — the same class of data-loss bug FOCUS_OUT's redesign fixed.
4. **If `request_save(DOMAIN_SETTINGS)` arrives during a PROGRESSION debounce**: SETTINGS bypasses debounce and writes `settings.save` immediately; the PROGRESSION debounce timer continues uninterrupted. The two writes touch different files and are independent.
4a. **If multiple `request_save(DOMAIN_PROGRESSION)` calls arrive in rapid sequence during DIRTY**: leading-edge debounce per Rule 8 — the timer started by the first call continues counting; subsequent calls only union new domain payloads into the pending write. The timer is NOT reset. The total wall-clock window between READY → DIRTY entry and write fire is always exactly `debounce_seconds`, regardless of how many `request_save` calls arrive within the window.

### (B) Data shape

5. **If `schema_version` is the wrong type** (e.g., string `"1"` instead of int `1`): refuse with `ERR_INVALID_DATA` and cascade to backup1. No silent coercion. *Rationale*: silent type coercion masks encoder bugs.
6. **If `JSON.parse_string` returns a non-Dictionary** (array, `null`, primitive): treat as parse failure and cascade.
7. **If a domain key is entirely missing from the loaded Dictionary** (e.g., `catch_log` key not present): treat the domain as if at typed defaults (Rule 15). A missing domain is valid during the first session before that domain has been written.
8. **If a domain field has the wrong inner type** (e.g., `casting_distance` is a string): `get_*()` defensively casts each field with a fallback to the typed default for that field. Log a warning; do not abort the load. *Rationale*: type coercion within a schema version is `get_*()`'s responsibility, not the migration chain's.
9. **If the save file is zero bytes**: `JSON.parse_string("")` returns `null`, caught by Case 6. No separate handling needed.

### (C) Backup state

10. **If `progress.backup1.save` has a `last_saved_utc` newer than `progress.save`**: impossible per Rule 5 but can occur via external file manipulation. The recovery cascade does NOT use timestamps to choose between files — it tries active → backup1 → backup2 in fixed order. *Documented intent*.
11. **If `progress.backup1.save` exists but `progress.save` does not**: active open fails → backup1 succeeds → `recovered_from_backup = true` banner. Same path as a corrupt active.
12. **If `last_saved_utc` is in the future relative to the device clock** (user set clock back, or NTP corrected backward): rotation gap check computes a non-positive gap → rotation skips → next write overwrites in place. A clock jump backward must not force a rotation that overwrites a valid backup.
12a. **If the device clock jumps FORWARD mid-session** (NTP corrects forward after airplane mode, or timezone change during travel): the gap calculation `now - backup1.last_saved_utc` may suddenly exceed the rotation threshold by a large margin. To prevent a cascade-rotation storm (where every subsequent write within the same session rotates backups, collapsing the two-meaningful-snapshots property), **cap the effective gap at `backup_rotation_gap_seconds + 1`** before the threshold comparison. The clamp prevents a single forward jump from rolling backup2 forward with adjacent-write content. Implementation: `effective_gap = min(now - backup1.last_saved_utc, backup_rotation_gap_seconds + 1)`. After the rotation fires once (consuming the clamped gap), subsequent writes within the same session resume normal threshold behavior because the next gap measurement is post-rotation.
13. **If only `progress.backup1.save` exists** (no active, no backup2): cascade resolves correctly. The absence of backup2 is not an error; rotation has simply not occurred twice yet.

### (D) Platform / sandbox

14. **If `user://` is unavailable at startup** (iOS pre-first-unlock; OS reports the directory but `FileAccess.WRITE` returns a permission error): transition through LOADING to READY with typed defaults, set `full_reset_occurred = true`. **No write is attempted until `request_save` is called later** (after unlock). *Rationale*: a write into an unavailable sandbox leaves a corrupt `.tmp`; deferring is safe because in-memory state is correct. **Verification item open** — confirm iOS `NSFileProtectionClass` default per engine-programmer's findings.
15. **If storage is full** (< 5 KB free): `FileAccess.WRITE` may open but `store_string` returns `false`. Emit `save_failed(domain, "DISK_FULL")`. In-memory state remains valid; the player can continue. The recovery banner is NOT triggered — that mechanism is for *load* failures only. *Rationale*: do not show a modal; the fantasy is invisible saves.
16. **If the save file is locked by an external process** (iCloud Drive sync on iPad / Mac Catalyst): the rename step fails. Emit `save_failed`. Live file is intact. Retry on next trigger.
17. **If the device clock jumps backward mid-session** (NTP correction): in-flight debounce timer fires at its originally scheduled wall-clock moment. Backup rotation gap may be reduced/negative → rotation skips → next write overwrites in place. `last_saved_utc` reflects the corrected (backward) time and is self-consistent.

### (E) Lifecycle / development

18. **If Godot editor hot-reload (`F6`) re-runs the scene**: `SaveState._ready()` re-executes; in-memory state is NOT carried across hot-reloads. The on-disk file is authoritative. *Developer-only edge case* — documented so devs don't expect mid-run mutations to survive a reload.
19. **If the OS kills the app immediately on launch (memory pressure) before any `request_save`**: no write occurs, no `.tmp` is created, the live file is untouched. The next session loads the previous state. No data loss because nothing was dirty.
20. **If the player force-quits and immediately reopens**: the atomic-write guarantees the last completed write is intact. **If a debounce was pending at force-quit time, the catches that landed during the 2-second window since the last completed write are lost.** From the player's perspective: a fish they believed was permanently logged is no longer in the journal. This is the one true data-loss window in the system. The design accepts it because (a) graceful backgrounding via Home button always triggers `PAUSED` flush before `SIGKILL` is possible, so the only path that produces this loss is OS-initiated kill under memory pressure during foreground play OR explicit user force-quit via app-switcher (both rare for a low-RAM-footprint mobile game per Section A target); (b) the window is bounded at `debounce_seconds` (default 2.0s, leading-edge — see Rule 8) regardless of catch rate, so the worst-case loss is a small fixed number of catches, not an entire session; (c) tightening the debounce below 0.5s to eliminate this window would burn battery during rapid-catch play. The honest player-facing summary: in extremely rare cases, the last 1-2 catches before a force-quit may not have been written to disk. Acceptable within the Pillar 2 contract because the historical journal is always safe — only catches still in the active debounce window are at risk, never previously-saved progression.

### (F) Pillar / fantasy cross-check

21. **If a UI element subscribes to `save_completed` or `save_failed` for player-visible feedback**: violates Section B anti-fantasy ("no 'Saving…' spinner"). **Now enforced as Rule 16 (structural rule, not convention)**: these signals are internal to SaveState and the test seam. The Acceptance Criteria (Section H) include a scene-tree-inspection AC verifying no main-scene UI node is connected to these signals.
22. **If `recovered_from_backup` or `full_reset_occurred` banner is queued while the player is mid-cast or mid-fight**: the banner display is gated on Scene Management's "main-screen idle" state — never shown while `FightSystem` or `CastExecution` is non-idle. **Implementation note**: contract with Scene Management (#4) and Fight System (#12); document during their GDD authoring.
23. **If a force-quit occurs mid-fight at low battery**: `_notification()` is not called on SIGKILL; the in-flight catch is not logged. Bounded to the in-progress catch only, not historical progression. Explicitly acceptable per pillar analysis.
24. **If `full_reset_occurred` would fire on a true first-launch device with no prior save**: the banner must NOT show. **Now formalized in Rule 13**: the banner condition is `full_reset_occurred AND prior_save_file_existed_at_launch` (the latter is a Public-API state field set during LOADING when any of the three save-file paths returns a non-`ERR_FILE_NOT_FOUND` open). A first-launch device sees no banner; a device whose prior save corrupted catastrophically sees the warmer "Something went wrong. You're starting fresh." copy.

### Not in this section (owned elsewhere)

- "Player taps Reset Progress in Settings" → Settings & Accessibility GDD (#18)
- "Phone call interrupts a fight" → Fight System GDD (#12)
- "Player is mid-cast when app backgrounds" → Cast Execution GDD (#8)
- "Catch log UI shows stale data after backup recovery" → Catch Log UI GDD (#17); they consume our `load_failed` / banner signal
- "Player installs the app on a second device" → no cloud sync (Overview); product decision, not an edge case

## Dependencies

### Upstream dependencies (this system depends on)

**No upstream game systems.** Save & Persistence is a Foundation-tier system; it does not depend on any other game system.

**Engine API dependencies** (Godot 4.6):
- `FileAccess` (read/write, `store_string` returns `bool` in 4.4+, `flush()` returns void)
- `DirAccess` (atomic `rename`, requires `DirAccess.open("user://")` instance — no static variant in 4.6)
- `JSON` (`stringify` / `parse_string`)
- `Node` + `_notification()` (lifecycle hooks; bypass `process_mode` per Rule 1)
- `Resource` base class (typed save records — Rule 18)
- `OS.get_unix_time_from_system()` (for `last_saved_utc` timestamps)
- OS file-system semantics (POSIX rename atomicity on iOS APFS / Android ext4/F2FS for app-internal storage)

### Downstream dependents (systems that depend on this)

| System | # | Type | Domain | Notes |
|---|---|---|---|---|
| Stat Progression | 7 | **Hard** | `DOMAIN_PROGRESSION` | Reads `casting_distance`, `rod_strength` on init; writes after every per-catch stat update. Cannot function without persistence. |
| Catch Log UI & Data | 17 | **Hard** | `DOMAIN_CATCH_LOG` | Reads `catch_count[species_id]`, `biggest_catch_cm[species_id]` on init; writes after each successful catch. The journal IS the persisted record. |
| Location Unlock | 13 | **Hard** | `DOMAIN_LOCATIONS` | Reads `unlocked_locations[]` on init; writes when an unlock condition fires. Unlocks must survive sessions. |
| Settings & Accessibility | 18 | **Hard** | `DOMAIN_SETTINGS` | Reads `audio_master_volume`, `haptics_enabled`, `accessibility_flags[]` on init; writes on each settings change. Accessibility prefs must survive sessions. |

### Indirect / contractual (banner-gating)

The recovery banner (Rule 13 / Edge Case #22) is the only player-visible output of Save & Persistence. Its display is gated, but **the gating lives in a downstream UI controller — not in `SaveState` itself**.

The recommended wiring:

- **`SaveState`** exposes the session flags `recovered_from_backup` and `full_reset_occurred` (plus, optionally, a single forward-declared signal at implementation time — the exact API is an ADR concern, not GDD).
- **A UI controller** (likely **Stats / HUD UI (#15)** or the main scene controller) subscribes/reads the flag, queries **Scene Management (#4)**'s "main-screen idle" state, and queries **Fight System (#12)** + **Cast Execution (#8)** for non-idle state. It shows the banner only when all conditions align, then clears the flag.

**`SaveState` does NOT call into Scene Management, Fight System, or Cast Execution.** This preserves the Foundation-tier zero-upstream-dependency property; the cross-system coordination lives in the UI controller, which already sits at the Presentation layer with natural access to those state queries.

### Bidirectional consistency — systems-index status

`design/gdd/systems-index.md` lists Save & Persistence as a dependency of **Stat Progression (#7)**, **Location Unlock (#13)**, **Catch Log UI & Data (#17)**, and **Settings & Accessibility (#18)** — all four direct consumers per Section C's contract. Bidirectional consistency holds; no systems-index edit required. (Earlier revisions of this GDD flagged this row as a pending update; the registry was synced during the v1 revision pass.)

### Hard vs. indirect — summary

- **Hard** consumers (4 systems, 4 domains) consume `SaveState`'s public API directly: `get_<domain>()`, `request_save(domain)`, and `save_completed` / `save_failed` / `load_failed` signals. They cannot run without `SaveState` available as an Autoload.
- **Indirect** banner-gating participants (Scene Management, Fight System, Cast Execution) are neither called by `SaveState` nor callers of it. They are queried by a UI controller that subscribes to Save's recovery state and gates banner display.

## Tuning Knobs

These values are designer-adjustable without code changes. Expose them in a single configuration resource (e.g., `save_state_config.tres`) so they can be tuned without touching `save_state.gd`.

| Knob | Default | Safe Range | What it affects | Breaks at extremes |
|---|---|---|---|---|
| `debounce_seconds` | 2.0 | [0.5, 10.0] | Maximum data-loss window on `SIGKILL` force-quit only (graceful background flushes regardless). Affects write rate during rapid catch sequences. | **Too low (< 0.5)**: write storms during rapid catches; battery drain, flash wear on iOS. **Too high (> 10.0)**: noticeable catch loss after a crash — players will see missing journal entries. |
| `backup_rotation_gap_seconds` | 300 (5 min) | [60, 3600] | Minimum wall-clock interval between meaningful backup snapshots. Controls how "different" the two rotating backups are from each other. | **Too low (< 60s)**: backups represent adjacent moments; useless for corruption recovery (a write that corrupts active likely corrupted its immediate predecessor too). **Too high (> 3600s)**: backups stale; recovery rolls back > 1 hour of play. |
| `backup_count` | 2 | [0, 2] | Number of rotating backup snapshots. Disk cost ≈ N × save_size. The safe range is clamped to match Rule 4 + Rule 5, which define exactly two backup slots (`progress.backup1.save`, `progress.backup2.save`). Generalizing to N > 2 is post-MVP. | **0**: no corruption recovery; first bad active = full reset. **1**: single fallback; a write that corrupts both active and backup1 (rare but possible — bad sector, OS error during rotation) leaves no recovery path. **2** (default): two-deep history; the canonical setting. |

### Debug-only knobs (NOT shipped)

Available in dev/QA builds via in-code constants or editor-only configuration. Must be `#ifdef`-guarded or compile-time-stripped before release.

| Knob | Purpose |
|---|---|
| `force_corrupt_active_on_launch` | Pre-corrupts `progress.save` before load to exercise the recovery cascade (Rule 13). |
| `force_full_reset_on_launch` | Skips all load attempts; forces defaults; exercises the `full_reset_occurred` banner path. |
| `disable_lifecycle_flush` | Skips the `_notification()` flush, simulating a `SIGKILL` force-quit; exercises the bounded data-loss window (Edge Case #20). |
| `show_save_status_hud` | Dev-only HUD overlay showing `DIRTY` / `WRITING` / last save outcome. Used during QA, NEVER shipped (would violate the invisible-save fantasy). |

### Out of MVP scope (do not implement)

- Schema-version compile-time guard
- Compression toggle (file sizes don't justify it)
- Threaded write toggle (Rule 14 — synchronous I/O is sufficient at MVP file sizes)
- Cloud sync (explicit non-goal per Overview)
- Multi-slot save selector (MVP is single active slot per Rule 5)

## Visual/Audio Requirements

**N/A.** Save & Persistence is a Foundation/Infrastructure system with no direct visual or audio output. The one player-visible artifact — the recovery banner — is text content emitted by `SaveState` but rendered, styled, and animated by **Stats / HUD UI (#15)**. The banner copy is locked in Rule 13 (single source of truth):

- Backup recovery: *"Your progress picked up where it left off."*
- Full reset: *"Starting fresh."*

These strings are intentionally calm-continuity — they avoid the word "wrong" and frame recovery as a successful continuation, consonant with Pillar 4 ("Silence is a Feature") and the Alto's Adventure tonal reference. Tone, font, animation, dismiss behavior, and color are deferred to the Stats / HUD UI GDD and the art bible — but the words themselves do not change between this GDD and the UI implementation.

## UI Requirements

**N/A.** This system exposes no UI controls. The recovery banner specified in Rule 13 is the only player-facing surface, and its UI specification (placement, dismissal, animation) is owned by **Stats / HUD UI (#15)** per Section F. Save & Persistence emits the state (`recovered_from_backup` / `full_reset_occurred` session flags); the UI controller decides when and how to render.

## Acceptance Criteria

All criteria are GIVEN/WHEN/THEN. Each names its **gate level** per `coding-standards.md`: **BLOCKING** (must pass before story done), **ADVISORY** (evidence required but not auto-blocking).

### Load & first launch

1. **Autoload ordering** — *Logic, BLOCKING*. GIVEN any gameplay scene's `_ready()` runs, WHEN it calls `SaveState.get_<domain>()`, THEN `SaveState.state == READY` (verified via state assertion before the downstream call).
2. **True first launch** — *Logic, BLOCKING*. GIVEN no save files exist in `user://`, WHEN the app launches, THEN `SaveState` reaches `READY` with typed defaults; both `recovered_from_backup` and `full_reset_occurred` are `false`; no banner is queued.
3. **Valid save round-trip** — *Logic, BLOCKING*. GIVEN a valid `progress.save` and `settings.save` with known values, WHEN the app launches, THEN `get_progression()`, `get_catch_log()`, `get_location_unlocks()`, `get_settings()` each return the persisted values exactly.
4. **Integer casting** — *Logic, BLOCKING*. GIVEN a save where `schema_version: 1` and `catch_count: {"sunfish": 17}`, WHEN values are returned through `get_*()`, THEN `typeof(schema_version) == TYPE_INT` and `typeof(catch_count["sunfish"]) == TYPE_INT` (not float).
5. **Typed defaults** — *Logic, BLOCKING*. GIVEN no save exists, WHEN `get_progression()`, `get_location_unlocks()`, and `get_catch_log()` are called, THEN each returns a typed Resource of the correct class (`ProgressionData`, `LocationUnlockData`, `CatchLogData` per Rule 18) with the placeholder defaults specified in Rule 15. **Note**: the placeholder values (`casting_distance = 5.0` pixels, `rod_strength = 1.0`, `unlocked_locations = ["riverside_pond"]`, empty catch log) are owned by their downstream GDDs and may be overridden when those GDDs land. This AC verifies typed-return-shape correctness, not balance values.

### Atomic write (parameterized fault injection)

6. **Atomic write integrity** — *Logic, BLOCKING* (parameterized; uses filesystem sandbox + fault-injection harness from §Test infrastructure). For each step S in {open, store_string, flush, close, rename}: GIVEN the test harness injects a failure at S during a write of `progress.save`, WHEN the app subsequently reloads, THEN `progress.save` is byte-identical to its state before the failed write, no orphan `.tmp` is present in `user://` after relaunch initialization (Rule 7), and `save_failed(DOMAIN_PROGRESSION, <reason>)` was emitted synchronously at S with `reason ∈ {REASON_OPEN_FAILED, REASON_STORE_FAILED, REASON_RENAME_FAILED}` matching the injected step.
7. **Disk full** — *Logic, BLOCKING*. GIVEN `store_string` is forced to return `false` (simulating disk full via fault-injection harness), WHEN a write fires, THEN `save_failed(DOMAIN_PROGRESSION, REASON_STORE_FAILED)` is emitted **synchronously before `request_save` returns** (no wall-clock latency assertion), in-memory state is unchanged, and the live save file is unchanged.
8. **SHUTTING_DOWN is terminal** — *Logic, BLOCKING*. GIVEN `SaveState.state == SHUTTING_DOWN`, WHEN a second lifecycle notification fires (via the lifecycle harness), THEN no second flush is triggered (verified by signal-spy on `save_completed`), the state remains terminal, and no crash occurs.

### Debounce

9. **Debounce coalesce** — *Logic, BLOCKING*. GIVEN `request_save(DOMAIN_PROGRESSION)` is called 10 times within 1 second (timer mock advances), WHEN 2 simulated seconds pass with no further calls, THEN exactly one write to `progress.save` occurs containing the final state, and `save_completed(DOMAIN_PROGRESSION)` fires exactly once.
10. **SETTINGS bypasses debounce** — *Logic, BLOCKING*. GIVEN `request_save(DOMAIN_SETTINGS)` is called, WHEN it is processed, THEN `settings.save` is written **synchronously before `request_save` returns** and `save_completed(DOMAIN_SETTINGS)` is emitted (no wall-clock timing assertion — the SETTINGS path bypasses the debounce timer entirely per Rule 8).
11. **SETTINGS during PROGRESSION debounce** — *Logic, BLOCKING*. GIVEN `request_save(DOMAIN_PROGRESSION)` is called and the timer mock advances 200 ms, then `request_save(DOMAIN_SETTINGS)` is called, WHEN the timer mock advances to the 2-second mark: THEN `settings.save` was written synchronously at the SETTINGS call (before the PROGRESSION debounce expires); `progress.save` is then written at the 2-second mark; both writes touch different files; the PROGRESSION debounce was not reset by the SETTINGS call.

### Lifecycle flush

12. **Debounce + PAUSED → SHUTTING_DOWN (flush + expected-terminal)** — *Logic, BLOCKING*. GIVEN a `DOMAIN_PROGRESSION` debounce is pending, WHEN `SaveState._notification(NOTIFICATION_APPLICATION_PAUSED)` is invoked via the lifecycle harness, THEN after `_notification()` returns: `SaveState.state == SHUTTING_DOWN`, the on-disk `progress.save` content matches the expected post-flush JSON, the debounce timer is no longer scheduled, AND a subsequent `request_save(DOMAIN_PROGRESSION)` while still in SHUTTING_DOWN is a no-op (no write, no signal emission — verifies the expected-terminal-pending-recovery property).

12a. **FOCUS_OUT → flush → READY (not terminal)** — *Logic, BLOCKING*. GIVEN a `DOMAIN_PROGRESSION` debounce is pending, WHEN `SaveState._notification(NOTIFICATION_APPLICATION_FOCUS_OUT)` is invoked, THEN after `_notification()` returns: `SaveState.state == READY` (NOT `SHUTTING_DOWN`), the on-disk `progress.save` reflects the flushed state, AND a subsequent `request_save(DOMAIN_PROGRESSION)` after the notification triggers a fresh debounce that fires normally: `save_completed(DOMAIN_PROGRESSION)` is emitted and the on-disk file reflects the post-FOCUS_OUT mutation. *Rationale*: this AC enforces the iOS partial-occlusion fix from Rule 8.

12b. **PAUSED → SHUTTING_DOWN → RESUMED → READY (recovery path)** — *Logic, BLOCKING*. GIVEN `SaveState.state == SHUTTING_DOWN` (entered via PAUSED with flush completed), WHEN `SaveState._notification(NOTIFICATION_APPLICATION_RESUMED)` is invoked via the lifecycle harness, THEN after `_notification()` returns: `SaveState.state == READY` (recovery), AND a subsequent `set_progression(data)` + `request_save(DOMAIN_PROGRESSION)` triggers a debounced write that fires normally: `save_completed(DOMAIN_PROGRESSION)` is emitted and the on-disk `progress.save` reflects the post-RESUMED mutation. *Rationale*: enforces the data-loss fix for the case "PAUSED was received but the OS did not actually kill the process" (iOS app-switcher return without process termination — Edge Case #3a).

13. **WRITING + PAUSED drains pending** — *Logic, BLOCKING*. GIVEN a write is mid-flight (WRITING state) and other domains are also queued as DIRTY, WHEN `SaveState._notification(NOTIFICATION_APPLICATION_PAUSED)` is invoked, THEN the current write completes AND each pending domain is flushed; on-disk state for each domain reflects its in-memory state at notification time.

### Recovery cascade (parameterized matrix)

14. **Recovery matrix** — *Logic, BLOCKING*. For each row of the matrix below: GIVEN the indicated `user://` file state, WHEN the app launches, THEN `SaveState` reaches `READY` with the expected loaded domain content and the expected flag set, and `load_failed(domain, reason)` is emitted for each file that failed to load.

| # | Active | Backup1 | Backup2 | Prior save existed | Expected READY state from | Flag set |
|---|---|---|---|---|---|---|
| 14a | Valid v1 | * | * | * | Active | none |
| 14b | Corrupt JSON | Valid | * | yes | Backup1 | `recovered_from_backup` |
| 14c | Non-Dict (e.g., `[]`) | Valid | * | yes | Backup1 | `recovered_from_backup` |
| 14d | Zero bytes | Valid | * | yes | Backup1 | `recovered_from_backup` |
| 14e | Corrupt | Corrupt | Valid | yes | Backup2 | `recovered_from_backup` |
| 14f | Corrupt | Corrupt | Corrupt | yes | Defaults | `full_reset_occurred` |
| 14g | Missing | Missing | Missing | no | Defaults | none (true first launch — see AC 2) |
| 14h | `schema_version = 99` | Valid v1 | * | yes | Backup1 | `recovered_from_backup` |
| 14i | `schema_version = "1"` (string) | Valid v1 | * | yes | Backup1 | `recovered_from_backup` |
| 14j | Corrupt | * | * | yes (settings.save also exists, valid) | Defaults for progress domains; settings unaffected | `full_reset_occurred` for progress only; `get_settings()` returns the persisted settings values |
| 14k | Valid v1 | * | * | yes | Active; recovery write fires next `request_save` | Post-recovery active file is byte-valid at CURRENT_SCHEMA_VERSION (verifies recovery cascade completes the rewrite path on the next graceful save trigger) |

15. **Defensive field cast** — *Logic, BLOCKING*. GIVEN a `progress.save` with valid schema but `casting_distance` typed as a string (e.g., `"fast"`), WHEN `get_progression()` is called, THEN `casting_distance` returns `5.0` (typed default), a warning is logged, the load is NOT aborted, and `ERR_INVALID_DATA` is NOT raised.
16. **Rename failure** — *Logic, BLOCKING* (uses fault-injection harness). GIVEN the rename step fails (simulated via harness), WHEN the write sequence runs, THEN `save_failed(domain, REASON_RENAME_FAILED)` fires synchronously, the live `progress.save` is byte-identical to its pre-write state, no orphan `.tmp` remains after `SaveState`'s next launch cleanup, and `SaveState.state` returns to `READY`.
17. **No-write-on-cold-kill** — *Logic, BLOCKING*. GIVEN the app launches and terminates before any `request_save` call, WHEN it relaunches in the test sandbox, THEN `progress.save` is byte-identical to its pre-launch state (verified by hash comparison of the sandbox `user://` directory before and after).

### Banner display

> **Note**: ACs 18–20 depend on Scene Management (#4) and Fight System (#12) idle-state contracts that are not yet designed. These criteria are deferred to integration validation when those GDDs are authored. Until then, treat them as **placeholders** — they describe expected behavior but cannot be tested in isolation.

18. **Banner on recovery** — *Integration, ADVISORY*. GIVEN `recovered_from_backup = true` AND Scene Management reports "main-screen idle", WHEN the next frame renders, THEN the recovery banner is shown exactly once and the flag is cleared.
19. **No banner on true first launch** — *Integration, ADVISORY*. GIVEN `full_reset_occurred = true` but no prior save file existed at launch, WHEN the main scene loads, THEN no banner is shown (refinement per Edge Case #24).
20. **Banner suppressed during fight** — *Integration, ADVISORY*. GIVEN a banner is queued AND Fight System reports "active", WHEN frames render, THEN the banner is NOT shown; AND when Fight System transitions to idle, the banner shows on the next frame.

### Versioning

21. **Forward migration** — *Logic, BLOCKING*. GIVEN a save with `schema_version = 0` (or missing version field), WHEN the app at `CURRENT_SCHEMA_VERSION = 1` loads it, THEN `_migrate_v0_to_v1(data)` runs, returns a new Dictionary distinct from the input, and the migrated data is written back via the atomic-write path; the on-disk file now has `schema_version = 1`.
22. **Newer-save refusal** — *Logic, BLOCKING*. GIVEN a `progress.save` with `schema_version = CURRENT_SCHEMA_VERSION + 1` (the canonical "older app, newer save" case — same code path as AC 14h's far-future `99` per Rule 12; AC 22 is the canonical boundary-value parameterization), WHEN the app launches, THEN the active load is refused with **exactly three `load_failed` emissions**: `load_failed(DOMAIN_PROGRESSION, REASON_VERSION_TOO_NEW)`, `load_failed(DOMAIN_CATCH_LOG, REASON_VERSION_TOO_NEW)`, `load_failed(DOMAIN_LOCATIONS, REASON_VERSION_TOO_NEW)` (one per affected domain in the progress file; settings unaffected). The recovery cascade attempts `progress.backup1.save`, and `SaveState` reaches `READY` from whichever fallback succeeds (or `full_reset_occurred` if all are newer). No data is partial-loaded.

### Backup rotation

23. **Rotation threshold** — *Logic, BLOCKING*. Parameterized: GIVEN `progress.save.last_saved_utc` minus `progress.backup1.save.last_saved_utc` is `gap_seconds`, WHEN a write occurs:
    - GIVEN `gap_seconds = 240` (4 min, < 5 min threshold), THEN rotation does NOT happen; the active file is overwritten in place; `progress.backup1.save` is unchanged.
    - GIVEN `gap_seconds = 360` (6 min, ≥ 5 min threshold), THEN rotation happens: prior active → `progress.backup1.save`, prior `progress.backup1.save` → `progress.backup2.save`, new write → active.
    - GIVEN `gap_seconds = -30` (clock jumped backward), THEN rotation is skipped (same as the < 5 min case); backups are untouched.
    - GIVEN `gap_seconds = 28800` (8 hours — forward NTP correction or timezone change), THEN the effective gap is clamped to `backup_rotation_gap_seconds + 1` (301s) per EC #12a; rotation happens exactly once on this write; subsequent writes within the same session use the post-rotation gap and do not cascade. Verified by performing 3 writes after the simulated forward jump and asserting only the first triggers rotation.
24. **Backup count = 0** — *Config/Data, ADVISORY*. GIVEN `backup_count = 0` via tuning knob AND `progress.save` is corrupt, WHEN the app launches, THEN no backup load is attempted, `SaveState` proceeds directly to defaults with `full_reset_occurred = true`.

### Per-system contract

25. **Multi-domain coalesce** — *Integration, BLOCKING — DEFERRED PENDING DOWNSTREAM GDDs (#7, #13, #17, #18)*. GIVEN a test harness that exercises the SaveState public API directly (no actual downstream-system code required), `set_progression`, `set_catch_log`, `set_location_unlocks`, and `set_settings` are each called within the 2-second debounce window, WHEN the debounce expires, THEN exactly one write to `progress.save` (containing PROGRESSION + CATCH_LOG + LOCATIONS) AND exactly one write to `settings.save` (containing SETTINGS, written immediately at the SETTINGS call) occur, AND `save_completed` is emitted **per domain** (4 emissions total). **Implementation note**: this AC was originally framed as requiring four downstream system stubs; the test can be written today as a pure SaveState unit test calling the API directly. The cross-system integration version (with real downstream systems exercising the contract end-to-end) is deferred to when at least two downstream GDDs (#7, #17) are authored and implemented.
26. **`load_failed` signal — per-domain granularity** — *Logic, BLOCKING*. GIVEN a corrupt `progress.save` (covering 3 domains: PROGRESSION + CATCH_LOG + LOCATIONS), WHEN the app launches and the cascade reaches active-file open, THEN `load_failed` is emitted **once per affected domain** (3 emissions: `load_failed(DOMAIN_PROGRESSION, …)`, `load_failed(DOMAIN_CATCH_LOG, …)`, `load_failed(DOMAIN_LOCATIONS, …)`); each `reason` argument is one of the constants in the `REASON_*` table. The settings domain is unaffected (different file). Per-file emission is **not** the contract.

### Performance (manual, device-only)

> **Note**: ACs 27 and 28 require execution on a physical iPhone 11 (baseline target hardware). Not automatable in CI. Evidence: manual timing capture in `production/qa/evidence/save-perf-[date].md`.

27. **Write budget** — *Performance, ADVISORY*. GIVEN a typical MVP save (~5 KB) AND iPhone 11 hardware, WHEN a single domain write occurs (from build-dict through rename), THEN the entire sequence completes in ≤ 16 ms (one frame at 60 fps), measured with `Time.get_ticks_msec()`.
28. **Load budget** — *Performance, ADVISORY*. GIVEN the same save and hardware, WHEN `SaveState._ready()` runs (from method entry to method return), THEN it completes in ≤ 50 ms.

### Test seam

29. **DI test seam** — *Logic, BLOCKING — DEFERRED PENDING STAT PROGRESSION GDD (#7)*. GIVEN a GUT unit test for Stat Progression that injects a `MockSaveStateInterface` (via `add_child_autofree()` per Rule 17) and calls Stat Progression's `_init_from_save()`, WHEN the test runs to completion, THEN a directory snapshot of `user://` taken before and after the test shows zero file creations, modifications, or deletions; no orphan nodes remain after teardown (`Performance.get_monitor(Performance.OBJECT_NODE_COUNT)` delta is zero); the test completes in under 100 ms. **Implementation note**: this AC cannot be executed until Stat Progression GDD (#7) lands; the deferred classification matches AC 25's pattern. Until then, the `MockSaveStateInterface` infrastructure can be built and tested in isolation against any single downstream system's `_init_from_save` signature.

### Invisible-save fantasy

30. **No save UI** — *UI/Visual, ADVISORY*. GIVEN a 5-minute manual playtest session including catches, location unlocks, and a settings change, **AND the debug HUD overlay `show_save_status_hud` is enabled to verify no recovery condition was triggered during the session** (no `recovered_from_backup` or `full_reset_occurred` flag set — the HUD displays both flags; tester confirms they remain false throughout), WHEN the screen is observed (and recorded), THEN no "Saving…" indicator, spinner, modal, or banner appears at any point in the non-debug UI layer. Evidence: video recording in `production/qa/evidence/save-invisibility-[date].md` with the debug HUD visible in-frame for precondition verification. (Note: the recovery banner is a legitimate player-visible artifact per Rule 13 and is excluded by the GIVEN clause; it is tested separately in AC 18.)

### Negative-rule ACs (structural enforcement)

31. **No `class_name SaveState`** — *Logic, BLOCKING*. GIVEN the SaveState autoload's source file, WHEN scanned by a grep / lint check, THEN the file does NOT contain `class_name SaveState` (would collide with the autoload singleton name per Rule 1). Verified by a CI grep: `grep -L "^class_name SaveState" src/core/save/save_state.gd`.
32. **No subscribed UI signals** — *Logic, BLOCKING — DEFERRED PENDING SCENE MANAGEMENT GDD (#4)*. GIVEN the main gameplay scene tree at runtime (scene path TBD — owned by Scene Management #4; until that GDD lands, the AC is exercised against a dedicated test scene `tests/scenes/save_signal_isolation_test.tscn` that loads SaveState + a representative subset of UI nodes), WHEN the scene tree is inspected for signal connections to `save_completed` / `save_failed` / `load_failed`, THEN no node outside the `SaveState` autoload itself is connected. Verified via `Object.is_connected()` introspection on every Node in the tree. (Test-only mock subclasses of `SaveStateInterface` are not in the gameplay scene tree — they live only in unit-test scopes — and are therefore not subject to this check.)
33. **No periodic-autosave Timer** — *Logic, BLOCKING*. GIVEN the SaveState autoload at runtime, WHEN its children are inspected, THEN it has **zero `Timer` nodes** as children that trigger writes; AND `SaveState`'s source file defines **neither** `_process()` **nor** `_physics_process()` at all (forbidden by definition, not just by call-graph analysis — this is a stronger structural enforcement than "no `request_save` from `_process`"). Verified by `SaveState.get_children().filter(c => c is Timer and c.is_connected(...)).is_empty()` for the runtime check, and by grep against `save_state.gd` for `^func _process` and `^func _physics_process` for the source check.
34. **No async write path** — *Logic, BLOCKING*. GIVEN the SaveState autoload's script, WHEN inspected, THEN it contains no `Thread` member and no `await` keyword inside the write path (`request_save`, `_atomic_write`, or equivalent) — Rule 14 structural enforcement. Verified by a grep against the implementation file.
35. **iOS write-deferred recovery** — *Logic, BLOCKING — BLOCKED ON Open Question #3 (NSFileProtectionClass default)*. Uses sandbox + `user://` permission-error injection (test infrastructure item 8). GIVEN `user://` returns a permission error at startup (simulating iOS pre-first-unlock per EC #14), WHEN SaveState's LOADING completes, THEN `SaveState.state == READY` with typed defaults and `prior_save_file_existed_at_launch = false` (per Rule 13 — permission errors do NOT set the flag); `full_reset_occurred = false` (no actual files were known to exist). AND WHEN the permission state is cleared (sandbox transitions to writable) and a subsequent `request_save(DOMAIN_PROGRESSION)` fires, THEN the write succeeds and `save_completed(DOMAIN_PROGRESSION)` is emitted (verifies deferred-write recovery path). **Engine verification gate**: this AC's design assumption is that `NSFileProtectionClass` on `user://` defaults to a value that produces this transition pattern. If Open Q #3 resolves to a stricter class, the AC's GIVEN must be revised.

---

### Test infrastructure required

This AC set requires the following fixtures and harnesses (high-cost items first):

1. **Filesystem sandbox** — per-test `user://` substitute that can be pre-populated and torn down. Used by AC 3, 6, 7, 14 (matrix including 14j/14k), 15, 16, 17, 21, 23, 25, 29. **Build first.**
2. **`SaveStateInterface` + `MockSaveStateInterface`** — required by AC 29 and all downstream-system unit tests. Interface is defined inline in Rule 18 with `@abstract` decorator and concrete method signatures; no further design dependency on an ADR. Mock pattern: `MockSaveStateInterface extends SaveStateInterface`, overrides each method to return controlled fixtures, lives in `tests/mocks/`. Test usage: `add_child_autofree(mock)` per Rule 17.
3. **Timer mock / simulated time** — required by AC 9, 10, 11 (advance through 2-second debounce in <100 ms test time). Mocks the leading-edge debounce timer behavior per Rule 8.
4. **Lifecycle notification harness** — calls `_notification()` directly. Required by AC 8, 12, 12a, 12b, 13. Must support PAUSED → SHUTTING_DOWN → RESUMED → READY sequence verification.
5. **Fault-injection write harness** — injects failure at each step of the atomic-write sequence. Required by AC 6, 7, 16. Requires the implementation to expose internal write steps through a strategy or virtual method — flag as **implementation ADR concern** (not a design ADR; the API surface is settled, only the mechanism for the test seam is open).
6. **Scene Management / Fight System stubs** — required for AC 18–20 (banner gating) and the dedicated AC 32 test scene. Deferred until those GDDs land.
7. **Device performance harness** — manual protocol for iPhone 11. Required by AC 27, 28.
8. **`user://` permission-state mock** — sandbox extension that can transition between "writable" and "permission-error" mid-test. Required by AC 35 (iOS pre-first-unlock deferred-write recovery). Implementation: the filesystem sandbox (item 1) exposes a `set_permission_state(state: String)` hook that subsequent `FileAccess.open` calls respect. **Blocked on Open Question #3** (`NSFileProtectionClass` default) for the AC's design assumption to be confirmed; the harness itself can be built independently.

## Open Questions

**Not tracked in this GDD per the optional-sections decision during authoring.** See the project session state (`production/session-state/active.md`) for items raised during authoring that are unresolved or depend on future GDDs / ADRs.

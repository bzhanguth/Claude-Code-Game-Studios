## SaveState — atomic, debounced, lifecycle-aware save subsystem.
##
## See design/gdd/save-persistence.md for the full spec. This is the
## production autoload extending SaveStateInterface (the abstract DI seam,
## save-persistence.md Rule 17). Tests inject MockSaveStateInterface (also
## extending SaveStateInterface) to isolate downstream systems from disk I/O.
##
## Per Rule 1: this file does NOT declare `class_name SaveState`
## (autoload-vs-class_name collision documented in Touch Input GDD; still
## required as of Godot 4.6).
##
## Status: scaffold (2026-05-12). State machine, signal contract, public API
## complete. Atomic write, recovery cascade, and JSON ser/de are stubbed —
## marked with TODO comments referencing the GDD rule each must satisfy.
##
## Implementation order recommendation when filling stubs:
##   1. _write_domain          (Rule 7 atomic write — temp + rename)
##   2. _run_load_cascade      (Rule 13 recovery — active → backup1 → backup2 → defaults)
##   3. _probe_prior_save_existence  (Rule 13's `prior_save_file_existed_at_launch`)
##   4. _sweep_orphan_tmps     (Rule 7 idempotent .tmp cleanup)
##   5. _build_payload / _parse_payload  (JSON ser/de with schema_version)
##   6. _migrate_payload       (Rule 11 migration chain)

extends SaveStateInterface

# =============================================================================
# Constants
# =============================================================================

## Per Rule 10. Increment + add a migration when extending the schema.
const CURRENT_SCHEMA_VERSION: int = 1

# File paths under user:// per Rule 4
const PROGRESS_PATH: String = "user://progress.save"
const PROGRESS_BACKUP1_PATH: String = "user://progress.backup1.save"
const PROGRESS_BACKUP2_PATH: String = "user://progress.backup2.save"
const SETTINGS_PATH: String = "user://settings.save"
const PROGRESS_TMP_PATH: String = "user://progress.save.tmp"
const SETTINGS_TMP_PATH: String = "user://settings.save.tmp"

# Save-failure reason codes per Rule 7
const REASON_SERIALIZATION_EMPTY: StringName = &"serialization_empty"
const REASON_OPEN_FAILED: StringName = &"open_failed"
const REASON_STORE_FAILED: StringName = &"store_failed"
const REASON_DISK_FULL: StringName = &"disk_full"
const REASON_RENAME_FAILED: StringName = &"rename_failed"

# Load-failure reason codes per Rule 13
const REASON_FILE_NOT_FOUND: StringName = &"file_not_found"
const REASON_PARSE_FAILED: StringName = &"parse_failed"
const REASON_VERSION_NEWER: StringName = &"version_newer"      # Rule 12 refusal
const REASON_TOTAL_FAILURE: StringName = &"total_failure"      # All cascade paths failed

# =============================================================================
# Enums
# =============================================================================

## State machine per save-persistence.md "States and Transitions" section.
enum State {
	UNLOADED,
	LOADING,
	READY,
	DIRTY,
	WRITING,
	SHUTTING_DOWN,
}

# =============================================================================
# Signals (INTERNAL — UI must NOT subscribe per Rule 16a)
# =============================================================================

signal state_changed(from_state: State, to_state: State)
signal save_completed(domain: StringName)
signal save_failed(domain: StringName, reason: StringName)
signal load_failed(reason: StringName)

# =============================================================================
# Tuning knobs (Section G of save-persistence.md)
# =============================================================================

## Leading-edge debounce window for gameplay save triggers (Rule 8).
@export_range(0.5, 10.0, 0.1) var debounce_seconds: float = 2.0

## Number of rotating backup files (Rule 5). 0 disables backup rotation.
@export_range(0, 2) var backup_count: int = 2

## Gap-based backup rotation threshold in seconds (Rule 5).
@export var backup_rotation_gap_seconds: float = 300.0

# =============================================================================
# Public state (read-only — UI must NOT poll per Rule 16b)
# =============================================================================

var state: State = State.UNLOADED

## Set true if the load cascade recovered from a backup. Rule 13.
## The banner-gating UI controller clears this after one display.
var recovered_from_backup: bool = false

## Set true if total load failure forced defaults. Rule 13.
var full_reset_occurred: bool = false

## True if any save file existed at the FS level at launch. Rule 13.
var prior_save_file_existed_at_launch: bool = false

# =============================================================================
# Internal state
# =============================================================================

# Domain data (deep-copy contract per Rule 18 — get_* returns duplicate,
# set_* adopts caller's reference)
var _internal_progression: ProgressionData = ProgressionData.new()
var _internal_catch_log: CatchLogData = CatchLogData.new()
var _internal_locations: LocationUnlockData = LocationUnlockData.new()
var _internal_meta: MetaData = MetaData.new()
var _internal_settings: SettingsData = SettingsData.new()

# Pending domains awaiting write (set-semantics; values are unused).
var _pending_domains: Dictionary = {}

# Debounce countdown timer in seconds. Counts down in _process when in DIRTY.
var _debounce_timer: float = 0.0

# UTC epoch seconds of last successful progress.save write — used by backup
# rotation gap check (Rule 5).
var _last_saved_utc_progress: int = 0

# Re-entry guard for _flush_pending.
var _writing_in_progress: bool = false

# =============================================================================
# Lifecycle
# =============================================================================

func _ready() -> void:
	_transition_state(State.LOADING)
	_probe_prior_save_existence()
	_run_load_cascade()
	_sweep_orphan_tmps()
	_transition_state(State.READY)


func _process(delta: float) -> void:
	if state == State.DIRTY:
		_debounce_timer -= delta
		if _debounce_timer <= 0.0:
			_flush_pending()


## OS lifecycle notifications per Rule 8. These bypass `process_mode` entirely
## (dispatched by MainLoop via DisplayServer) so PROCESS_MODE_INHERIT is safe.
func _notification(what: int) -> void:
	match what:
		NOTIFICATION_APPLICATION_PAUSED:
			_on_application_paused()
		NOTIFICATION_APPLICATION_RESUMED:
			_on_application_resumed()
		NOTIFICATION_APPLICATION_FOCUS_OUT:
			_on_application_focus_out()
		NOTIFICATION_APPLICATION_FOCUS_IN:
			_on_application_focus_in()
		NOTIFICATION_WM_CLOSE_REQUEST:
			_on_wm_close_request()

# =============================================================================
# Public API — implementations of SaveStateInterface abstract methods
# =============================================================================

func get_progression() -> ProgressionData:
	return _internal_progression.duplicate(true) as ProgressionData


func get_catch_log() -> CatchLogData:
	return _internal_catch_log.duplicate(true) as CatchLogData


func get_location_unlocks() -> LocationUnlockData:
	return _internal_locations.duplicate(true) as LocationUnlockData


func get_meta_data() -> MetaData:
	return _internal_meta.duplicate(true) as MetaData


func get_settings() -> SettingsData:
	return _internal_settings.duplicate(true) as SettingsData


func set_progression(d: ProgressionData) -> void:
	_internal_progression = d


func set_catch_log(d: CatchLogData) -> void:
	_internal_catch_log = d


func set_location_unlocks(d: LocationUnlockData) -> void:
	_internal_locations = d


func set_meta_data(d: MetaData) -> void:
	_internal_meta = d


func set_settings(d: SettingsData) -> void:
	_internal_settings = d


## Request a save of the given domain. Per Rule 8:
##   - SETTINGS bypasses debounce and writes immediately.
##   - PROGRESSION / CATCH_LOG / LOCATIONS / META are debounced (leading-edge).
##
## Calls during SHUTTING_DOWN are silently dropped — no recovery from terminal
## state except via NOTIFICATION_APPLICATION_RESUMED (Rule 8 RESUMED handler).
func request_save(domain: StringName) -> void:
	if state == State.SHUTTING_DOWN:
		return

	if domain == DOMAIN_SETTINGS:
		_pending_domains[DOMAIN_SETTINGS] = true
		_flush_pending()
		return

	_pending_domains[domain] = true
	if state == State.READY:
		# Leading-edge: timer starts on the first transition READY → DIRTY.
		# Subsequent request_save calls during DIRTY do NOT reset the timer
		# (Rule 8 debounce semantics).
		_transition_state(State.DIRTY)
		_debounce_timer = debounce_seconds

# =============================================================================
# State machine
# =============================================================================

func _transition_state(to_state: State) -> void:
	var from_state := state
	state = to_state
	state_changed.emit(from_state, to_state)

# =============================================================================
# Load cascade — Rule 13
# =============================================================================

## Probe all known save-file paths to set `prior_save_file_existed_at_launch`.
## See Rule 13 for the three-way ERR_FILE_NOT_FOUND vs other-error semantics.
func _probe_prior_save_existence() -> void:
	# TODO (Rule 13): probe PROGRESS_PATH, PROGRESS_BACKUP1_PATH, PROGRESS_BACKUP2_PATH.
	#   - All return ERR_FILE_NOT_FOUND          → false (true first launch)
	#   - Any returns a valid handle             → true
	#   - Any returns other error (permissions)  → inconclusive, keep false default
	prior_save_file_existed_at_launch = false


## Run the recovery cascade per Rule 13:
##   1. Try active. On success: done.
##   2. On failure: try backup1. On success: set recovered_from_backup.
##   3. On failure: try backup2. On success: set recovered_from_backup.
##   4. Total failure: defaults already initialized; set full_reset_occurred.
##
## On success of any path, ALSO load settings.save independently.
func _run_load_cascade() -> void:
	# TODO (Rule 13): full cascade. Until then, defaults from field initializers stand.
	pass


## Idempotent sweep of orphan .tmp files left by crashed prior writes.
## Called after the load cascade completes (Rule 7).
func _sweep_orphan_tmps() -> void:
	# TODO (Rule 7): DirAccess.open("user://"); for each known save name,
	# DirAccess.remove(<name>.tmp) and log non-fatal failures.
	pass

# =============================================================================
# Atomic write — Rule 7
# =============================================================================

## Flush all pending domains synchronously, transitioning READY → WRITING
## → READY (or DIRTY if new requests arrived during the write).
func _flush_pending() -> void:
	if _writing_in_progress:
		return
	if _pending_domains.is_empty():
		if state == State.DIRTY:
			_transition_state(State.READY)
		return

	_writing_in_progress = true
	_transition_state(State.WRITING)

	# Snapshot pending domains; new requests during write go to a fresh dict.
	var domains_to_write := _pending_domains.keys()
	_pending_domains = {}

	for domain in domains_to_write:
		_write_domain(domain as StringName)

	_writing_in_progress = false

	# If new requests arrived during the write, transition back to DIRTY with a
	# fresh debounce window. Otherwise READY.
	if not _pending_domains.is_empty():
		_transition_state(State.DIRTY)
		_debounce_timer = debounce_seconds
	else:
		_transition_state(State.READY)


## Bypass debounce — flush all pending domains immediately. Used by lifecycle
## handlers (PAUSED, FOCUS_OUT) per Rule 8.
func _flush_pending_synchronous() -> void:
	_debounce_timer = 0.0
	if not _pending_domains.is_empty():
		_flush_pending()


## Write a single domain via the Rule 7 atomic temp + rename pattern.
## Emits save_completed on success, save_failed(domain, reason) on failure.
func _write_domain(domain: StringName) -> void:
	# TODO (Rule 7): full atomic-write pattern.
	#   1. Build in-memory Dictionary payload for the domain.
	#   2. JSON.stringify with "\t" indent. Bail with REASON_SERIALIZATION_EMPTY.
	#   3. FileAccess.open tmp path with WRITE; check get_open_error.
	#   4. file.store_string(content) — check bool return (Godot 4.4+).
	#   5. file.flush(); file.close().
	#   6. DirAccess.open("user://").rename(tmp_name, real_name); check Error.
	#   7. On success: update _last_saved_utc_progress if domain is progress-family;
	#      apply backup rotation per Rule 5.
	save_completed.emit(domain)

# =============================================================================
# Lifecycle handlers — Rule 8
# =============================================================================

## PAUSED: app is being backgrounded by the OS. Flush all pending, transition
## to SHUTTING_DOWN. Recoverable via NOTIFICATION_APPLICATION_RESUMED.
func _on_application_paused() -> void:
	_flush_pending_synchronous()
	_transition_state(State.SHUTTING_DOWN)


## RESUMED: process survived backgrounding without termination. If we're in
## SHUTTING_DOWN, recover to READY. This is the iOS app-switcher path.
func _on_application_resumed() -> void:
	if state == State.SHUTTING_DOWN:
		_transition_state(State.READY)


## FOCUS_OUT: partial occlusion (notification banner, Control Center, picker).
## App remains in foreground; flush and return to READY. NOT terminal.
func _on_application_focus_out() -> void:
	if state == State.SHUTTING_DOWN:
		return
	_flush_pending_synchronous()
	if state != State.READY:
		_transition_state(State.READY)


## FOCUS_IN: no-op (already in READY post-FOCUS_OUT flush).
func _on_application_focus_in() -> void:
	pass


## WM_CLOSE_REQUEST: desktop only — terminal. Does NOT fire on iOS / Android.
func _on_wm_close_request() -> void:
	_flush_pending_synchronous()
	_transition_state(State.SHUTTING_DOWN)

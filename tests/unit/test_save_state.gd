## SaveState unit tests — exercises the testable BLOCKING ACs from
## design/gdd/save-persistence.md Section H (Acceptance Criteria).
##
## ACs that depend on stubbed implementation (atomic write, recovery cascade,
## JSON ser/de, migration chain, orphan-tmp sweep) are marked `pending()` with
## a reference to the GDD rule and the SaveState method that must be filled in.
##
## Test isolation: each test creates a fresh SaveState instance via
## `preload(...).new()` and adds it via GUT's `add_child_autofree` so the
## node is automatically freed between tests. The autoload `SaveState` global
## is NOT touched.
##
## Run: open Godot, GUT panel (bottom), Run All in tests/unit/.

extends GutTest

const SaveStateScript: GDScript = preload("res://src/core/save_state.gd")

var save_state: SaveStateInterface = null


func before_each() -> void:
	save_state = SaveStateScript.new()
	add_child_autofree(save_state)
	# add_child_autofree triggers _ready(), which runs the load cascade
	# (stubbed) and transitions UNLOADED → LOADING → READY.


# =============================================================================
# State machine — Rules 1, 13 + AC bookkeeping
# =============================================================================

func test_initial_state_after_ready_is_READY() -> void:
	# Per Rule 13: _ready() runs the load cascade and ends in READY (defaults
	# loaded on fresh install). Verifies UNLOADED → LOADING → READY sequence.
	assert_eq(save_state.state, save_state.State.READY, "SaveState should reach READY after _ready()")


func test_fresh_install_does_not_set_recovered_from_backup() -> void:
	# AC #5 implication: fresh install with no save files should leave the
	# session flag false (no banner).
	assert_false(save_state.recovered_from_backup, "recovered_from_backup should be false on fresh install")


func test_fresh_install_does_not_set_full_reset_occurred() -> void:
	# Currently no save files exist, so _run_load_cascade is a no-op and
	# full_reset_occurred stays at its default false. When the cascade is
	# implemented, this test must be updated to reflect the actual semantics
	# (true if any save file existed at FS level but all failed to parse).
	pending("Depends on _run_load_cascade implementation (Rule 13). Currently no-op.")


# =============================================================================
# Public API — get/set ownership contract (Rule 18)
# =============================================================================

func test_get_progression_returns_deep_duplicate() -> void:
	# Rule 18: get_*() returns a deep duplicate. Mutating the returned object
	# must NOT alias SaveState's internal state.
	var first := save_state.get_progression()
	first.casting_distance = 999.0

	var second := save_state.get_progression()
	assert_ne(second.casting_distance, 999.0, "Mutating the get_progression() result must not affect internal state")
	assert_eq(second.casting_distance, 80.0, "Internal state should still hold boot default (80.0)")


func test_get_progression_does_not_alias_catches_per_species() -> void:
	# Rule 18 critical implementation rule: Dictionary fields must deep-copy.
	var first := save_state.get_progression()
	first.catches_per_species["test_species"] = 42

	var second := save_state.get_progression()
	assert_false(second.catches_per_species.has("test_species"), "Mutating get_progression() Dictionary must not alias internal state")


func test_set_progression_adopts_caller_reference() -> void:
	# Rule 18 symmetric rule: set_*() consumes ownership; no further copy on
	# the set path. After set, the next get returns a duplicate of the
	# adopted reference.
	var fresh := ProgressionData.new()
	fresh.casting_distance = 350.0
	fresh.rod_strength = 4.5
	save_state.set_progression(fresh)

	var read_back := save_state.get_progression()
	assert_eq(read_back.casting_distance, 350.0)
	assert_eq(read_back.rod_strength, 4.5)


func test_get_meta_data_returns_default_active_location_id() -> void:
	# Boot default per game-concept.md:250 + scene-location-management.md Rule 1
	var meta := save_state.get_meta_data()
	assert_eq(meta.active_location_id, "riverside_pond", "Boot MetaData should default to 'riverside_pond'")


func test_get_location_unlocks_returns_default_with_riverside_pond() -> void:
	var locations := save_state.get_location_unlocks()
	assert_true(locations.unlocked_locations.has("riverside_pond"), "Boot LocationUnlockData should contain riverside_pond")
	assert_eq(locations.unlocked_locations.size(), 1, "Fresh install should have exactly one unlocked location")


# =============================================================================
# Save triggers — Rule 8
# =============================================================================

func test_request_save_progression_enters_dirty_state() -> void:
	# Rule 8 leading-edge debounce: first request_save transitions READY → DIRTY
	# and starts a 2.0s timer.
	assert_eq(save_state.state, save_state.State.READY, "precondition: READY")
	save_state.request_save(save_state.DOMAIN_PROGRESSION)
	assert_eq(save_state.state, save_state.State.DIRTY, "request_save(PROGRESSION) should transition READY → DIRTY")


func test_request_save_settings_bypasses_debounce() -> void:
	# Rule 8: SETTINGS writes immediately, bypassing the debounce window.
	# Verifies via signal emission: save_completed fires synchronously inside
	# request_save when domain == DOMAIN_SETTINGS.
	watch_signals(save_state)
	save_state.request_save(save_state.DOMAIN_SETTINGS)
	assert_signal_emitted(save_state, "save_completed", "save_completed should fire synchronously for SETTINGS")


func test_request_save_during_shutting_down_is_dropped() -> void:
	# Rule 8 SHUTTING_DOWN semantics: saves no longer accepted (until RESUMED).
	save_state._transition_state(save_state.State.SHUTTING_DOWN)
	watch_signals(save_state)
	save_state.request_save(save_state.DOMAIN_PROGRESSION)
	assert_signal_emit_count(save_state, "save_completed", 0, "request_save during SHUTTING_DOWN must be a no-op")


# =============================================================================
# Signals — Rule 16 invariants
# =============================================================================

func test_state_changed_signal_emits_with_from_to_args() -> void:
	watch_signals(save_state)
	save_state._transition_state(save_state.State.DIRTY)
	# Note: assert_signal_emitted_with_parameters(emitter, name, params, index=-1).
	# The 4th arg is an int index (default -1 = last emission), NOT a message.
	assert_signal_emitted_with_parameters(
		save_state,
		"state_changed",
		[save_state.State.READY, save_state.State.DIRTY]
	)


# =============================================================================
# Lifecycle handlers — Rule 8
# =============================================================================

func test_paused_transitions_to_shutting_down() -> void:
	# PAUSED is expected-terminal but recoverable via RESUMED.
	assert_eq(save_state.state, save_state.State.READY, "precondition: READY")
	save_state._on_application_paused()
	assert_eq(save_state.state, save_state.State.SHUTTING_DOWN, "PAUSED should transition READY → SHUTTING_DOWN")


func test_resumed_recovers_from_shutting_down_to_ready() -> void:
	# Rule 8 RESUMED handler: if state == SHUTTING_DOWN, recover to READY.
	# This is the data-loss fix for iOS app-switcher path (PAUSED received,
	# OS didn't kill the process, user came back).
	save_state._on_application_paused()
	assert_eq(save_state.state, save_state.State.SHUTTING_DOWN, "precondition")
	save_state._on_application_resumed()
	assert_eq(save_state.state, save_state.State.READY, "RESUMED from SHUTTING_DOWN should recover to READY")


func test_resumed_when_not_shutting_down_is_noop() -> void:
	# Rule 8: RESUMED is no-op if state != SHUTTING_DOWN (clean app launch).
	assert_eq(save_state.state, save_state.State.READY, "precondition")
	save_state._on_application_resumed()
	assert_eq(save_state.state, save_state.State.READY, "RESUMED in READY should be no-op")


func test_focus_out_does_not_transition_to_shutting_down() -> void:
	# Rule 8: FOCUS_OUT is for partial occlusion (notification banner, Control
	# Center). App stays in foreground; SHUTTING_DOWN would be a data-loss bug.
	assert_eq(save_state.state, save_state.State.READY, "precondition")
	save_state._on_application_focus_out()
	assert_ne(save_state.state, save_state.State.SHUTTING_DOWN, "FOCUS_OUT must NOT transition to SHUTTING_DOWN")


func test_wm_close_request_transitions_to_shutting_down() -> void:
	# Rule 8: WM_CLOSE_REQUEST is desktop-only and truly terminal (no recovery).
	save_state._on_wm_close_request()
	assert_eq(save_state.state, save_state.State.SHUTTING_DOWN)


# =============================================================================
# Pending tests — waiting on stubbed implementation
# =============================================================================

func test_atomic_write_uses_temp_then_rename() -> void:
	pending("Rule 7 atomic write pattern is stubbed in _write_domain. Test requires actual disk I/O.")


func test_recovery_cascade_active_then_backup1_then_backup2_then_defaults() -> void:
	pending("Rule 13 cascade is stubbed in _run_load_cascade. Test requires fixture save files.")


func test_schema_version_migration_runs_for_older_saves() -> void:
	pending("Rule 11 migration chain is stubbed. Test requires fixture save with schema_version < CURRENT.")


func test_newer_save_refusal_with_invalid_data_error() -> void:
	pending("Rule 12 newer-save refusal is stubbed. Test requires fixture save with schema_version > CURRENT.")


func test_backup_rotation_skips_when_gap_under_threshold() -> void:
	pending("Rule 5 gap-based backup rotation is stubbed. Test requires fixture save files with timestamps.")


func test_orphan_tmp_sweep_removes_leftover_files() -> void:
	pending("Rule 7 orphan-tmp sweep is stubbed in _sweep_orphan_tmps. Test requires fixture .tmp files in user://")

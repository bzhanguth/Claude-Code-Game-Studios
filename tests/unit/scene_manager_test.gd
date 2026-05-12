## SceneManager unit tests — exercises testable BLOCKING ACs from
## design/gdd/scene-location-management.md Section H.
##
## Test isolation strategy: SceneManager._ready() awaits a process_frame and
## then asserts /root/Main exists (via _resolve_main_scene_refs). In tests we
## don't want to mount a full Main.tscn, so we instantiate SceneManager
## WITHOUT adding it to the scene tree — _ready() never fires, refs stay null,
## state stays at the default BOOTING. Tests then directly manipulate state
## and call public methods to exercise pure-logic paths.
##
## Tests that require the full boot pipeline (location-scene load, fade
## tween, threaded load, META save) are marked `pending()`.
##
## Run: open Godot, GUT panel, Run All in tests/unit/.

extends GutTest

const SceneManagerScript: GDScript = preload("res://src/core/scene_manager.gd")

var sm: Node = null


func before_each() -> void:
	sm = SceneManagerScript.new()
	# Intentionally do NOT add to scene tree. We want _ready() to NOT fire
	# so the Main.tscn ref-resolution assertions don't trip. State stays at
	# default BOOTING; tests manually set state to exercise transitions.


func after_each() -> void:
	if is_instance_valid(sm):
		sm.free()
	sm = null


# =============================================================================
# main_screen_idle predicate — Rule 8 truth table
# =============================================================================

func _setup_idle_state() -> void:
	# Helper: set sm to the "fully idle" state for main_screen_idle tests.
	sm.state = sm.State.IN_LOCATION
	sm._cast_idle = true
	sm._fight_idle = true
	# _modal_count is 0 by default


func test_main_screen_idle_true_when_all_inputs_true() -> void:
	_setup_idle_state()
	assert_true(sm.main_screen_idle, "main_screen_idle should be true when IN_LOCATION + cast_idle + fight_idle + modal_count==0")


func test_main_screen_idle_false_when_transitioning() -> void:
	_setup_idle_state()
	sm.state = sm.State.TRANSITIONING
	assert_false(sm.main_screen_idle, "main_screen_idle must be false during TRANSITIONING")


func test_main_screen_idle_false_when_booting() -> void:
	_setup_idle_state()
	sm.state = sm.State.BOOTING
	assert_false(sm.main_screen_idle, "main_screen_idle must be false during BOOTING")


func test_main_screen_idle_false_when_cast_active() -> void:
	_setup_idle_state()
	sm._cast_idle = false
	assert_false(sm.main_screen_idle, "main_screen_idle must be false when _cast_idle == false")


func test_main_screen_idle_false_when_fight_active() -> void:
	_setup_idle_state()
	sm._fight_idle = false
	assert_false(sm.main_screen_idle, "main_screen_idle must be false when _fight_idle == false")


func test_main_screen_idle_false_when_modal_open() -> void:
	_setup_idle_state()
	sm.push_modal()
	assert_false(sm.main_screen_idle, "main_screen_idle must be false when a modal is open")


func test_main_screen_idle_false_with_multiple_modals() -> void:
	_setup_idle_state()
	sm.push_modal()
	sm.push_modal()
	sm.push_modal()
	assert_false(sm.main_screen_idle, "main_screen_idle must be false with any modal_count > 0")


# =============================================================================
# Modal ref-count — Rule 8 + EC #13
# =============================================================================

func test_push_modal_disables_idle() -> void:
	_setup_idle_state()
	assert_true(sm.main_screen_idle)
	sm.push_modal()
	assert_false(sm.main_screen_idle)


func test_pop_modal_restores_idle_when_balanced() -> void:
	_setup_idle_state()
	sm.push_modal()
	sm.pop_modal()
	assert_true(sm.main_screen_idle, "balanced push/pop should restore main_screen_idle")


func test_nested_modals_require_balanced_pops() -> void:
	_setup_idle_state()
	sm.push_modal()
	sm.push_modal()
	sm.pop_modal()
	assert_false(sm.main_screen_idle, "one pop after two pushes should leave idle false")
	sm.pop_modal()
	assert_true(sm.main_screen_idle, "balanced pops should restore idle")


# =============================================================================
# rod_grip_position — Rule 14 + EC #11
# =============================================================================

func test_get_rod_grip_position_returns_sentinel_when_booting() -> void:
	# State default is BOOTING (not IN_LOCATION). EC #11: any non-IN_LOCATION
	# returns the sentinel Vector2(-1, -1).
	assert_eq(sm.state, sm.State.BOOTING, "precondition: state == BOOTING")
	assert_eq(sm.get_rod_grip_position(), sm.ROD_GRIP_SENTINEL, "must return sentinel outside IN_LOCATION")


func test_get_rod_grip_position_returns_sentinel_when_transitioning() -> void:
	sm.state = sm.State.TRANSITIONING
	assert_eq(sm.get_rod_grip_position(), sm.ROD_GRIP_SENTINEL)


func test_get_rod_grip_position_returns_sentinel_when_loading() -> void:
	sm.state = sm.State.LOADING_LOCATION
	assert_eq(sm.get_rod_grip_position(), sm.ROD_GRIP_SENTINEL)


func test_rod_grip_sentinel_value_is_negative_per_contract() -> void:
	# EC #11: sentinel must be a negative coordinate. Cast Direction & Aiming
	# treats any negative coordinate as "rod-grip not available."
	assert_lt(sm.ROD_GRIP_SENTINEL.x, 0.0, "sentinel x must be negative")
	assert_lt(sm.ROD_GRIP_SENTINEL.y, 0.0, "sentinel y must be negative")


# =============================================================================
# State machine — signal emissions
# =============================================================================

func test_state_changed_signal_emits_with_from_to_args() -> void:
	watch_signals(sm)
	sm._transition_state(sm.State.IN_LOCATION)
	assert_signal_emitted_with_parameters(
		sm,
		"state_changed",
		[sm.State.BOOTING, sm.State.IN_LOCATION],
		"state_changed should emit with (from, to) state values"
	)


# =============================================================================
# Constants — Rule 3, Rule 14
# =============================================================================

func test_fade_overlay_layer_is_above_hud_layer() -> void:
	# Rule 3 invariant: FadeOverlay (layer=100) must render above HUD (layer=10)
	# so the black absorbs everything during transitions.
	assert_gt(sm.FADE_OVERLAY_LAYER, sm.HUD_LAYER, "FADE_OVERLAY_LAYER must be > HUD_LAYER")


func test_default_location_id_matches_mvp_starting_location() -> void:
	# Per game-concept.md:250: Riverside Pond is the MVP starting location.
	assert_eq(sm.DEFAULT_LOCATION_ID, "riverside_pond")


func test_location_scene_paths_contains_mvp_locations() -> void:
	# Rule 4.3 fallback: hardcoded path constant must contain both MVP locations.
	assert_true(sm.LOCATION_SCENE_PATHS.has("riverside_pond"))
	assert_true(sm.LOCATION_SCENE_PATHS.has("deep_lake"))


# =============================================================================
# Tuning knob safe ranges — Section G
# =============================================================================

func test_default_fade_durations_are_within_safe_range() -> void:
	assert_true(sm.fade_out_duration >= 0.0 and sm.fade_out_duration <= 1.0, "fade_out_duration must be in [0, 1]")
	assert_true(sm.fade_in_duration >= 0.0 and sm.fade_in_duration <= 1.0, "fade_in_duration must be in [0, 1]")


func test_default_load_timeout_is_within_safe_range() -> void:
	assert_true(sm.load_timeout_seconds >= 1.0 and sm.load_timeout_seconds <= 30.0, "load_timeout_seconds must be in [1, 30]")


# =============================================================================
# Pending tests — waiting on stubbed implementation
# =============================================================================

func test_travel_to_self_location_is_noop() -> void:
	pending("Requires _ready() boot pipeline to be implemented (Rule 4) so active_location_id is set.")


func test_travel_to_unlocked_destination_completes_transition() -> void:
	pending("Requires full Rule 11 transition pipeline (threaded load + fade + scene swap + META save).")


func test_travel_to_locked_destination_is_rejected() -> void:
	pending("Rule 7.4 — needs Save's LOCATIONS domain populated for the test fixture.")


func test_travel_requested_signal_fires_before_fade_out() -> void:
	pending("EC #1 — requires the fade-tween portion of travel_to (Rule 11.4) to be implemented.")


func test_load_failure_rolls_back_to_prior_location() -> void:
	pending("Rule 13 failure-mode rollback — requires threaded-load failure injection.")


func test_meta_save_fires_on_transition_complete_not_start() -> void:
	pending("Rule 6 save-timing invariant — requires the full transition pipeline + SaveState mock.")


func test_boot_emits_boot_completed_signal() -> void:
	pending("Requires Rule 4 boot pipeline + a mock SaveState providing active_location_id.")

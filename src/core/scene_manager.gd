## SceneManager — owns active location, scene transitions, modal ref-count.
##
## See design/gdd/scene-location-management.md for the full spec. This is the
## production autoload that the gameplay tier consumes for travel, modal
## coordination, and `main_screen_idle` predicate (used by Save's banner-gating
## UI controller).
##
## Per Rule 2: this file does NOT declare `class_name SceneManager`
## (autoload-vs-class_name collision; same precedent as Touch Input, Save).
## Registered in project.godot's [autoload] as `SceneManager`, second entry
## after `SaveState`.
##
## Status: scaffold (2026-05-12). State machine + signal contract + public
## API complete. The threaded scene load (Rule 11.3-5), fade tween (Rule
## 11.4 / 11.10), 2-frame settle (Rule 11.8), and META save (Rule 11.9) are
## stubbed — marked with TODOs referencing the rule each must satisfy.
##
## ADR-001 compliance: SceneManager subscribes to CastExecution.cast_state_changed
## and FightSystem.fight_state_changed during its own _ready(). Those autoloads
## don't exist yet at MVP-bootstrap; subscription is deferred and noted with
## TODO (Cast Execution #8 + Fight System #12 not yet authored).

extends Node

# =============================================================================
# Constants
# =============================================================================

## Layer ordering per Rule 3. Project convention: location scenes must NOT
## use a CanvasLayer with layer > 50, to guarantee FadeOverlay always renders
## on top.
const FADE_OVERLAY_LAYER: int = 100
const HUD_LAYER: int = 10

## Sentinel returned by get_rod_grip_position when state != IN_LOCATION
## (Rule 14 + EC #11). Cast Direction & Aiming (#6) treats any negative
## coordinate as "rod-grip not available."
const ROD_GRIP_SENTINEL: Vector2 = Vector2(-1, -1)

## MVP fallback location-scene paths per Rule 4.3 — replaced by LocationCatalog
## (#9) when that autoload lands. Keep this constant in lockstep with the
## .tres entries in res://design/data/locations/ until Catalog migration.
const LOCATION_SCENE_PATHS: Dictionary = {
	"riverside_pond": "res://src/locations/riverside_pond/riverside_pond.tscn",
	"deep_lake": "res://src/locations/deep_lake/deep_lake.tscn",
}

## Default location for fresh installs (EC #5 fallback). Locked to MVP starting
## location per game-concept.md:250.
const DEFAULT_LOCATION_ID: String = "riverside_pond"

# =============================================================================
# Enums
# =============================================================================

## State machine per scene-location-management.md "States and Transitions".
enum State {
	BOOTING,
	LOADING_LOCATION,
	IN_LOCATION,
	TRANSITIONING,
}

# =============================================================================
# Signals
# =============================================================================

## Signals state transitions. Useful for tests and the banner-gating predicate.
signal state_changed(from_state: State, to_state: State)

## Fired once at app launch when the boot location finishes loading and
## state transitions to IN_LOCATION. Per Rule 4.6.
signal boot_completed(location_id: String)

## Fired at the start of every travel_to call, before fade-out tween begins.
## Audio (#3) subscribes for ambient crossfade.
signal transition_started(from_id: String, to_id: String)

## Fired when state returns to IN_LOCATION after a successful travel. Audio
## (#3) subscribes for ambient crossfade completion. Stats/HUD UI (#15)
## subscribes for Travel button re-enable.
signal transition_completed(target_id: String)

## Per EC #1: fired synchronously BEFORE fade-out begins, to give Cast
## Execution (#8) a window to call its own abort_active_cast() and cancel
## any in-flight lure without it counting as a catch attempt.
signal travel_requested(from_id: String, to_id: String)

## Fired on threaded-load failure or instantiate() returning null (Rule 13
## failure-mode rollback). No UI consumer in MVP; analytics/debug only.
signal location_load_failed(target_id: String, reason: StringName)

# =============================================================================
# Tuning knobs (Section G of scene-location-management.md)
# =============================================================================

@export_range(0.0, 1.0, 0.05) var fade_out_duration: float = 0.4
@export_range(0.0, 1.0, 0.05) var fade_in_duration: float = 0.4
@export_range(1.0, 30.0, 0.5) var load_timeout_seconds: float = 5.0

# =============================================================================
# Public state (read-only)
# =============================================================================

var state: State = State.BOOTING
var active_location_id: String = ""

# =============================================================================
# Internal state
# =============================================================================

## Cached idle state from gameplay-tier signals per ADR-001 / Rule 8.
## Boot defaults to true so main_screen_idle is computable before Cast
## Execution and Fight System emit their _ready() ground-truth signals.
var _cast_idle: bool = true
var _fight_idle: bool = true

## Modal ref-count per Rule 8. Incremented by push_modal(), decremented by
## pop_modal(). Clamped to floor of 0 in release builds (EC #13).
var _modal_count: int = 0

## Node references into Main.tscn. Resolved in _post_main_setup (deferred
## from _ready because autoload _ready runs BEFORE the main scene mounts).
var _location_container: Node2D = null
var _hud_layer: CanvasLayer = null
var _fade_overlay: CanvasLayer = null
var _fade_rect: ColorRect = null

## The currently-active location scene — sole child of _location_container
## while state == IN_LOCATION.
var _active_location_scene: Node = null

# =============================================================================
# Public API
# =============================================================================

## main_screen_idle: true when the player is at a moment that disruptive UI
## (e.g., Save's recovery banner) can safely appear. Per Rule 8:
##   state == IN_LOCATION ∧ _cast_idle ∧ _fight_idle ∧ _modal_count == 0
var main_screen_idle: bool:
	get:
		return state == State.IN_LOCATION \
			and _cast_idle \
			and _fight_idle \
			and _modal_count == 0


## Returns the rod-grip world position for the active location, or
## ROD_GRIP_SENTINEL (Vector2(-1, -1)) if not currently IN_LOCATION.
## Per Rule 14 + EC #11. Cast Direction & Aiming (#6) must check for negative
## coordinates before beginning an aim cycle.
func get_rod_grip_position() -> Vector2:
	if state != State.IN_LOCATION:
		return ROD_GRIP_SENTINEL
	if _active_location_scene == null:
		return ROD_GRIP_SENTINEL
	if not (_active_location_scene is LocationBase):
		# Per EC #7: location scene doesn't extend LocationBase. Sentinel return
		# keeps the player in a playable (rod-less) state until the issue is fixed.
		return ROD_GRIP_SENTINEL
	return (_active_location_scene as LocationBase).get_rod_grip_position()


## Travel to target_id. Per Rule 11 sequence:
##   1. Assert state == IN_LOCATION ∧ _fight_idle (defensive).
##   2. State → TRANSITIONING; emit travel_requested + transition_started.
##   3. Threaded load + fade-out (parallel).
##   4. Poll until LOADED or timeout; on failure → Rule 13 rollback.
##   5. Instantiate; free prior; add to LocationContainer; 2-frame settle.
##   6. Update active_location_id; write META + request_save(DOMAIN_META).
##   7. Fade-in; state → IN_LOCATION; emit transition_completed.
##
## No-op cases:
##   - target_id == active_location_id (Rule 7.5).
##   - target_id not in unlocked_locations (Rule 7.4).
##   - state != IN_LOCATION (assert in debug; silent return in release).
func travel_to(target_id: String) -> void:
	# Defensive assertions per Rule 11.1
	assert(state == State.IN_LOCATION, "travel_to called outside IN_LOCATION (state=%s)" % State.keys()[state])
	assert(_fight_idle, "travel_to called while mid-fight")

	# Rule 7.5: no-op self-travel
	if target_id == active_location_id:
		return

	# Rule 7.4: locked-destination guard (read unlocked list from Save)
	var locations := SaveState.get_location_unlocks()
	if not locations.unlocked_locations.has(target_id):
		push_warning("SceneManager.travel_to: '%s' is not in unlocked_locations; ignoring" % target_id)
		return

	# EC #1: emit travel_requested BEFORE fade-out so Cast Execution can abort
	var prior_id := active_location_id
	travel_requested.emit(prior_id, target_id)
	await get_tree().process_frame  # let Cast Execution's abort settle

	# TODO (Rule 11.2-11): full transition pipeline. For scaffold, perform the
	# state machine bookkeeping so consumers can wire up signals. The actual
	# scene-swap + fade + threaded load are stubbed.
	_transition_state(State.TRANSITIONING)
	transition_started.emit(prior_id, target_id)

	# --- TODO Rule 11.3-11.10: threaded load + fade + swap + settle ---
	# 3. ResourceLoader.load_threaded_request(target_path)
	# 4. Fade-out tween (await t.finished)
	# 5. Poll load_threaded_get_status; handle THREAD_LOAD_FAILED / INVALID_RESOURCE
	# 6. ResourceLoader.load_threaded_get -> PackedScene; instantiate; null-check
	# 7. _location_container.get_child(0).queue_free(); add new scene
	# 8. await two process_frames for GPU texture upload + new-scene _ready()
	# 9. Update active_location_id; SaveState.set_meta + request_save(DOMAIN_META)
	# 10. Fade-in tween (await t.finished)

	active_location_id = target_id
	_persist_active_location()

	_transition_state(State.IN_LOCATION)
	transition_completed.emit(target_id)


## Push a modal. Used by Settings (#18), Catch Log UI (#17), and SceneManager's
## own location picker. Affects main_screen_idle predicate.
func push_modal() -> void:
	_modal_count += 1


## Pop a modal. In debug builds, asserts `_modal_count >= 1` before decrement
## (EC #13). In release builds, clamps to a floor of 0 — prevents a consumer
## bug from making main_screen_idle "more true than possible."
func pop_modal() -> void:
	assert(_modal_count >= 1, "pop_modal called with _modal_count == 0 (consumer underflow)")
	_modal_count = max(0, _modal_count - 1)

# =============================================================================
# Lifecycle
# =============================================================================

func _ready() -> void:
	# Autoload _ready() runs BEFORE Main.tscn is mounted. Await one frame so
	# get_tree().root.get_node("Main") returns a valid reference before we
	# touch any scene-tree children.
	await get_tree().process_frame

	# In CLI test contexts (e.g., `godot -s addons/gut/gut_cmdln.gd`), the GUT
	# script replaces run/main_scene — Main.tscn never mounts. Skip all
	# Main-dependent setup so autoloads don't crash test runs. Production
	# bootstraps run/main_scene normally and reach the full pipeline below.
	if get_tree().root.get_node_or_null("Main") == null:
		push_warning("SceneManager: /root/Main not mounted; skipping boot pipeline. Expected in CLI test contexts.")
		return

	_resolve_main_scene_refs()
	_subscribe_to_gameplay_signals()
	await _boot_load_active_location()


## Resolve references into Main.tscn. Called from _ready() after the first
## process_frame yields. If Main.tscn is malformed (missing LocationContainer,
## HUD, or FadeOverlay), this method asserts and the game enters an
## unrecoverable state — Main.tscn is project-critical infrastructure.
func _resolve_main_scene_refs() -> void:
	var root := get_tree().root
	_location_container = root.get_node_or_null("Main/LocationContainer") as Node2D
	_hud_layer = root.get_node_or_null("Main/HUD") as CanvasLayer
	_fade_overlay = root.get_node_or_null("Main/FadeOverlay") as CanvasLayer
	if _fade_overlay != null:
		_fade_rect = _fade_overlay.get_node_or_null("FadeRect") as ColorRect
	assert(_location_container != null, "Main.tscn is missing /Main/LocationContainer")
	assert(_hud_layer != null, "Main.tscn is missing /Main/HUD")
	assert(_fade_overlay != null, "Main.tscn is missing /Main/FadeOverlay")
	assert(_fade_rect != null, "Main.tscn is missing /Main/FadeOverlay/FadeRect")


## Subscribe to gameplay-tier idle signals per ADR-001 / Rule 8.
## At MVP-bootstrap, neither CastExecution (#8) nor FightSystem (#12)
## autoloads exist; this is a no-op until those land.
func _subscribe_to_gameplay_signals() -> void:
	# TODO (ADR-001): subscribe to gameplay signals when those autoloads land.
	#   if has_node("/root/CastExecution"):
	#       CastExecution.cast_state_changed.connect(_on_cast_state_changed)
	#   if has_node("/root/FightSystem"):
	#       FightSystem.fight_state_changed.connect(_on_fight_state_changed)
	pass


## Boot the active location per Rule 4 sequence.
func _boot_load_active_location() -> void:
	_transition_state(State.LOADING_LOCATION)

	# Rule 4.2: read active_location_id from SaveState's META domain
	var meta := SaveState.get_meta_data()
	var boot_id := meta.active_location_id

	# EC #5: if persisted ID is not in unlocked_locations, fall back
	var locations := SaveState.get_location_unlocks()
	if not locations.unlocked_locations.has(boot_id):
		push_warning("SceneManager: persisted active_location_id '%s' not in unlocked_locations; falling back to '%s'" % [boot_id, DEFAULT_LOCATION_ID])
		boot_id = DEFAULT_LOCATION_ID
		meta.active_location_id = boot_id
		SaveState.set_meta_data(meta)
		SaveState.request_save(SaveStateInterface.DOMAIN_META)

	# Rule 4.3: resolve path via fallback constant (replaced by LocationCatalog later)
	var scene_path: String = LOCATION_SCENE_PATHS.get(boot_id, "")
	if scene_path.is_empty():
		push_error("SceneManager: no scene path for boot location '%s'" % boot_id)
		return

	# TODO (Rule 4.4-4.5): synchronous load + instantiate + add as child of
	# _location_container. No fade on cold launch per Rule 4.6.
	#   var packed := load(scene_path) as PackedScene
	#   if packed == null: ... fatal
	#   _active_location_scene = packed.instantiate()
	#   _location_container.add_child(_active_location_scene)

	active_location_id = boot_id
	_transition_state(State.IN_LOCATION)
	boot_completed.emit(boot_id)

# =============================================================================
# Internal helpers
# =============================================================================

func _transition_state(to_state: State) -> void:
	var from_state := state
	state = to_state
	state_changed.emit(from_state, to_state)


## Persist the new active_location_id via Save's META domain. Per Rule 6:
## fires on transition COMPLETE, not on start — if the app is force-killed
## mid-transition, the player reopens at the prior location.
func _persist_active_location() -> void:
	var meta := SaveState.get_meta_data()
	meta.active_location_id = active_location_id
	SaveState.set_meta_data(meta)
	SaveState.request_save(SaveStateInterface.DOMAIN_META)


## Signal handler for CastExecution.cast_state_changed (ADR-001 inversion).
## Subscribed by _subscribe_to_gameplay_signals when Cast Execution autoload lands.
func _on_cast_state_changed(is_active: bool) -> void:
	_cast_idle = not is_active


## Signal handler for FightSystem.fight_state_changed (ADR-001 inversion).
## Subscribed by _subscribe_to_gameplay_signals when Fight System autoload lands.
func _on_fight_state_changed(is_active: bool) -> void:
	_fight_idle = not is_active

# PROTOTYPE - NOT FOR PRODUCTION
# Question: Can a touch-driven, visually-responsive rod give the player enough
#           tension feedback to read a fight rhythm without a UI tension bar?
# Date: 2026-05-11

extends Node2D

# === Layout constants ===
# Rod is at the bottom (first-person POV — player holds rod at bottom of view).
# Water/ocean fills the upper region. Fish swims in water. Rod tip pokes up into the water area.
const ROD_GRIP_NORM := Vector2(0.5, 0.92)        # rod handle at the bottom (player view)
const ROD_NEUTRAL_OFFSET_Y := -0.35              # rod tip 35% above grip → neutral tip at y≈0.57 (below dock edge)
const WATER_BOTTOM_NORM := 0.50                  # dock edge: water above, rod region below — rod tip stays below this
const ROD_TIP_BUFFER_BELOW_WATER := 8.0          # rod tip must stay at least this many pixels below the dock edge
const FISH_Y_NEAR := 0.45                        # fish y when landed (just above dock edge, still in water)
const FISH_Y_FAR := 0.05                         # fish y at max distance (near top of water area)

# === Rod / tension tuning ===
const ROD_TIP_RESTORE_SPEED := 8.0               # lerp speed when releasing
const ROD_DRAG_LERP_SPEED := 12.0                # lerp speed while dragging

const TENSION_ATTACK_SPEED := 8.0                # how fast tension rises (1/sec)
const TENSION_DECAY_SPEED := 3.0                 # how fast tension falls (1/sec)
const TENSION_GAIN := 1.0                        # multiplier on bend-derived tension
const ROD_BREAK_TENSION := 1.0                   # tension at which line starts to break
const ROD_BREAK_HOLD_TIME := 1.5                 # seconds at break tension before snap

# === Fish distance — replaces the old stamina mechanic ===
# Distance is the abstract "how far away the fish is from being landed". 1.0 = far, 0.0 = at the rod.
# Larger / harder species start with greater distance.
const FISH_INITIAL_DISTANCE_BASS := 0.7
const FISH_INITIAL_DISTANCE_TROUT := 1.0
const FISH_REEL_RATE_SURGE := 0.06               # how fast distance closes per second when fighting hard during a surge
const FISH_REEL_RATE_RECOVERY := 0.20            # faster reel rate during the fish's recovery phase
const FISH_DISTANCE_GAIN_RATE := 0.04            # rate fish GAINS distance if player isn't fighting during a surge

# PROTOTYPE-ONLY VIZ — art bible §6 says fish must be invisible underwater in production.
# Setting this false hides the fish and reverts the fishing line to going only to the water surface.
const DEBUG_VISIBLE_FISH := true

# === Fight profiles ===
const PROFILE_A := {
	"name": "A (bass — surge)",
	"surge_force": 0.55,
	"surge_duration_min": 0.4,
	"surge_duration_max": 0.7,
	"recovery_force": 0.05,
	"recovery_duration_min": 0.6,
	"recovery_duration_max": 0.9,
}
const PROFILE_B := {
	"name": "B (trout — run)",
	"surge_force": 0.32,
	"surge_duration_min": 2.0,
	"surge_duration_max": 3.5,
	"recovery_force": 0.0,
	"recovery_duration_min": 0.7,
	"recovery_duration_max": 1.2,
}

# === Runtime state ===
var rod_grip: Vector2
var rod_neutral_tip: Vector2
var rod_tip: Vector2
var current_drag_pos: Vector2
var is_dragging: bool = false

var current_profile: Dictionary = PROFILE_A
var fish_phase: String = "surge"
var fish_phase_time_remaining: float = 0.0
var fish_distance: float = 1.0                   # 1.0 = far away, 0.0 = at the rod (landed)
var fish_initial_distance: float = 1.0           # the species' starting distance
var fish_active: bool = true

# Fish swimming state — fish moves around underwater and pulls from different directions
var fish_position: Vector2 = Vector2.ZERO
var fish_swim_target: Vector2 = Vector2.ZERO
var fish_swim_timer: float = 0.0
var fish_pull_dir: Vector2 = Vector2.DOWN     # direction from rod tip TOWARD the fish (the way fish is pulling)

var tension: float = 0.0
var tension_held_time: float = 0.0
var critical_held_time: float = 0.0     # time spent in pre-break warning zone (tension > 0.85)
var fight_elapsed: float = 0.0           # seconds since the current fight started (for tutorial labels)
var line_broken: bool = false
var fish_landed: bool = false

var show_debug: bool = false                     # toggled with D
var profile_hidden: bool = false                 # set by Space (blind mode)

var session_log: Array[String] = []


func _ready() -> void:
	_update_geometry()
	get_viewport().size_changed.connect(_update_geometry)
	_start_new_fight()


func _update_geometry() -> void:
	var sz: Vector2 = get_viewport_rect().size
	rod_grip = sz * ROD_GRIP_NORM
	rod_neutral_tip = rod_grip + Vector2(0.0, ROD_NEUTRAL_OFFSET_Y * sz.y)
	rod_tip = rod_neutral_tip


func _start_new_fight() -> void:
	# Different species start at different distances — larger fish farther away
	if current_profile == PROFILE_A:
		fish_initial_distance = FISH_INITIAL_DISTANCE_BASS
	else:
		fish_initial_distance = FISH_INITIAL_DISTANCE_TROUT
	fish_distance = fish_initial_distance
	fish_active = true
	line_broken = false
	fish_landed = false
	fish_phase = "surge"
	fish_phase_time_remaining = randf_range(current_profile.surge_duration_min, current_profile.surge_duration_max)
	tension = 0.0
	tension_held_time = 0.0
	critical_held_time = 0.0
	fight_elapsed = 0.0
	rod_tip = rod_neutral_tip
	# Initialize fish at its starting depth (deep in the water for a new fight)
	var sz: Vector2 = get_viewport_rect().size
	fish_position = Vector2(rod_grip.x, lerp(sz.y * FISH_Y_NEAR, sz.y * FISH_Y_FAR, fish_distance))
	fish_swim_target = fish_position
	fish_swim_timer = 0.0
	fish_pull_dir = Vector2.DOWN
	_log("New fight — profile %s (distance %.2f)" % [current_profile.name, fish_distance])


func _log(msg: String) -> void:
	session_log.append(msg)
	if session_log.size() > 8:
		session_log.pop_front()


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_D:
				show_debug = not show_debug
			KEY_A:
				current_profile = PROFILE_A
				profile_hidden = false
				_start_new_fight()
			KEY_B:
				current_profile = PROFILE_B
				profile_hidden = false
				_start_new_fight()
			KEY_R:
				_start_new_fight()
			KEY_SPACE:
				current_profile = PROFILE_A if randi() % 2 == 0 else PROFILE_B
				profile_hidden = true
				_start_new_fight()
				_log("BLIND fight started — guess A or B")
	if event is InputEventScreenTouch or event is InputEventMouseButton:
		if event.pressed:
			is_dragging = true
			current_drag_pos = event.position
		else:
			is_dragging = false
	if event is InputEventScreenDrag or event is InputEventMouseMotion:
		if is_dragging:
			current_drag_pos = event.position


func _process(delta: float) -> void:
	if fish_active:
		fight_elapsed += delta
		_update_fish(delta)
		_update_rod(delta)
		_update_tension(delta)
		_check_end_conditions(delta)
	queue_redraw()


func _update_fish(delta: float) -> void:
	# Phase transitions (surge ↔ recovery)
	fish_phase_time_remaining -= delta
	if fish_phase_time_remaining <= 0.0:
		if fish_phase == "surge":
			fish_phase = "recovery"
			fish_phase_time_remaining = randf_range(current_profile.recovery_duration_min, current_profile.recovery_duration_max)
		else:
			fish_phase = "surge"
			fish_phase_time_remaining = randf_range(current_profile.surge_duration_min, current_profile.surge_duration_max)

	# Fish swimming behavior — fish wanders around an "ideal depth" derived from current distance.
	# As distance decreases, the fish's swim region funnels CLOSER to the rod tip (downward on screen, since rod is at bottom).
	var sz: Vector2 = get_viewport_rect().size
	# Distance maps fish vertical position: near rod when distance=0, far (high on screen) when distance=1
	var ideal_y: float = lerp(sz.y * FISH_Y_NEAR, sz.y * FISH_Y_FAR, fish_distance)
	var y_wander: float = lerp(8.0, 40.0, fish_distance)         # narrow swim radius as fish gets close
	var x_wander: float = lerp(sz.x * 0.04, sz.x * 0.30, fish_distance)
	var water_top: float = sz.y * 0.03
	var water_bottom: float = sz.y * (WATER_BOTTOM_NORM - 0.03)
	var water_left: float = rod_grip.x - x_wander
	var water_right: float = rod_grip.x + x_wander

	fish_swim_timer -= delta
	if fish_swim_timer <= 0.0:
		if fish_phase == "surge":
			# Bass (short surges): dart in a random direction. Trout (long surges): pick one direction and hold.
			var dart_radius: float = sz.x * 0.25
			var dir: Vector2 = Vector2(randf_range(-1, 1), randf_range(-0.5, 0.5))
			if dir.length() < 0.1:
				dir = Vector2.LEFT
			fish_swim_target = fish_position + dir.normalized() * dart_radius
			fish_swim_target.x = clamp(fish_swim_target.x, water_left, water_right)
			fish_swim_target.y = clamp(fish_swim_target.y, max(water_top, ideal_y - y_wander), min(water_bottom, ideal_y + y_wander))
			if current_profile.surge_duration_max > 1.5:
				fish_swim_timer = randf_range(1.8, 2.8)   # trout: sustained direction
			else:
				fish_swim_timer = randf_range(0.5, 0.9)   # bass: still rapid, but slower than before — readable rhythm
		else:
			# Recovery: drift slowly toward the ideal depth
			fish_swim_target = Vector2(rod_grip.x + randf_range(-x_wander * 0.5, x_wander * 0.5), ideal_y + randf_range(-y_wander * 0.4, y_wander * 0.4))
			fish_swim_target.x = clamp(fish_swim_target.x, water_left, water_right)
			fish_swim_target.y = clamp(fish_swim_target.y, water_top, water_bottom)
			fish_swim_timer = randf_range(0.8, 1.4)
	# Smoothly move toward target
	fish_position = fish_position.lerp(fish_swim_target, clamp(delta * 2.5, 0.0, 1.0))
	# Update pull direction (from rod tip TOWARD the fish — that's where the line is pulling)
	var to_fish: Vector2 = fish_position - rod_tip
	if to_fish.length() > 1.0:
		fish_pull_dir = to_fish.normalized()


func _update_rod(delta: float) -> void:
	var sz: Vector2 = get_viewport_rect().size
	var fish_force: float = current_profile.surge_force if fish_phase == "surge" else current_profile.recovery_force
	# Fish pulls the rod tip TOWARD the fish (directional, not always downward)
	var fish_pull_offset: Vector2 = fish_pull_dir * fish_force * sz.y * 0.30
	var target_tip: Vector2

	if is_dragging:
		var to_drag: Vector2 = current_drag_pos - rod_grip
		var max_reach: float = sz.y * 0.50
		to_drag = to_drag.limit_length(max_reach)
		target_tip = rod_grip + to_drag * 0.85 + fish_pull_offset * 0.30
		rod_tip = rod_tip.lerp(target_tip, clamp(delta * ROD_DRAG_LERP_SPEED, 0.0, 1.0))
	else:
		# Not dragging — fish pulls the tip toward itself; rod tries to restore to neutral
		target_tip = rod_neutral_tip + fish_pull_offset
		rod_tip = rod_tip.lerp(target_tip, clamp(delta * ROD_TIP_RESTORE_SPEED, 0.0, 1.0))
	# Clamp: rod tip must stay below the dock edge (never enter the water area)
	var min_tip_y: float = sz.y * WATER_BOTTOM_NORM + ROD_TIP_BUFFER_BELOW_WATER
	if rod_tip.y < min_tip_y:
		rod_tip.y = min_tip_y


func _update_tension(delta: float) -> void:
	var sz: Vector2 = get_viewport_rect().size
	var bend_vec: Vector2 = rod_tip - rod_neutral_tip
	var bend_magnitude: float = bend_vec.length() / (sz.y * 0.50)
	var fish_force: float = current_profile.surge_force if fish_phase == "surge" else current_profile.recovery_force
	# Fight factor: how much the player is pulling against the fish (1.0 = opposite, 0.0 = same direction).
	# Drag away from fish → tension rises. Drag toward fish → low tension (you're going along with it).
	var fight_factor: float = 0.3   # baseline rod resistance
	if bend_magnitude > 0.02 and fish_pull_dir.length() > 0.1:
		var bend_dir: Vector2 = bend_vec.normalized()
		# -bend_dir.dot(fish_pull_dir) is +1 when player drags exactly opposite to fish_pull_dir
		fight_factor = clamp(0.3 + 0.7 * (-bend_dir.dot(fish_pull_dir)), 0.0, 1.0)
	var target_tension: float = clamp(bend_magnitude * (1.0 + fish_force * 2.0) * fight_factor * TENSION_GAIN, 0.0, 1.5)

	if target_tension > tension:
		tension = lerp(tension, target_tension, clamp(delta * TENSION_ATTACK_SPEED, 0.0, 1.0))
	else:
		tension = lerp(tension, target_tension, clamp(delta * TENSION_DECAY_SPEED, 0.0, 1.0))

	# Close fish distance — drag opposite to fish (fight_factor high) AND tension applied = reel in
	# During recovery, the fish is tiring and reeling is faster.
	# If the fish is in surge and the player isn't fighting, fish actually GAINS some distance.
	if tension > 0.4 and fight_factor > 0.55:
		if fish_phase == "surge":
			fish_distance -= FISH_REEL_RATE_SURGE * delta
		else:
			fish_distance -= FISH_REEL_RATE_RECOVERY * delta
	elif fish_phase == "surge" and fight_factor < 0.35:
		fish_distance += FISH_DISTANCE_GAIN_RATE * delta
	fish_distance = clamp(fish_distance, 0.0, fish_initial_distance)

	# Track time at break tension
	if tension >= ROD_BREAK_TENSION:
		tension_held_time += delta
	else:
		tension_held_time = max(0.0, tension_held_time - delta * 2.0)

	# Track pre-break warning zone (rod tip starts pulsing after 0.5s here)
	if tension > 0.85:
		critical_held_time += delta
	else:
		critical_held_time = max(0.0, critical_held_time - delta * 3.0)


func _check_end_conditions(_delta: float) -> void:
	if tension_held_time >= ROD_BREAK_HOLD_TIME:
		line_broken = true
		fish_active = false
		_log("Line BROKE — fight lost (profile was %s)" % current_profile.name)
		profile_hidden = false
		return
	if fish_distance <= 0.0:
		fish_landed = true
		fish_active = false
		_log("Fish LANDED — fight won (profile was %s)" % current_profile.name)
		profile_hidden = false


# === Drawing ===

const COLOR_PAPER := Color(0.957, 0.925, 0.851)
const COLOR_WATER := Color(0.427, 0.541, 0.6, 0.45)
const COLOR_INK := Color(0.239, 0.18, 0.122)
const COLOR_INK_FAINT := Color(0.36, 0.31, 0.28)
const COLOR_TENSION_NORMAL := Color(0.4, 0.5, 0.35)
const COLOR_TENSION_CRITICAL := Color(0.6, 0.3, 0.2)
const COLOR_LANDED := Color(0.3, 0.5, 0.3)
const COLOR_BROKEN := Color(0.6, 0.2, 0.2)
# Rod-color ramp: tension drives rod from light tan -> ink -> warning red
const COLOR_ROD_CALM := Color(0.6, 0.5, 0.38)
const COLOR_ROD_NORMAL := Color(0.239, 0.18, 0.122)
const COLOR_ROD_CRITICAL := Color(0.55, 0.12, 0.08)


func _draw() -> void:
	var sz: Vector2 = get_viewport_rect().size

	# Background — water/ocean fills the upper region; the rod (player POV) is at the bottom.
	# Clear separation between the two regions via a "dock edge" line.
	draw_rect(Rect2(Vector2.ZERO, sz), COLOR_PAPER)
	var water_bottom_y: float = sz.y * WATER_BOTTOM_NORM
	draw_rect(Rect2(Vector2(0, 0), Vector2(sz.x, water_bottom_y)), COLOR_WATER)
	# Dock-edge ink line — separates water (above) from rod region (below)
	draw_line(Vector2(0, water_bottom_y), Vector2(sz.x, water_bottom_y), COLOR_INK, 2.0, true)

	var font: Font = ThemeDB.fallback_font

	# Tension drives rod color
	var rod_color: Color
	if tension < 0.5:
		rod_color = COLOR_ROD_CALM.lerp(COLOR_ROD_NORMAL, clamp(tension * 2.0, 0.0, 1.0))
	else:
		rod_color = COLOR_ROD_NORMAL.lerp(COLOR_ROD_CRITICAL, clamp((tension - 0.5) * 2.0, 0.0, 1.0))
	# Rod thickness ramp is now more dramatic — "pull back rod, gets shorter AND thicker"
	var line_width: float = lerp(3.0, 14.0, clamp(tension, 0.0, 1.0))

	# DEBUG: visible fish underwater (PROTOTYPE ONLY — art bible §6 requires invisible fish in production)
	if DEBUG_VISIBLE_FISH and fish_active and not line_broken:
		var fish_color: Color = COLOR_INK
		fish_color.a = 0.55
		var facing: Vector2 = -fish_pull_dir if fish_pull_dir.length() > 0.1 else Vector2.LEFT
		facing = facing.normalized()
		var body_size: float = 13.0
		# Body
		draw_circle(fish_position, body_size, fish_color)
		# Tail — small triangle behind the body, on the opposite side of facing
		var tail_base: Vector2 = fish_position - facing * body_size * 0.9
		var perp: Vector2 = Vector2(-facing.y, facing.x)
		var tail_top: Vector2 = tail_base + perp * body_size * 0.6 - facing * body_size * 0.5
		var tail_bot: Vector2 = tail_base - perp * body_size * 0.6 - facing * body_size * 0.5
		draw_colored_polygon(PackedVector2Array([tail_base, tail_top, tail_bot]), fish_color)

	# Fishing line from rod tip to fish (visible) or water surface (invisible mode)
	# Both color AND thickness scale with tension
	if not line_broken:
		var line_target: Vector2
		if DEBUG_VISIBLE_FISH:
			line_target = fish_position
		else:
			# Fish invisible — line continues from rod tip up into water
			line_target = Vector2(rod_tip.x, sz.y * 0.20)
		var fishing_line_width: float = lerp(1.8, 4.0, clamp(tension, 0.0, 1.0))
		draw_line(rod_tip, line_target, rod_color, fishing_line_width, true)

	# Rod — tapered and slightly curved (Bezier with control point biased by current bend)
	var bend_offset: Vector2 = rod_tip - rod_neutral_tip
	var control_point: Vector2 = rod_grip.lerp(rod_tip, 0.6) + bend_offset * 0.18
	var segments: int = 10
	var prev_point: Vector2 = rod_grip
	for i in range(1, segments + 1):
		var t: float = float(i) / segments
		var omt: float = 1.0 - t
		var pt: Vector2 = omt * omt * rod_grip + 2.0 * omt * t * control_point + t * t * rod_tip
		var seg_w: float = lerp(line_width * 1.7, line_width * 0.5, t)
		draw_line(prev_point, pt, rod_color, seg_w, true)
		prev_point = pt

	# Reel + grip handle near the rod base
	var rod_axis: Vector2 = (rod_tip - rod_grip).normalized() if (rod_tip - rod_grip).length() > 0.1 else Vector2.UP
	var reel_pos: Vector2 = rod_grip + rod_axis * 22.0
	draw_circle(reel_pos, 10.0, rod_color)
	draw_circle(reel_pos, 5.0, COLOR_PAPER)
	var grip_back: Vector2 = rod_grip - rod_axis * 18.0
	draw_line(grip_back, rod_grip, rod_color, line_width * 2.0, true)
	draw_circle(rod_grip, line_width * 1.2, rod_color)

	# Rod tip — pulses larger when in pre-break warning zone
	var tip_radius: float = 6.0
	if critical_held_time > 0.5 and fish_active:
		var blink_phase: float = (sin(Time.get_ticks_msec() / 80.0) + 1.0) * 0.5
		tip_radius = lerp(6.0, 16.0, blink_phase)
	draw_circle(rod_tip, tip_radius, rod_color)

	# Fish-pull chevron — rotates to point in the fish's current pull direction
	if fish_phase == "surge" and fish_active and not line_broken:
		var pulse: float = (sin(Time.get_ticks_msec() / 110.0) + 1.0) * 0.5
		var arrow_size: float = 8.0 + 4.0 * pulse
		var arrow_distance: float = 30.0 + 4.0 * pulse
		var arrow_center: Vector2 = rod_tip + fish_pull_dir * arrow_distance
		var perpend: Vector2 = Vector2(-fish_pull_dir.y, fish_pull_dir.x)
		var left_pt: Vector2 = arrow_center + perpend * arrow_size
		var right_pt: Vector2 = arrow_center - perpend * arrow_size
		var head_pt: Vector2 = arrow_center + fish_pull_dir * arrow_size
		draw_line(left_pt, head_pt, COLOR_INK_FAINT, 2.5, true)
		draw_line(right_pt, head_pt, COLOR_INK_FAINT, 2.5, true)

	# Tutorial labels (fade out over the first 2.5 seconds of each fight)
	if fish_active and fight_elapsed < 2.5:
		var label_alpha: float = 1.0
		if fight_elapsed > 1.5:
			label_alpha = clamp(1.0 - (fight_elapsed - 1.5) / 1.0, 0.0, 1.0)
		var label_color: Color = COLOR_INK
		label_color.a = label_alpha
		var rod_mid: Vector2 = (rod_grip + rod_tip) * 0.5
		draw_string(font, rod_mid + Vector2(24, 5), "← rod (drag this)", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, label_color)
		draw_string(font, Vector2(sz.x * 0.04, sz.y * 0.36), "drag OPPOSITE to chevron to fight", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, label_color)
		if DEBUG_VISIBLE_FISH:
			draw_string(font, fish_position + Vector2(18, 0), "← fish (debug viz)", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, label_color)

	# Debug tension bar (only when shown)
	if show_debug:
		var bx: float = sz.x * 0.06
		var by: float = sz.y * 0.10
		var bw: float = sz.x * 0.06
		var bh: float = sz.y * 0.30
		draw_rect(Rect2(bx, by, bw, bh), COLOR_PAPER, false, 2.0)
		var fill_h: float = bh * clamp(tension, 0.0, 1.0)
		var fc: Color = COLOR_TENSION_CRITICAL if tension > 0.85 else COLOR_TENSION_NORMAL
		draw_rect(Rect2(bx + 2, by + bh - fill_h, bw - 4, fill_h), fc)

	# Tension speedometer — hand-drawn semicircular gauge in the rod region (bottom-left).
	# Needle rotates with tension; needle color shifts green → yellow → red.
	var gauge_center: Vector2 = Vector2(sz.x * 0.18, sz.y * 0.78)
	var gauge_radius: float = sz.x * 0.10
	# Paper-color background fill (approximate the semicircle with a triangle fan)
	var fan_segments: int = 22
	var fan_points: PackedVector2Array = PackedVector2Array()
	fan_points.append(gauge_center)
	for i in range(fan_segments + 1):
		var t: float = float(i) / fan_segments
		var ang: float = PI + t * PI
		fan_points.append(gauge_center + Vector2(cos(ang), sin(ang)) * gauge_radius)
	draw_colored_polygon(fan_points, COLOR_PAPER)
	# Ink outline around the arc
	var arc_outline: PackedVector2Array = PackedVector2Array()
	for i in range(fan_segments + 1):
		var t2: float = float(i) / fan_segments
		var ang2: float = PI + t2 * PI
		arc_outline.append(gauge_center + Vector2(cos(ang2), sin(ang2)) * gauge_radius)
	draw_polyline(arc_outline, COLOR_INK, 1.5, true)
	# Diameter (bottom edge of the gauge)
	draw_line(gauge_center + Vector2(-gauge_radius, 0), gauge_center + Vector2(gauge_radius, 0), COLOR_INK, 1.5, true)
	# Tick marks at 0/25/50/75/100%
	for i in range(5):
		var tick_t: float = float(i) / 4.0
		var tick_ang: float = PI + tick_t * PI
		var ti: Vector2 = gauge_center + Vector2(cos(tick_ang), sin(tick_ang)) * gauge_radius * 0.82
		var to_: Vector2 = gauge_center + Vector2(cos(tick_ang), sin(tick_ang)) * gauge_radius * 0.96
		draw_line(ti, to_, COLOR_INK, 1.0, true)
	# Needle — color shifts green → yellow → red across the tension range
	var needle_ang: float = PI + clamp(tension, 0.0, 1.0) * PI
	var needle_end: Vector2 = gauge_center + Vector2(cos(needle_ang), sin(needle_ang)) * gauge_radius * 0.80
	var needle_color: Color
	if tension < 0.5:
		needle_color = Color(0.30, 0.55, 0.25).lerp(Color(0.85, 0.65, 0.15), clamp(tension * 2.0, 0.0, 1.0))
	else:
		needle_color = Color(0.85, 0.65, 0.15).lerp(Color(0.75, 0.15, 0.10), clamp((tension - 0.5) * 2.0, 0.0, 1.0))
	draw_line(gauge_center, needle_end, needle_color, 3.5, true)
	draw_circle(gauge_center, 4.5, COLOR_INK)
	# Label
	draw_string(font, gauge_center + Vector2(-gauge_radius * 0.35, gauge_radius * 0.55), "tension", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, COLOR_INK_FAINT)

	# Fish distance bar — sits in the rod region (bottom-right), separated from the water/gauge
	var sb_x: float = sz.x * 0.88
	var sb_y: float = sz.y * 0.58
	var sb_w: float = sz.x * 0.06
	var sb_h: float = sz.y * 0.30
	draw_rect(Rect2(sb_x, sb_y, sb_w, sb_h), COLOR_PAPER, false, 2.0)
	var distance_h: float = sb_h * clamp(fish_distance / max(fish_initial_distance, 0.01), 0.0, 1.0)
	draw_rect(Rect2(sb_x + 2, sb_y + sb_h - distance_h, sb_w - 4, distance_h), Color(0.5, 0.4, 0.3))
	draw_string(font, Vector2(sb_x - 8, sb_y - 6), "distance", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, COLOR_INK_FAINT)

	# Control hints
	var info: String = "[A] bass surge   [B] trout run   [Space] blind   [R] restart   [D] debug bar"
	draw_string(font, Vector2(sz.x * 0.04, sz.y * 0.04), info, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, COLOR_INK)

	# Profile label
	var profile_text: String
	if profile_hidden and fish_active:
		profile_text = "Profile: HIDDEN (blind test — guess A or B)"
	else:
		profile_text = "Profile: %s" % current_profile.name
	if show_debug:
		profile_text += "    tension=%.2f    distance=%.2f" % [tension, fish_distance]
	draw_string(font, Vector2(sz.x * 0.04, sz.y * 0.07), profile_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, COLOR_INK)

	# End-state overlay
	if line_broken:
		draw_string(font, Vector2(sz.x * 0.04, sz.y * 0.42), "LINE BROKE — [R] retry", HORIZONTAL_ALIGNMENT_LEFT, -1, 24, COLOR_BROKEN)
	elif fish_landed:
		draw_string(font, Vector2(sz.x * 0.04, sz.y * 0.42), "FISH LANDED — [R] for another", HORIZONTAL_ALIGNMENT_LEFT, -1, 24, COLOR_LANDED)

	# Session log (recent events, scrolling)
	var log_y: float = sz.y * 0.90
	for i in range(session_log.size()):
		var line: String = session_log[i]
		var y_pos: float = log_y - (session_log.size() - 1 - i) * 16
		draw_string(font, Vector2(sz.x * 0.04, y_pos), line, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, COLOR_INK_FAINT)

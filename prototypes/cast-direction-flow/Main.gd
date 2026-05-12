# PROTOTYPE - NOT FOR PRODUCTION
# Question: Is the cast-direction-only flow (aim → release → arc → land) satisfying
#           when the player cannot choose cast length?
# Date: 2026-05-11

extends Node2D

# === Layout ===
const FISHER_NORM := Vector2(0.5, 0.90)       # bottom-center of screen
const SKY_BOTTOM_NORM := 0.15
const SHORE_TOP_NORM := 0.85

# === Test casting distances (as fraction of screen height) ===
const DISTANCE_LOW := 0.30                    # early game — short reach
const DISTANCE_MED := 0.55                    # mid game
const DISTANCE_HIGH := 0.70                   # late game — long reach (capped so straight-up stays in water)

# === Cast physics ===
const CAST_DURATION := 0.85                   # seconds for the cast arc to complete
const CAST_ARC_HEIGHT_NORM := 0.18            # peak height of arc as fraction of screen height

# === Trail ===
const MAX_TRAIL_POINTS := 8

# === Runtime state ===
var fisher_pos: Vector2
var aim_dir: Vector2 = Vector2(0, -1)
var casting_distance_norm: float = DISTANCE_MED
var is_aiming: bool = false
var current_touch_pos: Vector2 = Vector2.ZERO

var cast_active: bool = false
var cast_progress: float = 0.0
var cast_start: Vector2 = Vector2.ZERO
var cast_end: Vector2 = Vector2.ZERO

var ripples: Array = []                       # each: {pos, radius, max_radius, alpha}
var trail_points: Array[Vector2] = []
var structures: Array = []                    # each: {pos, radius, type, color}

var cast_count: int = 0
var landed_near_structure_count: int = 0
var session_log: Array[String] = []

# === Colors (drawn from new Fishing Man art bible — Riverside Pond palette) ===
const COLOR_SKY := Color(0.847, 0.878, 0.784)
const COLOR_WATER_FAR := Color(0.420, 0.561, 0.451)
const COLOR_WATER_NEAR := Color(0.345, 0.549, 0.494)
const COLOR_SHORE := Color(0.784, 0.647, 0.361)
const COLOR_INK := Color(0.227, 0.180, 0.122)
const COLOR_INK_FAINT := Color(0.40, 0.36, 0.30)
const COLOR_LURE := Color(0.91, 0.71, 0.27)
const COLOR_RANGE_PREVIEW := Color(0.482, 0.647, 0.760, 0.28)
const COLOR_AIMER := Color(0.91, 0.71, 0.27, 0.85)


func _ready() -> void:
	_update_geometry()
	_setup_structures()
	get_viewport().size_changed.connect(_on_viewport_resized)
	_log("Prototype ready. Drag from rod to aim; release to cast.")


func _on_viewport_resized() -> void:
	_update_geometry()
	_setup_structures()


func _update_geometry() -> void:
	var sz: Vector2 = get_viewport_rect().size
	fisher_pos = sz * FISHER_NORM


func _setup_structures() -> void:
	var sz: Vector2 = get_viewport_rect().size
	structures.clear()
	structures.append({
		"pos": Vector2(sz.x * 0.25, sz.y * 0.60),
		"radius": 35.0,
		"type": "lily pads",
		"color": Color(0.486, 0.682, 0.396),
	})
	structures.append({
		"pos": Vector2(sz.x * 0.52, sz.y * 0.35),
		"radius": 28.0,
		"type": "rock",
		"color": Color(0.467, 0.439, 0.380),
	})
	structures.append({
		"pos": Vector2(sz.x * 0.78, sz.y * 0.50),
		"radius": 32.0,
		"type": "dead snag",
		"color": Color(0.392, 0.290, 0.176),
	})


func _log(msg: String) -> void:
	session_log.append(msg)
	if session_log.size() > 8:
		session_log.pop_front()


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_1:
				casting_distance_norm = DISTANCE_LOW
				_log("Distance: LOW (%.0f%%)" % (DISTANCE_LOW * 100))
			KEY_2:
				casting_distance_norm = DISTANCE_MED
				_log("Distance: MED (%.0f%%)" % (DISTANCE_MED * 100))
			KEY_3:
				casting_distance_norm = DISTANCE_HIGH
				_log("Distance: HIGH (%.0f%%)" % (DISTANCE_HIGH * 100))
			KEY_R:
				_reset_session()
			KEY_SPACE:
				if is_aiming and not cast_active:
					_commit_cast()

	if event is InputEventScreenTouch or event is InputEventMouseButton:
		if event.pressed and not cast_active:
			is_aiming = true
			current_touch_pos = event.position
			_update_aim()
		elif not event.pressed:
			if is_aiming and not cast_active:
				_commit_cast()
			is_aiming = false

	if event is InputEventScreenDrag or event is InputEventMouseMotion:
		if is_aiming and not cast_active:
			current_touch_pos = event.position
			_update_aim()


func _update_aim() -> void:
	var to_touch: Vector2 = current_touch_pos - fisher_pos
	if to_touch.length() > 1.0:
		aim_dir = to_touch.normalized()
		# Clamp to upper hemisphere — cast must go upward into the water
		if aim_dir.y > -0.05:
			aim_dir.y = -0.05
			aim_dir = aim_dir.normalized()


func _commit_cast() -> void:
	if cast_active:
		return
	var sz: Vector2 = get_viewport_rect().size
	var distance_pixels: float = sz.y * casting_distance_norm
	cast_start = fisher_pos
	cast_end = fisher_pos + aim_dir * distance_pixels
	cast_active = true
	cast_progress = 0.0
	trail_points.clear()
	is_aiming = false
	cast_count += 1
	var angle_deg: float = rad_to_deg(atan2(-aim_dir.y, aim_dir.x))
	_log("Cast #%d at %.0f° (dist %.0f%%)" % [cast_count, angle_deg, casting_distance_norm * 100])


func _reset_session() -> void:
	cast_count = 0
	landed_near_structure_count = 0
	ripples.clear()
	trail_points.clear()
	cast_active = false
	is_aiming = false
	session_log.clear()
	_log("Session reset")


func _process(delta: float) -> void:
	if cast_active:
		cast_progress += delta / CAST_DURATION
		if cast_progress >= 1.0:
			cast_progress = 1.0
			_on_cast_landed()
		else:
			var lure_pos: Vector2 = _get_lure_position(cast_progress)
			trail_points.append(lure_pos)
			if trail_points.size() > MAX_TRAIL_POINTS:
				trail_points.pop_front()

	# Update ripples
	for i in range(ripples.size() - 1, -1, -1):
		var r: Dictionary = ripples[i]
		r.radius += delta * 80.0
		r.alpha = clamp(1.0 - r.radius / r.max_radius, 0.0, 1.0)
		if r.alpha <= 0.0:
			ripples.remove_at(i)

	queue_redraw()


func _get_lure_position(t: float) -> Vector2:
	var sz: Vector2 = get_viewport_rect().size
	var linear: Vector2 = cast_start.lerp(cast_end, t)
	var arc_lift: float = sin(t * PI) * sz.y * CAST_ARC_HEIGHT_NORM
	return linear + Vector2(0, -arc_lift)


func _on_cast_landed() -> void:
	cast_active = false
	# Spawn two ripples (different sizes) at landing point
	ripples.append({
		"pos": cast_end,
		"radius": 6.0,
		"max_radius": 60.0,
		"alpha": 1.0,
	})
	ripples.append({
		"pos": cast_end,
		"radius": 2.0,
		"max_radius": 40.0,
		"alpha": 0.7,
	})
	# Check structure proximity
	for s in structures:
		var dist: float = cast_end.distance_to(s.pos)
		if dist <= s.radius * 2.5:
			landed_near_structure_count += 1
			_log("Landed near %s — bonus zone!" % s.type)
			return
	_log("Landed in open water")


# === Drawing ===

func _draw() -> void:
	var sz: Vector2 = get_viewport_rect().size
	var sky_bottom_y: float = sz.y * SKY_BOTTOM_NORM
	var shore_top_y: float = sz.y * SHORE_TOP_NORM
	var water_mid_y: float = (sky_bottom_y + shore_top_y) * 0.5
	var font: Font = ThemeDB.fallback_font

	# Sky / water / shore
	draw_rect(Rect2(Vector2.ZERO, Vector2(sz.x, sky_bottom_y)), COLOR_SKY)
	draw_rect(Rect2(Vector2(0, sky_bottom_y), Vector2(sz.x, water_mid_y - sky_bottom_y)), COLOR_WATER_FAR)
	draw_rect(Rect2(Vector2(0, water_mid_y), Vector2(sz.x, shore_top_y - water_mid_y)), COLOR_WATER_NEAR)
	draw_rect(Rect2(Vector2(0, shore_top_y), Vector2(sz.x, sz.y - shore_top_y)), COLOR_SHORE)
	# Horizon line + shore line
	draw_line(Vector2(0, sky_bottom_y), Vector2(sz.x, sky_bottom_y), COLOR_INK_FAINT, 1.0, true)
	draw_line(Vector2(0, shore_top_y), Vector2(sz.x, shore_top_y), COLOR_INK, 2.0, true)

	# Range preview — translucent semicircle showing reachable area in the water
	var distance_pixels: float = sz.y * casting_distance_norm
	var segs: int = 30
	var fan: PackedVector2Array = PackedVector2Array()
	fan.append(fisher_pos)
	for i in range(segs + 1):
		var t: float = float(i) / segs
		var ang: float = PI + t * PI
		fan.append(fisher_pos + Vector2(cos(ang), sin(ang)) * distance_pixels)
	draw_colored_polygon(fan, COLOR_RANGE_PREVIEW)
	# Outline of range
	var outline: PackedVector2Array = PackedVector2Array()
	for i in range(segs + 1):
		var t2: float = float(i) / segs
		var ang2: float = PI + t2 * PI
		outline.append(fisher_pos + Vector2(cos(ang2), sin(ang2)) * distance_pixels)
	draw_polyline(outline, COLOR_INK_FAINT, 1.0, true)

	# Structures
	for s in structures:
		draw_circle(s.pos, s.radius, s.color)
		draw_arc(s.pos, s.radius, 0.0, TAU, 24, COLOR_INK, 1.5, true)
		# Label below structure
		draw_string(font, s.pos + Vector2(-s.radius * 0.9, s.radius + 14), s.type, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, COLOR_INK_FAINT)

	# Ripples
	for r in ripples:
		var c: Color = COLOR_INK_FAINT
		c.a = r.alpha
		draw_arc(r.pos, r.radius, 0.0, TAU, 24, c, 1.5, true)

	# Cast trail (fading line behind lure)
	if trail_points.size() > 1:
		for i in range(trail_points.size() - 1):
			var a: float = float(i) / float(MAX_TRAIL_POINTS)
			var tc: Color = COLOR_LURE
			tc.a = a * 0.6
			draw_line(trail_points[i], trail_points[i + 1], tc, 2.0, true)

	# Lure in flight
	if cast_active:
		var lp: Vector2 = _get_lure_position(cast_progress)
		draw_circle(lp, 5.0, COLOR_LURE)
		draw_arc(lp, 6.0, 0.0, TAU, 16, COLOR_INK, 1.0, true)

	# Cast aimer (only when aiming, not casting)
	if is_aiming and not cast_active:
		var aimer_length: float = distance_pixels
		var aimer_end: Vector2 = fisher_pos + aim_dir * aimer_length
		draw_line(fisher_pos, aimer_end, COLOR_AIMER, 2.5, true)
		# Arrowhead
		var perp: Vector2 = Vector2(-aim_dir.y, aim_dir.x)
		var head_size: float = 12.0
		var head_a: Vector2 = aimer_end - aim_dir * head_size + perp * head_size * 0.5
		var head_b: Vector2 = aimer_end - aim_dir * head_size - perp * head_size * 0.5
		draw_line(aimer_end, head_a, COLOR_AIMER, 2.5, true)
		draw_line(aimer_end, head_b, COLOR_AIMER, 2.5, true)

	# Rod — points in aim direction when aiming/casting; otherwise straight up
	var rod_dir: Vector2 = aim_dir if (is_aiming or cast_active) else Vector2(0, -1)
	var rod_length: float = 75.0
	var rod_tip: Vector2 = fisher_pos + rod_dir * rod_length
	draw_line(fisher_pos, rod_tip, COLOR_INK, 4.0, true)
	draw_circle(fisher_pos, 7.0, COLOR_INK)
	draw_circle(rod_tip, 4.0, COLOR_INK)

	# HUD: controls (top)
	var controls: String = "[drag] aim   [release] cast   [1/2/3] distance LOW/MED/HIGH   [R] reset"
	draw_string(font, Vector2(sz.x * 0.03, sz.y * 0.04), controls, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, COLOR_INK)

	var stat_text: String = "casting_distance: %d%% screen" % int(casting_distance_norm * 100)
	draw_string(font, Vector2(sz.x * 0.03, sz.y * 0.075), stat_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, COLOR_INK)

	var stats_text: String = "casts: %d    near-structure: %d" % [cast_count, landed_near_structure_count]
	draw_string(font, Vector2(sz.x * 0.03, sz.y * 0.105), stats_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, COLOR_INK_FAINT)

	# Session log
	var log_y: float = sz.y * 0.97
	for i in range(session_log.size()):
		var line_text: String = session_log[i]
		var y_pos: float = log_y - (session_log.size() - 1 - i) * 14
		draw_string(font, Vector2(sz.x * 0.03, y_pos), line_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, COLOR_INK_FAINT)

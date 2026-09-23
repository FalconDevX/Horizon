extends Node2D

signal ship_clicked

@export var ship_mass: float = 10.0
@export var thrust_force: float = 6.0
@export var throttle_ramp_time := 1.2
@export var lock_adjust_rate := 0.5
@export var rotation_speed: float = 2.5
@export var collision_radius: float = 8.0
@export var correction_thrust_force := 1.0
@export var fuel_consumption: float = 0.0
@export var fuel_capacity: float = 0.0
@export var energy_consumption: float = 0.0
@export var energy_generation: float = 0.0
@export var energy_capacity: float = 0.0
@export var shield_strength: float = 0.0

## Fallback when the shipyard has no modules yet (keeps the default orbital ship flyable).
const DEFAULT_SHIP_MASS := 10.0
const DEFAULT_THRUST_FORCE := 6.0
const DEFAULT_CORRECTION_THRUST := 1.0
const MIN_SHIP_MASS := 1.0
## RCS scales with main thrust so module builds keep a usable attitude/translation ratio.
const RCS_THRUST_RATIO := 1.0 / 6.0

## FOV devices synced from the shipyard (weapons + radars).
var fov_devices: Array[Dictionary] = []
## Body names currently inside at least one radar cone.
var radar_contacts: Array[String] = []
## Body names inside a weapon cone (engageable).
var weapon_locks: Array[String] = []
var _fire_flash_timer := 0.0
var _fire_flash_to := Vector2.ZERO
var show_fov_cones := true

var velocity := Vector2.ZERO
var throttle := 0.0
var autopilot_thrust := Vector2.ZERO
var autopilot_rcs_local_command := Vector2.ZERO
var manual_rcs_local_command := Vector2.ZERO
var autopilot_main_engine_output := 0.0
var throttle_locked := false
var _lock_key_was_pressed := false
var paused := false
var true_scale := false:
	set(value):
		if true_scale == value:
			return
		true_scale = value
		queue_redraw()


@onready var rcs_sound: AudioStreamPlayer = $RcsSound


func _ready() -> void:
	$ClickArea.input_event.connect(_on_click_area_input_event)
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_ON
	reset_physics_interpolation()


## Applies aggregated ShipHull / ShipStats totals to flight parameters.
## Empty builds restore scene defaults so the orbital ship stays usable.
func apply_module_stats(stats: Dictionary) -> void:
	var module_count: int = int(stats.get("module_count", 0))
	if module_count <= 0:
		ship_mass = DEFAULT_SHIP_MASS
		thrust_force = DEFAULT_THRUST_FORCE
		correction_thrust_force = DEFAULT_CORRECTION_THRUST
		fuel_consumption = 0.0
		fuel_capacity = 0.0
		energy_consumption = 0.0
		energy_generation = 0.0
		energy_capacity = 0.0
		shield_strength = 0.0
		apply_fov_devices([])
		return

	ship_mass = maxf(float(stats.get("mass", 0.0)), MIN_SHIP_MASS)
	thrust_force = maxf(float(stats.get("thrust", 0.0)), 0.0)
	var rcs: float = maxf(float(stats.get("correction_thrust", 0.0)), 0.0)
	# Fallback keeps attitude control usable before any Corrective Engine is fitted.
	correction_thrust_force = rcs if rcs > 0.0 else thrust_force * RCS_THRUST_RATIO
	fuel_consumption = maxf(float(stats.get("fuel_consumption", 0.0)), 0.0)
	fuel_capacity = maxf(float(stats.get("fuel_capacity", 0.0)), 0.0)
	energy_consumption = maxf(float(stats.get("energy_consumption", 0.0)), 0.0)
	energy_generation = maxf(float(stats.get("energy_generation", 0.0)), 0.0)
	energy_capacity = maxf(float(stats.get("energy_capacity", 0.0)), 0.0)
	shield_strength = maxf(float(stats.get("shield_strength", 0.0)), 0.0)


func apply_fov_devices(devices: Array) -> void:
	fov_devices.clear()
	for item in devices:
		if typeof(item) != TYPE_DICTIONARY:
			continue
		fov_devices.append((item as Dictionary).duplicate(true))
	radar_contacts.clear()
	weapon_locks.clear()
	queue_redraw()


func clear_fov_contacts() -> void:
	radar_contacts.clear()
	weapon_locks.clear()


func set_fov_contacts(radar: Array[String], weapons: Array[String]) -> void:
	radar_contacts = radar.duplicate()
	weapon_locks = weapons.duplicate()
	queue_redraw()


func device_world_origin(device: Dictionary) -> Vector2:
	var local_origin: Vector2 = device.get("local_origin", Vector2.ZERO)
	return global_position + local_origin.rotated(rotation)


func device_world_facing(device: Dictionary) -> Vector2:
	var local_facing: Vector2 = device.get("local_facing", Vector2.RIGHT)
	return local_facing.rotated(rotation)


func is_body_in_device_fov(device: Dictionary, body_pos: Vector2) -> bool:
	var origin := device_world_origin(device)
	var facing := device_world_facing(device)
	var half := deg_to_rad(float(device.get("angle_deg", 0.0))) * 0.5
	var range_su := float(device.get("range", 0.0))
	if not FovUtil.is_point_in_cone(origin, facing, half, range_su, body_pos):
		return false
	# Hull blocks LOS in ship-local space.
	var local_origin: Vector2 = device.get("local_origin", Vector2.ZERO)
	var to_local: Vector2 = (body_pos - global_position).rotated(-rotation)
	var hull_rects: Array = device.get("hull_rects", [])
	var ignore_rects: Array = device.get("ignore_rects", [])
	if hull_rects.is_empty():
		return true
	return FovUtil.has_clear_los(local_origin, to_local, hull_rects, ignore_rects)


func try_fire_at(world_pos: Vector2) -> bool:
	if weapon_locks.is_empty():
		return false
	var best_range := INF
	var fired := false
	for device in fov_devices:
		if str(device.get("kind", "")) != "weapon":
			continue
		if not is_body_in_device_fov(device, world_pos):
			continue
		var dist := device_world_origin(device).distance_to(world_pos)
		if dist < best_range:
			best_range = dist
			_fire_flash_to = to_local(world_pos)
			_fire_flash_timer = 0.35
			fired = true
	if fired:
		queue_redraw()
	return fired


func _on_click_area_input_event(
	_viewport: Node,
	event: InputEvent,
	_shape_idx: int
) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			ship_clicked.emit()


func update_rotation(delta: float) -> void:
	if not Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
		return

	var to_cursor: Vector2 = get_global_mouse_position() - global_position
	if to_cursor.length_squared() < 1.0:
		return

	rotation = rotate_toward(rotation, to_cursor.angle(), rotation_speed * delta)


func update_autopilot_rotation(delta: float) -> void:
	if autopilot_thrust == Vector2.ZERO:
		return

	rotation = rotate_toward(rotation, autopilot_thrust.angle(), rotation_speed * delta)


func disengage_manual_main_engine() -> void:
	throttle = 0.0
	throttle_locked = false


func poll_lock_toggle(is_realtime: bool) -> bool:
	if not is_realtime:
		return false

	var lock_key_pressed := Input.is_key_pressed(KEY_X)
	var just_locked := false
	if lock_key_pressed and not _lock_key_was_pressed:
		throttle_locked = not throttle_locked
		just_locked = throttle_locked
	_lock_key_was_pressed = lock_key_pressed
	return just_locked


func update_throttle(delta: float, is_realtime: bool = true) -> void:
	if not is_realtime:
		return

	if throttle_locked:
		if Input.is_key_pressed(KEY_W):
			throttle = clampf(throttle + lock_adjust_rate * delta, 0.0, 1.0)
		elif Input.is_key_pressed(KEY_S):
			throttle = clampf(throttle - lock_adjust_rate * delta, 0.0, 1.0)
		return

	var target := 1.0 if Input.is_key_pressed(KEY_W) else 0.0
	throttle = move_toward(throttle, target, delta / throttle_ramp_time)


func get_thrust_acceleration() -> Vector2:
	if throttle <= 0.0:
		return Vector2.ZERO

	var direction := Vector2.RIGHT.rotated(rotation)
	var acceleration: float = thrust_force * throttle / ship_mass

	return direction * acceleration


func get_manual_rcs_acceleration() -> Vector2:
	var local_command := Vector2.ZERO

	if not throttle_locked and Input.is_key_pressed(KEY_S):
		local_command.x -= 1.0
	if Input.is_key_pressed(KEY_A):
		local_command.y -= 1.0
	if Input.is_key_pressed(KEY_D):
		local_command.y += 1.0

	manual_rcs_local_command = local_command
	if local_command == Vector2.ZERO:
		return Vector2.ZERO

	return local_command.rotated(rotation) * correction_thrust_force / ship_mass


func set_autopilot_thrust(command: Vector2) -> void:
	autopilot_thrust = Vector2(
		clampf(command.x, -1.0, 1.0),
		clampf(command.y, -1.0, 1.0)
	)


func clear_autopilot_thrust() -> void:
	autopilot_thrust = Vector2.ZERO


func get_autopilot_acceleration(max_force: float, is_main_engine: bool) -> Vector2:
	if autopilot_thrust == Vector2.ZERO:
		autopilot_rcs_local_command = Vector2.ZERO
		autopilot_main_engine_output = 0.0
		return Vector2.ZERO

	if is_main_engine:
		autopilot_rcs_local_command = Vector2.ZERO
		var forward: Vector2 = Vector2.RIGHT.rotated(rotation)
		var alignment: float = forward.dot(autopilot_thrust.normalized())
		if alignment <= 0.0:
			autopilot_main_engine_output = 0.0
			return Vector2.ZERO
		autopilot_main_engine_output = autopilot_thrust.length() * alignment
		return forward * (autopilot_main_engine_output * max_force / ship_mass)

	autopilot_main_engine_output = 0.0

	var local_command: Vector2 = autopilot_thrust.rotated(-rotation)
	autopilot_rcs_local_command = Vector2(
		clampf(local_command.x, -1.0, 1.0),
		clampf(local_command.y, -1.0, 1.0)
	)

	return (
		autopilot_rcs_local_command.rotated(rotation)
		* max_force
		/ ship_mass
	)


func _process(delta: float) -> void:
	if _fire_flash_timer > 0.0:
		_fire_flash_timer = maxf(0.0, _fire_flash_timer - delta)
	queue_redraw()
	_update_rcs_sound()


func _update_rcs_sound() -> void:
	if paused:
		if rcs_sound.playing:
			rcs_sound.stop()
		return

	var combined: Vector2 = autopilot_rcs_local_command + manual_rcs_local_command
	var active: bool = combined.length() > RCS_ACTIVE_THRESHOLD

	if active and not rcs_sound.playing:
		rcs_sound.play()
	elif not active and rcs_sound.playing:
		rcs_sound.stop()


const SHIP_TEXTURE := preload("res://textures/ship_blueprint.png")
const SHIP_VISUAL_LENGTH := 22.0

const FRONT_POS := Vector2(0.50, 0.10)
const BACK_POS := Vector2(0.50, 0.72)
const LEFT_POS := Vector2(0.03, 0.47)
const RIGHT_POS := Vector2(0.96, 0.475)
const ENGINE_EXIT_POS := Vector2(0.58, 0.97)

const RCS_DOT_RADIUS := 1.6
const RCS_ACTIVE_THRESHOLD := 0.05
const RCS_FLAME_LENGTH := 3.0
const RCS_FLAME_WIDTH := 1.8

const ENGINE_OUTER_HALF_WIDTH := 3.0
const ENGINE_MAX_LENGTH := 11.0
const MAIN_OUTER_COLOR := Color(1.0, 0.45, 0.1)
const MAIN_MID_COLOR := Color(1.0, 0.65, 0.2)
const MAIN_CORE_COLOR := Color(1.0, 0.85, 0.5)


var MARKER_POINTS := PackedVector2Array([
	Vector2(12, 0),
	Vector2(-8, -7),
	Vector2(-8, 7),
])


func _draw() -> void:
	_draw_fov_cones()

	var front_pos: Vector2
	var back_pos: Vector2
	var left_pos: Vector2
	var right_pos: Vector2
	var engine_pos: Vector2

	if true_scale:
		var texture_size: Vector2 = SHIP_TEXTURE.get_size()
		var draw_size := Vector2(
			SHIP_VISUAL_LENGTH * texture_size.x / texture_size.y,
			SHIP_VISUAL_LENGTH
		)
		draw_set_transform(Vector2.ZERO, PI * 0.5, Vector2.ONE)
		draw_texture_rect(SHIP_TEXTURE, Rect2(-draw_size * 0.5, draw_size), false)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

		front_pos = _image_to_local(FRONT_POS, draw_size)
		back_pos = _image_to_local(BACK_POS, draw_size)
		left_pos = _image_to_local(LEFT_POS, draw_size)
		right_pos = _image_to_local(RIGHT_POS, draw_size)
		engine_pos = _image_to_local(ENGINE_EXIT_POS, draw_size)
	else:
		draw_colored_polygon(MARKER_POINTS, Color.WHITE)

		front_pos = Vector2(12, 0)
		back_pos = Vector2(-8, 0)
		left_pos = Vector2(2, -7)
		right_pos = Vector2(2, 7)
		engine_pos = back_pos

	if throttle > 0.0:
		_draw_engine_flame(engine_pos)

	if Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
		draw_line(Vector2.ZERO, to_local(get_global_mouse_position()), Color(1.0, 1.0, 1.0, 0.35), 1.0)

	if _fire_flash_timer > 0.0:
		var alpha := clampf(_fire_flash_timer / 0.35, 0.0, 1.0)
		draw_line(Vector2.ZERO, _fire_flash_to, Color(1.0, 0.45, 0.2, 0.85 * alpha), 2.0)

	var combined: Vector2 = autopilot_rcs_local_command + manual_rcs_local_command
	_draw_rcs_thruster(front_pos, Vector2.RIGHT, combined.x < -RCS_ACTIVE_THRESHOLD, 0.0)
	_draw_rcs_thruster(back_pos, Vector2.LEFT, combined.x > RCS_ACTIVE_THRESHOLD, 1.7)
	_draw_rcs_thruster(left_pos, Vector2.UP, combined.y < -RCS_ACTIVE_THRESHOLD, 3.4)
	_draw_rcs_thruster(right_pos, Vector2.DOWN, combined.y > RCS_ACTIVE_THRESHOLD, 5.1)


func _draw_fov_cones() -> void:
	if not show_fov_cones or fov_devices.is_empty():
		return
	# Ship visual scale (screen-space sizing) must not stretch world-SU cones.
	var inv_scale := 1.0 / maxf(scale.x, 0.0001)
	for device in fov_devices:
		var local_origin: Vector2 = device.get("local_origin", Vector2.ZERO) * inv_scale
		var local_facing: Vector2 = device.get("local_facing", Vector2.RIGHT)
		var angle_deg := float(device.get("angle_deg", 0.0))
		var range_su := float(device.get("range", 0.0)) * inv_scale
		var is_weapon := str(device.get("kind", "")) == "weapon"
		var fill := (
			Color(0.9, 0.25, 0.2, 0.08) if is_weapon
			else Color(0.25, 0.75, 0.85, 0.07)
		)
		var outline := (
			Color(0.95, 0.4, 0.3, 0.35) if is_weapon
			else Color(0.45, 0.9, 1.0, 0.3)
		)
		var hull_rects: Array = _scale_rects(device.get("hull_rects", []), inv_scale)
		var ignore_rects: Array = _scale_rects(device.get("ignore_rects", []), inv_scale)
		FovUtil.draw_cone_rects(
			self,
			local_origin,
			local_facing,
			angle_deg,
			range_su,
			fill,
			outline,
			1.0,
			hull_rects,
			ignore_rects
		)


func _scale_rects(rects: Array, inv_scale: float) -> Array:
	var out: Array = []
	for item in rects:
		if item is Rect2:
			var r: Rect2 = item
			out.append(Rect2(r.position * inv_scale, r.size * inv_scale))
	return out


func _image_to_local(frac: Vector2, draw_size: Vector2) -> Vector2:
	return ((frac - Vector2(0.5, 0.5)) * draw_size).rotated(PI * 0.5)


func _draw_rcs_thruster(local_pos: Vector2, outward_dir: Vector2, active: bool, phase: float) -> void:
	draw_circle(local_pos, RCS_DOT_RADIUS, Color(0.75, 0.9, 1.0, 0.9) if active else Color(0.4, 0.4, 0.4, 0.35))

	if not active:
		return

	var t: float = Time.get_ticks_msec() / 1000.0
	var flicker: float = 0.75 + 0.25 * sin(t * 19.0 + phase) + 0.15 * sin(t * 53.0 + phase * 2.0)
	var length: float = RCS_FLAME_LENGTH * flicker
	var half_width: float = RCS_FLAME_WIDTH * 0.5
	var side: Vector2 = outward_dir.orthogonal()
	var base: Vector2 = local_pos + outward_dir * RCS_DOT_RADIUS

	_draw_wavy_flame(base, outward_dir, side, half_width, length, t + phase, Color(0.3, 0.65, 1.0, 0.75 * flicker))
	_draw_sparks(base, outward_dir, side, half_width, length, t + phase, Color(0.85, 0.95, 1.0))

	draw_colored_polygon(
		PackedVector2Array([
			base + side * half_width * 0.4,
			base - side * half_width * 0.4,
			base + outward_dir * length * 0.55
		]),
		Color(0.8, 0.95, 1.0, 0.9 * flicker)
	)


# The edge waves sinusoidally instead of being a perfectly straight triangle -
# same approach as the main engine (see ship_blueprint_panel.gd).
func _draw_wavy_flame(
	tip: Vector2, direction: Vector2, side: Vector2, half_width: float, length: float, t: float, color: Color
) -> void:
	var segments := 4
	var left_points := PackedVector2Array()
	var right_points := PackedVector2Array()

	for i in range(segments + 1):
		var f: float = float(i) / float(segments)
		var pos: Vector2 = tip + direction * (length * f)
		var taper: float = 1.0 - f
		var wobble: float = sin(t * 16.0 + f * 6.0) * half_width * 0.2 * f
		var width: float = half_width * taper + wobble
		left_points.append(pos + side * width)
		right_points.append(pos - side * width)

	var points := PackedVector2Array()
	points.append_array(left_points)
	right_points.reverse()
	points.append_array(right_points)
	draw_colored_polygon(points, color)


# A few tiny sparks breaking off the stream, flickering independently
# of the main flame - same approach as ship_blueprint_panel.gd, so the
# ship looks identical out in space.
func _draw_sparks(
	tip: Vector2, direction: Vector2, side: Vector2, half_width: float, length: float, t: float, spark_color: Color
) -> void:
	var spark_count := 3
	for i in range(spark_count):
		var phase_seed: float = float(i) * 17.3
		var f: float = fmod(t * 0.7 + phase_seed, 1.0)
		var pos: Vector2 = tip + direction * (length * (0.35 + f * 0.9))
		var drift: float = sin(t * 9.0 + phase_seed) * half_width * 0.5 * f
		pos += side * drift
		var alpha: float = (1.0 - f) * 0.8
		var radius: float = maxf(0.4, 0.9 * (1.0 - f * 0.6) * (half_width / 3.0))
		draw_circle(pos, radius, Color(spark_color, alpha))


# Multi-layer main engine flame (outer + middle wavy-flame, triangle core,
# sparks) - same look as the ship preview in the bottom-right corner
# (ship_blueprint_panel.gd).
func _draw_engine_flame(tip: Vector2) -> void:
	var direction := Vector2.LEFT
	var side: Vector2 = direction.orthogonal()

	var t: float = Time.get_ticks_msec() / 1000.0
	var flicker: float = 0.85 + 0.15 * sin(t * 24.0) + 0.08 * sin(t * 61.0 + 1.3)
	var length: float = ENGINE_MAX_LENGTH * throttle * flicker

	_draw_wavy_flame(
		tip, direction, side, ENGINE_OUTER_HALF_WIDTH, length, t,
		Color(MAIN_OUTER_COLOR, 0.55 * flicker)
	)

	var mid_half_width: float = ENGINE_OUTER_HALF_WIDTH * 0.75
	_draw_wavy_flame(
		tip, direction, side, mid_half_width, length * 0.8, t + 3.1,
		Color(MAIN_MID_COLOR, 0.7 * flicker)
	)

	var inner_half_width: float = ENGINE_OUTER_HALF_WIDTH * 0.4
	draw_colored_polygon(
		PackedVector2Array([
			tip + side * inner_half_width,
			tip - side * inner_half_width,
			tip + direction * (length * 0.6)
		]),
		Color(MAIN_CORE_COLOR, 0.95 * flicker)
	)

	_draw_sparks(tip, direction, side, ENGINE_OUTER_HALF_WIDTH, length, t, Color(1.0, 0.8, 0.4))

extends Node2D

signal ship_clicked

@export var ship_mass: float = 10.0
@export var thrust_force: float = 144.0
@export var throttle_ramp_time := 0.15
@export var lock_adjust_rate := 0.5
@export var rotation_speed: float = 2.5
@export var collision_radius: float = 8.0
@export var fuel_consumption: float = 0.0
@export var fuel_capacity: float = 0.0
@export var energy_consumption: float = 0.0
@export var energy_generation: float = 0.0
@export var energy_capacity: float = 0.0
@export var shield_strength: float = 0.0

## Fallback when the shipyard has no modules yet (keeps the default orbital ship flyable).
const DEFAULT_SHIP_MASS := 10.0
const DEFAULT_THRUST_FORCE := 144.0
const MIN_SHIP_MASS := 1.0

## Main engine output relative to the modules' rated thrust: 6x so the ship
## stays punchy on its main engine alone (no RCS), times 4 for the 4x world
## scale (solar_system.gd G) - speeds and distances are both 4x, so
## accelerations must be too.
const MAIN_ENGINE_BOOST := 24.0
## Turning speed relative to the Turn Rate setting.
const TURN_RATE_SCALE := 1.2

## Holding Shift scales manual thrust and turning down to this, for fine
## orbit corrections.
const PRECISION_SCALE := 0.2

## Flight assist (V): arcade handling like the enemy craft, done with thrust.
## W pushes along the nose exactly like the locked throttle does - no speed
## cap - and on top of that vectored thrust cancels sideways drift (relative to
## the SOI body), so the velocity swings round with the nose. Releasing W cuts
## the engine and the ship coasts under gravity; S brakes to a stop.
## Most sideways / braking push the assist may use, units/s^2. Holding a turn
## at speed v and turn rate w takes v * w (80 units/s at 3 rad/s is ~240).
const ASSIST_MAX_ACCEL := 600.0
## How quickly sideways drift (and, braking, speed) is cancelled, per second.
const ASSIST_RESPONSE := 10.0

## Attitude hold (SAS): keeps the nose on a direction set by the flight path.
enum AttitudeHold { NONE, PROGRADE, RETROGRADE }

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
var autopilot_main_engine_output := 0.0
var throttle_locked := false
var attitude_hold: AttitudeHold = AttitudeHold.NONE
var flight_assist := true
## 0..1 share of full thrust the assist brake used last step (engine sound).
var assist_brake_output := 0.0
## Speed along the nose the assist is flying at while W is held.
## Velocity relative to the body whose SOI the ship is in - what prograde and
## retrograde point along. solar_system.gd sets it every sim step.
var hold_reference_velocity := Vector2.ZERO
var _lock_key_was_pressed := false
var paused := false
var true_scale := false:
	set(value):
		if true_scale == value:
			return
		true_scale = value
		queue_redraw()



const MAIN_ENGINE_SOUND := preload("res://sounds/main_engine.wav")
## Loudest the main engine gets, at full throttle.
const MAIN_ENGINE_VOLUME_DB := -4.0
## How fast the engine sound swells and dies away, in gain per second.
const MAIN_ENGINE_FADE_RATE := 5.0

## Locked-throttle beeps: one file per two segments of the HUD thrust bar
## (hud_status_panel.gd BAR_SEGMENTS), rising with the throttle.
const THROTTLE_BEEPS: Array[AudioStream] = [
	preload("res://sounds/throttle_beep_1.wav"), preload("res://sounds/throttle_beep_2.wav"),
	preload("res://sounds/throttle_beep_3.wav"), preload("res://sounds/throttle_beep_4.wav"),
	preload("res://sounds/throttle_beep_5.wav"), preload("res://sounds/throttle_beep_6.wav"),
	preload("res://sounds/throttle_beep_7.wav"), preload("res://sounds/throttle_beep_8.wav"),
	preload("res://sounds/throttle_beep_9.wav"),
]
const THROTTLE_SEGMENTS := 18

const LASER_SOUND := preload("res://sounds/laser.wav")
var _laser_player: AudioStreamPlayer

## A few players taken in turn, so a beep rings out under the next one
## (changing a player's stream would cut it off).
var _throttle_beeps: Array[AudioStreamPlayer] = []
var _next_throttle_beep := 0

## Looping main engine burn; volume and pitch follow the throttle.
var main_engine_sound: AudioStreamPlayer
var _main_engine_gain := 0.0


func _ready() -> void:
	$ClickArea.input_event.connect(_on_click_area_input_event)
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_ON
	reset_physics_interpolation()

	main_engine_sound = AudioStreamPlayer.new()
	main_engine_sound.name = "MainEngineSound"
	main_engine_sound.stream = MAIN_ENGINE_SOUND
	main_engine_sound.bus = &"SFX"
	add_child(main_engine_sound)

	_laser_player = AudioStreamPlayer.new()
	_laser_player.name = "LaserSound"
	_laser_player.stream = LASER_SOUND
	_laser_player.bus = &"SFX"
	_laser_player.max_polyphony = 4
	add_child(_laser_player)

	for i in range(4):
		var beep := AudioStreamPlayer.new()
		beep.name = "ThrottleBeep%d" % i
		beep.bus = &"SFX"
		add_child(beep)
		_throttle_beeps.append(beep)


## Applies aggregated ShipHull / ShipStats totals to flight parameters.
## Empty builds restore scene defaults so the orbital ship stays usable.
func apply_module_stats(stats: Dictionary) -> void:
	var module_count: int = int(stats.get("module_count", 0))
	if module_count <= 0:
		ship_mass = DEFAULT_SHIP_MASS
		thrust_force = DEFAULT_THRUST_FORCE
		fuel_consumption = 0.0
		fuel_capacity = 0.0
		energy_consumption = 0.0
		energy_generation = 0.0
		energy_capacity = 0.0
		shield_strength = 0.0
		apply_fov_devices([])
		return

	ship_mass = maxf(float(stats.get("mass", 0.0)), MIN_SHIP_MASS)
	thrust_force = maxf(float(stats.get("thrust", 0.0)), 0.0) * MAIN_ENGINE_BOOST
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
		_laser_player.play()
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


## Manual attitude: A / D (or the arrows) turn, holding RMB points the nose
## at the cursor, and either one cancels an attitude hold. With neither, an
## active hold (Z prograde / C retrograde) steers the nose along the flight path.
func update_rotation(delta: float) -> void:
	var turn_rate: float = get_turn_rate() * precision_scale()

	var turn: float = 0.0
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
		turn -= 1.0
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		turn += 1.0
	if turn != 0.0:
		attitude_hold = AttitudeHold.NONE
		rotation = wrapf(rotation + turn * turn_rate * delta, -PI, PI)
		return

	if Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
		attitude_hold = AttitudeHold.NONE
		var to_cursor: Vector2 = get_global_mouse_position() - global_position
		if to_cursor.length_squared() >= 1.0:
			rotation = rotate_toward(rotation, to_cursor.angle(), turn_rate * delta)
		return

	if attitude_hold != AttitudeHold.NONE and hold_reference_velocity.length_squared() > 1e-6:
		var target: float = hold_reference_velocity.angle()
		if attitude_hold == AttitudeHold.RETROGRADE:
			target += PI
		rotation = rotate_toward(rotation, target, turn_rate * delta)


## Z / C: hold prograde / retrograde; pressing the active one again releases it.
func toggle_attitude_hold(mode: AttitudeHold) -> void:
	attitude_hold = AttitudeHold.NONE if attitude_hold == mode else mode


## Radians per second the ship turns at, from the Turn Rate setting.
func get_turn_rate() -> float:
	return rotation_speed * TURN_RATE_SCALE


## 1, or PRECISION_SCALE while Shift is held.
func precision_scale() -> float:
	return PRECISION_SCALE if Input.is_key_pressed(KEY_SHIFT) else 1.0


func update_autopilot_rotation(delta: float) -> void:
	if autopilot_thrust == Vector2.ZERO:
		return

	rotation = rotate_toward(rotation, autopilot_thrust.angle(), get_turn_rate() * delta)


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
		var segments_before: int = roundi(throttle * THROTTLE_SEGMENTS)
		if Input.is_key_pressed(KEY_W):
			throttle = clampf(throttle + lock_adjust_rate * delta, 0.0, 1.0)
		elif Input.is_key_pressed(KEY_S):
			throttle = clampf(throttle - lock_adjust_rate * delta, 0.0, 1.0)
		var segments_after: int = roundi(throttle * THROTTLE_SEGMENTS)
		if segments_after != segments_before:
			_play_throttle_beep(segments_after)
		return

	# S cuts the engine at once; W spools it up.
	if Input.is_key_pressed(KEY_S):
		throttle = 0.0
		return
	var target := 1.0 if Input.is_key_pressed(KEY_W) else 0.0
	throttle = move_toward(throttle, target, delta / throttle_ramp_time)


## Segment n of the thrust bar (1..18) plays beep ceil(n / 2) - two segments
## per sound. Dropping to empty plays the lowest one.
func _play_throttle_beep(segments: int) -> void:
	var index: int = clampi((maxi(segments, 1) - 1) / 2, 0, THROTTLE_BEEPS.size() - 1)
	var player: AudioStreamPlayer = _throttle_beeps[_next_throttle_beep]
	_next_throttle_beep = (_next_throttle_beep + 1) % _throttle_beeps.size()
	player.stream = THROTTLE_BEEPS[index]
	player.play()


## Manual engine output for this sim step: plain thrust along the nose, or
## with flight assist on (and the throttle not locked) the assisted version.
func get_manual_acceleration() -> Vector2:
	if not flight_assist or throttle_locked:
		assist_brake_output = 0.0
		return get_thrust_acceleration()

	var velocity_rel: Vector2 = hold_reference_velocity
	var assist_cap: float = ASSIST_MAX_ACCEL * precision_scale()

	# S: brake to a stop relative to the body we orbit.
	if Input.is_key_pressed(KEY_S):
		var brake: Vector2 = (-velocity_rel * ASSIST_RESPONSE).limit_length(assist_cap)
		assist_brake_output = brake.length() / assist_cap
		return brake

	assist_brake_output = 0.0
	if throttle <= 0.0:
		# Engine off: coast.
		return Vector2.ZERO

	# The same push along the nose as the locked throttle, plus a vectored
	# sideways push that cancels drift.
	var forward := Vector2.RIGHT.rotated(rotation)
	var side: Vector2 = forward.orthogonal()
	var drift: float = velocity_rel.dot(side)
	var lateral: float = clampf(-drift * ASSIST_RESPONSE, -assist_cap, assist_cap)
	return get_thrust_acceleration() + side * lateral * throttle


func toggle_flight_assist() -> void:
	flight_assist = not flight_assist


func get_thrust_acceleration() -> Vector2:
	if throttle <= 0.0:
		return Vector2.ZERO

	var direction := Vector2.RIGHT.rotated(rotation)
	var acceleration: float = thrust_force * throttle * precision_scale() / ship_mass

	return direction * acceleration


func set_autopilot_thrust(command: Vector2) -> void:
	autopilot_thrust = Vector2(
		clampf(command.x, -1.0, 1.0),
		clampf(command.y, -1.0, 1.0)
	)


func clear_autopilot_thrust() -> void:
	autopilot_thrust = Vector2.ZERO


## The autopilot flies on the main engine only: it turns the nose onto the
## burn direction (update_autopilot_rotation) and fires as much of the burn as
## the nose is lined up with.
func get_autopilot_acceleration(max_force: float) -> Vector2:
	if autopilot_thrust == Vector2.ZERO:
		autopilot_main_engine_output = 0.0
		return Vector2.ZERO

	var forward: Vector2 = Vector2.RIGHT.rotated(rotation)
	var alignment: float = forward.dot(autopilot_thrust.normalized())
	if alignment <= 0.0:
		autopilot_main_engine_output = 0.0
		return Vector2.ZERO
	autopilot_main_engine_output = autopilot_thrust.length() * alignment
	return forward * (autopilot_main_engine_output * max_force / ship_mass)


func _process(delta: float) -> void:
	if _fire_flash_timer > 0.0:
		_fire_flash_timer = maxf(0.0, _fire_flash_timer - delta)
	queue_redraw()
	_update_main_engine_sound(delta)


## Manual throttle or the autopilot's main-engine burn, whichever is higher.
## Fades in and out rather than cutting, and falls silent on pause.
func _update_main_engine_sound(delta: float) -> void:
	var level: float = 0.0
	if not paused:
		level = clampf(maxf(maxf(throttle, autopilot_main_engine_output), assist_brake_output), 0.0, 1.0)
	var target: float = lerpf(0.45, 1.0, level) if level > 0.01 else 0.0
	_main_engine_gain = move_toward(_main_engine_gain, target, MAIN_ENGINE_FADE_RATE * delta)

	if _main_engine_gain <= 0.0:
		if main_engine_sound.playing:
			main_engine_sound.stop()
		return

	main_engine_sound.volume_db = MAIN_ENGINE_VOLUME_DB + linear_to_db(_main_engine_gain)
	main_engine_sound.pitch_scale = lerpf(0.92, 1.05, level)
	if not main_engine_sound.playing:
		main_engine_sound.play()


const SHIP_TEXTURE := preload("res://textures/ship_blueprint.png")
const SHIP_VISUAL_LENGTH := 22.0

const ENGINE_EXIT_POS := Vector2(0.58, 0.97)

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

		engine_pos = _image_to_local(ENGINE_EXIT_POS, draw_size)
	else:
		draw_colored_polygon(MARKER_POINTS, Color.WHITE)

		engine_pos = Vector2(-8, 0)

	# Too small a flame folds into polygons Godot cannot triangulate.
	if throttle > 0.02:
		_draw_engine_flame(engine_pos)

	if Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
		draw_line(Vector2.ZERO, to_local(get_global_mouse_position()), Color(1.0, 1.0, 1.0, 0.35), 1.0)

	if _fire_flash_timer > 0.0:
		var alpha := clampf(_fire_flash_timer / 0.35, 0.0, 1.0)
		draw_line(Vector2.ZERO, _fire_flash_to, Color(1.0, 0.45, 0.2, 0.85 * alpha), 2.0)


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

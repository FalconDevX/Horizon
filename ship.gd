extends Node2D

signal ship_clicked

@export var ship_mass: float = 10.0
@export var thrust_force: float = 6.0
@export var throttle_ramp_time := 1.2
@export var lock_adjust_rate := 0.5
@export var rotation_speed: float = 2.5
@export var collision_radius: float = 8.0
@export var correction_thrust_force := 1.0

var velocity := Vector2.ZERO
var throttle := 0.0
var autopilot_thrust := Vector2.ZERO
var autopilot_rcs_local_command := Vector2.ZERO
var manual_rcs_local_command := Vector2.ZERO
var autopilot_main_engine_output := 0.0
var throttle_locked := false
var _lock_key_was_pressed := false
var true_scale := false:
	set(value):
		if true_scale == value:
			return
		true_scale = value
		queue_redraw()


@onready var rcs_sound: AudioStreamPlayer = $RcsSound


func _ready() -> void:
	$ClickArea.input_event.connect(_on_click_area_input_event)


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


func _process(_delta: float) -> void:
	queue_redraw()
	_update_rcs_sound()


func _update_rcs_sound() -> void:
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


var MARKER_POINTS := PackedVector2Array([
	Vector2(12, 0),
	Vector2(-8, -7),
	Vector2(-8, 7),
])


func _draw() -> void:
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
		var flame_length: float = 10.0 * throttle
		var flame := PackedVector2Array([
			engine_pos + Vector2(0, -3),
			engine_pos + Vector2(0, 3),
			engine_pos + Vector2(-flame_length, 0)
		])
		draw_colored_polygon(flame, Color(1.0, 0.55, 0.15, 0.9))

	if Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
		draw_line(Vector2.ZERO, to_local(get_global_mouse_position()), Color(1.0, 1.0, 1.0, 0.35), 1.0)

	var combined: Vector2 = autopilot_rcs_local_command + manual_rcs_local_command
	_draw_rcs_thruster(front_pos, Vector2.RIGHT, combined.x < -RCS_ACTIVE_THRESHOLD, 0.0)
	_draw_rcs_thruster(back_pos, Vector2.LEFT, combined.x > RCS_ACTIVE_THRESHOLD, 1.7)
	_draw_rcs_thruster(left_pos, Vector2.UP, combined.y < -RCS_ACTIVE_THRESHOLD, 3.4)
	_draw_rcs_thruster(right_pos, Vector2.DOWN, combined.y > RCS_ACTIVE_THRESHOLD, 5.1)


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
	_draw_spark(base, outward_dir, side, half_width, length, t + phase)

	draw_colored_polygon(
		PackedVector2Array([
			base + side * half_width * 0.4,
			base - side * half_width * 0.4,
			base + outward_dir * length * 0.55
		]),
		Color(0.8, 0.95, 1.0, 0.9 * flicker)
	)


# Krawędź faluje sinusoidalnie zamiast być idealnie prostym trójkątem -
# to samo podejście co przy głównym silniku (patrz ship_blueprint_panel.gd).
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


# Pojedyncza migająca iskra odrywająca się od strumienia.
func _draw_spark(tip: Vector2, direction: Vector2, side: Vector2, half_width: float, length: float, t: float) -> void:
	var f: float = fmod(t * 0.8, 1.0)
	var pos: Vector2 = tip + direction * (length * (0.4 + f * 0.9))
	pos += side * sin(t * 9.0) * half_width * 0.5 * f
	var alpha: float = (1.0 - f) * 0.8
	var radius: float = maxf(0.5, 0.9 * (1.0 - f * 0.6))
	draw_circle(pos, radius, Color(0.85, 0.95, 1.0, alpha))

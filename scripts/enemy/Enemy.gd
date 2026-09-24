class_name Enemy
extends Node2D
## Standalone sprite-based hostile ship for the sandbox (E menu). Not built via
## the modular ShipHull/ship.gd system - single sprite, arcade WASD movement,
## detailed red engine flame, and a Space-bar laser fire. No thrust-force /
## correction-engine physics: this flies by direct kinematic moves along a
## trajectory, not by simulating engine forces. Proper steering feel comes later.

const LASER_BOLT_SCENE := preload("res://scenes/enemies/LaserBolt.tscn")

@export var ship_texture: Texture2D = preload("res://textures/enemies/enemy_basic.png")
@export var visual_length: float = 26.0
@export var move_speed: float = 160.0
@export var turn_speed: float = 2.6
@export var fire_cooldown: float = 0.35
## Played once per shot; the tank sets its own heavier one.
@export var laser_sound: AudioStream = preload("res://sounds/laser.wav")
@export var laser_speed: float = 420.0
## How far a bolt flies before it burns out, in world units.
@export var laser_range: float = 840.0
## Damage one bolt carries. Nothing is hit yet (see LaserBolt), but each
## enemy type already states what its guns deal.
@export var laser_damage: float = 10.0
@export var laser_width: float = 2.2
@export var laser_length: float = 14.0
@export var player_controlled: bool = true
## Barrel tips in the artwork, as fractions of the nose-up image - one bolt
## leaves each per shot.
@export var muzzles: PackedVector2Array = PackedVector2Array([Vector2(0.32, 0.24), Vector2(0.68, 0.24)])
## Engine nozzles in the artwork, same space - a flame burns behind each.
@export var engine_exits: PackedVector2Array = PackedVector2Array([Vector2(0.5, 0.94)])
@export var engine_half_width: float = 3.0

const FLAME_OUTER_COLOR := Color(1.0, 0.15, 0.1)
const FLAME_MID_COLOR := Color(1.0, 0.3, 0.15)
const FLAME_CORE_COLOR := Color(1.0, 0.55, 0.35)

var _throttle := 0.0
var _fire_timer := 0.0
var _laser_player: AudioStreamPlayer = null


func _process(delta: float) -> void:
	if player_controlled:
		_handle_input(delta)
	_fire_timer = maxf(0.0, _fire_timer - delta)
	queue_redraw()


func _handle_input(delta: float) -> void:
	if Input.is_key_pressed(KEY_A):
		rotation -= turn_speed * delta
	if Input.is_key_pressed(KEY_D):
		rotation += turn_speed * delta

	var target_throttle := 0.0
	if Input.is_key_pressed(KEY_W):
		target_throttle = 1.0
	elif Input.is_key_pressed(KEY_S):
		target_throttle = -0.6
	_throttle = move_toward(_throttle, target_throttle, delta * 2.5)

	if not is_zero_approx(_throttle):
		position += Vector2.RIGHT.rotated(rotation) * move_speed * _throttle * delta

	if Input.is_key_pressed(KEY_SPACE):
		_try_fire()


func _try_fire() -> void:
	if _fire_timer > 0.0:
		return
	_fire_timer = fire_cooldown
	fire_laser()


func fire_laser() -> void:
	if get_parent() == null:
		return
	_play_laser_sound()
	var dir := Vector2.RIGHT.rotated(rotation)
	var draw_size := _get_draw_size()
	for frac in muzzles:
		var muzzle_local: Vector2 = _image_to_local(frac, draw_size)
		var bolt := LASER_BOLT_SCENE.instantiate() as LaserBolt
		bolt.lifetime = laser_range / laser_speed
		bolt.damage = laser_damage
		bolt.width = laser_width
		bolt.length = laser_length
		get_parent().add_child(bolt)
		bolt.global_position = global_position + muzzle_local.rotated(rotation)
		bolt.velocity = dir * laser_speed


## One shot, one sound, however many muzzles fire. Quick shots overlap.
func _play_laser_sound() -> void:
	if _laser_player == null:
		_laser_player = AudioStreamPlayer.new()
		_laser_player.stream = laser_sound
		_laser_player.bus = &"SFX"
		_laser_player.max_polyphony = 4
		add_child(_laser_player)
	_laser_player.play()


func _get_draw_size() -> Vector2:
	if ship_texture == null:
		return Vector2(visual_length, visual_length)
	var texture_size: Vector2 = ship_texture.get_size()
	return Vector2(visual_length * texture_size.x / texture_size.y, visual_length)


func _draw() -> void:
	if ship_texture == null:
		return
	var draw_size := _get_draw_size()
	draw_set_transform(Vector2.ZERO, PI * 0.5, Vector2.ONE)
	draw_texture_rect(ship_texture, Rect2(-draw_size * 0.5, draw_size), false)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	if _throttle > 0.05:
		for exit in engine_exits:
			_draw_engine_flame(_image_to_local(exit, draw_size))


func _image_to_local(frac: Vector2, draw_size: Vector2) -> Vector2:
	return ((frac - Vector2(0.5, 0.5)) * draw_size).rotated(PI * 0.5)


## Multi-layer red engine flame (outer + mid wavy-flame, triangle core, sparks) -
## same technique as ship.gd's main engine, recolored for a hostile ship.
func _draw_engine_flame(tip: Vector2) -> void:
	var direction := Vector2.LEFT
	var side: Vector2 = direction.orthogonal()

	var t: float = Time.get_ticks_msec() / 1000.0
	var flicker: float = 0.85 + 0.15 * sin(t * 24.0) + 0.08 * sin(t * 61.0 + 1.3)
	var length: float = 11.0 * absf(_throttle) * flicker

	_draw_wavy_flame(
		tip, direction, side, engine_half_width, length, t,
		Color(FLAME_OUTER_COLOR, 0.55 * flicker)
	)

	var mid_half_width: float = engine_half_width * 0.75
	_draw_wavy_flame(
		tip, direction, side, mid_half_width, length * 0.8, t + 3.1,
		Color(FLAME_MID_COLOR, 0.7 * flicker)
	)

	var inner_half_width: float = engine_half_width * 0.4
	draw_colored_polygon(
		PackedVector2Array([
			tip + side * inner_half_width,
			tip - side * inner_half_width,
			tip + direction * (length * 0.6)
		]),
		Color(FLAME_CORE_COLOR, 0.95 * flicker)
	)

	_draw_sparks(tip, direction, side, engine_half_width, length, t, Color(1.0, 0.5, 0.3))


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
		# Kept above zero: a negative width crosses the outline over itself
		# and the polygon fails to triangulate.
		var width: float = maxf(half_width * taper + wobble, 0.05)
		left_points.append(pos + side * width)
		right_points.append(pos - side * width)

	var points := PackedVector2Array()
	points.append_array(left_points)
	right_points.reverse()
	points.append_array(right_points)
	draw_colored_polygon(points, color)


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

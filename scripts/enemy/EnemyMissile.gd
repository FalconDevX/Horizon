class_name EnemyMissile
extends Node2D
## A missile fired at the player by an enemy launcher (the Frigate). It leaves
## its pod along the pod's facing with the launcher's own velocity, then
## flies at `speed`, turning toward the player's ship at `turn` rad/s - hard
## enough to follow a cruising ship, not to catch one that breaks sharply or
## boosts away. It bursts on the ship (damage through ship.take_damage) or,
## out of fuel after `max_distance`, harmlessly. While the ship is landed it
## loses its target and flies straight on. Sizes are in screen pixels, so it
## reads at any zoom. Reads the scene's time_scale, so it holds with the game.

const BOOST_TIME := 0.8
const BLAST_TIME := 0.6
## Screen px.
const LENGTH := 14.0
const TRAIL_POINTS := 16
const BODY_COLOR := Color(0.78, 0.8, 0.84)
const GLOW_COLOR := Color(1.0, 0.22, 0.12)

var damage: float = 24.0
var speed: float = 2300.0
var turn: float = 1.6
var max_distance: float = 22000.0
var velocity := Vector2.ZERO
## The enemy that fired it (never hit by its own missiles).
var ignore_enemy: Node = null

var _heading := Vector2.RIGHT
var _launch_velocity := Vector2.ZERO
var _age := 0.0
var _travelled := 0.0
var _blast_age: float = -1.0
var _trail: PackedVector2Array = []


func _init() -> void:
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	z_index = 1


## Sets it off nose along `direction`, carrying `launch_velocity` at first.
func launch(direction: Vector2, launch_velocity: Vector2) -> void:
	_heading = direction.normalized()
	_launch_velocity = launch_velocity
	velocity = _launch_velocity + _heading * speed * 0.3
	rotation = _heading.angle()


func _process(delta: float) -> void:
	var held: Variant = get_parent().get("time_scale") if get_parent() != null else null
	var scale_now: float = float(held) if held != null else 1.0
	var dt: float = delta * minf(scale_now, 1.0)
	if _blast_age >= 0.0:
		_blast_age += delta
		if _blast_age >= BLAST_TIME:
			queue_free()
		queue_redraw()
		return
	if dt <= 0.0:
		return
	_age += dt
	var ship: Node2D = _target()
	if ship != null and _age > BOOST_TIME * 0.4:
		var wanted: Vector2 = (ship.global_position - global_position).normalized()
		_heading = _heading.rotated(clampf(_heading.angle_to(wanted), -turn * dt, turn * dt))
	var boost: float = clampf(_age / BOOST_TIME, 0.0, 1.0)
	velocity = _heading * speed * lerpf(0.3, 1.0, boost) + _launch_velocity * (1.0 - boost)
	rotation = _heading.angle()

	var previous: Vector2 = global_position
	global_position += velocity * dt
	_travelled += (velocity * dt).length()
	_trail.append(global_position)
	if _trail.size() > TRAIL_POINTS:
		_trail.remove_at(0)

	if ship != null:
		var reach: float = maxf(float(ship.get("collision_radius")), 6.0) + 2.0 * _px()
		if LaserBolt._segment_hits_circle(previous, global_position, ship.global_position, reach):
			global_position = ship.global_position
			ship.call("take_damage", damage, previous)
			_burst()
			return
	if _travelled >= max_distance:
		_burst()
		return
	queue_redraw()


## The player's ship, or null while it is landed (or gone).
func _target() -> Node2D:
	if get_parent() == null:
		return null
	var ship: Node2D = get_parent().get_node_or_null("Ship") as Node2D
	if ship == null or bool(ship.get("landed")) or not ship.has_method("take_damage"):
		return null
	return ship


func _burst() -> void:
	if get_parent() != null and get_parent().has_method("play_ship_explosion_sound"):
		get_parent().call("play_ship_explosion_sound")
	_blast_age = 0.0
	queue_redraw()


func _px() -> float:
	return 1.0 / maxf(get_global_transform_with_canvas().get_scale().x, 0.0001)


func _draw() -> void:
	var px: float = _px()
	if _blast_age >= 0.0:
		ExplosionFX.draw(self, Vector2.ZERO, _blast_age / BLAST_TIME, 18.0 * px, get_instance_id(), px, Color(1.0, 0.35, 0.15), 0.8, false)
		return
	if _trail.size() >= 2:
		var local := PackedVector2Array()
		for point in _trail:
			local.append(to_local(point))
		for i in local.size() - 1:
			var a: float = float(i + 1) / local.size()
			draw_line(local[i], local[i + 1], Color(0.75, 0.7, 0.7, 0.3 * a), 2.0 * px * a + px)
	var flicker: float = 0.8 + 0.2 * sin(Time.get_ticks_msec() * 0.05 + get_instance_id())
	var l: float = LENGTH * px
	var w: float = 2.2 * px
	draw_circle(Vector2(-l * 0.55, 0.0), 3.4 * px * flicker, Color(GLOW_COLOR, 0.85))
	draw_colored_polygon(PackedVector2Array([
		Vector2(l * 0.5, 0.0), Vector2(l * 0.25, -w), Vector2(-l * 0.45, -w),
		Vector2(-l * 0.45, w), Vector2(l * 0.25, w),
	]), BODY_COLOR)
	# Red nose and fins: an enemy's missile at a glance.
	draw_colored_polygon(PackedVector2Array([Vector2(l * 0.5, 0.0), Vector2(l * 0.25, -w), Vector2(l * 0.25, w)]), GLOW_COLOR)
	draw_colored_polygon(PackedVector2Array([Vector2(-l * 0.2, -w), Vector2(-l * 0.5, -w * 2.4), Vector2(-l * 0.45, -w)]), GLOW_COLOR)
	draw_colored_polygon(PackedVector2Array([Vector2(-l * 0.2, w), Vector2(-l * 0.5, w * 2.4), Vector2(-l * 0.45, w)]), GLOW_COLOR)

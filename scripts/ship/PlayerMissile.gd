class_name PlayerMissile
extends Node2D
## One missile from the player's Rocket Launcher (types in MissileCatalog).
## It leaves with the ship's velocity, then flies at its own speed, turning
## toward its target at the type's turn rate; seekers pick the nearest enemy
## ahead of them when they have none (or lose theirs). It bursts on contact,
## within its proxy fuse of the target, or at the end of its flight - hurting
## (or, EMP, disabling) every enemy in its blast. Sizes are in screen pixels,
## so it reads at any zoom. Spawned by solar_system.gd.

## How long the launch velocity takes to give way to the missile's own.
const BOOST_TIME := 0.6
## A seeker looks for prey within this angle of its nose.
const SEEK_CONE := 1.2
const BLAST_TIME := 0.7
## Screen px.
const LENGTH := 11.0
const TRAIL_POINTS := 14

var type: StringName = MissileCatalog.DEFAULT
var target: Enemy = null
var damage: float = 80.0
## World units it may fly before it bursts.
var max_distance: float = 9000.0
## The enemy the player is flying (never hit by their own ship's missiles).
var ignore: Node = null
var velocity := Vector2.ZERO

var _info: Dictionary = {}
var _heading := Vector2.RIGHT
var _age := 0.0
var _travelled := 0.0
var _launch_velocity := Vector2.ZERO
## After it went off: seconds into its blast, or -1 while flying.
var _blast_age: float = -1.0
var _trail: PackedVector2Array = []


func _init() -> void:
	# Moved by hand every frame, like PlayerShot.
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF


## Sets it off from where it stands, nose along `direction`, carrying
## `launch_velocity` (the ship's) at first.
func launch(direction: Vector2, launch_velocity: Vector2) -> void:
	_info = MissileCatalog.info(type)
	_heading = direction.normalized()
	_launch_velocity = launch_velocity
	velocity = _launch_velocity + _heading * float(_info["speed"]) * 0.35
	rotation = _heading.angle()


func _process(delta: float) -> void:
	if _info.is_empty():
		_info = MissileCatalog.info(type)
	var scale_now: float = float(get_parent().get("time_scale")) if get_parent() != null else 1.0
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

	if not _alive(target):
		target = _find_prey() if _info.get("seek", false) or target != null else null
	if _alive(target):
		var wanted: Vector2 = (target.global_position - global_position).normalized()
		var turn: float = clampf(_heading.angle_to(wanted), -float(_info["turn"]) * dt, float(_info["turn"]) * dt)
		_heading = _heading.rotated(turn)
	# The launch push fades into the missile's own speed along its heading.
	var boost: float = clampf(_age / BOOST_TIME, 0.0, 1.0)
	var own: Vector2 = _heading * float(_info["speed"]) * lerpf(0.35, 1.0, boost)
	velocity = own + _launch_velocity * (1.0 - boost)
	rotation = _heading.angle()

	var previous: Vector2 = global_position
	global_position += velocity * dt
	_travelled += (velocity * dt).length()
	_trail.append(global_position)
	if _trail.size() > TRAIL_POINTS:
		_trail.remove_at(0)

	var struck: Enemy = _first_enemy_on(previous, global_position)
	if struck != null:
		global_position = struck.global_position
		_burst()
		return
	var fuse: float = float(_info.get("fuse", 0.0))
	if fuse > 0.0 and _alive(target) and global_position.distance_to(target.global_position) <= fuse + target.hit_radius():
		_burst()
		return
	if _travelled >= max_distance * float(_info.get("life", 1.0)):
		_burst()
		return
	queue_redraw()


static func _alive(enemy: Enemy) -> bool:
	return enemy != null and is_instance_valid(enemy) and enemy.is_alive()


func _enemies() -> Array[Enemy]:
	var out: Array[Enemy] = []
	if get_parent() == null:
		return out
	for child in get_parent().get_children():
		if child is Enemy and child != ignore and (child as Enemy).is_alive():
			out.append(child)
	return out


## The nearest enemy ahead of the nose, within the rest of its flight.
func _find_prey() -> Enemy:
	var best: Enemy = null
	var best_d := INF
	var reach: float = max_distance * float(_info.get("life", 1.0)) - _travelled
	for enemy in _enemies():
		var offset: Vector2 = enemy.global_position - global_position
		var d: float = offset.length()
		if d > reach or absf(_heading.angle_to(offset)) > SEEK_CONE:
			continue
		if d < best_d:
			best_d = d
			best = enemy
	return best


func _first_enemy_on(from: Vector2, to: Vector2) -> Enemy:
	var best: Enemy = null
	var best_d := INF
	for enemy in _enemies():
		if LaserBolt._segment_hits_circle(from, to, enemy.global_position, enemy.hit_radius() + 3.0 * _px()):
			var d: float = from.distance_squared_to(enemy.global_position)
			if d < best_d:
				best_d = d
				best = enemy
	return best


## Goes off: damage (or EMP) to every enemy in the blast.
func _burst() -> void:
	var blast: float = float(_info.get("blast", 60.0))
	var emp: float = float(_info.get("emp", 0.0))
	for enemy in _enemies():
		if enemy.global_position.distance_to(global_position) > blast + enemy.hit_radius():
			continue
		if emp > 0.0:
			enemy.disable_for(emp)
		if damage > 0.0:
			enemy.take_hit(damage)
	_blast_age = 0.0
	queue_redraw()


func _px() -> float:
	return 1.0 / maxf(get_global_transform_with_canvas().get_scale().x, 0.0001)


func _draw() -> void:
	var px: float = _px()
	var colour: Color = _info.get("color", Color(1.0, 0.55, 0.22))
	if _blast_age >= 0.0:
		var blast: float = float(_info.get("blast", 60.0))
		if float(_info.get("emp", 0.0)) > 0.0:
			# A blue ring snapping outward instead of fire.
			var t: float = _blast_age / BLAST_TIME
			draw_set_transform(Vector2.ZERO, -rotation, Vector2.ONE)
			draw_arc(Vector2.ZERO, maxf(blast, 14.0 * px) * (0.3 + 0.7 * t), 0.0, TAU, 48, Color(colour, 1.0 - t), 3.0 * px, true)
			draw_circle(Vector2.ZERO, maxf(blast, 14.0 * px) * 0.4 * (1.0 - t), Color(0.8, 0.85, 1.0, 0.5 * (1.0 - t)))
			return
		ExplosionFX.draw(self, Vector2.ZERO, _blast_age / BLAST_TIME, maxf(blast * 0.7, 16.0 * px), get_instance_id(), px, colour, 0.9, false)
		return
	# Smoke trail, in world space undone into the missile's frame.
	if _trail.size() >= 2:
		var local := PackedVector2Array()
		for point in _trail:
			local.append(to_local(point))
		for i in local.size() - 1:
			var a: float = float(i + 1) / local.size()
			draw_line(local[i], local[i + 1], Color(0.85, 0.85, 0.9, 0.35 * a), 2.0 * px * a + px)
	var flicker: float = 0.8 + 0.2 * sin(Time.get_ticks_msec() * 0.05 + get_instance_id())
	draw_circle(Vector2(-LENGTH * 0.55 * px, 0.0), 3.2 * px * flicker, Color(1.0, 0.65, 0.25, 0.8))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(px, px))
	MissileCatalog.draw_icon(self, Vector2.ZERO, LENGTH, type)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

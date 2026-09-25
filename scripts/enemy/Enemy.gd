class_name Enemy
extends Node2D
## Standalone sprite-based hostile ship for the sandbox (E menu). Not built via
## the modular ShipHull/ship.gd system - single sprite, arcade WASD movement,
## detailed red engine flame, and a Space-bar laser fire. No thrust-force /
## correction-engine physics: this flies by direct kinematic moves along a
## trajectory, not by simulating engine forces. Proper steering feel comes later.
##
## Special roles (set per scene): kamikaze ram, mothership fighter deploy,
## minelayer damage fields, black-hole attract+fuse.

const LASER_BOLT_SCENE := preload("res://scenes/enemies/LaserBolt.tscn")
const DAMAGE_ZONE_SCRIPT := preload("res://scripts/enemy/DamageZone.gd")
## Ignore the parked player ship for this long after spawn (kamikaze starts on
## top of it when picked from the E menu).
const CONTACT_GRACE := 0.75
const EXPLOSION_DURATION := 0.45
const BLACK_HOLE_EXPLOSION_DURATION := 1.1

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
## Pitch the laser sound plays at (lower = heavier).
@export var laser_pitch: float = 1.0
## Fire one long SniperBeam reaching `laser_range` in an instant, instead of
## travelling bolts.
@export var beam_mode: bool = false
@export var beam_color: Color = Color(1.0, 0.78, 0.12)
@export var player_controlled: bool = true
## When false, Space does nothing for guns (kamikaze / black hole / etc.).
@export var can_fire: bool = true
## Blow up on ship contact or when a bolt/beam hits (kamikaze).
@export var explodes_on_hit: bool = false
@export var collision_radius: float = 12.0
## Barrel tips in the artwork, as fractions of the nose-up image - one bolt
## leaves each per shot.
@export var muzzles: PackedVector2Array = PackedVector2Array([Vector2(0.32, 0.24), Vector2(0.68, 0.24)])
## Engine nozzles in the artwork, same space - a flame burns behind each.
@export var engine_exits: PackedVector2Array = PackedVector2Array([Vector2(0.5, 0.94)])
@export var engine_half_width: float = 3.0

## Uncontrolled craft (mothership drones): full throttle, optional seek.
@export var ai_forward: bool = false
@export var ai_seek_ship: bool = false

## Mothership: Space launches Fast fighters instead of shooting.
@export var deploy_fighters: bool = false
@export var fighter_scene: PackedScene
@export var deploy_cooldown: float = 1.4
@export var deploy_offset: float = 36.0

## Minelayer: Space drops a DamageZone at the ship.
@export var lay_mines: bool = false
@export var mine_radius: float = 140.0
@export var mine_dps: float = 28.0
@export var mine_lifetime: float = 14.0
@export var mine_cooldown: float = 1.1

## Black hole: attract everything nearby, then detonate after the fuse.
@export var black_hole_mode: bool = false
@export var black_hole_radius: float = 520.0
@export var black_hole_pull: float = 220.0
@export var black_hole_fuse: float = 6.0
@export var black_hole_blast_radius: float = 380.0
@export var black_hole_blast_damage: float = 120.0

const FLAME_OUTER_COLOR := Color(1.0, 0.15, 0.1)
const FLAME_MID_COLOR := Color(1.0, 0.3, 0.15)
const FLAME_CORE_COLOR := Color(1.0, 0.55, 0.35)

var _throttle := 0.0
var _fire_timer := 0.0
var _ability_timer := 0.0
var _laser_player: AudioStreamPlayer = null
var _alive_time := 0.0
var _exploding := false
var _explode_age := 0.0
var _explosion_duration: float = EXPLOSION_DURATION
var _blast_radius: float = 0.0


func _process(delta: float) -> void:
	if _exploding:
		_explode_age += delta
		queue_redraw()
		if _explode_age >= _explosion_duration:
			queue_free()
		return

	_alive_time += delta
	_fire_timer = maxf(0.0, _fire_timer - delta)
	_ability_timer = maxf(0.0, _ability_timer - delta)

	if player_controlled:
		_handle_input(delta)
	elif ai_forward or ai_seek_ship:
		_handle_ai(delta)

	if explodes_on_hit:
		_check_ship_contact()
	if black_hole_mode:
		_black_hole_tick(delta)
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
		if deploy_fighters:
			_try_deploy_fighter()
		elif lay_mines:
			_try_lay_mine()
		elif can_fire:
			_try_fire()


func _handle_ai(delta: float) -> void:
	if ai_seek_ship:
		var target := _find_player_ship()
		if target != null:
			var desired: float = (target.global_position - global_position).angle()
			var diff: float = wrapf(desired - rotation, -PI, PI)
			rotation += clampf(diff, -turn_speed * delta, turn_speed * delta)
	_throttle = 1.0
	position += Vector2.RIGHT.rotated(rotation) * move_speed * _throttle * delta
	if can_fire and not deploy_fighters and not lay_mines:
		_try_fire()


func _try_fire() -> void:
	if not can_fire or _fire_timer > 0.0:
		return
	_fire_timer = fire_cooldown
	fire_laser()


func fire_laser() -> void:
	if not can_fire or get_parent() == null:
		return
	_play_laser_sound()
	var dir := Vector2.RIGHT.rotated(rotation)
	var draw_size := _get_draw_size()
	for frac in muzzles:
		var muzzle_local: Vector2 = _image_to_local(frac, draw_size)
		if beam_mode:
			var beam := SniperBeam.new()
			beam.direction = dir
			beam.reach = laser_range
			beam.damage = laser_damage
			beam.glow_color = beam_color
			beam.ignore_enemy = self
			get_parent().add_child(beam)
			beam.global_position = global_position + muzzle_local.rotated(rotation)
			continue
		var bolt := LASER_BOLT_SCENE.instantiate() as LaserBolt
		bolt.lifetime = laser_range / laser_speed
		bolt.damage = laser_damage
		bolt.width = laser_width
		bolt.length = laser_length
		bolt.ignore_enemy = self
		get_parent().add_child(bolt)
		bolt.global_position = global_position + muzzle_local.rotated(rotation)
		bolt.velocity = dir * laser_speed


func _try_deploy_fighter() -> void:
	if fighter_scene == null or _ability_timer > 0.0 or get_parent() == null:
		return
	_ability_timer = deploy_cooldown
	var fighter := fighter_scene.instantiate() as Enemy
	if fighter == null:
		return
	fighter.player_controlled = false
	fighter.ai_forward = true
	fighter.ai_seek_ship = true
	get_parent().add_child(fighter)
	var aft := -Vector2.RIGHT.rotated(rotation) * deploy_offset
	fighter.global_position = global_position + aft
	fighter.rotation = rotation
	_play_laser_sound()


func _try_lay_mine() -> void:
	if _ability_timer > 0.0 or get_parent() == null:
		return
	_ability_timer = mine_cooldown
	var zone: DamageZone = DAMAGE_ZONE_SCRIPT.new() as DamageZone
	zone.radius = mine_radius
	zone.damage_per_second = mine_dps
	zone.lifetime = mine_lifetime
	zone.ignore_enemy = self
	get_parent().add_child(zone)
	zone.global_position = global_position
	_play_laser_sound()


func _black_hole_tick(delta: float) -> void:
	_pull_nearby(delta)
	if _alive_time >= black_hole_fuse:
		_detonate_black_hole()


func _pull_nearby(delta: float) -> void:
	var parent := get_parent()
	if parent == null:
		return
	for child in parent.get_children():
		if child == self or not (child is Node2D):
			continue
		# Only sandbox combatants - never Sun / Planets / HUD siblings.
		var is_ship: bool = child.name == "Ship"
		var is_enemy: bool = child is Enemy
		var is_bolt: bool = child is LaserBolt
		var is_zone: bool = child is DamageZone
		if not (is_ship or is_enemy or is_bolt or is_zone):
			continue
		var node := child as Node2D
		var offset: Vector2 = global_position - node.global_position
		var dist: float = offset.length()
		if dist < 1.0 or dist > black_hole_radius:
			continue
		var falloff: float = 1.0 - dist / black_hole_radius
		var pull_dir: Vector2 = offset.normalized()
		var step: Vector2 = pull_dir * black_hole_pull * falloff * falloff * delta
		if is_bolt:
			(child as LaserBolt).velocity += pull_dir * black_hole_pull * 1.6 * falloff * delta
			node.position += step * 0.35
		elif is_ship:
			# Ship pose is owned by solar_system's PhysicsBody - route through it.
			var ship_vel: Vector2 = node.get("velocity") as Vector2
			var new_vel: Vector2 = ship_vel + pull_dir * black_hole_pull * falloff * falloff * delta
			var new_pos: Vector2 = node.position + step
			if parent.has_method("set_ship_state"):
				parent.call("set_ship_state", new_pos, new_vel)
			else:
				node.position = new_pos
				node.set("velocity", new_vel)
		else:
			node.position += step


func _detonate_black_hole() -> void:
	_apply_blast_damage(black_hole_blast_radius, black_hole_blast_damage)
	_blast_radius = black_hole_blast_radius
	_explosion_duration = BLACK_HOLE_EXPLOSION_DURATION
	explode()


func _apply_blast_damage(radius: float, amount: float) -> void:
	var parent := get_parent()
	if parent == null:
		return
	for child in parent.get_children():
		if child == self:
			continue
		if child is Enemy:
			var enemy := child as Enemy
			if enemy.global_position.distance_squared_to(global_position) <= radius * radius:
				enemy.take_hit(amount)
		elif child.name == "Ship" and child is Node2D:
			var ship := child as Node2D
			if ship.global_position.distance_squared_to(global_position) <= radius * radius:
				var taken: float = float(ship.get_meta("sandbox_damage_taken", 0.0))
				ship.set_meta("sandbox_damage_taken", taken + amount)


## One shot, one sound, however many muzzles fire. Quick shots overlap.
func _play_laser_sound() -> void:
	if _laser_player == null:
		_laser_player = AudioStreamPlayer.new()
		_laser_player.stream = laser_sound
		_laser_player.bus = &"SFX"
		_laser_player.max_polyphony = 4
		_laser_player.pitch_scale = laser_pitch
		add_child(_laser_player)
	_laser_player.play()


## Called by LaserBolt / SniperBeam / DamageZone. Kamikaze detonates; others ignore for now.
func take_hit(_amount: float) -> void:
	if explodes_on_hit:
		explode()


func is_hittable() -> bool:
	return explodes_on_hit and not _exploding


func explode() -> void:
	if _exploding:
		return
	_exploding = true
	_explode_age = 0.0
	_throttle = 0.0
	player_controlled = false
	queue_redraw()


func _check_ship_contact() -> void:
	if _alive_time < CONTACT_GRACE:
		return
	var player_ship := _find_player_ship()
	if player_ship == null:
		return
	var ship_radius: float = float(player_ship.get("collision_radius"))
	if ship_radius <= 0.0:
		ship_radius = 8.0
	var reach: float = collision_radius + ship_radius
	if global_position.distance_squared_to(player_ship.global_position) <= reach * reach:
		explode()


func _find_player_ship() -> Node2D:
	var parent := get_parent()
	if parent == null:
		return null
	return parent.get_node_or_null("Ship") as Node2D


func _get_draw_size() -> Vector2:
	if ship_texture == null:
		return Vector2(visual_length, visual_length)
	var texture_size: Vector2 = ship_texture.get_size()
	return Vector2(visual_length * texture_size.x / texture_size.y, visual_length)


func _draw() -> void:
	if _exploding:
		_draw_explosion()
		return
	if black_hole_mode:
		_draw_black_hole_field()
	if ship_texture == null:
		return
	var draw_size := _get_draw_size()
	draw_set_transform(Vector2.ZERO, PI * 0.5, Vector2.ONE)
	draw_texture_rect(ship_texture, Rect2(-draw_size * 0.5, draw_size), false)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	if _throttle > 0.05:
		for exit in engine_exits:
			_draw_engine_flame(_image_to_local(exit, draw_size))


func _draw_black_hole_field() -> void:
	var t: float = Time.get_ticks_msec() / 1000.0
	var fuse_left: float = maxf(0.0, black_hole_fuse - _alive_time)
	var urgency: float = 1.0 - clampf(fuse_left / black_hole_fuse, 0.0, 1.0)
	var pulse: float = 0.7 + 0.3 * sin(t * (4.0 + urgency * 10.0))
	var rim := Color(0.55, 0.2, 0.95, 0.2 * pulse)
	draw_circle(Vector2.ZERO, black_hole_radius, Color(0.15, 0.05, 0.28, 0.12 * pulse))
	draw_arc(Vector2.ZERO, black_hole_radius * pulse, 0.0, TAU, 64, rim, 2.0)
	draw_arc(Vector2.ZERO, black_hole_radius * 0.55, 0.0, TAU, 48, Color(0.8, 0.4, 1.0, 0.35 * pulse), 1.5)
	draw_circle(Vector2.ZERO, lerpf(8.0, visual_length * 0.6, urgency), Color(0.05, 0.0, 0.1, 0.85))


func _draw_explosion() -> void:
	var t: float = clampf(_explode_age / _explosion_duration, 0.0, 1.0)
	var fade: float = 1.0 - t
	var max_r: float = visual_length * 2.4 if _blast_radius <= 0.0 else _blast_radius
	var radius: float = lerpf(6.0, max_r, t)
	draw_circle(Vector2.ZERO, radius, Color(1.0, 0.35, 0.1, 0.35 * fade))
	draw_circle(Vector2.ZERO, radius * 0.65, Color(1.0, 0.55, 0.15, 0.55 * fade))
	draw_circle(Vector2.ZERO, radius * 0.3, Color(1.0, 0.9, 0.5, 0.9 * fade))
	var ring_r: float = radius * (0.85 + 0.15 * sin(t * TAU * 3.0))
	draw_arc(Vector2.ZERO, ring_r, 0.0, TAU, 32, Color(1.0, 0.7, 0.3, 0.7 * fade), 2.0)
	if _blast_radius > 0.0:
		draw_arc(Vector2.ZERO, radius, 0.0, TAU, 64, Color(0.7, 0.35, 1.0, 0.5 * fade), 3.0)


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

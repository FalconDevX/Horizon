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
const SOUND_TARGET_DESTROYED := preload("res://sounds/target--destroyed.wav")
## Ignore the parked player ship for this long after spawn (kamikaze starts on
## top of it when picked from the E menu).
const CONTACT_GRACE := 0.75
const EXPLOSION_DURATION := 1.1
const BLACK_HOLE_EXPLOSION_DURATION := 1.6

## Shown in the player's enemy contacts panel (set from EnemyCatalog on spawn).
@export var title: String = "Enemy"
## Catalog id for the flat map/HUD glyph (shape + colour).
@export var kind_id: String = "basic"
@export var ship_texture: Texture2D = preload("res://textures/enemies/enemy_basic.png")
@export var visual_length: float = 26.0
@export var move_speed: float = 160.0
## Hostile chase: always at least this many times the player's current speed.
const SPEED_VS_PLAYER := 1.1
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
## Hits it takes from the player's weapons before it blows up (a kamikaze
## goes off at the first hit whatever this says).
@export var max_health: float = 60.0
## What ramming the player's ship does to it (kamikaze contact).
@export var contact_damage: float = 45.0
## Barrel tips in the artwork, as fractions of the nose-up image - one bolt
## leaves each per shot.
@export var muzzles: PackedVector2Array = PackedVector2Array([Vector2(0.32, 0.24), Vector2(0.68, 0.24)])
## Engine nozzles in the artwork, same space - a flame burns behind each.
@export var engine_exits: PackedVector2Array = PackedVector2Array([Vector2(0.5, 0.94)])
@export var engine_half_width: float = 3.0

## Uncontrolled craft (mothership drones): full throttle, optional seek.
@export var ai_forward: bool = false
@export var ai_seek_ship: bool = false

## Mothership: auto-launches Fast fighters on an interval; Space also launches
## when the craft is player-controlled.
@export var deploy_fighters: bool = false
@export var fighter_scene: PackedScene
## Seconds between fighter launches (rolled uniformly each time).
@export var deploy_cooldown: float = 10.0
@export var deploy_cooldown_max: float = 15.0
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
var _damage_taken: float = 0.0
## Picked as the target in the player's contacts panel: drawn with brackets.
var targeted := false:
	set(value):
		targeted = value
		queue_redraw()
var _explode_age := 0.0
var _explosion_duration: float = EXPLOSION_DURATION
var _blast_radius: float = 0.0
## Seconds the black-hole pull has been active (fuse only counts while armed).
var _bh_active_time := 0.0
## When false the craft is drawn as a fixed-size screen marker (solar_system
## scales the node with 1/zoom, same as the player ship).
var true_scale: bool = true

## Circular patrol around a planet (PlanetGuards). Null = not orbiting.
var orbit_anchor: Node2D = null
var orbit_radius: float = 0.0
var orbit_angle: float = 0.0
var orbit_omega: float = 0.0
## Player distance to the planet that wakes this craft (0 = never).
var orbit_alert_range: float = 0.0
## Leave the rail and chase while the player is near the guarded planet.
var _alerted: bool = false
var _orbiting: bool = false


func _init() -> void:
	# Moved by hand in _process: interpolating it between physics ticks
	# would make it shake.
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF


func _ready() -> void:
	if deploy_fighters:
		_ability_timer = _next_deploy_delay()


## Park this craft on a circular orbit around `anchor`. Not player-controlled.
## `alert_range` is how close the player may get to the planet before the
## craft leaves the rail and attacks.
func begin_orbit(
	anchor: Node2D,
	radius: float,
	angle: float,
	omega: float,
	alert_range: float = 0.0
) -> void:
	player_controlled = false
	ai_forward = false
	ai_seek_ship = false
	orbit_anchor = anchor
	orbit_radius = radius
	orbit_angle = angle
	orbit_omega = omega
	orbit_alert_range = alert_range
	_alerted = false
	_orbiting = true
	_bh_active_time = 0.0
	if deploy_fighters:
		_ability_timer = _next_deploy_delay()
	if anchor != null:
		global_position = anchor.global_position + Vector2.from_angle(angle) * radius
		rotation = angle + PI * 0.5 * signf(omega if omega != 0.0 else 1.0)


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

	if _orbiting:
		_handle_orbit(delta)
	elif player_controlled:
		_handle_input(delta)
	elif ai_forward or ai_seek_ship:
		_handle_ai(delta)

	if explodes_on_hit:
		_check_ship_contact()
	if black_hole_mode and not _orbiting:
		# Sandbox / free-fly: fuse runs from spawn. Orbiting craft arm in
		# _handle_orbit when the player is close enough.
		_black_hole_tick(delta, true)
	queue_redraw()


func _handle_orbit(delta: float) -> void:
	if orbit_anchor == null or not is_instance_valid(orbit_anchor):
		_orbiting = false
		return

	var player := _chase_target()
	var planet_pos: Vector2 = orbit_anchor.global_position
	if player == null and _alerted:
		# The player landed (or is gone): back onto a rail from here.
		_alerted = false
		var back: Vector2 = global_position - planet_pos
		orbit_angle = back.angle()
		orbit_radius = maxf(back.length(), orbit_radius * 0.5)
	if player != null and orbit_alert_range > 0.0:
		var d2: float = planet_pos.distance_squared_to(player.global_position)
		var alert2: float = orbit_alert_range * orbit_alert_range
		if d2 <= alert2:
			_alerted = true
		elif _alerted and d2 > alert2 * 1.45:
			# Player left: settle back onto a circular rail from here.
			_alerted = false
			var offset: Vector2 = global_position - planet_pos
			orbit_angle = offset.angle()
			orbit_radius = maxf(offset.length(), orbit_radius * 0.5)

	if _alerted:
		_orbit_attack(delta, player)
		return

	orbit_angle += orbit_omega * delta
	global_position = planet_pos + Vector2.from_angle(orbit_angle) * orbit_radius
	rotation = orbit_angle + PI * 0.5 * signf(orbit_omega if orbit_omega != 0.0 else 1.0)
	_throttle = 0.55


## Break orbit: chase the player and use guns / specials.
func _orbit_attack(delta: float, player: Node2D) -> void:
	if player == null:
		_throttle = 0.0
		return

	var desired: float = (player.global_position - global_position).angle()
	var diff: float = wrapf(desired - rotation, -PI, PI)
	rotation += clampf(diff, -turn_speed * delta, turn_speed * delta)
	_throttle = 1.0
	position += Vector2.RIGHT.rotated(rotation) * _speed_vs_player(player) * _throttle * delta

	if deploy_fighters:
		_try_deploy_fighter()
	elif lay_mines:
		_try_lay_mine()
	elif can_fire:
		_try_fire()

	if black_hole_mode:
		var in_pull: bool = (
			global_position.distance_squared_to(player.global_position)
			<= black_hole_radius * black_hole_radius
		)
		_black_hole_tick(delta, in_pull)


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

	if deploy_fighters:
		_try_deploy_fighter()
	elif Input.is_key_pressed(KEY_SPACE):
		if lay_mines:
			_try_lay_mine()
		elif can_fire:
			_try_fire()


func _handle_ai(delta: float) -> void:
	var target := _chase_target() if ai_seek_ship else null
	if target != null:
		var desired: float = (target.global_position - global_position).angle()
		var diff: float = wrapf(desired - rotation, -PI, PI)
		rotation += clampf(diff, -turn_speed * delta, turn_speed * delta)
	_throttle = 1.0
	var speed: float = _speed_vs_player(target) if target != null else move_speed
	position += Vector2.RIGHT.rotated(rotation) * speed * _throttle * delta
	if deploy_fighters:
		_try_deploy_fighter()
	elif lay_mines:
		_try_lay_mine()
	elif can_fire:
		_try_fire()


## At least `SPEED_VS_PLAYER` × the player's current speed, never below this
## craft's own move_speed (so a parked ship still gets chased at cruise).
func _speed_vs_player(player: Node2D) -> float:
	if player == null:
		return move_speed
	var velocity: Variant = player.get("velocity")
	if typeof(velocity) != TYPE_VECTOR2:
		return move_speed
	return maxf((velocity as Vector2).length() * SPEED_VS_PLAYER, move_speed)


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


func _next_deploy_delay() -> float:
	return randf_range(deploy_cooldown, maxf(deploy_cooldown, deploy_cooldown_max))


func _try_deploy_fighter() -> void:
	if fighter_scene == null or _ability_timer > 0.0 or get_parent() == null:
		return
	_ability_timer = _next_deploy_delay()
	var fighter := fighter_scene.instantiate() as Enemy
	if fighter == null:
		return
	fighter.player_controlled = false
	fighter.ai_forward = true
	fighter.ai_seek_ship = true
	EnemyCatalog.configure(fighter, "fast")
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


func _black_hole_tick(delta: float, armed: bool = true) -> void:
	if not armed:
		return
	_pull_nearby(delta)
	_bh_active_time += delta
	if _bh_active_time >= black_hole_fuse:
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
				if ship.has_method("take_damage"):
					ship.call("take_damage", amount, global_position)


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


## Called by LaserBolt / SniperBeam / DamageZone and the player's weapons
## (solar_system.gd _try_fire_fov_weapon). A kamikaze detonates at once; the
## rest go when the hits add up to max_health.
func take_hit(amount: float) -> void:
	if _exploding or amount <= 0.0:
		return
	if explodes_on_hit:
		explode()
		return
	_damage_taken += amount
	if _damage_taken >= max_health:
		explode()
	else:
		queue_redraw()


func health_fraction() -> float:
	return clampf((max_health - _damage_taken) / maxf(max_health, 1.0), 0.0, 1.0)


## At wide zoom the enemy is a fixed-size marker; its hit area follows it.
func hit_radius() -> float:
	return maxf(collision_radius, 14.0 * scale.x) if not true_scale else collision_radius


func is_alive() -> bool:
	return not _exploding


func is_hittable() -> bool:
	return explodes_on_hit and not _exploding


func explode() -> void:
	if _exploding:
		return
	_exploding = true
	_explode_age = 0.0
	_throttle = 0.0
	player_controlled = false
	_play_destroyed_sound()
	queue_redraw()


func _play_destroyed_sound() -> void:
	var tree := get_tree()
	if tree == null:
		return
	var root := tree.current_scene
	if root != null and root.has_method("play_target_destroyed_sound"):
		root.call("play_target_destroyed_sound", self)
		return
	var player := AudioStreamPlayer.new()
	player.stream = SOUND_TARGET_DESTROYED
	player.bus = &"SFX"
	player.finished.connect(player.queue_free)
	tree.root.add_child(player)
	player.play()


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
		if player_ship.has_method("take_damage"):
			player_ship.call("take_damage", contact_damage, global_position)
		explode()


## The player's ship to chase, or null while it is down on a planet - no
## enemy follows it there.
func _chase_target() -> Node2D:
	var player := _find_player_ship()
	if player != null and bool(player.get("landed")):
		return null
	return player


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
	if targeted:
		_draw_target_brackets()
	if black_hole_mode and true_scale:
		_draw_black_hole_field()

	if not true_scale:
		_draw_map_marker()
		if _throttle > 0.05:
			_draw_engine_flame(Vector2(-8, 0))
		_draw_health_bar()
		_draw_type_label()
		return

	if ship_texture == null:
		_draw_health_bar()
		return
	var draw_size := _get_draw_size()
	draw_set_transform(Vector2.ZERO, PI * 0.5, Vector2.ONE)
	draw_texture_rect(ship_texture, Rect2(-draw_size * 0.5, draw_size), false)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	if _throttle > 0.05:
		for exit in engine_exits:
			_draw_engine_flame(_image_to_local(exit, draw_size))
	_draw_health_bar()
	_draw_type_label()


## The type's short code ("MS" for a mothership...) in its marker colour,
## upright, right of the craft - a fixed size on screen.
func _draw_type_label() -> void:
	var px: float = 1.0 / maxf(get_global_transform_with_canvas().get_scale().x, 0.0001)
	var extent: float = (visual_length * 0.6) / px if true_scale else 11.0
	draw_set_transform(Vector2.ZERO, -rotation, Vector2(px, px))
	draw_string(
		HudPanelStyle.get_font(), Vector2(extent + 4.0, 4.0), EnemyCatalog.abbreviation(kind_id),
		HORIZONTAL_ALIGNMENT_LEFT, -1, 11, EnemyCatalog.marker_color(kind_id)
	)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_health_bar() -> void:
	var px: float = 1.0 / maxf(get_global_transform_with_canvas().get_scale().x, 0.0001)
	var width: float = 36.0 * px
	var height: float = 4.0 * px
	var extent: float = visual_length * 0.6 if true_scale else 14.0 * px
	var top: float = -(extent + 8.0 * px)
	var rect := Rect2(Vector2(-width * 0.5, top), Vector2(width, height))
	draw_set_transform(Vector2.ZERO, -rotation, Vector2.ONE)
	draw_rect(rect.grow(1.0 * px), Color(0.04, 0.05, 0.08, 0.85))
	draw_rect(rect, Color(0.35, 0.08, 0.08, 0.9))
	draw_rect(Rect2(rect.position, Vector2(width * health_fraction(), height)), Color(0.35, 0.9, 0.45))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## Far-zoom glyph: flat shape + colour from EnemyCatalog (not the ship art).
func _draw_map_marker() -> void:
	EnemyCatalog.draw_glyph(self, Vector2.ZERO, 11.0, kind_id, true)


## Red corner brackets round a targeted enemy, a fixed size on screen.
func _draw_target_brackets() -> void:
	var px: float = 1.0 / maxf(get_global_transform_with_canvas().get_scale().x, 0.0001)
	var r: float = maxf(visual_length * 0.8, 14.0 * px)
	var l: float = r * 0.45
	var color := Color(1.0, 0.3, 0.25, 0.95)
	draw_set_transform(Vector2.ZERO, -rotation, Vector2.ONE)
	for corner: Vector2 in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
		var c: Vector2 = corner * r
		draw_line(c, c - Vector2(corner.x * l, 0.0), color, 1.5 * px)
		draw_line(c, c - Vector2(0.0, corner.y * l), color, 1.5 * px)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _world_to_local_radius(world_r: float) -> float:
	# Node scale is 1/zoom when far out; world-sized FX must undo that.
	return world_r / maxf(scale.x, 0.0001)


func _draw_black_hole_field() -> void:
	var t: float = Time.get_ticks_msec() / 1000.0
	var fuse_left: float = maxf(0.0, black_hole_fuse - _bh_active_time)
	var urgency: float = 1.0 - clampf(fuse_left / black_hole_fuse, 0.0, 1.0)
	var pulse: float = 0.7 + 0.3 * sin(t * (4.0 + urgency * 10.0))
	var rim := Color(0.55, 0.2, 0.95, 0.2 * pulse)
	var r: float = black_hole_radius
	draw_circle(Vector2.ZERO, r, Color(0.15, 0.05, 0.28, 0.12 * pulse))
	draw_arc(Vector2.ZERO, r * pulse, 0.0, TAU, 64, rim, 2.0)
	draw_arc(Vector2.ZERO, r * 0.55, 0.0, TAU, 48, Color(0.8, 0.4, 1.0, 0.35 * pulse), 1.5)
	draw_circle(Vector2.ZERO, lerpf(8.0, visual_length * 0.6, urgency), Color(0.05, 0.0, 0.1, 0.85))


## The ship going up (ExplosionFX): fire and debris, or a violet implosion
## blast for a black hole bomb.
func _draw_explosion() -> void:
	var t: float = clampf(_explode_age / _explosion_duration, 0.0, 1.0)
	var px: float = 1.0 / maxf(get_global_transform_with_canvas().get_scale().x, 0.0001)
	# Never smaller on screen than a few pixels, so it reads zoomed out.
	var radius: float = maxf(visual_length * 1.3, 18.0 * px)
	var tint := Color(1.0, 0.45, 0.12)
	if _blast_radius > 0.0:
		radius = _world_to_local_radius(_blast_radius) * 0.6
		tint = Color(0.7, 0.35, 1.0)
	ExplosionFX.draw(self, Vector2.ZERO, t, radius, get_instance_id(), px, tint)


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

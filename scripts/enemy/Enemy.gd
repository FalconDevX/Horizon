class_name Enemy
extends Node2D
## Standalone sprite-based hostile ship for the sandbox (E menu). Not built via
## the modular ShipHull/ship.gd system - single sprite, arcade WASD movement,
## detailed red engine flame, and a Space-bar laser fire. No thrust-force /
## correction-engine physics: this flies by direct kinematic moves along a
## trajectory, not by simulating engine forces. Proper steering feel comes later.
##
## Special roles (set per scene): kamikaze ram, mothership fighter deploy,
## minelayer damage fields, black-hole attract+fuse, missile launchers.

const LASER_BOLT_SCENE := preload("res://scenes/enemies/LaserBolt.tscn")
const DAMAGE_ZONE_SCRIPT := preload("res://scripts/enemy/DamageZone.gd")
const SOUND_TARGET_DESTROYED := preload("res://sounds/target--destroyed.wav")
const SOUND_EXPLOSION := preload("res://sounds/explosion.wav")
## Ignore the parked player ship for this long after spawn (kamikaze starts on
## top of it when picked from the E menu).
const CONTACT_GRACE := 0.75
const EXPLOSION_DURATION := 1.1
const BLACK_HOLE_EXPLOSION_DURATION := 1.6
## Seconds the player must stay inside a guard's alert range before it
## leaves its rail and attacks.
const ALERT_DELAY := 5.0
## An alerted guard gives up once the player is this many times the alert
## range from the planet (squared: 1.45 = about 1.2x the range).
const GIVE_UP_RANGE2 := 1.45
## A guard that gave up flies home in at most about this many seconds, however
## far the chase took it (never slower than move_speed).
const RETURN_TIME := 6.0
## A provoked guard (hit, or the player opened fire near its planet) attacks at
## once and keeps chasing this long even with the player out of range.
const PROVOKED_CHASE := 15.0

## Shown in the player's enemy contacts panel (set from EnemyCatalog on spawn).
@export var title: String = "Enemy"
## Catalog id for the flat map/HUD glyph (shape + colour).
@export var kind_id: String = "basic"
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

## Missile launchers (the Frigate): instead of guns, a salvo of homing
## EnemyMissiles every fire_cooldown, only while the player is within
## missile_launch_range. Every launcher fires one missile a salvo,
## missile_salvo_gap apart; points sharing a group are one launcher whose
## pods take turns. Points are fractions of the nose-up art (like muzzles),
## launch directions are in the same space ((0, -1) = out of the nose).
@export var missile_mode: bool = false
@export var missile_launchers: PackedVector2Array = PackedVector2Array()
@export var missile_launch_dirs: PackedVector2Array = PackedVector2Array()
@export var missile_groups: PackedInt32Array = PackedInt32Array()
@export var missile_damage: float = 24.0
@export var missile_speed: float = 2300.0
@export var missile_turn: float = 1.6
## How far a missile flies before it bursts.
@export var missile_range: float = 22000.0
## The player must be this close for a salvo.
@export var missile_launch_range: float = 16000.0
@export var missile_salvo_gap: float = 0.35

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
## Seconds the player has been in alert range while this craft still patrols.
var _alert_time: float = 0.0
## Gave up the chase: flying back to its rail (orbit_radius round the planet).
var _returning: bool = false
## Seconds left of the chase forced by provoke().
var _provoked_left: float = 0.0
## Seconds left knocked out by an EMP missile: no moving, no guns.
var _emp_left: float = 0.0
## Launcher point indices still to fire this salvo, and the time to the next.
var _salvo: Array[int] = []
var _salvo_timer: float = 0.0
## Group -> how many salvos it has fired (picks the pod whose turn it is).
var _group_shots: Dictionary = {}
## Where it was last frame, for the velocity missiles leave with.
var _last_position := Vector2.INF
var _velocity := Vector2.ZERO


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
	_alert_time = 0.0
	_returning = false
	_provoked_left = 0.0
	_bh_active_time = 0.0
	if deploy_fighters:
		_ability_timer = _next_deploy_delay()
	if anchor != null:
		global_position = anchor.global_position + Vector2.from_angle(angle) * radius
		rotation = angle + PI * 0.5 * signf(omega if omega != 0.0 else 1.0)


## What a save keeps of this craft. The planet it guards is stored by the
## caller (by index); everything else is here.
func save_state() -> Dictionary:
	return {
		"kind": kind_id,
		"position": global_position,
		"rotation": rotation,
		"max_health": max_health,
		"damage": _damage_taken,
		"player_controlled": player_controlled,
		"ai_forward": ai_forward,
		"ai_seek_ship": ai_seek_ship,
		"orbiting": _orbiting,
		"orbit": [orbit_radius, orbit_angle, orbit_omega, orbit_alert_range],
		"alerted": _alerted,
		"returning": _returning,
		"provoked": _provoked_left,
		"emp": _emp_left,
		"bh_time": _bh_active_time,
	}


## Puts a saved craft back; `anchor` is its guarded planet, or null.
func load_state(state: Dictionary, anchor: Node2D) -> void:
	max_health = float(state.get("max_health", max_health))
	_damage_taken = float(state.get("damage", 0.0))
	player_controlled = bool(state.get("player_controlled", false))
	ai_forward = bool(state.get("ai_forward", false))
	ai_seek_ship = bool(state.get("ai_seek_ship", false))
	var orbit: Array = state.get("orbit", [0.0, 0.0, 0.0, 0.0])
	if bool(state.get("orbiting", false)) and anchor != null:
		begin_orbit(anchor, orbit[0], orbit[1], orbit[2], orbit[3])
	else:
		orbit_anchor = anchor
		orbit_radius = orbit[0]
		orbit_angle = orbit[1]
		orbit_omega = orbit[2]
		orbit_alert_range = orbit[3]
	_alerted = bool(state.get("alerted", false))
	_returning = bool(state.get("returning", false))
	_provoked_left = float(state.get("provoked", 0.0))
	_emp_left = float(state.get("emp", 0.0))
	_bh_active_time = float(state.get("bh_time", 0.0))
	if _alerted:
		_alert_time = ALERT_DELAY
	global_position = state.get("position", global_position)
	rotation = float(state.get("rotation", rotation))


func _process(delta: float) -> void:
	if _exploding:
		_explode_age += delta
		queue_redraw()
		if _explode_age >= _explosion_duration:
			queue_free()
		return

	_alive_time += delta
	if _emp_left > 0.0:
		# Dead in space: engines and guns out until the EMP wears off.
		_emp_left = maxf(_emp_left - delta, 0.0)
		_throttle = 0.0
		queue_redraw()
		return
	_fire_timer = maxf(0.0, _fire_timer - delta)
	_ability_timer = maxf(0.0, _ability_timer - delta)
	if _last_position != Vector2.INF and delta > 0.0:
		_velocity = (global_position - _last_position) / delta
	_last_position = global_position
	_advance_salvo(delta)

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
	# Null while the player is landed (or gone): nothing to chase.
	var in_range := false
	if player != null and orbit_alert_range > 0.0:
		var d2: float = planet_pos.distance_squared_to(player.global_position)
		var alert2: float = orbit_alert_range * orbit_alert_range
		in_range = d2 <= (alert2 * GIVE_UP_RANGE2 if _alerted else alert2)
	_provoked_left = maxf(_provoked_left - delta, 0.0)
	if _provoked_left > 0.0 and player != null:
		in_range = true

	if _alerted and not in_range:
		# Lost interest: fly home to the patrol rail.
		_alerted = false
		_returning = true
		_alert_time = 0.0
	elif not _alerted:
		_alert_time = _alert_time + delta if in_range else 0.0
		if _alert_time >= ALERT_DELAY:
			_alerted = true
			_returning = false

	if _alerted:
		_orbit_attack(delta, player)
		return
	if _returning:
		_return_to_rail(delta, planet_pos)
		return

	orbit_angle += orbit_omega * delta
	global_position = planet_pos + Vector2.from_angle(orbit_angle) * orbit_radius
	rotation = orbit_angle + PI * 0.5 * signf(orbit_omega if orbit_omega != 0.0 else 1.0)
	_throttle = 0.55


## Wakes this guard at once - no ALERT_DELAY - for at least PROVOKED_CHASE.
func provoke() -> void:
	if not _orbiting or _exploding:
		return
	_alerted = true
	_returning = false
	_alert_time = ALERT_DELAY
	_provoked_left = PROVOKED_CHASE


## Provokes every guard orbiting the same planet as this one.
func provoke_patrol() -> void:
	if not _orbiting or orbit_anchor == null or get_parent() == null:
		return
	for child in get_parent().get_children():
		if child is Enemy and (child as Enemy).orbit_anchor == orbit_anchor:
			(child as Enemy).provoke()


## True while the player (not landed) is inside this guard's alert range.
func player_in_alert_range() -> bool:
	if not _orbiting or orbit_anchor == null or not is_instance_valid(orbit_anchor) or orbit_alert_range <= 0.0:
		return false
	var player := _chase_target()
	if player == null:
		return false
	return orbit_anchor.global_position.distance_squared_to(player.global_position) <= orbit_alert_range * orbit_alert_range


## Seconds until this patrolling guard attacks, or -1 when it is not counting
## down (player out of range, or already attacking).
func alert_countdown() -> float:
	if not _orbiting or _alerted or _exploding or _alert_time <= 0.0:
		return -1.0
	return maxf(ALERT_DELAY - _alert_time, 0.0)


func is_attacking() -> bool:
	return _orbiting and _alerted and not _exploding


## Flies back to the point on its rail nearest to it, moving with the planet,
## and takes up the patrol there.
func _return_to_rail(delta: float, planet_pos: Vector2) -> void:
	var offset: Vector2 = global_position - planet_pos
	var home: Vector2 = offset.normalized() * orbit_radius if offset.length_squared() > 1.0 else Vector2.RIGHT * orbit_radius
	var to_home: Vector2 = home - offset
	var step: float = maxf(move_speed, to_home.length() / RETURN_TIME) * delta
	if to_home.length() <= step:
		orbit_angle = home.angle()
		global_position = planet_pos + home
		_returning = false
		_throttle = 0.55
		return
	var diff: float = wrapf(to_home.angle() - rotation, -PI, PI)
	rotation += clampf(diff, -turn_speed * delta, turn_speed * delta)
	global_position = planet_pos + offset + to_home.normalized() * step
	_throttle = 1.0


## Break orbit: chase the player and use guns / specials.
func _orbit_attack(delta: float, player: Node2D) -> void:
	if player == null:
		_throttle = 0.0
		return

	_steer_combat(delta, player)
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
		_steer_combat(delta, target)
	else:
		_throttle = 1.0
	var speed: float = _speed_vs_player(target) if target != null else move_speed
	position += Vector2.RIGHT.rotated(rotation) * speed * _throttle * delta
	if deploy_fighters:
		_try_deploy_fighter()
	elif lay_mines:
		_try_lay_mine()
	elif can_fire:
		_try_fire()


## Face the player. Kamikaze charge in; everyone else holds at half weapon range.
func _steer_combat(delta: float, player: Node2D) -> void:
	var to_player: Vector2 = player.global_position - global_position
	var desired: float = to_player.angle()
	var diff: float = wrapf(desired - rotation, -PI, PI)
	rotation += clampf(diff, -turn_speed * delta, turn_speed * delta)
	if explodes_on_hit:
		_throttle = 1.0
		return
	var hold: float = laser_range * 0.5
	var dist: float = to_player.length()
	if dist > hold * 1.08:
		_throttle = 1.0
	elif dist < hold * 0.92:
		_throttle = -0.7
	else:
		_throttle = 0.0


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
	if missile_mode:
		_try_missile_salvo()
		return
	# AI only shoots when the player is inside weapon reach.
	if not player_controlled:
		var target := _chase_target()
		if target == null:
			return
		var reach2: float = laser_range * laser_range
		if global_position.distance_squared_to(target.global_position) > reach2:
			return
	_fire_timer = fire_cooldown
	fire_laser()


## A salvo when the player is in reach: one launch per launcher (group),
## the pods of a group taking turns.
func _try_missile_salvo() -> void:
	var player := _chase_target()
	if player == null or not _salvo.is_empty():
		return
	if global_position.distance_to(player.global_position) > missile_launch_range:
		return
	_fire_timer = fire_cooldown
	var pods: Dictionary = {}
	for i in missile_launchers.size():
		var group: int = missile_groups[i] if i < missile_groups.size() else i
		if not pods.has(group):
			pods[group] = []
		(pods[group] as Array).append(i)
	var groups: Array = pods.keys()
	groups.sort()
	for group: int in groups:
		var members: Array = pods[group]
		var shot: int = int(_group_shots.get(group, 0))
		_group_shots[group] = shot + 1
		_salvo.append(int(members[shot % members.size()]))
	_salvo_timer = 0.0


func _advance_salvo(delta: float) -> void:
	if _salvo.is_empty():
		return
	_salvo_timer -= delta
	if _salvo_timer > 0.0:
		return
	_salvo_timer = missile_salvo_gap
	_launch_missile(_salvo.pop_front())


func _launch_missile(index: int) -> void:
	if get_parent() == null or index < 0 or index >= missile_launchers.size():
		return
	var draw_size := _get_draw_size()
	var pod: Vector2 = global_position + _image_to_local(missile_launchers[index], draw_size).rotated(rotation)
	var image_dir: Vector2 = missile_launch_dirs[index] if index < missile_launch_dirs.size() else Vector2(0.0, -1.0)
	var missile := EnemyMissile.new()
	missile.damage = missile_damage
	missile.speed = missile_speed
	missile.turn = missile_turn
	missile.max_distance = missile_range
	missile.ignore_enemy = self
	get_parent().add_child(missile)
	missile.global_position = pod
	missile.launch(image_dir.rotated(PI * 0.5).rotated(rotation), _velocity)
	_play_laser_sound()


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
	provoke_patrol()
	if explodes_on_hit:
		explode()
		return
	_damage_taken += amount
	if _damage_taken >= max_health:
		explode()
	else:
		queue_redraw()


## An EMP hit: no moving, no firing, no abilities for `seconds` (a longer
## one already running is kept).
func disable_for(seconds: float) -> void:
	if _exploding:
		return
	provoke_patrol()
	_emp_left = maxf(_emp_left, seconds)
	queue_redraw()


func is_disabled() -> bool:
	return _emp_left > 0.0


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
	player.stream = SOUND_EXPLOSION
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


## The square the craft occupies: muzzles, pods and engine exits are fractions of it.
func _get_draw_size() -> Vector2:
	return Vector2(visual_length, visual_length)


func _draw() -> void:
	if _exploding:
		_draw_explosion()
		return
	if targeted:
		_draw_target_brackets()
	if _emp_left > 0.0:
		_draw_emp_crackle()
	if black_hole_mode and true_scale:
		_draw_black_hole_field()

	if not true_scale:
		_draw_map_marker()
		if _throttle > 0.05:
			_draw_engine_flame(Vector2(-8, 0))
		_draw_health_bar()
		_draw_type_label()
		return

	# Up close the same glyph as on the map, grown to the craft's size.
	var draw_size := _get_draw_size()
	EnemyCatalog.draw_glyph(self, Vector2.ZERO, visual_length * 0.5, kind_id, true)

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


## Knocked out by an EMP: blue sparks jumping round the hull.
func _draw_emp_crackle() -> void:
	var px: float = 1.0 / maxf(get_global_transform_with_canvas().get_scale().x, 0.0001)
	var r: float = maxf(visual_length * 0.7, 12.0 * px)
	var t: float = Time.get_ticks_msec() / 1000.0
	var colour := Color(0.55, 0.65, 1.0, 0.55 + 0.35 * sin(t * 23.0))
	draw_arc(Vector2.ZERO, r, 0.0, TAU, 32, Color(colour, 0.3), 1.2 * px, true)
	for k in 5:
		var a: float = t * 3.0 + k * 1.37 + sin(t * 11.0 + k) * 0.6
		var from: Vector2 = Vector2.from_angle(a) * r
		var mid: Vector2 = Vector2.from_angle(a + 0.25) * r * 0.75
		var to: Vector2 = Vector2.from_angle(a + 0.45) * r * 1.05
		draw_polyline(PackedVector2Array([from, mid, to]), colour, 1.4 * px, true)


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

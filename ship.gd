extends Node2D

signal ship_clicked

@export var ship_mass: float = 10.0
@export var thrust_force: float = 3000.0
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

## Energy the ship's parts draw, split by when they draw it (ShipStats):
## engines while thrusting, shields while recharging, weapons per shot; the
## rest (radars, utilities, cockpit) all the time.
var energy_engines: float = 0.0
var energy_shields: float = 0.0
var energy_weapons: float = 0.0
## Hull points repaired per second by repair modules (while powered).
var repair_rate: float = 0.0
var max_hull_hp: float = 0.0

## Live resources, 0..their maxima from the modules (apply_module_stats).
## Only a ship built in the yard has them: the stock ship with no modules
## (`resources_enabled` false) flies with no limits, as it always did.
var resources_enabled := false
var fuel: float = 0.0
var energy: float = 0.0
var shield: float = 0.0
var hull_hp: float = 0.0
## Warp drive fuel (solar_system.gd Q), every ship - the stock one included.
## Burned per unit of distance flown in warp, refilled on a planet's surface.
var warp_fuel: float = WARP_FUEL_CAPACITY
## Whether the ship has power: stored energy, or (with no batteries) as much
## generated as is drawn. Unpowered, radars go dark, weapons cannot fire and
## shields and repairs stop - the engines still run, so the ship is never stuck.
var powered := true
## Seconds since the last hit; shields start recharging after SHIELD_REGEN_DELAY.
var _since_hit: float = 999.0
## instance_id -> seconds left before that weapon can fire again.
var _weapon_cooldowns: Dictionary = {}

## The weapon picked in the weapons panel (instance id, -1 for none): LMB
## fires it, and RMB turns it toward the cursor if it sits on a turret.
var selected_weapon: int = -1
## Weapon instance ids in the order the weapons panel lists them (the player
## drags rows to reorder); keys 1-9 pick by this order.
var weapon_order: Array[int] = []
## instance_id -> how far a turret is turned off the way it was placed
## (radians, within half its arc).
var turret_aim: Dictionary = {}
## Radians per second a turret turns.
const TURRET_TURN_SPEED := 3.0


## Fuel burned per second at full throttle, per unit of the engines' rated
## consumption (an S chemical engine empties an S tank in about a minute and a half).
const FUEL_PER_SECOND := 0.2
## Shields recharge this share of their maximum per second, this long after a hit.
const SHIELD_REGEN_FRACTION := 0.08
const SHIELD_REGEN_DELAY := 3.0
## Energy one shot costs, per unit of that weapon's rated energy use.
const SHOT_ENERGY := 0.5
## Share of the tanks refilled (and batteries recharged) per second on a
## planet's surface.
const GROUND_REFILL_FRACTION := 0.15
const WARP_FUEL_CAPACITY := 100.0
## Warp distance a full tank covers: Taurvane is ~5.6M out, so a couple of
## long hops (or many short ones) before landing to refuel.
const WARP_RANGE := 12000000.0

## Fallback when the shipyard has no modules yet (keeps the default orbital ship flyable).
const DEFAULT_SHIP_MASS := 10.0
const DEFAULT_THRUST_FORCE := 3000.0
const MIN_SHIP_MASS := 1.0

## Main engine output relative to the modules' rated thrust. With no time
## warp the ship has to cover real distances in real time: the starter ship
## (~40 thrust, ~60 mass) pulls ~300 units/s^2 and reaches CRUISE_SPEED_LIMIT
## in about 7 s - far above any planet's pull (a few tens at most).
const MAIN_ENGINE_BOOST := 450.0
## Turning speed relative to rotation_speed.
const TURN_RATE_SCALE := 1.1
## The engines stop pushing forward past this speed relative to the SOI body
## (units/s). Gravity may still carry the ship faster; the warp drive
## (solar_system.gd) is the way to go further, faster.
const CRUISE_SPEED_LIMIT := 2000.0

## Holding Shift scales manual thrust and turning down to this, for fine
## orbit corrections.
const PRECISION_SCALE := 0.2

## Flight assist (V): arcade "space fighter" handling, done with thrust.
## Vectored thrust always cancels sideways drift (relative to the SOI body),
## so the ship flies where the nose points, W or not; W pushes along the
## nose; with the engine off it slowly bleeds speed (ASSIST_COAST_DRAG); S
## brakes to a stop. Coasting, all that only runs while the player is flying
## (a flight key within ASSIST_IDLE_TIME) - left alone, the ship coasts under
## gravity and keeps its orbit.
## Most sideways push the assist may use, units/s^2. Holding a turn at speed
## v and turn rate w takes v * w (2000 units/s at 3 rad/s is ~6000).
const ASSIST_MAX_ACCEL := 9000.0
## Share of its speed an unpowered assisted ship loses per second.
const ASSIST_COAST_DRAG := 0.35
## Seconds after the last flight key the coasting assist lets go.
const ASSIST_IDLE_TIME := 3.0
## Most braking push (S) - from CRUISE_SPEED_LIMIT to a stop in ~1.5 s.
const ASSIST_BRAKE_ACCEL := 1500.0
## How quickly sideways drift (and, braking, speed) is cancelled, per second.
const ASSIST_RESPONSE := 10.0
## How quickly sideways drift is cancelled in a turn, per second - lower
## than ASSIST_RESPONSE so the ship slides a little through its turns.
const ASSIST_TURN_RESPONSE := 3.5

## Attitude hold (SAS): keeps the nose on a direction set by the flight path.
enum AttitudeHold { NONE, PROGRADE, RETROGRADE }

## FOV devices synced from the shipyard (weapons + radars).
var fov_devices: Array[Dictionary] = []
var show_fov_cones := true

var velocity := Vector2.ZERO
var throttle := 0.0
var throttle_locked := false
var attitude_hold: AttitudeHold = AttitudeHold.NONE
var flight_assist := true
## Seconds since the player last pressed a flight key (update_rotation).
var _since_flight_input: float = 999.0
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

const LASER_SOUND := preload("res://sounds/laser.wav")
var _laser_player: AudioStreamPlayer
## The Sniper Laser (ModuleCatalog) fires a long yellow beam out to its full
## reach, like the enemy sniper's (SniperBeam, spawned by solar_system.gd).
const SNIPER_ID := &"weapon_sniper"
const SNIPER_GLOW_COLOR := Color(1.0, 0.78, 0.12)
const SNIPER_CORE_COLOR := Color(1.0, 0.97, 0.75)
var _sniper_player: AudioStreamPlayer

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

	# Same sample, pitched down: a heavier crack for the sniper.
	_sniper_player = AudioStreamPlayer.new()
	_sniper_player.name = "SniperSound"
	_sniper_player.stream = LASER_SOUND
	_sniper_player.bus = &"SFX"
	_sniper_player.pitch_scale = 0.55
	_sniper_player.max_polyphony = 2
	add_child(_sniper_player)


## Applies aggregated ShipHull / ShipStats totals to flight parameters.
## Empty builds restore scene defaults so the orbital ship stays usable.
func apply_module_stats(stats: Dictionary) -> void:
	var module_count: int = int(stats.get("module_count", 0))
	# The share of each resource left over, so a changed layout keeps it
	# (a brand-new ship starts full).
	var was_enabled: bool = resources_enabled
	var fuel_share: float = fuel / fuel_capacity if fuel_capacity > 0.0 else 1.0
	var energy_share: float = energy / energy_capacity if energy_capacity > 0.0 else 1.0
	var shield_share: float = shield / shield_strength if shield_strength > 0.0 else 1.0
	var hull_share: float = hull_hp / max_hull_hp if max_hull_hp > 0.0 else 1.0
	if module_count <= 0:
		ship_mass = DEFAULT_SHIP_MASS
		thrust_force = DEFAULT_THRUST_FORCE
		fuel_consumption = 0.0
		fuel_capacity = 0.0
		energy_consumption = 0.0
		energy_generation = 0.0
		energy_capacity = 0.0
		shield_strength = 0.0
		energy_engines = 0.0
		energy_shields = 0.0
		energy_weapons = 0.0
		repair_rate = 0.0
		max_hull_hp = 0.0
		resources_enabled = false
		powered = true
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
	energy_engines = maxf(float(stats.get("energy_engines", 0.0)), 0.0)
	energy_shields = maxf(float(stats.get("energy_shields", 0.0)), 0.0)
	energy_weapons = maxf(float(stats.get("energy_weapons", 0.0)), 0.0)
	repair_rate = maxf(float(stats.get("repair_rate", 0.0)), 0.0)
	max_hull_hp = maxf(float(stats.get("health", 0.0)), 1.0)
	if not was_enabled:
		fuel_share = 1.0
		energy_share = 1.0
		shield_share = 1.0
		hull_share = 1.0
	resources_enabled = true
	fuel = fuel_capacity * fuel_share
	energy = energy_capacity * energy_share
	shield = shield_strength * shield_share
	hull_hp = max_hull_hp * hull_share


## Everything back to full (a respawn, or a fresh start).
func refill() -> void:
	warp_fuel = WARP_FUEL_CAPACITY
	fuel = fuel_capacity
	energy = energy_capacity
	shield = shield_strength
	hull_hp = max_hull_hp
	_since_hit = 999.0
	_weapon_cooldowns.clear()


## Whether the engines can burn: always for the stock ship, else while there is fuel.
func has_fuel() -> bool:
	return not resources_enabled or fuel > 0.0 or PlayerProgress.god_mode


func has_warp_fuel_for(distance: float) -> bool:
	return PlayerProgress.god_mode or warp_fuel >= distance * WARP_FUEL_CAPACITY / WARP_RANGE


## Burns the warp fuel a jump of `distance` takes.
func burn_warp_fuel(distance: float) -> void:
	if not PlayerProgress.god_mode:
		warp_fuel = maxf(warp_fuel - distance * WARP_FUEL_CAPACITY / WARP_RANGE, 0.0)


## One step of the ship's systems: fuel burned by the engines, energy made
## and drawn, shields recharging, repairs, weapons reloading. `engine_output`
## is the main engine's share of full power right now; `landed` refills.
func update_resources(dt: float, engine_output: float, landed: bool) -> void:
	for id: int in _weapon_cooldowns.keys():
		_weapon_cooldowns[id] = float(_weapon_cooldowns[id]) - dt
		if float(_weapon_cooldowns[id]) <= 0.0:
			_weapon_cooldowns.erase(id)
	if landed:
		warp_fuel = minf(warp_fuel + WARP_FUEL_CAPACITY * GROUND_REFILL_FRACTION * dt, WARP_FUEL_CAPACITY)
	if not resources_enabled:
		powered = true
		return
	if PlayerProgress.god_mode:
		refill()
		powered = true
		return
	_since_hit += dt

	fuel = maxf(fuel - fuel_consumption * FUEL_PER_SECOND * engine_output * dt, 0.0)

	var recharging: bool = shield < shield_strength and _since_hit >= SHIELD_REGEN_DELAY
	var idle: float = maxf(energy_consumption - energy_engines - energy_shields - energy_weapons, 0.0)
	var draw: float = idle + energy_engines * engine_output + (energy_shields if recharging else 0.0)
	var net: float = energy_generation - draw
	if energy_capacity > 0.0:
		energy = clampf(energy + net * dt, 0.0, energy_capacity)
		powered = energy > 0.0 or net >= 0.0
	else:
		powered = net >= 0.0

	if landed:
		fuel = minf(fuel + fuel_capacity * GROUND_REFILL_FRACTION * dt, fuel_capacity)
		energy = minf(energy + energy_capacity * GROUND_REFILL_FRACTION * dt, energy_capacity)
		powered = true

	if powered and recharging:
		shield = minf(shield + shield_strength * SHIELD_REGEN_FRACTION * dt, shield_strength)
	if powered and repair_rate > 0.0:
		hull_hp = minf(hull_hp + repair_rate * dt, max_hull_hp)


## A hit: shields soak it up first, the hull takes the rest. Returns true if
## that destroyed the ship (solar_system.gd respawns it).
func take_damage(amount: float) -> bool:
	if not resources_enabled or amount <= 0.0 or PlayerProgress.god_mode:
		return false
	_since_hit = 0.0
	var soaked: float = minf(shield, amount)
	shield -= soaked
	hull_hp = maxf(hull_hp - (amount - soaked), 0.0)
	return hull_hp <= 0.0


func is_destroyed() -> bool:
	return resources_enabled and hull_hp <= 0.0

func apply_fov_devices(devices: Array) -> void:
	fov_devices.clear()
	_dead_zones.clear()
	for item in devices:
		if typeof(item) != TYPE_DICTIONARY:
			continue
		fov_devices.append((item as Dictionary).duplicate(true))
	queue_redraw()


## Where a device looks from, in ship-local units: a turret from its middle
## (it turns about it), anything else from the muzzle edge.
func device_local_origin(device: Dictionary) -> Vector2:
	if float(device.get("turret_arc", 0.0)) > 0.0:
		return device.get("center", Vector2.ZERO)
	return device.get("local_origin", Vector2.ZERO)


## The way a device points in ship-local space, turret turn included.
func device_local_facing(device: Dictionary) -> Vector2:
	var local_facing: Vector2 = device.get("local_facing", Vector2.RIGHT)
	return local_facing.rotated(float(turret_aim.get(int(device.get("instance_id", -1)), 0.0)))


func device_world_origin(device: Dictionary) -> Vector2:
	return global_position + device_local_origin(device).rotated(rotation)


func device_world_facing(device: Dictionary) -> Vector2:
	return device_local_facing(device).rotated(rotation)


## The mounted weapons in panel order: weapon_order first, any new ones after.
func ordered_weapons() -> Array[Dictionary]:
	var weapons: Array[Dictionary] = []
	for device: Dictionary in fov_devices:
		if str(device.get("kind", "")) == "weapon":
			weapons.append(device)
	weapons.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var ia: int = weapon_order.find(int(a.get("instance_id", -1)))
		var ib: int = weapon_order.find(int(b.get("instance_id", -1)))
		if ia < 0:
			ia = 1 << 20
		if ib < 0:
			ib = 1 << 20
		return ia < ib
	)
	return weapons


## Dead zones: for each weapon (instance id), which directions across its
## turret arc - or, fixed, its cone - would put the ship in its line of fire,
## sampled every DEAD_ZONE_STEP: {half, blocked: PackedByteArray}. Worked out
## once per layout (apply_fov_devices clears it) and drawn red over the cones.
var _dead_zones: Dictionary = {}
const DEAD_ZONE_STEP := 0.035
const DEAD_ZONE_FILL := Color(1.0, 0.2, 0.18, 0.13)
const DEAD_ZONE_LINE := Color(1.0, 0.3, 0.25, 0.55)

## How far out a shot's path is checked against the ship's own structure.
const LINE_OF_FIRE_CHECK := 90.0
const LINE_OF_FIRE_STEP := 0.3


## True if the ship's own hull, cockpit or connectors stand in the way of
## `device` firing along `direction` (ship-local) - a gun never shoots
## through its own ship. Truss is an open frame and never blocks; the gun's
## own cells are skipped.
func is_shot_blocked(device: Dictionary, direction: Vector2) -> bool:
	if direction.length_squared() < 1e-8:
		return false
	var dir: Vector2 = direction.normalized()
	var from: Vector2 = device_local_origin(device)
	var rects: Array = device.get("hull_rects", [])
	var own: Array = device.get("ignore_rects", [])
	var t: float = 0.0
	while t < LINE_OF_FIRE_CHECK:
		var point: Vector2 = from + dir * t
		if not own.any(func(r: Rect2) -> bool: return r.has_point(point)):
			if rects.any(func(r: Rect2) -> bool: return r.has_point(point)):
				return true
		t += LINE_OF_FIRE_STEP
	return false


func _dead_zone(device: Dictionary) -> Dictionary:
	var id: int = int(device.get("instance_id", -1))
	if _dead_zones.has(id):
		return _dead_zones[id]
	var arc: float = float(device.get("turret_arc", 0.0))
	var span: float = deg_to_rad(arc if arc > 0.0 else float(device.get("angle_deg", 0.0)))
	var half: float = span * 0.5
	var base: Vector2 = device.get("local_facing", Vector2.RIGHT)
	var count: int = int(ceil(span / DEAD_ZONE_STEP)) + 1
	var blocked := PackedByteArray()
	blocked.resize(count)
	for i in count:
		var offset: float = minf(-half + i * DEAD_ZONE_STEP, half)
		blocked[i] = 1 if is_shot_blocked(device, base.rotated(offset)) else 0
	var zone := {"half": half, "blocked": blocked}
	_dead_zones[id] = zone
	return zone


## Red wedges over the directions between `from` and `to` (turn off the
## placed facing, radians) where the gun would fire into its own ship.
func _draw_dead_zone(device: Dictionary, from: float, to: float, origin: Vector2, reach: float, line_px: float) -> void:
	var zone: Dictionary = _dead_zone(device)
	var blocked: PackedByteArray = zone["blocked"]
	var half: float = zone["half"]
	var base: Vector2 = device.get("local_facing", Vector2.RIGHT)
	var run: PackedVector2Array = PackedVector2Array()
	for i in blocked.size():
		var offset: float = minf(-half + i * DEAD_ZONE_STEP, half)
		var inside: bool = offset >= from - 1e-4 and offset <= to + 1e-4
		if inside and blocked[i] == 1:
			run.append(origin + base.rotated(offset) * reach)
			continue
		_flush_dead_run(run, origin, line_px)
		run = PackedVector2Array()
	_flush_dead_run(run, origin, line_px)


func _flush_dead_run(run: PackedVector2Array, origin: Vector2, line_px: float) -> void:
	if run.size() < 2:
		return
	var wedge := PackedVector2Array([origin])
	wedge.append_array(run)
	draw_colored_polygon(wedge, DEAD_ZONE_FILL)
	draw_line(origin, run[0], DEAD_ZONE_LINE, line_px, true)
	draw_line(origin, run[run.size() - 1], DEAD_ZONE_LINE, line_px, true)


func selected_device() -> Dictionary:
	for device: Dictionary in fov_devices:
		if int(device.get("instance_id", -1)) == selected_weapon:
			return device
	return {}


## Turns the selected turret toward `world_pos`, as far as its arc allows.
func aim_selected(world_pos: Vector2, dt: float) -> void:
	aim_device(selected_device(), world_pos, dt)


## Turns `device` (a turret) toward `world_pos`, as far as its arc allows.
func aim_device(device: Dictionary, world_pos: Vector2, dt: float) -> void:
	var arc: float = float(device.get("turret_arc", 0.0))
	if device.is_empty() or arc <= 0.0:
		return
	var id: int = int(device["instance_id"])
	var base: float = (device.get("local_facing", Vector2.RIGHT) as Vector2).angle()
	var wanted: float = (to_local(world_pos) - device_local_origin(device)).angle()
	var half: float = deg_to_rad(arc) * 0.5
	var target: float = clampf(wrapf(wanted - base, -PI, PI), -half, half)
	turret_aim[id] = move_toward(float(turret_aim.get(id, 0.0)), target, TURRET_TURN_SPEED * dt)
	queue_redraw()


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


## Fires every loaded weapon whose cone holds `world_pos`, if there is the
## power for it; each shot costs energy and starts that weapon's reload.
## Returns the devices that fired (their `damage` is what the target takes).
func fire_weapons_at(world_pos: Vector2, only_id: int = -1) -> Array[Dictionary]:
	var shots: Array[Dictionary] = []
	if resources_enabled and not powered and not PlayerProgress.god_mode:
		return shots
	var best_range := INF
	var fired := false
	var sniper_fired := false
	for device in fov_devices:
		if str(device.get("kind", "")) != "weapon":
			continue
		if not is_body_in_device_fov(device, world_pos):
			continue
		var id: int = int(device.get("instance_id", -1))
		if only_id >= 0 and id != only_id:
			continue
		if _weapon_cooldowns.has(id):
			continue
		# Holds fire (costing nothing) while its own ship is in the way.
		if is_shot_blocked(device, to_local(world_pos) - device_local_origin(device)):
			continue
		var cost: float = float(device.get("energy", 0.0)) * SHOT_ENERGY
		if resources_enabled and energy_capacity > 0.0 and not PlayerProgress.god_mode:
			if energy < cost:
				continue
			energy -= cost
		_weapon_cooldowns[id] = maxf(float(device.get("reload_time", 0.0)), 0.05)
		shots.append(device)
		if device.get("id", &"") == SNIPER_ID:
			# Its long beam is spawned by solar_system.gd (SniperBeam).
			sniper_fired = true
			continue
		# The projectiles themselves are spawned by solar_system.gd (PlayerShot).
		fired = true
	if fired:
		_laser_player.play()
	if sniper_fired:
		_sniper_player.play()
	return shots


func _on_click_area_input_event(
	_viewport: Node,
	event: InputEvent,
	_shape_idx: int
) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			ship_clicked.emit()


## Manual attitude: A / D (or the arrows) turn, which cancels an attitude
## hold. (RMB aims the selected turret instead - solar_system.gd.) With neither, an
## active hold (Z prograde / C retrograde) steers the nose along the flight path.
func update_rotation(delta: float) -> void:
	var turn_rate: float = get_turn_rate() * precision_scale()
	var flying: bool = (
		Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_D)
		or Input.is_key_pressed(KEY_LEFT) or Input.is_key_pressed(KEY_RIGHT)
	)
	_since_flight_input = 0.0 if flying else _since_flight_input + delta

	var turn: float = 0.0
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
		turn -= 1.0
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		turn += 1.0
	if turn != 0.0:
		attitude_hold = AttitudeHold.NONE
		rotation = wrapf(rotation + turn * turn_rate * delta, -PI, PI)
		return

	if attitude_hold != AttitudeHold.NONE and hold_reference_velocity.length_squared() > 1e-6:
		var target: float = hold_reference_velocity.angle()
		if attitude_hold == AttitudeHold.RETROGRADE:
			target += PI
		rotation = rotate_toward(rotation, target, turn_rate * delta)


## Z / C: hold prograde / retrograde; pressing the active one again releases it.
func toggle_attitude_hold(mode: AttitudeHold) -> void:
	attitude_hold = AttitudeHold.NONE if attitude_hold == mode else mode


## Radians per second the ship turns at.
func get_turn_rate() -> float:
	return rotation_speed * TURN_RATE_SCALE


## 1, or PRECISION_SCALE while Shift is held.
func precision_scale() -> float:
	return PRECISION_SCALE if Input.is_key_pressed(KEY_SHIFT) else 1.0


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

	# S cuts the engine at once; W spools it up.
	if Input.is_key_pressed(KEY_S):
		throttle = 0.0
		return
	var target := 1.0 if Input.is_key_pressed(KEY_W) else 0.0
	throttle = move_toward(throttle, target, delta / throttle_ramp_time)


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
		var brake_cap: float = ASSIST_BRAKE_ACCEL * precision_scale()
		var brake: Vector2 = (-velocity_rel * ASSIST_RESPONSE).limit_length(brake_cap)
		assist_brake_output = brake.length() / brake_cap
		return brake

	assist_brake_output = 0.0
	# A vectored sideways push that cancels drift, so the velocity swings
	# round with the nose...
	var forward := Vector2.RIGHT.rotated(rotation)
	var side: Vector2 = forward.orthogonal()
	var drift: float = velocity_rel.dot(side)
	var lateral: float = clampf(-drift * ASSIST_TURN_RESPONSE, -assist_cap, assist_cap)
	if throttle <= 0.0:
		if _since_flight_input > ASSIST_IDLE_TIME:
			# Left alone: coast on the orbit.
			return Vector2.ZERO
		# ...and with the engine off, a slow bleed of forward speed.
		return side * lateral - forward * velocity_rel.dot(forward) * ASSIST_COAST_DRAG
	return get_thrust_acceleration() + side * lateral


func toggle_flight_assist() -> void:
	flight_assist = not flight_assist


func get_thrust_acceleration() -> Vector2:
	if throttle <= 0.0 or not has_fuel():
		return Vector2.ZERO

	var direction := Vector2.RIGHT.rotated(rotation)
	var acceleration: float = thrust_force * throttle * precision_scale() / ship_mass
	# Fades out over the last 5% below the speed limit, so the ship settles on
	# it instead of stuttering across it.
	var forward_speed: float = hold_reference_velocity.dot(direction)
	acceleration *= clampf((CRUISE_SPEED_LIMIT - forward_speed) / (CRUISE_SPEED_LIMIT * 0.05), 0.0, 1.0)

	return direction * acceleration


func _process(delta: float) -> void:
	queue_redraw()
	_update_main_engine_sound(delta)


## The throttle, or the assist's braking, whichever is higher. Fades in and
## out rather than cutting, and falls silent on pause.
func _update_main_engine_sound(delta: float) -> void:
	var level: float = 0.0
	if not paused:
		level = clampf(maxf(throttle, assist_brake_output), 0.0, 1.0)
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

## The ship as built in the yard (ShipRender.compose): its picture, where it
## goes in local space, and the main engines' aft points. Empty for the stock
## ship, which keeps SHIP_TEXTURE.
var built_visual: Dictionary = {}


func set_built_visual(visual: Dictionary) -> void:
	built_visual = visual
	queue_redraw()

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

	var engine_points: Array[Vector2] = []
	if true_scale and not built_visual.is_empty():
		# Nose to +x like the ship itself, so no turn: the modules sit where
		# the weapon and radar cones start from.
		draw_texture_rect(built_visual["texture"], built_visual["rect"], false)
		engine_points = built_visual["engines"]
		_draw_turrets()
	elif true_scale:
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
		if engine_points.is_empty():
			_draw_engine_flame(engine_pos)
		else:
			for point: Vector2 in engine_points:
				_draw_engine_flame(point)

	# RMB aims the selected turret: a faint line from it to the cursor.
	if Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT) and not selected_device().is_empty():
		var from: Vector2 = device_local_origin(selected_device())
		draw_line(from, to_local(get_global_mouse_position()), Color(1.0, 1.0, 1.0, 0.3), 1.0)


func _draw_fov_cones() -> void:
	if not show_fov_cones or fov_devices.is_empty():
		return
	# Ship visual scale (screen-space sizing) must not stretch world-SU cones.
	var inv_scale := 1.0 / maxf(scale.x, 0.0001)
	# Outlines a steady 1.2 screen pixels at any zoom, so they stay crisp.
	var line_px: float = 1.2 / maxf(get_global_transform_with_canvas().get_scale().x, 0.0001)
	for device in fov_devices:
		# Radars sweep all round (CombatControl draws their scans), no cone.
		if str(device.get("kind", "")) == "radar":
			continue
		var local_origin: Vector2 = device_local_origin(device) * inv_scale
		var local_facing: Vector2 = device_local_facing(device)
		var angle_deg := float(device.get("angle_deg", 0.0))
		var range_su := float(device.get("range", 0.0)) * inv_scale
		var is_weapon := str(device.get("kind", "")) == "weapon"
		# Weapons grey (the selected one brighter), radars cyan.
		var picked: bool = is_weapon and int(device.get("instance_id", -1)) == selected_weapon
		var fill := (
			Color(0.8, 0.83, 0.88, 0.1 if picked else 0.05) if is_weapon
			else Color(0.25, 0.75, 0.85, 0.07)
		)
		var outline := (
			Color(0.85, 0.88, 0.92, 0.55 if picked else 0.25) if is_weapon
			else Color(0.45, 0.9, 1.0, 0.3)
		)
		var hull_rects: Array = _scale_rects(device.get("hull_rects", []), inv_scale)
		var ignore_rects: Array = _scale_rects(device.get("ignore_rects", []), inv_scale)
		# A selected turret also shows how far it can turn, faintly, with the
		# part where it would fire into its own ship in red.
		var turret_arc: float = float(device.get("turret_arc", 0.0))
		if picked and turret_arc > 0.0:
			FovUtil.draw_cone_rects(
				self, local_origin, device.get("local_facing", Vector2.RIGHT), turret_arc, range_su,
				Color(0.8, 0.83, 0.88, 0.03), Color(0.85, 0.88, 0.92, 0.18), line_px, hull_rects, ignore_rects
			)
			var half_arc: float = deg_to_rad(turret_arc) * 0.5
			_draw_dead_zone(device, -half_arc, half_arc, local_origin, range_su, line_px)
		elif is_weapon:
			# The cone it fires in now: red where the ship is in the way.
			var aim_off: float = float(turret_aim.get(int(device.get("instance_id", -1)), 0.0))
			var half_cone: float = deg_to_rad(angle_deg) * 0.5
			_draw_dead_zone(device, aim_off - half_cone, aim_off + half_cone, local_origin, range_su, line_px)
		FovUtil.draw_cone_rects(
			self,
			local_origin,
			local_facing,
			angle_deg,
			range_su,
			fill,
			outline,
			line_px,
			hull_rects,
			ignore_rects
		)


## Turret guns over the hull, each turned by its aim; the selected one ringed.
func _draw_turrets() -> void:
	for turret: Dictionary in built_visual.get("turrets", []):
		var id: int = int(turret["id"])
		var size_local: Vector2 = turret["size"]
		draw_set_transform(turret["center"], float(turret_aim.get(id, 0.0)), Vector2.ONE)
		draw_texture_rect(turret["texture"], Rect2(-size_local * 0.5, size_local), false)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		if id == selected_weapon:
			draw_arc(turret["center"], size_local.length() * 0.55, 0.0, TAU, 32, Color(0.85, 0.9, 1.0, 0.8), 0.25)


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

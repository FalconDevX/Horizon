class_name CombatControl
extends Node2D
## The ship's combat control: what it knows about enemies, what it has locked
## and which guns fire on their own. solar_system.gd owns one (a child, drawn
## in the world) and calls update() every frame the game runs; the contacts
## and weapons panels read its state.
##
## Detection. Enemies within PASSIVE_RANGE (at least the longest gun's reach)
## are seen all the time; beyond that only a radar scan finds them. A scan is
## fired by hand (weapons panel, or R): the radar's green beam turns round the
## ship SWEEP_TURN_TIME per turn for the radar's scan_time, marking every enemy
## it passes within its range - unless a planet or the sun is in the way -
## then the radar recharges for its reload_time. A contact only the passive
## sensors saw is kept (and tracked) for CONTACT_HOLD seconds; one a radar
## sweep has found stays on the list (tracked) until it dies.
##
## Locks. Ctrl+click a contact a radar sweep has found, within the radar's
## reach: the lock builds over LOCK_TIME, then holds until the contact dies,
## leaves the radar's reach, or is Ctrl+clicked again. Any number of contacts
## can be locked at once; the picked one (`target`) is the active lock.
## Enemies only the passive sensors see cannot be locked.
##
## Active modules. Every gun works on one lock at a time. Clicking a gun in
## the module rack (EVE-style) switches it on at the active lock; clicking a
## gun already on another lock moves it to the active one, clicking it again
## switches it off. An active gun turns onto its lock and fires every time it
## has reloaded and the lock is in its cone. A gun switched on with nothing
## locked (or whose lock was lost) waits and takes the active lock once there
## is one. Guns on a target that is destroyed switch off. Guns that are off
## turn onto the active lock.

const PASSIVE_RANGE_MIN := 8000.0
const CONTACT_HOLD := 30.0
const LOCK_TIME := 1.5
const SWEEP_TURN_TIME := 1.2
const SWEEP_COLOR := Color(0.3, 1.0, 0.45)
## How far behind the beam its fading trail reaches, radians.
const SWEEP_TRAIL := 1.1

var game: Node = null
var ship: Node2D = null

## Enemy -> seconds of game time when last seen.
var _seen: Dictionary = {}
## Enemies a radar sweep has found (and not forgotten since) -> true.
var _scanned: Dictionary = {}
var _time: float = 0.0
## The picked contact - the active lock, if it is locked.
var target: Enemy = null
## Enemy -> 0..1 lock progress (1 = locked).
var locks: Dictionary = {}
## Weapon instance id -> true while it fires on its own.
var auto_fire: Dictionary = {}
## Weapon instance id -> the Enemy it works on (only guns switched on).
var assigned: Dictionary = {}
## Radar instance id -> {scan: seconds left, cooldown: seconds left, angle}.
var radars: Dictionary = {}


func _init() -> void:
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	z_index = -1


## Whether the picked target is locked.
func is_locked() -> bool:
	return is_locked_on(target)


func is_locked_on(enemy: Enemy) -> bool:
	return _alive(enemy) and float(locks.get(enemy, 0.0)) >= 1.0


## Every contact fully locked.
func locked_enemies() -> Array[Enemy]:
	var out: Array[Enemy] = []
	for enemy in locks.keys():
		if is_instance_valid(enemy) and is_locked_on(enemy):
			out.append(enemy)
	return out


## The locked enemy gun `id` works on, or null (off, waiting, still locking).
func gun_target(id: int) -> Enemy:
	var enemy: Variant = assigned.get(id)
	if not auto_fire.has(id) or not is_instance_valid(enemy) or not is_locked_on(enemy):
		return null
	return enemy


static func _alive(enemy: Enemy) -> bool:
	return enemy != null and is_instance_valid(enemy) and enemy.is_alive()


## Reach of passive sensors: the longest gun, but never under PASSIVE_RANGE_MIN.
## Missile launchers do not count - they reach far past what the eye sees,
## and fire at what a radar lock finds.
func passive_range() -> float:
	var reach: float = PASSIVE_RANGE_MIN
	for device: Dictionary in ship.fov_devices:
		if str(device.get("kind", "")) == "weapon" and device.get("id", &"") != &"weapon_rockets":
			reach = maxf(reach, float(device.get("range", 0.0)))
	return reach


## How far a lock reaches: the longest radar's range (0 with no radar).
func lock_range() -> float:
	var reach := 0.0
	for device: Dictionary in radar_devices():
		reach = maxf(reach, float(device.get("range", 0.0)))
	return reach


## Whether `enemy` can be locked: found by a radar sweep and within its reach.
func can_lock(enemy: Enemy) -> bool:
	return (
		_alive(enemy) and _scanned.has(enemy)
		and ship.global_position.distance_to(enemy.global_position) <= lock_range()
	)


func radar_devices() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for device: Dictionary in ship.fov_devices:
		if str(device.get("kind", "")) == "radar":
			out.append(device)
	return out


## Whether a planet or the sun stands between `from` and `to`.
func is_occluded(from: Vector2, to: Vector2) -> bool:
	var sun: Node2D = game.get("sun")
	if LaserBolt._segment_hits_circle(from, to, sun.position, float(sun.get("radius"))):
		return true
	var planets: Array = game.get("planets")
	var present: Array = game.get("planet_present")
	for i in planets.size():
		if i < present.size() and not present[i]:
			continue
		var planet: Node2D = planets[i]
		if LaserBolt._segment_hits_circle(from, to, planet.position, float(planet.get("radius"))):
			return true
	return false


## Every live enemy but the one the player is flying.
func _enemies() -> Array[Enemy]:
	var out: Array[Enemy] = []
	var flown: Node = game.get("_test_enemy")
	for child in game.get_children():
		if child is Enemy and child != flown and (child as Enemy).is_alive():
			out.append(child)
	return out


func update(delta: float) -> void:
	_time += delta
	var here: Vector2 = ship.global_position
	var enemies: Array[Enemy] = _enemies()

	# Passive sensors.
	var reach: float = passive_range()
	for enemy in enemies:
		if here.distance_to(enemy.global_position) <= reach and not is_occluded(here, enemy.global_position):
			_seen[enemy] = _time

	# Radar scans and recharges.
	var ids: Dictionary = {}
	for device in radar_devices():
		var id: int = int(device.get("instance_id", -1))
		ids[id] = true
		var state: Dictionary = radars.get(id, {"scan": 0.0, "cooldown": 0.0, "angle": 0.0})
		if float(state["scan"]) > 0.0:
			var before: float = float(state["angle"])
			var after: float = before + TAU / SWEEP_TURN_TIME * delta
			state["angle"] = after
			_sweep(before, after, float(device.get("range", 0.0)), enemies)
			state["scan"] = float(state["scan"]) - delta
			if float(state["scan"]) <= 0.0:
				state["scan"] = 0.0
				state["cooldown"] = maxf(float(device.get("reload_time", 10.0)), 0.1)
		elif float(state["cooldown"]) > 0.0:
			state["cooldown"] = maxf(float(state["cooldown"]) - delta, 0.0)
		radars[id] = state
	for id in radars.keys():
		if not ids.has(id):
			radars.erase(id)

	# Forget what the passive sensors have not seen for too long. What a
	# radar found stays until it dies.
	for enemy in _seen.keys():
		if not _alive(enemy) or (not _scanned.has(enemy) and _time - float(_seen[enemy]) > CONTACT_HOLD):
			_seen.erase(enemy)
			_scanned.erase(enemy)
	for enemy in _scanned.keys():
		if not _alive(enemy):
			_scanned.erase(enemy)

	if target != null and (not _alive(target) or not _seen.has(target)):
		set_target(null)
	# Locks build together; one out of the radar's reach (or dead) drops.
	for enemy in locks.keys():
		if not _alive(enemy):
			_unlock(enemy, true)
		elif not can_lock(enemy):
			_unlock(enemy)
		else:
			locks[enemy] = minf(float(locks[enemy]) + delta / LOCK_TIME, 1.0)
	# Guns switched on with no lock of their own take the active one.
	for id in auto_fire.keys():
		if not locks.has(assigned.get(id)) and is_locked():
			assigned[id] = target
	_run_auto_fire(delta)
	queue_redraw()


## The beam passed from `before` to `after` (radians): mark everything it
## crossed within `reach` that no planet hides.
func _sweep(before: float, after: float, reach: float, enemies: Array[Enemy]) -> void:
	var here: Vector2 = ship.global_position
	for enemy in enemies:
		var offset: Vector2 = enemy.global_position - here
		if offset.length() > reach:
			continue
		var bearing: float = fposmod(offset.angle() - before, TAU)
		if bearing <= after - before and not is_occluded(here, enemy.global_position):
			_seen[enemy] = _time
			_scanned[enemy] = true


func start_scan(id: int) -> bool:
	if ship.resources_enabled and not ship.powered and not PlayerProgress.god_mode:
		return false
	var state: Dictionary = radars.get(id, {"scan": 0.0, "cooldown": 0.0, "angle": 0.0})
	if float(state["scan"]) > 0.0 or float(state["cooldown"]) > 0.0:
		return false
	for device in radar_devices():
		if int(device.get("instance_id", -1)) == id:
			state["scan"] = maxf(float(device.get("scan_time", 3.0)), 0.5)
			state["angle"] = ship.rotation
			radars[id] = state
			return true
	return false


## R: every radar that is ready scans.
func scan_all() -> bool:
	var any := false
	for device in radar_devices():
		any = start_scan(int(device.get("instance_id", -1))) or any
	return any


## Picks `enemy` as the target (the active lock if it is locked); locks
## stay as they are.
func set_target(enemy: Enemy) -> void:
	var old: Enemy = target
	target = enemy
	_mark(old)
	_mark(target)


## Ctrl+click: lock on `enemy` (and pick it), or let go of a lock on it.
func toggle_lock(enemy: Enemy) -> void:
	if enemy == null:
		return
	if locks.has(enemy):
		_unlock(enemy)
		if enemy == target:
			set_target(null)
		return
	if not can_lock(enemy):
		return
	locks[enemy] = 0.0
	set_target(enemy)


## Drops the lock on `enemy`; the guns on it wait for another - or, with
## `destroyed` (the target is dead), switch off and are ready again.
func _unlock(enemy: Enemy, destroyed: bool = false) -> void:
	locks.erase(enemy)
	for id in assigned.keys():
		if assigned[id] != enemy:
			continue
		assigned.erase(id)
		if destroyed:
			auto_fire.erase(id)
			if ship.selected_weapon == id:
				ship.selected_weapon = -1
	if is_instance_valid(enemy):
		_mark(enemy)


## Brackets on the picked target and every lock.
func _mark(enemy: Enemy) -> void:
	if enemy != null and is_instance_valid(enemy):
		enemy.targeted = enemy == target or locks.has(enemy)


## Click on a gun in the rack: switch it on at the active lock, move it
## there from another lock, or switch it off.
func toggle_auto_fire(id: int) -> void:
	var active: Enemy = target if locks.has(target) else null
	if auto_fire.has(id) and (active == null or assigned.get(id) == active):
		auto_fire.erase(id)
		assigned.erase(id)
		return
	auto_fire[id] = true
	if active != null:
		assigned[id] = active
	else:
		assigned.erase(id)


## Every turret (laser, revolver, ...) swings onto its lock - the guns that
## are off onto the active one - all but the picked one while the player
## aims it by hand (RMB); the guns switched on fire whenever they can.
func _run_auto_fire(delta: float) -> void:
	var hand_aimed: int = ship.selected_weapon if ship.rmb_aim else -1
	for device: Dictionary in ship.fov_devices:
		if str(device.get("kind", "")) != "weapon":
			continue
		var id: int = int(device.get("instance_id", -1))
		var on: Enemy = gun_target(id)
		var aim_at: Enemy = on
		if aim_at == null and not auto_fire.has(id) and is_locked():
			aim_at = target
		if aim_at == null:
			continue
		var aim: Vector2 = aim_at.global_position
		if id != hand_aimed:
			ship.aim_device(device, aim, delta)
		if on != null and ship.is_body_in_device_fov(device, aim):
			game.call("_spawn_weapon_shots", ship.fire_weapons_at(aim, id), aim, on)


## Contacts panel rows, nearest first: {enemy, title, kind_id, distance, status}.
func contacts() -> Array:
	var rows: Array = []
	var here: Vector2 = ship.global_position
	for enemy in _seen.keys():
		if not _alive(enemy):
			continue
		var status: String = ""
		if locks.has(enemy):
			if is_locked_on(enemy):
				status = "LOCKED"
			else:
				status = "LOCK %d%%" % roundi(float(locks[enemy]) * 100.0)
		elif enemy == target:
			status = "TARGET"
		elif not _scanned.has(enemy):
			status = "NO SCAN"
		elif here.distance_to(enemy.global_position) > lock_range():
			status = "TOO FAR"
		elif _time - float(_seen[enemy]) > 0.5:
			# Not seen right now: where it was last swept.
			status = "%ds" % roundi(_time - float(_seen[enemy]))
		rows.append({
			"enemy": enemy, "title": enemy.title, "kind_id": enemy.kind_id,
			"distance": here.distance_to(enemy.global_position), "status": status,
			"locked": is_locked_on(enemy),
		})
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["distance"] < b["distance"])
	return rows


## Weapons panel row for a radar: {id, title, radar, scan (0..1 left),
## reload (0 ready .. 1 just finished)}.
func radar_rows() -> Array:
	var rows: Array = []
	for device in radar_devices():
		var id: int = int(device.get("instance_id", -1))
		var state: Dictionary = radars.get(id, {"scan": 0.0, "cooldown": 0.0})
		rows.append({
			"id": id, "module_id": device.get("id", &""), "title": device.get("title", "Radar"), "radar": true,
			"scan": float(state["scan"]) / maxf(float(device.get("scan_time", 1.0)), 0.1),
			"reload": float(state["cooldown"]) / maxf(float(device.get("reload_time", 1.0)), 0.1),
		})
	return rows


## The green beam of every radar that is scanning, and a ring at its reach.
func _draw() -> void:
	if ship == null:
		return
	var px: float = 1.0 / maxf(get_global_transform_with_canvas().get_scale().x, 0.0001)
	var centre: Vector2 = to_local(ship.global_position)
	for device in radar_devices():
		var state: Dictionary = radars.get(int(device.get("instance_id", -1)), {})
		if float(state.get("scan", 0.0)) <= 0.0:
			continue
		var reach: float = float(device.get("range", 0.0))
		var angle: float = float(state["angle"])
		draw_arc(centre, reach, 0.0, TAU, 128, Color(SWEEP_COLOR, 0.35), 1.5 * px, true)
		# The trail: thin wedges fading out behind the beam.
		var steps := 16
		for i in steps:
			var a0: float = angle - SWEEP_TRAIL * float(i + 1) / steps
			var a1: float = angle - SWEEP_TRAIL * float(i) / steps
			var alpha: float = 0.22 * (1.0 - float(i) / steps)
			draw_colored_polygon(PackedVector2Array([
				centre, centre + Vector2.RIGHT.rotated(a0) * reach, centre + Vector2.RIGHT.rotated(a1) * reach,
			]), Color(SWEEP_COLOR, alpha))
		draw_line(centre, centre + Vector2.RIGHT.rotated(angle) * reach, Color(SWEEP_COLOR, 0.9), 2.0 * px, true)
	# Blips on every contact the radar picked up but the eye would miss.
	for enemy in _seen.keys():
		if _alive(enemy):
			var age: float = _time - float(_seen[enemy])
			var floor_alpha: float = 0.35 if _scanned.has(enemy) else 0.15
			var fade: float = clampf(1.0 - age / CONTACT_HOLD, floor_alpha, 1.0)
			draw_circle(to_local(enemy.global_position), 4.0 * px, Color(SWEEP_COLOR, 0.8 * fade))

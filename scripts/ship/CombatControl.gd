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
## then the radar recharges for its reload_time. A contact seen once is kept
## (and tracked) for CONTACT_HOLD seconds.
##
## Lock. Ctrl+click a contact: the lock builds over LOCK_TIME while the
## contact is held, then holds until the contact is lost or let go.
##
## Auto-fire. With a lock every turret turns onto the target; clicking a gun
## in the weapons panel sets it firing on its own: it fires every time it has
## reloaded and the target is in its cone - until clicked again or the lock
## goes.

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
var _time: float = 0.0
var target: Enemy = null
## 0..1 while locking on `target`; 1 = locked; 0 with no lock under way.
var lock_progress: float = 0.0
var locking: bool = false
## Weapon instance id -> true while it fires on its own.
var auto_fire: Dictionary = {}
## Radar instance id -> {scan: seconds left, cooldown: seconds left, angle}.
var radars: Dictionary = {}


func _init() -> void:
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	z_index = -1


func is_locked() -> bool:
	return locking and lock_progress >= 1.0 and _alive(target)


static func _alive(enemy: Enemy) -> bool:
	return enemy != null and is_instance_valid(enemy) and enemy.is_alive()


## Reach of passive sensors: the longest gun, but never under PASSIVE_RANGE_MIN.
func passive_range() -> float:
	var reach: float = PASSIVE_RANGE_MIN
	for device: Dictionary in ship.fov_devices:
		if str(device.get("kind", "")) == "weapon":
			reach = maxf(reach, float(device.get("range", 0.0)))
	return reach


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

	# Forget what has not been seen for too long.
	for enemy in _seen.keys():
		if not _alive(enemy) or _time - float(_seen[enemy]) > CONTACT_HOLD:
			_seen.erase(enemy)

	# The lock builds while the target is held, and goes with it.
	if target != null and (not _alive(target) or not _seen.has(target)):
		set_target(null)
	if locking and target != null:
		lock_progress = minf(lock_progress + delta / LOCK_TIME, 1.0)
	if not is_locked():
		auto_fire.clear()
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


func set_target(enemy: Enemy) -> void:
	if target != null and is_instance_valid(target):
		target.targeted = false
	target = enemy
	locking = false
	lock_progress = 0.0
	auto_fire.clear()
	if target != null:
		target.targeted = true


## Ctrl+click: lock on `enemy`, or let go of a lock on it.
func toggle_lock(enemy: Enemy) -> void:
	if enemy == target and locking:
		set_target(null)
		return
	set_target(enemy)
	locking = enemy != null


## Click on a gun with a lock: it fires on its own, or stops.
func toggle_auto_fire(id: int) -> void:
	if auto_fire.has(id):
		auto_fire.erase(id)
	elif is_locked():
		auto_fire[id] = true


## With a lock, every turret (laser, revolver, ...) swings onto the target -
## all but the picked one while the player aims it by hand (RMB) - and the
## guns on AUTO fire whenever they can.
func _run_auto_fire(delta: float) -> void:
	if not is_locked():
		return
	var aim: Vector2 = target.global_position
	var hand_aimed: int = ship.selected_weapon if Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT) else -1
	for device: Dictionary in ship.fov_devices:
		if str(device.get("kind", "")) != "weapon":
			continue
		var id: int = int(device.get("instance_id", -1))
		if id != hand_aimed:
			ship.aim_device(device, aim, delta)
		if auto_fire.has(id) and ship.is_body_in_device_fov(device, aim):
			game.call("_spawn_weapon_shots", ship.fire_weapons_at(aim, id), aim, target)


## Contacts panel rows, nearest first: {enemy, title, kind_id, distance, status}.
func contacts() -> Array:
	var rows: Array = []
	var here: Vector2 = ship.global_position
	for enemy in _seen.keys():
		if not _alive(enemy):
			continue
		var status: String = ""
		if enemy == target:
			if is_locked():
				status = "LOCKED"
			elif locking:
				status = "LOCK %d%%" % roundi(lock_progress * 100.0)
			else:
				status = "TARGET"
		elif _time - float(_seen[enemy]) > 0.5:
			# Not seen right now: where it was last swept.
			status = "%ds" % roundi(_time - float(_seen[enemy]))
		rows.append({
			"enemy": enemy, "title": enemy.title, "kind_id": enemy.kind_id,
			"distance": here.distance_to(enemy.global_position), "status": status,
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
			var fade: float = clampf(1.0 - age / CONTACT_HOLD, 0.15, 1.0)
			draw_circle(to_local(enemy.global_position), 4.0 * px, Color(SWEEP_COLOR, 0.8 * fade))

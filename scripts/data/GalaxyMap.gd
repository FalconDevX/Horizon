class_name GalaxyMap
extends RefCounted
## The galaxy the star systems live in, and which of them the player has been
## to. A system is its world seed (solar_system.gd world_seed): the seed also
## fixes where in the galaxy it lies and what it is called, so a system seen
## again lands on the same spot with the same name.
##
## Besides the visited ones the galaxy holds a fixed catalogue of systems
## (`systems()`) that can be picked on the map as a course. A course is flown
## with the hyperdrive (solar_system.gd), and each system left behind keeps
## what the player did there (`save_state()`), so going back finds it as it was.
##
## Static, like PlayerProgress, so it survives scene reloads; there is no save
## system yet, so it resets when the game restarts.

## Galaxy coordinates are in units of its radius: the disc spans -1..1.
const ARM_COUNT := 4
## How far an arm winds (radians) from the core to the rim.
const ARM_TWIST := 3.4
const CORE_RADIUS := 0.12
## How many systems the galaxy offers besides the ones already visited.
const SYSTEM_COUNT := 160

## Our own galaxy, as named on the map once it is zoomed out among its
## neighbours.
const HOME_GALAXY_NAME := "Virelian Spiral"

## Other galaxies, seen on the map past our own rim. Out of the hyperdrive's
## reach - scenery for now. `position` and `radius` are in our galaxy's radii;
## `tilt` squashes the disc (1 = face on), `rotation` turns it; `arms` and
## `twist` shape a spiral; `seed` varies its noise.
const NEIGHBOURS := [
	{
		"name": "Andrasyl", "kind": "spiral", "position": Vector2(-7.6, -4.2), "radius": 1.75,
		"rotation": 0.6, "tilt": 0.36, "arms": 2.0, "twist": 3.0,
		"tint": Color(0.68, 0.8, 1.0), "seed": 11.0,
	},
	{
		"name": "Large Veil Cloud", "kind": "irregular", "position": Vector2(-1.7, 1.75), "radius": 0.4,
		"rotation": 0.4, "tilt": 0.75, "arms": 0.0, "twist": 0.0,
		"tint": Color(0.7, 0.8, 1.0), "seed": 23.0,
	},
	{
		"name": "Small Veil Cloud", "kind": "irregular", "position": Vector2(-2.3, 2.7), "radius": 0.24,
		"rotation": -0.9, "tilt": 0.6, "arms": 0.0, "twist": 0.0,
		"tint": Color(0.75, 0.82, 1.0), "seed": 37.0,
	},
	{
		"name": "Nerith Dwarf", "kind": "elliptical", "position": Vector2(3.0, -2.2), "radius": 0.2,
		"rotation": 0.3, "tilt": 0.8, "arms": 0.0, "twist": 0.0,
		"tint": Color(1.0, 0.86, 0.66), "seed": 41.0,
	},
	{
		"name": "Thessaly Whirl", "kind": "spiral", "position": Vector2(5.1, -6.9), "radius": 1.1,
		"rotation": 1.9, "tilt": 0.93, "arms": 3.0, "twist": 4.2,
		"tint": Color(0.62, 0.78, 1.0), "seed": 53.0,
	},
	{
		"name": "Corvane", "kind": "elliptical", "position": Vector2(10.6, 2.9), "radius": 1.3,
		"rotation": -0.5, "tilt": 0.66, "arms": 0.0, "twist": 0.0,
		"tint": Color(1.0, 0.84, 0.62), "seed": 67.0,
	},
	{
		"name": "Oriel Needle", "kind": "spiral", "position": Vector2(-9.9, 6.2), "radius": 1.25,
		"rotation": -0.35, "tilt": 0.14, "arms": 2.0, "twist": 2.6,
		"tint": Color(0.72, 0.82, 1.0), "seed": 79.0,
	},
	{
		"name": "Halcyon", "kind": "spiral", "position": Vector2(-3.4, -9.4), "radius": 0.85,
		"rotation": 2.6, "tilt": 0.6, "arms": 4.0, "twist": 3.4,
		"tint": Color(0.9, 0.86, 0.8), "seed": 97.0,
	},
]

## Star classes, hottest first: letter, colour on the map, and how common
## (weights). Picked from a system's seed by `star_class()`.
const STAR_CLASSES := [
	{"letter": "O", "name": "Blue giant", "color": Color(0.62, 0.72, 1.0), "weight": 1.0},
	{"letter": "B", "name": "Blue-white star", "color": Color(0.72, 0.82, 1.0), "weight": 3.0},
	{"letter": "A", "name": "White star", "color": Color(0.9, 0.93, 1.0), "weight": 6.0},
	{"letter": "F", "name": "Yellow-white star", "color": Color(1.0, 0.97, 0.86), "weight": 10.0},
	{"letter": "G", "name": "Yellow dwarf", "color": Color(1.0, 0.9, 0.6), "weight": 14.0},
	{"letter": "K", "name": "Orange dwarf", "color": Color(1.0, 0.72, 0.42), "weight": 16.0},
	{"letter": "M", "name": "Red dwarf", "color": Color(1.0, 0.52, 0.4), "weight": 20.0},
]

const _SYLLABLES := [
	"ka", "ve", "lo", "ri", "tha", "mor", "sel", "an", "dra", "ny", "os", "qui",
	"zen", "el", "ur", "cy", "ma", "thor", "is", "ga", "le", "vor", "ae", "ix",
]
const _SUFFIXES := ["", "", "", " Prime", " Minor", " Reach", " Drift", " Deep"]

## Visited systems in the order first reached: {seed, position, name}.
static var _visits: Array[Dictionary] = []
static var _current_seed: int = 0
static var _has_current := false
## The system the hyperdrive is set to jump to.
static var _target_seed: int = 0
static var _has_target := false
## seed -> whatever solar_system.gd saved when leaving that system.
static var _saved: Dictionary = {}
static var _catalog: Array[Dictionary] = []


## Marks `system_seed` as the system the player is in, adding it on a first visit.
static func visit(system_seed: int) -> void:
	_current_seed = system_seed
	_has_current = true
	if _has_target and _target_seed == system_seed:
		_has_target = false
	if index_of(system_seed) < 0:
		_visits.append({
			"seed": system_seed,
			"position": position_for(system_seed),
			"name": system_name(system_seed),
		})


static func visits() -> Array[Dictionary]:
	return _visits


static func current_seed() -> int:
	return _current_seed


static func is_current(system_seed: int) -> bool:
	return _has_current and system_seed == _current_seed


## Back to a galaxy nobody has travelled (a new game).
static func reset() -> void:
	_visits.clear()
	_current_seed = 0
	_has_current = false
	_target_seed = 0
	_has_target = false
	_saved.clear()


## Everything the player did in the galaxy, for SaveGame.
static func to_dict() -> Dictionary:
	return {
		"visits": _visits.duplicate(true),
		"current": _current_seed,
		"has_current": _has_current,
		"target": _target_seed,
		"has_target": _has_target,
		"saved": _saved.duplicate(true),
	}


static func from_dict(data: Dictionary) -> void:
	_visits.clear()
	for visit_entry: Dictionary in data.get("visits", []):
		_visits.append(visit_entry)
	_current_seed = int(data.get("current", 0))
	_has_current = bool(data.get("has_current", false))
	_target_seed = int(data.get("target", 0))
	_has_target = bool(data.get("has_target", false))
	_saved = (data.get("saved", {}) as Dictionary).duplicate(true)


static func is_visited(system_seed: int) -> bool:
	return index_of(system_seed) >= 0


## Every system on the map: the catalogue, plus any visited system outside it
## (the starting one, or a reroll with N). {seed, position, name}.
static func systems() -> Array[Dictionary]:
	if _catalog.is_empty():
		for i in SYSTEM_COUNT:
			var system_seed: int = hash([i, "system"]) & 0x7fffffff
			_catalog.append({
				"seed": system_seed,
				"position": position_for(system_seed),
				"name": system_name(system_seed),
			})
	var all: Array[Dictionary] = _catalog.duplicate()
	for system: Dictionary in _visits:
		if not _catalog.any(func(c: Dictionary) -> bool: return c["seed"] == system["seed"]):
			all.append(system)
	return all


static func set_target(system_seed: int) -> void:
	_target_seed = system_seed
	_has_target = true


static func clear_target() -> void:
	_has_target = false


static func has_target() -> bool:
	return _has_target


static func target_seed() -> int:
	return _target_seed


static func save_state(system_seed: int, state: Dictionary) -> void:
	_saved[system_seed] = state


## What was saved on leaving `system_seed`, or {} for a system never left.
static func saved_state(system_seed: int) -> Dictionary:
	return _saved.get(system_seed, {})


static func index_of(system_seed: int) -> int:
	for i in _visits.size():
		if int(_visits[i]["seed"]) == system_seed:
			return i
	return -1


## Where a system lies: on one of the spiral arms (a few near the core or
## between arms), further out less often, as stars thin toward the rim.
static func position_for(system_seed: int) -> Vector2:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([system_seed, "galaxy"])
	var r: float = lerpf(CORE_RADIUS * 1.4, 0.93, sqrt(rng.randf()))
	var angle: float
	if rng.randf() < 0.8:
		var arm: int = rng.randi_range(0, ARM_COUNT - 1)
		angle = arm_angle(arm, r) + rng.randfn(0.0, 0.16)
	else:
		angle = rng.randf() * TAU
	return Vector2.from_angle(angle) * r


## Angle of arm `arm` at radius `r` (a log-ish spiral).
static func arm_angle(arm: int, r: float) -> float:
	return float(arm) * TAU / float(ARM_COUNT) + ARM_TWIST * sqrt(r)


## The kind of star at a system's heart (an entry of STAR_CLASSES), fixed by
## the seed.
static func star_class(system_seed: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([system_seed, "star"])
	var total: float = 0.0
	for entry: Dictionary in STAR_CLASSES:
		total += float(entry["weight"])
	var roll: float = rng.randf() * total
	for entry: Dictionary in STAR_CLASSES:
		roll -= float(entry["weight"])
		if roll <= 0.0:
			return entry
	return STAR_CLASSES[STAR_CLASSES.size() - 1]


static func system_name(system_seed: int) -> String:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([system_seed, "name"])
	var result := ""
	for i in rng.randi_range(2, 3):
		result += _SYLLABLES[rng.randi_range(0, _SYLLABLES.size() - 1)]
	result = result.capitalize() + _SUFFIXES[rng.randi_range(0, _SUFFIXES.size() - 1)]
	return result

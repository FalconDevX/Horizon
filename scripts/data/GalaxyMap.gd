class_name GalaxyMap
extends RefCounted
## The galaxy the star systems live in, and which of them the player has been
## to. A system is its world seed (solar_system.gd world_seed): the seed also
## fixes where in the galaxy it lies and what it is called, so a system seen
## again lands on the same spot with the same name.
##
## Static, like PlayerProgress, so it survives scene reloads; there is no save
## system yet, so it resets when the game restarts.

## Galaxy coordinates are in units of its radius: the disc spans -1..1.
const ARM_COUNT := 4
## How far an arm winds (radians) from the core to the rim.
const ARM_TWIST := 3.4
const CORE_RADIUS := 0.12

const _SYLLABLES := [
	"ka", "ve", "lo", "ri", "tha", "mor", "sel", "an", "dra", "ny", "os", "qui",
	"zen", "el", "ur", "cy", "ma", "thor", "is", "ga", "le", "vor", "ae", "ix",
]
const _SUFFIXES := ["", "", "", " Prime", " Minor", " Reach", " Drift", " Deep"]

## Visited systems in the order first reached: {seed, position, name}.
static var _visits: Array[Dictionary] = []
static var _current_seed: int = 0
static var _has_current := false


## Marks `system_seed` as the system the player is in, adding it on a first visit.
static func visit(system_seed: int) -> void:
	_current_seed = system_seed
	_has_current = true
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


static func system_name(system_seed: int) -> String:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([system_seed, "name"])
	var result := ""
	for i in rng.randi_range(2, 3):
		result += _SYLLABLES[rng.randi_range(0, _SYLLABLES.size() - 1)]
	result = result.capitalize() + _SUFFIXES[rng.randi_range(0, _SUFFIXES.size() - 1)]
	return result

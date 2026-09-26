class_name PlanetGuards
extends RefCounted
## Spawns hostile craft in circular orbits around planets, by each planet's
## difficulty (PlanetRoster.DIFFICULTY, 1 low .. 4 extreme - see GUARDS): the
## easy worlds get a few light craft, the hard ones the elite roster
## (Cruiser / Mothership / Minelayer / Black hole) on top of basic escorts.
##
## `system_depth` is the discovery order of the star system (0 = first
## visited). Each later system gets EXTRA_PER_SYSTEM more guards than the
## one before, spread across its planets.

## Per difficulty: how many basic craft (from `basic`) and how many elite
## (EnemyCatalog.ELITE_IDS) orbit a planet.
const GUARDS := {
	1: {"basic": Vector2i(1, 2), "elite": Vector2i(0, 0), "pool": ["basic", "kamikaze"]},
	2: {"basic": Vector2i(2, 4), "elite": Vector2i(0, 0), "pool": ["basic", "tank", "sniper", "kamikaze"]},
	3: {"basic": Vector2i(2, 3), "elite": Vector2i(1, 1), "pool": ["basic", "tank", "sniper", "kamikaze"]},
	4: {"basic": Vector2i(1, 2), "elite": Vector2i(2, 3), "pool": ["basic", "tank", "sniper", "kamikaze"]},
}
## Extra hostile craft for the whole system per discovery step.
const EXTRA_PER_SYSTEM := 3
## Orbit altitude as a multiple of the planet's radius, plus a flat pad so
## tiny worlds still have room outside the disc.
const ORBIT_RADII := Vector2(1.7, 2.6)
const ORBIT_PAD := 160.0
## Player-to-planet distance that wakes the whole patrol (vs orbit radius /
## body radius). Past this they chase and shoot; a bit of hysteresis in
## Enemy lets them stand down without flickering.
const ALERT_ORBIT_FACTOR := 2.2
const ALERT_RADIUS_FACTOR := 5.0
const ALERT_PAD := 500.0


static func spawn_system(
	host: Node2D,
	planets: Array,
	gravity_constant: float,
	skip_planet: Node2D = null,
	system_depth: int = 0
) -> Array[Enemy]:
	var eligible: Array[Node2D] = []
	for planet: Node2D in planets:
		if planet == skip_planet:
			continue
		if planet.get("is_star") or planet.get("is_anomaly") or planet.get("is_black_hole"):
			continue
		eligible.append(planet)

	var extras: Dictionary = _extras_per_planet(eligible, maxi(0, system_depth))
	var spawned: Array[Enemy] = []
	for planet: Node2D in eligible:
		spawned.append_array(
			spawn_planet(host, planet, gravity_constant, int(extras.get(planet, 0)))
		)
	return spawned


## Spread `system_depth * EXTRA_PER_SYSTEM` bonus craft across planets
## (stable for the same set of worlds).
static func _extras_per_planet(planets: Array[Node2D], system_depth: int) -> Dictionary:
	var extras: Dictionary = {}
	var remaining: int = system_depth * EXTRA_PER_SYSTEM
	if remaining <= 0 or planets.is_empty():
		return extras
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(planets[0].get("generation_seed")) ^ (0x51F2E01 + system_depth)
	while remaining > 0:
		var planet: Node2D = planets[rng.randi() % planets.size()]
		extras[planet] = int(extras.get(planet, 0)) + 1
		remaining -= 1
	return extras


static func spawn_planet(
	host: Node2D,
	planet: Node2D,
	gravity_constant: float,
	extra_count: int = 0
) -> Array[Enemy]:
	var difficulty: int = PlanetRoster.difficulty(String(planet.get("body_name")))
	var recipe: Dictionary = GUARDS.get(difficulty, GUARDS[1])

	var rng := RandomNumberGenerator.new()
	# Stable per planet / world so a reload of the same seed keeps the same
	# patrol (fighters deployed later are still free-roaming).
	rng.seed = hash(planet.get("generation_seed")) ^ 0x6A17D5E1

	var body_radius: float = float(planet.get("radius"))
	var mass: float = float(planet.get("mass"))
	var base_orbit: float = body_radius * rng.randf_range(ORBIT_RADII.x, ORBIT_RADII.y) + ORBIT_PAD
	var mu: float = gravity_constant * mass
	var base_omega: float = sqrt(mu / maxf(base_orbit * base_orbit * base_orbit, 1.0))
	base_omega = clampf(base_omega, 0.015, 0.28)

	# Elites first, then basic craft - the system's extra guards join the
	# basic ones.
	var ids: Array[String] = []
	for _i in rng.randi_range(recipe["elite"].x, recipe["elite"].y):
		ids.append(EnemyCatalog.ELITE_IDS[rng.randi() % EnemyCatalog.ELITE_IDS.size()])
	var basic_pool: Array = recipe["pool"]
	for _i in rng.randi_range(recipe["basic"].x, recipe["basic"].y) + maxi(0, extra_count):
		ids.append(basic_pool[rng.randi() % basic_pool.size()])
	var count: int = ids.size()
	var alert_range: float = maxf(
		base_orbit * ALERT_ORBIT_FACTOR,
		body_radius * ALERT_RADIUS_FACTOR
	) + ALERT_PAD
	var spawned: Array[Enemy] = []
	for i in count:
		var enemy_id: String = ids[i]
		var scene: PackedScene = EnemyCatalog.scene_for(enemy_id)
		if scene == null:
			continue
		var enemy := scene.instantiate() as Enemy
		if enemy == null:
			continue
		EnemyCatalog.configure(enemy, enemy_id)
		var angle: float = (TAU * float(i) / float(count)) + rng.randf_range(-0.2, 0.2)
		var radius: float = base_orbit * rng.randf_range(0.88, 1.18)
		var omega: float = base_omega * (1.0 if rng.randf() > 0.35 else -1.0)
		host.add_child(enemy)
		enemy.begin_orbit(planet, radius, angle, omega, alert_range)
		spawned.append(enemy)
	return spawned

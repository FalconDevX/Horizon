class_name EnemyWaves
extends RefCounted
## Timed hostile waves that hunt the player. Every INTERVAL_HOURS of sim time
## a new wave spawns around the ship; later waves field more craft and a
## higher share of elite types, without an end.

## Mission hours between waves (elapsed from session start).
const INTERVAL_HOURS := 12
## Craft in wave 1, then +COUNT_PER_WAVE each step until the soft cap.
const BASE_COUNT := 3
const COUNT_PER_WAVE := 2
const COUNT_SOFT_CAP := 20
## Distance from the player where the ring of attackers appears.
const SPAWN_DISTANCE := Vector2(9000.0, 14000.0)
## How much of the ring ahead of the ship is used (full circle = TAU).
const SPAWN_ARC := PI * 1.35


## How many craft wave `n` (1-based) should spawn.
static func enemy_count(wave: int) -> int:
	var n: int = maxi(1, wave)
	return mini(BASE_COUNT + (n - 1) * COUNT_PER_WAVE, COUNT_SOFT_CAP)


## Hull multiplier once count is capped - keeps late waves hard without flooding.
static func health_scale(wave: int) -> float:
	var n: int = maxi(1, wave)
	var uncapped: int = BASE_COUNT + (n - 1) * COUNT_PER_WAVE
	if uncapped <= COUNT_SOFT_CAP:
		return 1.0
	return float(uncapped) / float(COUNT_SOFT_CAP)


## Pick catalog ids for this wave (length = enemy_count).
static func composition(wave: int, rng: RandomNumberGenerator) -> Array[String]:
	var ids: Array[String] = []
	var count: int = enemy_count(wave)
	for _i in count:
		ids.append(_pick_id(wave, rng))
	return ids


static func _pick_id(wave: int, rng: RandomNumberGenerator) -> String:
	# Elite share climbs with wave number; early waves stay on the basic roster.
	var elite_chance: float = clampf(0.06 * float(maxi(0, wave - 1)), 0.0, 0.72)
	var fast_chance: float = clampf(0.04 * float(maxi(0, wave - 1)), 0.0, 0.28)
	var roll: float = rng.randf()
	if wave >= 3 and roll < elite_chance:
		return EnemyCatalog.ELITE_IDS[rng.randi() % EnemyCatalog.ELITE_IDS.size()]
	if wave >= 2 and roll < elite_chance + fast_chance:
		return "fast"
	return EnemyCatalog.BASIC_IDS[rng.randi() % EnemyCatalog.BASIC_IDS.size()]


## Spawns the wave around `ship`, chasing it immediately. Returns the new craft.
static func spawn_wave(
	host: Node2D,
	ship: Node2D,
	wave: int
) -> Array[Enemy]:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var ids: Array[String] = composition(wave, rng)
	var scale: float = health_scale(wave)
	var origin: Vector2 = ship.global_position
	var facing: float = ship.rotation
	var spawned: Array[Enemy] = []
	var count: int = ids.size()
	for i in count:
		var enemy_id: String = ids[i]
		var scene: PackedScene = EnemyCatalog.scene_for(enemy_id)
		if scene == null:
			continue
		var enemy := scene.instantiate() as Enemy
		if enemy == null:
			continue
		EnemyCatalog.configure(enemy, enemy_id)
		enemy.player_controlled = false
		enemy.ai_forward = true
		enemy.ai_seek_ship = true
		if scale > 1.001:
			enemy.max_health = enemy.max_health * scale
		host.add_child(enemy)
		var t: float = 0.0 if count <= 1 else float(i) / float(count - 1)
		var angle: float = facing - SPAWN_ARC * 0.5 + SPAWN_ARC * t
		angle += rng.randf_range(-0.12, 0.12)
		var dist: float = rng.randf_range(SPAWN_DISTANCE.x, SPAWN_DISTANCE.y)
		enemy.global_position = origin + Vector2.from_angle(angle) * dist
		enemy.rotation = (origin - enemy.global_position).angle()
		spawned.append(enemy)
	return spawned


## Elapsed whole mission hours since sim start (0 at launch).
static func elapsed_hours(sim_time: float, hours_per_sim_second: float) -> int:
	return int(sim_time * hours_per_sim_second)


## How many waves should already have fired by this sim time.
static func waves_due(sim_time: float, hours_per_sim_second: float) -> int:
	return elapsed_hours(sim_time, hours_per_sim_second) / INTERVAL_HOURS


## Whole hours left until the next wave (INTERVAL_HOURS at session start).
static func hours_until_next(
	sim_time: float,
	hours_per_sim_second: float,
	waves_spawned: int
) -> int:
	var elapsed: int = elapsed_hours(sim_time, hours_per_sim_second)
	var next_at: int = (waves_spawned + 1) * INTERVAL_HOURS
	return maxi(0, next_at - elapsed)

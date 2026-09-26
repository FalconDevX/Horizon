class_name PlanetRoster
extends RefCounted
## Which planets a system has. Every system is built from the same 20 planets
## of solar_system.tscn; its seed decides which of them are there. Each planet
## has a rarity tier - 1 common .. 5 rare - rolled on its own, then the count
## is kept to COUNT and one giant (ice or gas) is always in. Deterministic per
## seed, so a system is the same every visit. Planets not listed here (Erebus,
## the anomaly) are in every system and do not count.
##
## Chances measured over 40 000 systems: tier 1 ~72-76%, tier 2 ~34%, tier 3
## ~23%, tier 4 ~10%, tier 5 ~3%; 7 planets in ~56% of systems, 8 in ~19%,
## 9 in ~13%, 10 in ~7%, 11 in ~4%.
##
## Each planet also has a DIFFICULTY (1 low .. 4 extreme) that sets the
## guards orbiting it (PlanetGuards) - independent of its rarity.

const TIERS := {
	"Cindral": 1, "Coralyss": 1, "Oruvel": 1, "Rimebeck": 1, "Taurvane": 1, "Vantauri": 1,
	"Ashkar": 2, "Cinderhal": 2, "Dunmere": 2, "Emberrock": 2, "Thornix": 2, "Vesk": 2,
	"Anthea": 3, "Duskveil": 3, "Glacenna": 3, "Hoarveil": 3, "Nyxholm": 3,
	"Aurumbra": 4, "Mireth": 4,
	"Marrow": 5,
}
## Chance of a planet of each tier being in a system, before the count is
## trimmed or topped up to COUNT.
const TIER_CHANCE := {1: 0.68, 2: 0.31, 3: 0.21, 4: 0.085, 5: 0.022}

## How dangerous a planet is to visit: 1 low .. 4 extreme (PlanetGuards).
const DIFFICULTY := {
	"Anthea": 2, "Ashkar": 2, "Aurumbra": 4, "Cinderhal": 1, "Cindral": 2,
	"Coralyss": 1, "Dunmere": 2, "Duskveil": 1, "Emberrock": 2, "Glacenna": 3,
	"Hoarveil": 3, "Marrow": 1, "Mireth": 4, "Nyxholm": 1, "Oruvel": 1,
	"Rimebeck": 1, "Taurvane": 1, "Thornix": 2, "Vantauri": 1, "Vesk": 3,
}
const DIFFICULTY_NAMES := {1: "Low", 2: "Moderate", 3: "High", 4: "Extreme"}
const TIER_NAMES := {1: "Common", 2: "Uncommon", 3: "Scarce", 4: "Rare", 5: "Very rare"}
## Planets per system (not counting ones outside TIERS).
const COUNT := Vector2i(7, 11)
## One of these is always in.
const GIANTS: Array[String] = ["Oruvel", "Taurvane"]


## The planets of system `system_seed`: name -> true.
static func roll(system_seed: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(system_seed) ^ 0x51A7E0
	var present: Dictionary = {}
	for name: String in TIERS:
		if rng.randf() < chance(name):
			present[name] = true
	var giant: String = ""
	for name: String in GIANTS:
		if present.has(name):
			giant = name
			break
	if giant == "":
		giant = GIANTS[rng.randi() % GIANTS.size()]
		present[giant] = true
	# Too few: add more, the common ones likelier.
	while present.size() < COUNT.x:
		var absent: Array = TIERS.keys().filter(func(name: String) -> bool: return not present.has(name))
		present[_weighted(absent, rng)] = true
	# Too many: drop some at random, never the giant.
	while present.size() > COUNT.y:
		var removable: Array = present.keys().filter(func(name: String) -> bool: return name != giant)
		present.erase(removable[rng.randi() % removable.size()])
	return present


## Whether `body_name` is in system `system_seed` (planets outside TIERS
## always are).
static func includes(system_seed: int, body_name: String) -> bool:
	return not TIERS.has(body_name) or roll(system_seed).has(body_name)


static func chance(body_name: String) -> float:
	return TIER_CHANCE[TIERS.get(body_name, 1)]


static func tier(body_name: String) -> int:
	return TIERS.get(body_name, 0)


## 1 low .. 4 extreme; 1 for a planet not in the table.
static func difficulty(body_name: String) -> int:
	return DIFFICULTY.get(body_name, 1)


static func _weighted(names: Array, rng: RandomNumberGenerator) -> String:
	var total := 0.0
	for name: String in names:
		total += chance(name)
	var pick: float = rng.randf() * total
	for name: String in names:
		pick -= chance(name)
		if pick <= 0.0:
			return name
	return names[names.size() - 1]

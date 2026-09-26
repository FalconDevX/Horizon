class_name ShipStats
extends RefCounted
## Aggregated ship totals recalculated whenever the module layout changes.

var mass: float = 0.0
var health: float = 0.0
var durability: float = 0.0
var thrust: float = 0.0
var correction_thrust: float = 0.0
var fuel_consumption: float = 0.0
var fuel_capacity: float = 0.0
var energy_consumption: float = 0.0
var energy_generation: float = 0.0
var energy_capacity: float = 0.0
## Parts of energy_consumption drawn only at times (ship.gd update_resources):
## engines while thrusting, shields while recharging, weapons per shot.
var energy_engines: float = 0.0
var energy_shields: float = 0.0
var energy_weapons: float = 0.0
var shield_strength: float = 0.0
var damage: float = 0.0
var repair_rate: float = 0.0
var module_count: int = 0
var max_heat: float = 0.0 ## Highest engine overheat limit among engines
var hulls_linked: bool = true
## Ship-wide: ≥1 RCS on each outer side except the main-engine side.
var rcs_sides_ok: bool = true


func to_dictionary() -> Dictionary:
	return {
		"mass": mass,
		"health": health,
		"durability": durability,
		"thrust": thrust,
		"correction_thrust": correction_thrust,
		"fuel_consumption": fuel_consumption,
		"fuel_capacity": fuel_capacity,
		"energy_consumption": energy_consumption,
		"energy_generation": energy_generation,
		"energy_capacity": energy_capacity,
		"energy_engines": energy_engines,
		"energy_shields": energy_shields,
		"energy_weapons": energy_weapons,
		"shield_strength": shield_strength,
		"damage": damage,
		"repair_rate": repair_rate,
		"module_count": module_count,
		"max_heat": max_heat,
		"net_energy": energy_generation - energy_consumption,
		"thrust_to_weight": thrust / maxf(mass, 0.001),
		"hulls_linked": hulls_linked,
		"rcs_sides_ok": rcs_sides_ok,
	}


func duplicate_stats() -> ShipStats:
	var copy := ShipStats.new()
	copy.mass = mass
	copy.health = health
	copy.durability = durability
	copy.thrust = thrust
	copy.correction_thrust = correction_thrust
	copy.fuel_consumption = fuel_consumption
	copy.fuel_capacity = fuel_capacity
	copy.energy_consumption = energy_consumption
	copy.energy_generation = energy_generation
	copy.energy_capacity = energy_capacity
	copy.energy_engines = energy_engines
	copy.energy_shields = energy_shields
	copy.energy_weapons = energy_weapons
	copy.shield_strength = shield_strength
	copy.damage = damage
	copy.repair_rate = repair_rate
	copy.module_count = module_count
	copy.max_heat = max_heat
	copy.hulls_linked = hulls_linked
	copy.rcs_sides_ok = rcs_sides_ok
	return copy

class_name ShipStats
extends RefCounted
## Aggregated ship totals recalculated whenever the module layout changes.

var mass: float = 0.0
var health: float = 0.0
var durability: float = 0.0
var thrust: float = 0.0
var fuel_consumption: float = 0.0
var fuel_capacity: float = 0.0
var energy_consumption: float = 0.0
var energy_generation: float = 0.0
var energy_capacity: float = 0.0
var shield_strength: float = 0.0
var damage: float = 0.0
var repair_rate: float = 0.0
var module_count: int = 0
var occupied_cells: int = 0
var capacity: int = 0
var max_heat: float = 0.0 ## Highest engine overheat limit among engines
var hulls_linked: bool = true


func to_dictionary() -> Dictionary:
	return {
		"mass": mass,
		"health": health,
		"durability": durability,
		"thrust": thrust,
		"fuel_consumption": fuel_consumption,
		"fuel_capacity": fuel_capacity,
		"energy_consumption": energy_consumption,
		"energy_generation": energy_generation,
		"energy_capacity": energy_capacity,
		"shield_strength": shield_strength,
		"damage": damage,
		"repair_rate": repair_rate,
		"module_count": module_count,
		"occupied_cells": occupied_cells,
		"capacity": capacity,
		"max_heat": max_heat,
		"net_energy": energy_generation - energy_consumption,
		"thrust_to_weight": thrust / maxf(mass, 0.001),
		"hulls_linked": hulls_linked,
	}


func duplicate_stats() -> ShipStats:
	var copy := ShipStats.new()
	copy.mass = mass
	copy.health = health
	copy.durability = durability
	copy.thrust = thrust
	copy.fuel_consumption = fuel_consumption
	copy.fuel_capacity = fuel_capacity
	copy.energy_consumption = energy_consumption
	copy.energy_generation = energy_generation
	copy.energy_capacity = energy_capacity
	copy.shield_strength = shield_strength
	copy.damage = damage
	copy.repair_rate = repair_rate
	copy.module_count = module_count
	copy.occupied_cells = occupied_cells
	copy.capacity = capacity
	copy.max_heat = max_heat
	copy.hulls_linked = hulls_linked
	return copy

class_name ControlModel
extends RefCounted

# Jedna zasada sterowania dla kosmosu, lądowania, autopilota i powierzchni.
# Konstrukcja daje paliwo, pancerz i wyposażenie — nie zmienia przyspieszenia ani obrotu.
const MAIN_ACCELERATION := 12.0
const RCS_ACCELERATION := 4.0
const TURN_ACCELERATION := 5.5
const SURFACE_SPEED := 120.0
const FUEL_BURN_MAIN := 2.4
const FUEL_BURN_RCS := 0.45
const GROUND_CLEARANCE := 2.0
const LAUNCH_CLEARANCE := 480.0
const LAUNCH_KICK := 18.0
const EXIT_MARGIN := 80.0
const APPROACH_SPEED := 32.0


static func has_main_engine(ship) -> bool:
	return ship != null and ship.graph != null and ship.graph.stats().engine_count >= 1


static func main_acceleration(ship) -> float:
	if ship == null or ship.fuel <= 0.0 or not has_main_engine(ship):
		return 0.0
	return MAIN_ACCELERATION


static func rcs_acceleration(ship) -> float:
	if ship == null or ship.fuel <= 0.0:
		return 0.0
	return RCS_ACCELERATION


static func yaw_acceleration(_ship) -> float:
	return TURN_ACCELERATION


static func consume_main(ship, throttle_abs: float, dt: float) -> void:
	if ship == null or throttle_abs <= 0.0 or dt <= 0.0:
		return
	ship.graph.consume_fuel(FUEL_BURN_MAIN * throttle_abs * dt)
	ship.fuel = ship.graph.fuel_total()


static func consume_rcs(ship, dt: float) -> void:
	if ship == null or dt <= 0.0:
		return
	ship.graph.consume_fuel(FUEL_BURN_RCS * dt)
	ship.fuel = ship.graph.fuel_total()

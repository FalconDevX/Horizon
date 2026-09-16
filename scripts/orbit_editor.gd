class_name OrbitEditor
extends RefCounted

const COARSE_RADIUS_STEP := 0.02
const FINE_RADIUS_STEP := 0.0025
const COARSE_SPEED_STEP := 0.02
const FINE_SPEED_STEP := 0.0025

var active: bool = false
var planet: ProcPlanet = null
var original_radius: float = 0.0
var original_speed: float = 0.0
var draft_radius: float = 0.0
var draft_speed: float = 0.0
var last_error: String = ""


func begin(target: ProcPlanet) -> bool:
	if target == null:
		return false
	planet = target
	original_radius = target.orbit_radius
	original_speed = target.orbit_speed
	draft_radius = original_radius
	draft_speed = original_speed
	last_error = ""
	active = true
	return true


func cancel() -> void:
	if not active or planet == null:
		active = false
		planet = null
		return
	planet.orbit_radius = original_radius
	planet.orbit_speed = original_speed
	planet.tick(0.0)
	active = false
	planet = null
	last_error = ""


func commit() -> bool:
	if not active or planet == null:
		return false
	active = false
	planet = null
	last_error = ""
	return true


func adjust_radius(universe: Universe, finer: bool, enlarge: bool) -> bool:
	if not active or planet == null or universe == null:
		return false
	var step := FINE_RADIUS_STEP if finer else COARSE_RADIUS_STEP
	var factor := 1.0 + (step if enlarge else -step)
	var next_radius := maxf(draft_radius * factor, 1.0)
	return _try_set_radius(universe, next_radius)


func restore_circular(universe: Universe) -> bool:
	if not active or planet == null or universe == null:
		return false
	var direction := 1.0 if draft_speed >= 0.0 else -1.0
	var circular := universe.circular_orbit_speed(planet, draft_radius)
	draft_speed = direction * circular
	planet.orbit_speed = draft_speed
	planet.tick(0.0)
	last_error = ""
	return true


func adjust_speed(finer: bool, faster: bool) -> bool:
	if not active or planet == null:
		return false
	var step := FINE_SPEED_STEP if finer else COARSE_SPEED_STEP
	var factor := 1.0 + (step if faster else -step)
	draft_speed *= factor
	planet.orbit_speed = draft_speed
	planet.tick(0.0)
	last_error = ""
	return true


func parent_name() -> String:
	if planet == null:
		return "—"
	if planet.parent_body is ProcPlanet:
		return (planet.parent_body as ProcPlanet).planet_name
	return "słońce"


func period(universe: Universe) -> float:
	if planet == null or universe == null:
		return INF
	return OrbitalPhysics.orbital_period(universe.parent_mu(planet), draft_radius)


func linear_speed() -> float:
	return absf(draft_speed * draft_radius)


func _try_set_radius(universe: Universe, next_radius: float) -> bool:
	var check := universe.validate_orbit_radius(planet, next_radius)
	if not check["ok"]:
		last_error = check["reason"]
		return false
	var direction := 1.0 if draft_speed >= 0.0 else -1.0
	draft_radius = next_radius
	draft_speed = direction * universe.circular_orbit_speed(planet, draft_radius)
	planet.orbit_radius = draft_radius
	planet.orbit_speed = draft_speed
	planet.tick(0.0)
	last_error = ""
	return true

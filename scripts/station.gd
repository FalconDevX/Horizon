class_name Station
extends Node2D

var station_name: String = "Stacja"
var parent_planet: ProcPlanet
var orbit_radius: float = 1000.0
var orbit_angle: float = 0.0
var orbit_speed: float = 0.04


func configure(p: ProcPlanet, p_name: String, rng: RandomNumberGenerator) -> void:
	parent_planet = p
	station_name = p_name
	orbit_radius = p.radius * rng.randf_range(1.55, 1.9)
	orbit_angle = rng.randf() * TAU
	orbit_speed = OrbitalPhysics.circular_speed(p.mu, orbit_radius) / orbit_radius
	z_index = 4
	tick(0.0)


func tick(delta: float) -> void:
	if parent_planet == null:
		return
	orbit_angle += orbit_speed * delta
	global_position = parent_planet.global_position + Vector2(cos(orbit_angle), sin(orbit_angle)) * orbit_radius
	queue_redraw()


func inertial_velocity() -> Vector2:
	var pv := parent_planet.inertial_velocity() if parent_planet else Vector2.ZERO
	var tangent := Vector2(-sin(orbit_angle), cos(orbit_angle))
	return pv + tangent * (orbit_speed * orbit_radius)


func _draw() -> void:
	var r := 28.0
	draw_arc(Vector2.ZERO, r, 0.0, TAU, 32, Color(0.55, 0.78, 0.9, 0.95), 4.0, true)
	draw_arc(Vector2.ZERO, r * 0.55, 0.0, TAU, 24, Color(0.7, 0.85, 1.0, 0.8), 2.0, true)
	for i in 6:
		var a := TAU * float(i) / 6.0
		draw_line(Vector2.from_angle(a) * r * 0.55, Vector2.from_angle(a) * r, Color(0.65, 0.82, 0.95, 0.7), 2.0, true)
	draw_circle(Vector2.ZERO, 6.0, Color(0.85, 0.95, 1.0))

class_name OrbitalFrame
extends RefCounted

var body: ProcPlanet = null
var center_position: Vector2 = Vector2.ZERO
var center_velocity: Vector2 = Vector2.ZERO
var mu: float = 0.0
var body_radius: float = 0.0


func _init(p_body: ProcPlanet = null, universe: Universe = null) -> void:
	body = p_body
	update(universe)


func update(universe: Universe = null) -> void:
	if is_instance_valid(body):
		center_position = body.global_position
		center_velocity = body.inertial_velocity()
		mu = body.mu
		body_radius = body.radius
	elif universe != null:
		center_position = Vector2.ZERO
		center_velocity = Vector2.ZERO
		mu = universe.sun_mu()
		body_radius = universe.sun_radius
	else:
		center_position = Vector2.ZERO
		center_velocity = Vector2.ZERO
		if mu <= 0.0:
			mu = 10000000.0
		if body_radius <= 0.0:
			body_radius = 6000.0


func relative_position(world_position: Vector2) -> Vector2:
	return world_position - center_position


func relative_velocity(world_velocity: Vector2) -> Vector2:
	return world_velocity - center_velocity


func world_position(rel_position: Vector2) -> Vector2:
	return rel_position + center_position


func world_velocity(rel_velocity: Vector2) -> Vector2:
	return rel_velocity + center_velocity


func prograde(rel_pos: Vector2, rel_vel: Vector2) -> Vector2:
	if rel_vel.length_squared() > 0.0001:
		return rel_vel.normalized()
	var radial := radial_out(rel_pos)
	return radial.orthogonal()


func retrograde(rel_pos: Vector2, rel_vel: Vector2) -> Vector2:
	return -prograde(rel_pos, rel_vel)


func radial_out(rel_pos: Vector2) -> Vector2:
	if rel_pos.length_squared() > 0.0001:
		return rel_pos.normalized()
	return Vector2.RIGHT


func radial_in(rel_pos: Vector2) -> Vector2:
	return -radial_out(rel_pos)

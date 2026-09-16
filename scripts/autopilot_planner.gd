class_name AutopilotPlanner
extends RefCounted

static func plan_orbit_change(state: OrbitState, target_altitude: float, target_mu: float) -> Array[Maneuver]:
	var maneuvers: Array[Maneuver] = []
	var target_radius = target_altitude + (state.radius - state.altitude) # target.radius + altitude
	
	# If eccentric, first circularize at periapsis or apoapsis
	if not state.is_near_circular and state.is_bound:
		# Just wait for apsis and circularize.
		var circular_v = OrbitalPhysics.circular_speed(target_mu, state.periapsis_radius)
		var pe_v = OrbitalPhysics.escape_speed(target_mu, state.periapsis_radius) # No, actual speed at PE.
		# Let's simplify.
	return maneuvers

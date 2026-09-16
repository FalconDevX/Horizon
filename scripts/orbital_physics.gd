class_name OrbitalPhysics
extends RefCounted


static func mu_from_surface_gravity(surface_g: float, radius: float) -> float:
	return surface_g * radius * radius


static func gravity_at(point: Vector2, center: Vector2, mu: float, min_radius: float = 1.0) -> Vector2:
	var toward := center - point
	var r2 := maxf(toward.length_squared(), min_radius * min_radius)
	if toward.length_squared() < 0.000001:
		return Vector2.ZERO
	return toward * (mu / (r2 * sqrt(r2)))


static func circular_speed(mu: float, radius: float) -> float:
	return sqrt(maxf(mu, 0.0) / maxf(radius, 1.0))


static func escape_speed(mu: float, radius: float) -> float:
	return sqrt(2.0 * maxf(mu, 0.0) / maxf(radius, 1.0))


static func orbital_period(mu: float, semi_major_axis: float) -> float:
	if mu <= 0.0 or semi_major_axis <= 0.0:
		return INF
	return TAU * sqrt(pow(semi_major_axis, 3.0) / mu)


static func elements(relative_position: Vector2, relative_velocity: Vector2, mu: float) -> Dictionary:
	var r := maxf(relative_position.length(), 1.0)
	var v2 := relative_velocity.length_squared()
	var energy := 0.5 * v2 - mu / r
	var angular_momentum := relative_position.cross(relative_velocity)
	var eccentricity_vector := (
		relative_position * (v2 - mu / r)
		- relative_velocity * relative_position.dot(relative_velocity)
	) / maxf(mu, 1.0)
	var eccentricity := eccentricity_vector.length()
	var bound := energy < 0.0 and eccentricity < 1.0
	var semi_major_axis := INF
	var periapsis := 0.0
	var apoapsis := INF
	if absf(energy) > 0.000001:
		semi_major_axis = -mu / (2.0 * energy)
	if bound:
		periapsis = semi_major_axis * (1.0 - eccentricity)
		apoapsis = semi_major_axis * (1.0 + eccentricity)
	else:
		periapsis = angular_momentum * angular_momentum / maxf(mu * (1.0 + eccentricity), 1.0)
	var radial := relative_position / r
	var times := apsidal_times(relative_position, relative_velocity, mu)
	return {
		"energy": energy,
		"h": angular_momentum,
		"e": eccentricity,
		"e_vec": eccentricity_vector,
		"bound": bound,
		"a": semi_major_axis,
		"pe": periapsis,
		"ap": apoapsis,
		"radial_speed": relative_velocity.dot(radial),
		"tangent_speed": relative_velocity.dot(radial.orthogonal()),
		"time_to_pe": times["time_to_pe"],
		"time_to_ap": times["time_to_ap"],
		"period": times["period"],
	}


static func orbit_kind(bound: bool, periapsis: float, body_radius: float) -> String:
	if periapsis <= body_radius:
		return "kolizyjna"
	if not bound:
		return "ucieczkowa"
	return "stabilna"


static func _wrap_tau(value: float) -> float:
	return wrapf(value, 0.0, TAU)


static func _true_anomaly(relative_position: Vector2, eccentricity_vector: Vector2) -> float:
	if eccentricity_vector.length_squared() < 0.000001:
		return 0.0
	return atan2(
		eccentricity_vector.cross(relative_position),
		eccentricity_vector.dot(relative_position)
	)


static func _mean_anomaly_from_true(true_anomaly: float, eccentricity: float) -> float:
	var e := clampf(eccentricity, 0.0, 0.999)
	var nu := true_anomaly
	var eccentric := atan2(sqrt(1.0 - e * e) * sin(nu), e + cos(nu))
	return eccentric - e * sin(eccentric)


static func apsidal_times(relative_position: Vector2, relative_velocity: Vector2, mu: float) -> Dictionary:
	var r := maxf(relative_position.length(), 1.0)
	var v2 := relative_velocity.length_squared()
	var energy := 0.5 * v2 - mu / r
	var eccentricity_vector := (
		relative_position * (v2 - mu / r)
		- relative_velocity * relative_position.dot(relative_velocity)
	) / maxf(mu, 1.0)
	var eccentricity := eccentricity_vector.length()
	var bound := energy < 0.0 and eccentricity < 1.0
	if not bound or absf(energy) <= 0.000001:
		return {"time_to_pe": INF, "time_to_ap": INF, "period": INF}
	var semi_major_axis := -mu / (2.0 * energy)
	var period := orbital_period(mu, semi_major_axis)
	if period == INF:
		return {"time_to_pe": INF, "time_to_ap": INF, "period": INF}
	var nu := _true_anomaly(relative_position, eccentricity_vector)
	var mean := _wrap_tau(_mean_anomaly_from_true(nu, eccentricity))
	var time_to_pe := _wrap_tau(-mean) / TAU * period
	var time_to_ap := _wrap_tau(PI - mean) / TAU * period
	return {
		"time_to_pe": time_to_pe,
		"time_to_ap": time_to_ap,
		"period": period,
	}


static func sample_conic(relative_position: Vector2, relative_velocity: Vector2, mu: float, count: int = 960, max_radius: float = -1.0) -> PackedVector2Array:
	var result := PackedVector2Array()
	var el := elements(relative_position, relative_velocity, mu)
	var ecc: float = el["e"]
	var h: float = el["h"]
	if absf(h) < 0.00001:
		return result
	var p := h * h / maxf(mu, 1.0)
	var peri_direction: Vector2 = el["e_vec"]
	if peri_direction.length_squared() < 0.000001:
		peri_direction = relative_position.normalized()
	else:
		peri_direction = peri_direction.normalized()
	var start_a := -PI
	var finish := PI
	if not el["bound"]:
		var asymptote := acos(clampf(-1.0 / maxf(ecc, 1.00001), -1.0, 1.0))
		var safe_limit := acos(clampf((0.035 - 1.0) / maxf(ecc, 1.00001), -1.0, 1.0))
		var limit := minf(asymptote - 0.04, safe_limit)
		start_a = -limit
		finish = limit
	for i in count:
		var anomaly := lerpf(start_a, finish, float(i) / float(maxi(count - 1, 1)))
		var denominator := 1.0 + ecc * cos(anomaly)
		if denominator <= 0.015:
			continue
		var radius := p / denominator
		if max_radius > 0.0 and radius > max_radius:
			continue
		result.append(peri_direction.rotated(anomaly) * radius)
	return result

static func calculate_state(relative_position: Vector2, relative_velocity: Vector2, mu: float, body_radius: float) -> OrbitState:
	var state := OrbitState.new()
	state.radius = maxf(relative_position.length(), 1.0)
	state.altitude = state.radius - body_radius
	state.total_velocity = relative_velocity.length()
	
	var radial := relative_position / state.radius
	state.radial_velocity = relative_velocity.dot(radial)
	state.tangential_velocity = relative_velocity.dot(radial.orthogonal())
	
	var v2 := relative_velocity.length_squared()
	state.specific_energy = 0.5 * v2 - mu / state.radius
	state.angular_momentum = relative_position.cross(relative_velocity)
	
	state.eccentricity_vector = (
		relative_position * (v2 - mu / state.radius)
		- relative_velocity * relative_position.dot(relative_velocity)
	) / maxf(mu, 1.0)
	state.eccentricity = state.eccentricity_vector.length()
	state.is_bound = state.specific_energy < 0.0 and state.eccentricity < 1.0
	state.is_near_circular = state.is_bound and state.eccentricity < 0.03
	
	state.semi_major_axis = INF
	state.periapsis_radius = 0.0
	state.apoapsis_radius = INF
	
	if absf(state.specific_energy) > 0.000001:
		state.semi_major_axis = -mu / (2.0 * state.specific_energy)
	
	if state.is_bound:
		state.periapsis_radius = state.semi_major_axis * (1.0 - state.eccentricity)
		state.apoapsis_radius = state.semi_major_axis * (1.0 + state.eccentricity)
	else:
		state.periapsis_radius = state.angular_momentum * state.angular_momentum / maxf(mu * (1.0 + state.eccentricity), 1.0)
		
	state.periapsis_altitude = state.periapsis_radius - body_radius
	state.apoapsis_altitude = state.apoapsis_radius - body_radius
	
	var times := apsidal_times(relative_position, relative_velocity, mu)
	state.orbital_period = times["period"]
	state.time_to_pe = times["time_to_pe"]
	state.time_to_ap = times["time_to_ap"]
	
	return state

class_name OrbitMath
extends RefCounted



static func stumpff_c(z: float) -> float:
	if z > 1e-6:
		return (1.0 - cos(sqrt(z))) / z
	if z < -1e-6:
		return (cosh(sqrt(-z)) - 1.0) / -z
	return 0.5 - z / 24.0


static func stumpff_s(z: float) -> float:
	if z > 1e-6:
		var s: float = sqrt(z)
		return (s - sin(s)) / (s * s * s)
	if z < -1e-6:
		var s: float = sqrt(-z)
		return (sinh(s) - s) / (s * s * s)
	return 1.0 / 6.0 - z / 120.0


static func kepler_propagate(r0: Vector2, v0: Vector2, dt: float, mu: float) -> Array:
	var r0m: float = r0.length()
	var vr0: float = r0.dot(v0) / r0m
	var alpha: float = 2.0 / r0m - v0.length_squared() / mu
	var sqmu: float = sqrt(mu)

	if alpha > 1e-12:
		dt = fmod(dt, TAU * sqrt(pow(1.0 / alpha, 3) / mu))

	if absf(dt) < 1e-9:
		return [r0, v0]

	var x: float
	if alpha > 1e-12:
		x = sqmu * dt * alpha
	elif alpha < -1e-12:
		var a: float = 1.0 / alpha
		var sdt: float = signf(dt)
		var num: float = -2.0 * mu * alpha * dt
		var den: float = r0.dot(v0) + sdt * sqrt(-mu * a) * (1.0 - r0m * alpha)
		if den != 0.0 and num / den > 0.0:
			x = sdt * sqrt(-a) * log(num / den)
		else:
			x = sqmu * absf(alpha) * dt
	else:
		x = sqmu * dt / r0m

	for _i in range(100):
		var z: float = alpha * x * x
		var c: float = stumpff_c(z)
		var s: float = stumpff_s(z)
		var f: float = (
			r0m * vr0 / sqmu * x * x * c
			+ (1.0 - alpha * r0m) * x * x * x * s
			+ r0m * x
			- sqmu * dt
		)
		var df: float = (
			r0m * vr0 / sqmu * x * (1.0 - alpha * x * x * s)
			+ (1.0 - alpha * r0m) * x * x * c
			+ r0m
		)
		var step: float = f / df
		x -= step
		if absf(step) < 1e-9 * maxf(1.0, absf(x)):
			break

	var z2: float = alpha * x * x
	var c2: float = stumpff_c(z2)
	var s2: float = stumpff_s(z2)
	var fl: float = 1.0 - x * x / r0m * c2
	var gl: float = dt - x * x * x * s2 / sqmu
	var r: Vector2 = r0 * fl + v0 * gl
	var rm: float = r.length()
	var fdot: float = sqmu / (rm * r0m) * (alpha * x * x * x * s2 - x)
	var gdot: float = 1.0 - x * x / rm * c2
	return [r, r0 * fdot + v0 * gdot]


static func elements(r: Vector2, v: Vector2, mu: float) -> Dictionary:
	var rm: float = r.length()
	var v2: float = v.length_squared()
	var h: float = r.cross(v)
	var energy: float = v2 / 2.0 - mu / rm
	var evec: Vector2 = (r * (v2 - mu / rm) - v * r.dot(v)) / mu
	var e: float = evec.length()
	var p: float = h * h / mu
	var sgn: float = 1.0 if h >= 0.0 else -1.0
	var ehat: Vector2 = r.normalized()
	var nu: float = 0.0

	if e > 1e-9:
		ehat = evec / e
		nu = atan2(sgn * ehat.cross(r), ehat.dot(r))

	return {
		"h": h,
		"energy": energy,
		"e": e,
		"ehat": ehat,
		"p": p,
		"sgn": sgn,
		"nu": nu,
		"rp": p / (1.0 + e),
		"ra": p / (1.0 - e) if e < 1.0 else INF,
		"a": -mu / (2.0 * energy) if absf(energy) > 1e-15 else INF,
	}


static func orbital_period(a: float, mu: float) -> float:
	return TAU * sqrt(a * a * a / mu)


static func half_period(a: float, mu: float) -> float:
	return PI * sqrt(a * a * a / mu)


static func time_to_periapsis(el: Dictionary, mu: float) -> float:
	var e: float = el.e
	var a: float = el.a
	var nu: float = el.nu

	if e < 1.0:
		var n: float = sqrt(mu / (a * a * a))
		var ea: float = 2.0 * atan2(sqrt(1.0 - e) * sin(nu / 2.0), sqrt(1.0 + e) * cos(nu / 2.0))
		return fposmod(-(ea - e * sin(ea)), TAU) / n

	var nh: float = sqrt(mu / pow(-a, 3))
	var arg: float = clampf(sqrt((e - 1.0) / (e + 1.0)) * tan(nu / 2.0), -0.999999, 0.999999)
	var fh: float = 2.0 * atanh(arg)
	return -(e * sinh(fh) - fh) / nh


static func time_to_apoapsis(el: Dictionary, mu: float) -> float:
	var e: float = el.e
	var a: float = el.a
	var nu: float = el.nu
	var n: float = sqrt(mu / (a * a * a))
	var ea: float = 2.0 * atan2(sqrt(1.0 - e) * sin(nu / 2.0), sqrt(1.0 + e) * cos(nu / 2.0))
	return fposmod(PI - (ea - e * sin(ea)), TAU) / n


static func hyperbolic_time_to_radius(rp: float, vinf: float, r: float, mu: float) -> float:
	var a: float = -mu / (vinf * vinf)
	var e: float = 1.0 - rp / a
	var fh: float = acosh(maxf(1.0, (1.0 - r / a) / e))
	return (e * sinh(fh) - fh) / sqrt(mu / pow(-a, 3))


## Lambert's problem, single revolution, universal variables (Curtis, alg. 5.2):
## the velocity needed at r1 to reach r2 after `tof` seconds round a body of
## gravitational parameter mu. `prograde` picks the counter-clockwise transfer
## (the way the planets orbit here). Returns {ok, v1, v2}.
static func lambert(r1: Vector2, r2: Vector2, tof: float, mu: float, prograde: bool = true) -> Dictionary:
	var fail := {"ok": false, "v1": Vector2.ZERO, "v2": Vector2.ZERO}
	var r1n: float = r1.length()
	var r2n: float = r2.length()
	if r1n < 1e-6 or r2n < 1e-6 or tof <= 0.0:
		return fail

	var cos_dtheta: float = clampf(r1.dot(r2) / (r1n * r2n), -1.0, 1.0)
	var dtheta: float = acos(cos_dtheta)
	var cross_z: float = r1.x * r2.y - r1.y * r2.x
	if (prograde and cross_z < 0.0) or (not prograde and cross_z >= 0.0):
		dtheta = TAU - dtheta
	# Degenerate geometry: the transfer plane is undefined 180 degrees apart.
	if absf(1.0 - cos(dtheta)) < 1e-8 or absf(sin(dtheta)) < 1e-6:
		return fail

	var a_coef: float = sin(dtheta) * sqrt(r1n * r2n / (1.0 - cos(dtheta)))
	var sqrt_mu: float = sqrt(mu)

	# y(z) must stay positive; F(z) grows with z, so bisect for F(z) = 0.
	# Very negative z is a fast hyperbola; cosh stays finite well past -2000.
	var z_lo: float = -2000.0
	var z_hi: float = 4.0 * PI * PI - 1e-6
	for _i in range(200):
		if _lambert_y(z_lo, r1n, r2n, a_coef) > 0.0:
			break
		z_lo += 0.05 * (z_hi - z_lo)
	if _lambert_y(z_lo, r1n, r2n, a_coef) <= 0.0:
		return fail
	if _lambert_f(z_hi, r1n, r2n, a_coef, sqrt_mu, tof) < 0.0:
		return fail # would need more than one revolution
	if _lambert_f(z_lo, r1n, r2n, a_coef, sqrt_mu, tof) > 0.0:
		return fail

	var z: float = 0.0
	for _i in range(80):
		z = 0.5 * (z_lo + z_hi)
		if _lambert_f(z, r1n, r2n, a_coef, sqrt_mu, tof) > 0.0:
			z_hi = z
		else:
			z_lo = z

	var y: float = _lambert_y(z, r1n, r2n, a_coef)
	if y <= 0.0:
		return fail
	var f: float = 1.0 - y / r1n
	var g: float = a_coef * sqrt(y / mu)
	var g_dot: float = 1.0 - y / r2n
	if absf(g) < 1e-9:
		return fail
	return {"ok": true, "v1": (r2 - f * r1) / g, "v2": (g_dot * r2 - r1) / g}


static func _lambert_y(z: float, r1n: float, r2n: float, a_coef: float) -> float:
	return r1n + r2n + a_coef * (z * stumpff_s(z) - 1.0) / sqrt(stumpff_c(z))


static func _lambert_f(z: float, r1n: float, r2n: float, a_coef: float, sqrt_mu: float, tof: float) -> float:
	var y: float = _lambert_y(z, r1n, r2n, a_coef)
	if y <= 0.0:
		return -INF
	var c: float = stumpff_c(z)
	return pow(y / c, 1.5) * stumpff_s(z) + a_coef * sqrt(y) - sqrt_mu * tof


static func tangent_dir(r: Vector2, sgn: float) -> Vector2:
	var rh: Vector2 = r.normalized()
	return Vector2(-rh.y, rh.x) * sgn


static func solve_transfer(r0: Vector2, v_guess: Vector2, tof: float, target: Vector2, mu: float) -> Vector2:
	var v: Vector2 = v_guess

	for _i in range(60):
		var r: Vector2 = kepler_propagate(r0, v, tof, mu)[0]
		var miss: Vector2 = r - target

		if miss.length() < 1.0:
			return v

		var dh: float = 1e-4 * maxf(1.0, v.length())
		var rx: Vector2 = kepler_propagate(r0, v + Vector2(dh, 0.0), tof, mu)[0]
		var ry: Vector2 = kepler_propagate(r0, v + Vector2(0.0, dh), tof, mu)[0]
		var step: Vector2 = solve_2x2((rx - r) / dh, (ry - r) / dh, -miss)

		if step == Vector2.INF:
			return Vector2.INF

		var max_step: float = 0.25 * maxf(1.0, v.length())
		if step.length() > max_step:
			step = step.normalized() * max_step

		v += step

	return Vector2.INF


static func solve_2x2(col_x: Vector2, col_y: Vector2, rhs: Vector2) -> Vector2:
	var det: float = col_x.x * col_y.y - col_y.x * col_x.y
	if absf(det) < 1e-15:
		return Vector2.INF
	return Vector2(
		(col_y.y * rhs.x - col_y.x * rhs.y) / det,
		(-col_x.y * rhs.x + col_x.x * rhs.y) / det
	)


static func propagate_numeric(
	r0: Vector2,
	v0: Vector2,
	tof: float,
	mu_sun: float,
	planets: Array,
	t0: float
) -> Array:
	var t: float = 0.0
	var r: Vector2 = r0
	var v: Vector2 = v0
	var acc: Array = _numeric_acceleration(r, t0, mu_sun, planets)
	var a: Vector2 = acc[0]
	var dmin: float = acc[1]

	while t < tof - 1e-9:
		var dt: float = minf(minf(maxf(0.004 * dmin, 0.5), 40.0), tof - t)
		r += v * dt + a * (0.5 * dt * dt)
		acc = _numeric_acceleration(r, t0 + t + dt, mu_sun, planets)
		v += (a + acc[0]) * (0.5 * dt)
		a = acc[0]
		dmin = acc[1]
		t += dt

	return [r, v]


static func closest_approach_numeric(
	r0: Vector2,
	v0: Vector2,
	t_max: float,
	mu_sun: float,
	planets: Array,
	target_index: int,
	target_soi: float
) -> Array:
	var t: float = 0.0
	var r: Vector2 = r0
	var v: Vector2 = v0
	var acc: Array = _numeric_acceleration(r, 0.0, mu_sun, planets)
	var a: Vector2 = acc[0]
	var dmin: float = acc[1]
	var target: Dictionary = planets[target_index]
	var best_distance: float = INF
	var best_time: float = 0.0
	var best_sign: float = 1.0

	while t < t_max:
		var dt: float = minf(maxf(0.003 * dmin, 0.25), 40.0)
		r += v * dt + a * (0.5 * dt * dt)
		acc = _numeric_acceleration(r, t + dt, mu_sun, planets)
		v += (a + acc[0]) * (0.5 * dt)
		a = acc[0]
		dmin = acc[1]
		t += dt

		var angle: float = target.omega * t
		var rel: Vector2 = r - target.pos.rotated(angle)
		var distance: float = rel.length()

		if distance < best_distance:
			var target_velocity: Vector2 = target.vel.rotated(angle)
			best_distance = distance
			best_time = t
			best_sign = 1.0 if rel.cross(v - target_velocity) >= 0.0 else -1.0
		elif distance > best_distance * 1.05 and best_distance < target_soi:
			break

	return [best_sign * best_distance, best_time]


static func _numeric_acceleration(p: Vector2, t: float, mu_sun: float, planets: Array) -> Array:
	var d2: float = p.length_squared()
	var d: float = sqrt(d2)
	var a: Vector2 = p * (-mu_sun / (d2 * d))
	var dmin: float = INF
	var positions: Array[Vector2] = []

	for planet in planets:
		var planet_position: Vector2 = planet.pos.rotated(planet.omega * t)
		positions.append(planet_position)
		var offset: Vector2 = planet_position - p
		var od2: float = offset.length_squared()
		var od: float = sqrt(od2)
		dmin = minf(dmin, od)
		a += offset * (planet.mu / (od2 * od))

	for i in range(planets.size()):
		if p.distance_squared_to(positions[i]) > planets[i].soi * planets[i].soi:
			continue
		for j in range(planets.size()):
			if j == i:
				continue
			var between: Vector2 = positions[j] - positions[i]
			var bd2: float = between.length_squared()
			a -= between * (planets[j].mu / (bd2 * sqrt(bd2)))
		break

	return [a, dmin]

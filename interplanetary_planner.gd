class_name InterplanetaryPlanner
extends RefCounted


enum Stage {
	COAST_TO_BURN,
	ESCAPE_BURN,
	ESCAPE_COAST,
	TRANSFER_BURN,
	TRANSFER_COAST,
}

enum Stop { AT_TIME, AT_EXIT, AT_CLOSEST }

const SCAN_HALF_WIDTH := 2.0
const SAMPLES_PER_PERIOD := 16
const REFINE_ITERATIONS := 8
const VERIFIED_CANDIDATES := 4
const TARGET_ITERATIONS := 20
const TARGET_TOLERANCE := 15.0
const CORRECTION_TOLERANCE := 40.0
const MAX_TARGET_STEP := 50.0
const BURN_DT := 0.5
const MIN_DT := 0.25
const MAX_DT := 40.0
const DT_FACTOR := 0.003
const MAX_ESCAPE_TIME := 30000.0
const RECORD_SPACING := 25.0


static func simulate(ctx: Dictionary, st: Dictionary, stop: int, t_stop: float, record: bool) -> Dictionary:
	var t0: float = ctx.t0
	var sun_pos: Vector2 = ctx.sun_pos
	var mu_sun: float = ctx.mu_sun
	var rel: PackedVector2Array = ctx.rel
	var omega: PackedFloat64Array = ctx.omega
	var mu: PackedFloat64Array = ctx.mu
	var count: int = rel.size()
	var dep: int = ctx.dep
	var target: int = ctx.target
	var acc: float = ctx.acc
	var exit_radius: float = ctx.exit_radius
	var soi: PackedFloat64Array = ctx.soi
	var target_soi: float = soi[target]
	var mu_dep: float = mu[dep]

	var p: Vector2 = st.pos
	var v: Vector2 = st.vel
	var t: float = st.t
	var stage: int = st.stage
	var t_start: float = st.get("t_start", INF)
	var eps_target: float = st.get("eps_target", 0.0)
	var dv: Vector2 = st.get("dv", Vector2.ZERO)
	var delivered: Vector2 = st.get("delivered", Vector2.ZERO)

	var out := {
		"ok": false,
		"burn1_pos": Vector2.INF,
		"burn1_t": INF,
		"burn2_pos": Vector2.INF,
		"burn2_t": INF,
		"closest": INF,
		"closest_signed": INF,
		"closest_t": INF,
		"closest_pos": Vector2.INF,
		"exit_state": {},
	}
	var points := PackedVector2Array()
	var last_recorded := Vector2.INF
	var positions := PackedVector2Array()
	positions.resize(count)

	if record and stage != Stage.COAST_TO_BURN:
		points.append(p)
		last_recorded = p

	var steps := 0
	while t < t_stop and steps < 200000:
		steps += 1

		for i in range(count):
			positions[i] = sun_pos + rel[i].rotated(omega[i] * (t - t0))

		if stage == Stage.COAST_TO_BURN and t >= t_start:
			stage = Stage.ESCAPE_BURN
			out.burn1_pos = p
			out.burn1_t = t
			if record:
				points.append(p)
				last_recorded = p

		var dep_pos: Vector2 = positions[dep]
		var dep_rel: Vector2 = p - dep_pos
		var dep_distance: float = dep_rel.length()
		var thrust := Vector2.ZERO

		if stage == Stage.ESCAPE_BURN:
			var dep_vel: Vector2 = Vector2(-(dep_pos - sun_pos).y, (dep_pos - sun_pos).x) * omega[dep]
			var rv: Vector2 = v - dep_vel
			var eps: float = rv.length_squared() * 0.5 - mu_dep / dep_distance
			if eps >= eps_target:
				stage = Stage.ESCAPE_COAST
			else:
				thrust = rv.normalized() * acc

		if stage == Stage.ESCAPE_COAST and dep_distance > exit_radius:
			stage = Stage.TRANSFER_BURN
			out.exit_state = {"pos": p, "vel": v, "t": t}
			out.burn2_pos = p
			out.burn2_t = t
			if stop == Stop.AT_EXIT:
				out.ok = true
				break

		var dmin: float = INF
		for i in range(count):
			dmin = minf(dmin, p.distance_to(positions[i]))
		var dt: float = clampf(DT_FACTOR * dmin, MIN_DT, MAX_DT)

		if stage == Stage.COAST_TO_BURN and t_start - t < dt:
			dt = maxf(t_start - t, 1e-3)
		elif stage == Stage.ESCAPE_BURN or stage == Stage.TRANSFER_BURN:
			dt = minf(dt, BURN_DT)
		dt = minf(dt, t_stop - t)

		if stage == Stage.TRANSFER_BURN:
			var remaining: Vector2 = dv - delivered
			var remaining_length: float = remaining.length()
			if remaining_length < 1e-4:
				stage = Stage.TRANSFER_COAST
			else:
				var magnitude: float = minf(acc, remaining_length / dt)
				thrust = remaining / remaining_length * magnitude
				delivered += thrust * dt

		var a0: Vector2 = _acceleration(p, t, t0, sun_pos, mu_sun, rel, omega, mu, soi) + thrust
		p += v * dt + a0 * (0.5 * dt * dt)
		var a1: Vector2 = _acceleration(p, t + dt, t0, sun_pos, mu_sun, rel, omega, mu, soi) + thrust
		v += (a0 + a1) * (0.5 * dt)
		t += dt

		if record and stage != Stage.COAST_TO_BURN and p.distance_to(last_recorded) >= RECORD_SPACING:
			points.append(p)
			last_recorded = p

		if stage == Stage.TRANSFER_COAST and stop == Stop.AT_CLOSEST:
			var target_pos: Vector2 = sun_pos + rel[target].rotated(omega[target] * (t - t0))
			var target_rel: Vector2 = p - target_pos
			var distance: float = target_rel.length()

			if distance < out.closest:
				var target_vel: Vector2 = Vector2(-(target_pos - sun_pos).y, (target_pos - sun_pos).x) * omega[target]
				var side: float = 1.0 if target_rel.cross(v - target_vel) >= 0.0 else -1.0
				out.closest = distance
				out.closest_signed = side * distance
				out.closest_t = t
				out.closest_pos = p
				out.ok = true
			elif distance > out.closest * 1.05 and out.closest < target_soi:
				break

			if distance < ctx.target_radius:
				break

	if record:
		points.append(p)

	out.pos = p
	out.vel = v
	out.t = t
	out.stage = stage
	out.points = points
	return out


static func _acceleration(
	p: Vector2,
	t: float,
	t0: float,
	sun_pos: Vector2,
	mu_sun: float,
	rel: PackedVector2Array,
	omega: PackedFloat64Array,
	mu: PackedFloat64Array,
	soi: PackedFloat64Array
) -> Vector2:
	for i in range(rel.size()):
		var body_pos: Vector2 = sun_pos + rel[i].rotated(omega[i] * (t - t0))
		if p.distance_squared_to(body_pos) <= soi[i] * soi[i]:
			var offset: Vector2 = body_pos - p
			var d2: float = offset.length_squared()
			var gravity: Vector2 = offset * (mu[i] / (d2 * sqrt(d2)))

			var sun_offset: Vector2 = sun_pos - body_pos
			var sd2: float = sun_offset.length_squared()
			var body_own_acceleration: Vector2 = sun_offset * (mu_sun / (sd2 * sqrt(sd2)))

			return gravity + body_own_acceleration

	var offset: Vector2 = sun_pos - p
	var d2: float = offset.length_squared()
	return offset * (mu_sun / (d2 * sqrt(d2)))


static func plan(ctx: Dictionary, request: Dictionary) -> Dictionary:
	match int(request.stage):
		Stage.COAST_TO_BURN:
			if request.has("t_start"):
				return _plan_from_escape(ctx, request)
			return _plan_departure(ctx, request)
		Stage.ESCAPE_BURN, Stage.ESCAPE_COAST:
			return _plan_from_escape(ctx, request)
		Stage.TRANSFER_BURN:
			return _plan_record(ctx, request)
		_:
			return _plan_cruise(ctx, request)


static func _plan_departure(ctx: Dictionary, request: Dictionary) -> Dictionary:
	var dep: int = ctx.dep
	var target: int = ctx.target
	var mu_sun: float = ctx.mu_sun
	var r1: float = ctx.rel[dep].length()
	var r2: float = ctx.rel[target].length()
	var omega_dep: float = ctx.omega[dep]
	var omega_target: float = ctx.omega[target]
	var now: float = request.t

	var a_transfer: float = 0.5 * (r1 + r2)
	var t_transfer: float = OrbitMath.half_period(a_transfer, mu_sun)
	var v_transfer: float = sqrt(mu_sun * (2.0 / r1 - 1.0 / a_transfer))
	var v_inf: float = absf(v_transfer - absf(omega_dep) * r1)
	var eps_target: float = 0.5 * v_inf * v_inf

	var gamma_required: float = wrapf(PI - omega_target * t_transfer, -PI, PI)
	var gamma_now: float = ctx.rel[dep].angle_to(ctx.rel[target])
	var rate: float = omega_target - omega_dep
	var synodic: float = TAU / absf(rate)
	var t_window: float = fposmod((gamma_required - gamma_now) * signf(rate), TAU) / absf(rate)

	var dep_pos: Vector2 = ctx.sun_pos + ctx.rel[dep]
	var dep_vel: Vector2 = Vector2(-ctx.rel[dep].y, ctx.rel[dep].x) * omega_dep
	var parking: Dictionary = OrbitMath.elements(request.pos - dep_pos, request.vel - dep_vel, ctx.mu[dep])
	var parking_period: float = 600.0
	if parking.e < 1.0 and parking.a > 0.0:
		parking_period = OrbitMath.orbital_period(parking.a, ctx.mu[dep])

	var half_width: float = SCAN_HALF_WIDTH * parking_period
	if t_window > synodic - half_width:
		t_window -= synodic

	var scan_start: float = maxf(now + 1.0, now + t_window - half_width)
	var scan_end: float = maxf(scan_start + parking_period, now + t_window + half_width)
	var samples: int = ceili((scan_end - scan_start) / parking_period * SAMPLES_PER_PERIOD) + 1

	var coast: Dictionary = simulate(ctx, {
		"pos": request.pos,
		"vel": request.vel,
		"t": now,
		"stage": Stage.COAST_TO_BURN,
	}, Stop.AT_TIME, scan_start, false)
	var start_state := {"pos": coast.pos, "vel": coast.vel, "t": coast.t}

	var step: float = (scan_end - scan_start) / float(samples - 1)
	var times := PackedFloat64Array()
	var scores := PackedFloat64Array()

	for i in range(samples):
		var candidate: float = scan_start + step * float(i)
		times.append(candidate)
		scores.append(_escape_score(ctx, start_state, candidate, eps_target, r2, omega_target))

	var minima: Array = []
	for i in range(samples):
		var left: float = scores[i - 1] if i > 0 else INF
		var right: float = scores[i + 1] if i < samples - 1 else INF
		if is_finite(scores[i]) and scores[i] <= left and scores[i] <= right:
			minima.append([scores[i], times[i]])
	minima.sort_custom(func(x, y): return x[0] < y[0])

	var best: Dictionary = {}
	var best_cost: float = INF

	for candidate in minima.slice(0, VERIFIED_CANDIDATES):
		var t_start: float = _refine_start(
			ctx, start_state, candidate[1], step, scan_start, scan_end, eps_target, r2, omega_target
		)
		var escape_state := start_state.duplicate()
		escape_state.stage = Stage.COAST_TO_BURN
		escape_state.t_start = t_start
		escape_state.eps_target = eps_target

		var result: Dictionary = _plan_from_escape(ctx, escape_state)
		if not result.ok:
			continue

		var cost: float = result.dv.length() + 0.3 * (result.closest_t - now) / t_transfer
		if absf(result.target_error) > CORRECTION_TOLERANCE:
			cost += 1000.0 + absf(result.target_error)

		if cost < best_cost:
			best_cost = cost
			best = result

	if best.is_empty():
		best = {"ok": false, "points": PackedVector2Array(), "dv": Vector2.ZERO}

	best.t_window = now + t_window
	return best


static func _refine_start(
	ctx: Dictionary,
	start_state: Dictionary,
	center: float,
	step: float,
	scan_start: float,
	scan_end: float,
	eps_target: float,
	r2: float,
	omega_target: float
) -> float:
	var lo: float = maxf(scan_start, center - step)
	var hi: float = minf(scan_end, center + step)
	var golden: float = 0.5 * (sqrt(5.0) - 1.0)
	var x1: float = hi - golden * (hi - lo)
	var x2: float = lo + golden * (hi - lo)
	var f1: float = _escape_score(ctx, start_state, x1, eps_target, r2, omega_target)
	var f2: float = _escape_score(ctx, start_state, x2, eps_target, r2, omega_target)

	for _i in range(REFINE_ITERATIONS):
		if f1 < f2:
			hi = x2
			x2 = x1
			f2 = f1
			x1 = hi - golden * (hi - lo)
			f1 = _escape_score(ctx, start_state, x1, eps_target, r2, omega_target)
		else:
			lo = x1
			x1 = x2
			f1 = f2
			x2 = lo + golden * (hi - lo)
			f2 = _escape_score(ctx, start_state, x2, eps_target, r2, omega_target)

	var center_score: float = _escape_score(ctx, start_state, center, eps_target, r2, omega_target)
	var refined: float = x1 if f1 < f2 else x2
	return refined if minf(f1, f2) < center_score else center


static func _escape_score(
	ctx: Dictionary,
	start_state: Dictionary,
	t_start: float,
	eps_target: float,
	r2: float,
	omega_target: float
) -> float:
	var st := start_state.duplicate()
	st.stage = Stage.COAST_TO_BURN
	st.t_start = t_start
	st.eps_target = eps_target
	var sim: Dictionary = simulate(ctx, st, Stop.AT_EXIT, t_start + MAX_ESCAPE_TIME, false)

	if not sim.ok:
		return INF

	var exit_state: Dictionary = sim.exit_state
	var helio: Dictionary = OrbitMath.elements(
		exit_state.pos - ctx.sun_pos, exit_state.vel, ctx.mu_sun
	)

	if signf(helio.h) != signf(omega_target):
		return 1e12

	var r1: float = ctx.rel[ctx.dep].length()
	if helio.e >= 1.0:
		return 1e9 + helio.energy

	var outward: bool = r2 > r1
	var far_apsis: float = helio.ra if outward else helio.rp
	var time_to_far: float = (
		OrbitMath.time_to_apoapsis(helio, ctx.mu_sun) if outward
		else OrbitMath.time_to_periapsis(helio, ctx.mu_sun)
	)
	var far_direction: Vector2 = -helio.ehat if outward else helio.ehat
	var target_direction: Vector2 = ctx.rel[ctx.target].rotated(
		omega_target * (exit_state.t + time_to_far - ctx.t0)
	)
	var phase_miss: float = absf(far_direction.angle_to(target_direction))
	return absf(far_apsis - r2) + r2 * phase_miss


static func _plan_from_escape(ctx: Dictionary, st: Dictionary) -> Dictionary:
	var to_exit: Dictionary = simulate(ctx, st, Stop.AT_EXIT, st.t + MAX_ESCAPE_TIME * 2.0, false)

	if not to_exit.ok:
		var failed: Dictionary = simulate(ctx, st, Stop.AT_TIME, st.t + MAX_ESCAPE_TIME, true)
		failed.ok = false
		failed.dv = Vector2.ZERO
		failed.target_error = INF
		return failed

	var exit_state: Dictionary = to_exit.exit_state
	var targeting: Dictionary = solve_targeting(ctx, exit_state, st.get("dv_guess", Vector2.ZERO))
	var dv: Vector2 = targeting.dv

	var full := st.duplicate()
	full.dv = dv
	full.delivered = Vector2.ZERO
	var result: Dictionary = simulate(ctx, full, Stop.AT_CLOSEST, exit_state.t + ctx.max_transfer_time, true)
	result.dv = dv
	result.target_error = targeting.error
	result.t_start = st.get("t_start", INF)
	result.eps_target = st.get("eps_target", 0.0)
	if targeting.error > CORRECTION_TOLERANCE:
		result.ok = false
	return result


static func _plan_record(ctx: Dictionary, st: Dictionary) -> Dictionary:
	var result: Dictionary = simulate(ctx, st, Stop.AT_CLOSEST, st.t + ctx.max_transfer_time, true)
	result.dv = st.get("dv", Vector2.ZERO)
	result.correction = false
	return result


static func _plan_cruise(ctx: Dictionary, st: Dictionary) -> Dictionary:
	var coast := st.duplicate()
	coast.stage = Stage.TRANSFER_COAST
	var result: Dictionary = simulate(ctx, coast, Stop.AT_CLOSEST, st.t + ctx.max_transfer_time, true)
	result.dv = Vector2.ZERO
	result.correction = false

	if result.ok and absf(result.closest_signed - _desired_signed(ctx)) <= CORRECTION_TOLERANCE:
		return result

	var targeting: Dictionary = solve_targeting(ctx, st, Vector2.ZERO)
	var dv: Vector2 = targeting.dv
	if dv == Vector2.ZERO:
		return result

	var corrected := st.duplicate()
	corrected.stage = Stage.TRANSFER_BURN
	corrected.dv = dv
	corrected.delivered = Vector2.ZERO
	var corrected_result: Dictionary = simulate(ctx, corrected, Stop.AT_CLOSEST, st.t + ctx.max_transfer_time, true)
	corrected_result.dv = dv
	corrected_result.correction = true
	return corrected_result


static func _desired_signed(ctx: Dictionary) -> float:
	return signf(ctx.omega[ctx.target]) * ctx.r_target


static func solve_targeting(ctx: Dictionary, state: Dictionary, dv_guess: Vector2) -> Dictionary:
	var desired: float = _desired_signed(ctx)
	var dv: Vector2 = dv_guess
	var best_dv: Vector2 = dv_guess
	var best_error: float = INF
	var h: float = 1e-3

	for _i in range(TARGET_ITERATIONS):
		var error: float = _targeting_error(ctx, state, dv, desired)

		if absf(error) < best_error:
			best_error = absf(error)
			best_dv = dv

		if absf(error) < TARGET_TOLERANCE:
			break

		var error_x: float = _targeting_error(ctx, state, dv + Vector2(h, 0.0), desired)
		var error_y: float = _targeting_error(ctx, state, dv + Vector2(0.0, h), desired)
		var gradient := Vector2((error_x - error) / h, (error_y - error) / h)
		var gradient_squared: float = gradient.length_squared()

		if gradient_squared < 1e-12 or not is_finite(gradient_squared):
			break

		var step: Vector2 = -gradient * (error / gradient_squared)
		if step.length() > MAX_TARGET_STEP:
			step = step.normalized() * MAX_TARGET_STEP
		dv += step

	return {"dv": best_dv, "error": best_error}


static func _targeting_error(ctx: Dictionary, state: Dictionary, dv: Vector2, desired: float) -> float:
	var st := {
		"pos": state.pos,
		"vel": state.vel,
		"t": state.t,
		"stage": Stage.TRANSFER_BURN,
		"dv": dv,
		"delivered": Vector2.ZERO,
	}
	var sim: Dictionary = simulate(ctx, st, Stop.AT_CLOSEST, state.t + ctx.max_transfer_time, false)

	if not sim.ok:
		return 1e9

	return sim.closest_signed - desired

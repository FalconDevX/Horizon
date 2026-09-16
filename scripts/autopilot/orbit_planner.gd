class_name OrbitPlanner
extends RefCounted

const ECCENTRICITY_CIRCULAR_THRESHOLD := 0.02
const RADIUS_TOLERANCE_METERS := 500.0


# Plans a sequence of physical maneuvers to transition the ship from its current
# orbital state into a stable circular orbit at target_radius around frame.body.
static func plan_circular_orbit(
	frame: OrbitalFrame,
	orbit_state: OrbitState,
	target_radius: float
) -> AutopilotPlan:
	var plan := AutopilotPlan.new(frame.body, target_radius - frame.body_radius)
	if frame == null or orbit_state == null or frame.mu <= 0.0 or target_radius <= frame.body_radius:
		plan.status = "FAILED"
		plan.failure_reason = "Invalid parameters for orbit planning"
		return plan

	var mu := frame.mu
	var current_r := orbit_state.radius
	var pe := orbit_state.periapsis_radius
	var ap := orbit_state.apoapsis_radius
	var e := orbit_state.eccentricity
	var a := orbit_state.semi_major_axis

	# Case 1: Already in target circular orbit
	var is_radius_close := absf(pe - target_radius) < RADIUS_TOLERANCE_METERS and absf(ap - target_radius) < RADIUS_TOLERANCE_METERS
	if e < ECCENTRICITY_CIRCULAR_THRESHOLD and is_radius_close:
		plan.status = "COMPLETED"
		plan.expected_final_periapsis = target_radius
		plan.expected_final_apoapsis = target_radius
		return plan

	# Case 2: Near-circular orbit, transfer to different circular radius (Classic Hohmann)
	if e < ECCENTRICITY_CIRCULAR_THRESHOLD:
		_plan_hohmann_from_circular(plan, frame, orbit_state, current_r, target_radius)
		return plan

	# Case 3: Eccentric initial orbit
	_plan_from_eccentric(plan, frame, orbit_state, target_radius)
	return plan


static func _plan_hohmann_from_circular(
	plan: AutopilotPlan,
	frame: OrbitalFrame,
	orbit_state: OrbitState,
	r1: float,
	r2: float
) -> void:
	var mu := frame.mu
	var a_transfer := (r1 + r2) * 0.5
	var v_current := sqrt(mu / r1)
	var v_transfer_1 := sqrt(mu * (2.0 / r1 - 1.0 / a_transfer))
	var dv1 := v_transfer_1 - v_current

	var v_transfer_2 := sqrt(mu * (2.0 / r2 - 1.0 / a_transfer))
	var v_target := sqrt(mu / r2)
	var dv2 := v_target - v_transfer_2

	var m1 := Maneuver.new()
	m1.reference_body = frame.body
	m1.trigger_type = Maneuver.TriggerType.IMMEDIATE
	m1.delta_v = absf(dv1)
	m1.remaining_delta_v = m1.delta_v

	var rel_p := orbit_state.eccentricity_vector # fallback
	var rel_v := Vector2.ZERO
	# Frame relative direction
	var prograde_dir := Vector2.RIGHT.orthogonal()
	if orbit_state.tangential_velocity < 0.0:
		prograde_dir = -prograde_dir

	var m2 := Maneuver.new()
	m2.reference_body = frame.body
	m2.delta_v = absf(dv2)
	m2.remaining_delta_v = m2.delta_v

	if dv1 > 0.0:
		# Raising orbit: Burn 1 is Prograde at current radius (Pe = r1, Ap = r2)
		m1.label = "Hohmann Raise 1 (Injection)"
		m1.direction = Maneuver.Direction.PROGRADE
		m1.expected_periapsis_radius = r1
		m1.expected_apoapsis_radius = r2

		# Burn 2 is Prograde at Apoapsis (r2)
		m2.label = "Hohmann Raise 2 (Circularize)"
		m2.trigger_type = Maneuver.TriggerType.APOAPSIS
		m2.direction = Maneuver.Direction.PROGRADE
		m2.expected_periapsis_radius = r2
		m2.expected_apoapsis_radius = r2
	else:
		# Lowering orbit: Burn 1 is Retrograde at current radius (Ap = r1, Pe = r2)
		m1.label = "Hohmann Lower 1 (Injection)"
		m1.direction = Maneuver.Direction.RETROGRADE
		m1.expected_periapsis_radius = r2
		m1.expected_apoapsis_radius = r1

		# Burn 2 is Retrograde at Periapsis (r2)
		m2.label = "Hohmann Lower 2 (Circularize)"
		m2.trigger_type = Maneuver.TriggerType.PERIAPSIS
		m2.direction = Maneuver.Direction.RETROGRADE
		m2.expected_periapsis_radius = r2
		m2.expected_apoapsis_radius = r2

	plan.add_maneuver(m1)
	plan.add_maneuver(m2)
	plan.expected_final_periapsis = r2
	plan.expected_final_apoapsis = r2
	plan.status = "PLANNED"


static func _plan_from_eccentric(
	plan: AutopilotPlan,
	frame: OrbitalFrame,
	orbit_state: OrbitState,
	target_radius: float
) -> void:
	var mu := frame.mu
	var pe := orbit_state.periapsis_radius
	var ap := orbit_state.apoapsis_radius
	var a := orbit_state.semi_major_axis

	# Subcase A: Target is close to periapsis -> single circularization burn at Periapsis
	if absf(pe - target_radius) < RADIUS_TOLERANCE_METERS * 2.0:
		var v_pe := sqrt(mu * (2.0 / pe - 1.0 / a))
		var v_circ := sqrt(mu / pe)
		var dv := v_circ - v_pe # Negative (retrograde) to circularize at Pe
		var m := Maneuver.new()
		m.reference_body = frame.body
		m.label = "Circularize at Periapsis"
		m.trigger_type = Maneuver.TriggerType.PERIAPSIS
		m.direction = Maneuver.Direction.PROGRADE if dv > 0.0 else Maneuver.Direction.RETROGRADE
		m.delta_v = absf(dv)
		m.remaining_delta_v = m.delta_v
		m.expected_periapsis_radius = pe
		m.expected_apoapsis_radius = pe
		plan.add_maneuver(m)
		plan.expected_final_periapsis = pe
		plan.expected_final_apoapsis = pe
		plan.status = "PLANNED"
		return

	# Subcase B: Target is close to apoapsis -> single circularization burn at Apoapsis
	if absf(ap - target_radius) < RADIUS_TOLERANCE_METERS * 2.0:
		var v_ap := sqrt(mu * (2.0 / ap - 1.0 / a))
		var v_circ := sqrt(mu / ap)
		var dv := v_circ - v_ap # Positive (prograde) to circularize at Ap
		var m := Maneuver.new()
		m.reference_body = frame.body
		m.label = "Circularize at Apoapsis"
		m.trigger_type = Maneuver.TriggerType.APOAPSIS
		m.direction = Maneuver.Direction.PROGRADE if dv > 0.0 else Maneuver.Direction.RETROGRADE
		m.delta_v = absf(dv)
		m.remaining_delta_v = m.delta_v
		m.expected_periapsis_radius = ap
		m.expected_apoapsis_radius = ap
		plan.add_maneuver(m)
		plan.expected_final_periapsis = ap
		plan.expected_final_apoapsis = ap
		plan.status = "PLANNED"
		return

	# Subcase C: Target is outside [Pe, Ap] or inside [Pe, Ap]
	# Choose the burn apsis based on target relation and arrival time
	var burn_at_pe := false
	if target_radius > ap:
		# Raising: burning prograde at Pe raises Ap to target_radius
		burn_at_pe = true
	elif target_radius < pe:
		# Lowering: burning retrograde at Ap lowers Pe to target_radius
		burn_at_pe = false
	else:
		# Between Pe and Ap: pick whichever apsis is reached sooner
		burn_at_pe = orbit_state.time_to_pe < orbit_state.time_to_ap

	if burn_at_pe:
		# Burn 1 at Periapsis: adjust Apoapsis to target_radius
		var a_trans := (pe + target_radius) * 0.5
		var v_pe_curr := sqrt(mu * (2.0 / pe - 1.0 / a))
		var v_pe_trans := sqrt(mu * (2.0 / pe - 1.0 / a_trans))
		var dv1 := v_pe_trans - v_pe_curr

		var m1 := Maneuver.new()
		m1.reference_body = frame.body
		m1.label = "Transfer 1 (at Periapsis)"
		m1.trigger_type = Maneuver.TriggerType.PERIAPSIS
		m1.direction = Maneuver.Direction.PROGRADE if dv1 > 0.0 else Maneuver.Direction.RETROGRADE
		m1.delta_v = absf(dv1)
		m1.remaining_delta_v = m1.delta_v
		m1.expected_periapsis_radius = pe
		m1.expected_apoapsis_radius = target_radius
		plan.add_maneuver(m1)

		# Burn 2 at the new Apoapsis (target_radius) to circularize
		var v_ap_trans := sqrt(mu * (2.0 / target_radius - 1.0 / a_trans))
		var v_circ := sqrt(mu / target_radius)
		var dv2 := v_circ - v_ap_trans

		var m2 := Maneuver.new()
		m2.reference_body = frame.body
		m2.label = "Circularize at Target Radius"
		m2.trigger_type = Maneuver.TriggerType.APOAPSIS
		m2.direction = Maneuver.Direction.PROGRADE if dv2 > 0.0 else Maneuver.Direction.RETROGRADE
		m2.delta_v = absf(dv2)
		m2.remaining_delta_v = m2.delta_v
		m2.expected_periapsis_radius = target_radius
		m2.expected_apoapsis_radius = target_radius
		plan.add_maneuver(m2)
	else:
		# Burn 1 at Apoapsis: adjust Periapsis to target_radius
		var a_trans := (ap + target_radius) * 0.5
		var v_ap_curr := sqrt(mu * (2.0 / ap - 1.0 / a))
		var v_ap_trans := sqrt(mu * (2.0 / ap - 1.0 / a_trans))
		var dv1 := v_ap_trans - v_ap_curr

		var m1 := Maneuver.new()
		m1.reference_body = frame.body
		m1.label = "Transfer 1 (at Apoapsis)"
		m1.trigger_type = Maneuver.TriggerType.APOAPSIS
		m1.direction = Maneuver.Direction.PROGRADE if dv1 > 0.0 else Maneuver.Direction.RETROGRADE
		m1.delta_v = absf(dv1)
		m1.remaining_delta_v = m1.delta_v
		m1.expected_periapsis_radius = target_radius
		m1.expected_apoapsis_radius = ap
		plan.add_maneuver(m1)

		# Burn 2 at the new Periapsis (target_radius) to circularize
		var v_pe_trans := sqrt(mu * (2.0 / target_radius - 1.0 / a_trans))
		var v_circ := sqrt(mu / target_radius)
		var dv2 := v_circ - v_pe_trans

		var m2 := Maneuver.new()
		m2.reference_body = frame.body
		m2.label = "Circularize at Target Radius"
		m2.trigger_type = Maneuver.TriggerType.PERIAPSIS
		m2.direction = Maneuver.Direction.PROGRADE if dv2 > 0.0 else Maneuver.Direction.RETROGRADE
		m2.delta_v = absf(dv2)
		m2.remaining_delta_v = m2.delta_v
		m2.expected_periapsis_radius = target_radius
		m2.expected_apoapsis_radius = target_radius
		plan.add_maneuver(m2)

	plan.expected_final_periapsis = target_radius
	plan.expected_final_apoapsis = target_radius
	plan.status = "PLANNED"

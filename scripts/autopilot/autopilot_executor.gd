class_name AutopilotExecutor
extends RefCounted

enum State {
	IDLE,
	WAIT_FOR_TRIGGER,
	ORIENT,
	BURN,
	VERIFY,
	COMPLETE,
	FAILED
}

var state: State = State.IDLE
var plan: AutopilotPlan = null
var active_maneuver: Maneuver = null
var frame: OrbitalFrame = null
var failure_reason: String = ""

var desired_heading: float = 0.0
var desired_throttle: float = 0.0

var _burn_start_rel_velocity: Vector2 = Vector2.ZERO
var _burn_axis: Vector2 = Vector2.ZERO
var _initial_maneuver_dv: float = 0.0
var _time_in_state: float = 0.0


func start(p_plan: AutopilotPlan, p_frame: OrbitalFrame) -> void:
	plan = p_plan
	frame = p_frame
	failure_reason = ""
	desired_throttle = 0.0

	if plan == null or plan.is_empty():
		state = State.COMPLETE
		return

	active_maneuver = plan.current_maneuver()
	if active_maneuver == null:
		state = State.COMPLETE
		return

	state = State.WAIT_FOR_TRIGGER
	_time_in_state = 0.0


func cancel() -> void:
	state = State.IDLE
	plan = null
	active_maneuver = null
	desired_throttle = 0.0
	failure_reason = ""


func tick(ship: SurveyShip, orbit_state: OrbitState, dt: float) -> void:
	if state == State.IDLE or state == State.COMPLETE or state == State.FAILED:
		desired_throttle = 0.0
		return

	if ship == null or active_maneuver == null or frame == null:
		_fail("Ship, maneuver, or orbital frame became invalid")
		return

	if ship.fuel <= 0.0:
		_fail("Insufficient fuel to complete maneuver")
		return

	_time_in_state += dt

	match state:
		State.WAIT_FOR_TRIGGER:
			_tick_wait_for_trigger(ship, orbit_state, dt)
		State.ORIENT:
			_tick_orient(ship, orbit_state, dt)
		State.BURN:
			_tick_burn(ship, orbit_state, dt)
		State.VERIFY:
			_tick_verify(ship, orbit_state, dt)


func _tick_wait_for_trigger(ship: SurveyShip, orbit_state: OrbitState, dt: float) -> void:
	desired_throttle = 0.0
	var accel := maxf(ControlModel.main_acceleration(ship), 0.1)
	var burn_duration := active_maneuver.remaining_delta_v / accel
	# Begin orienting ahead of the burn
	var orient_lead := 6.0
	var burn_lead := burn_duration * 0.5

	match active_maneuver.trigger_type:
		Maneuver.TriggerType.IMMEDIATE:
			state = State.ORIENT
			_time_in_state = 0.0
		Maneuver.TriggerType.PERIAPSIS:
			if orbit_state.time_to_pe <= burn_lead + orient_lead or is_nan(orbit_state.time_to_pe):
				state = State.ORIENT
				_time_in_state = 0.0
		Maneuver.TriggerType.APOAPSIS:
			if orbit_state.time_to_ap <= burn_lead + orient_lead or is_nan(orbit_state.time_to_ap):
				state = State.ORIENT
				_time_in_state = 0.0
		Maneuver.TriggerType.TIME:
			if active_maneuver.trigger_time <= _time_in_state + burn_lead + orient_lead:
				state = State.ORIENT
				_time_in_state = 0.0


func _tick_orient(ship: SurveyShip, orbit_state: OrbitState, dt: float) -> void:
	desired_throttle = 0.0
	var rel_pos := frame.relative_position(ship.global_position)
	var rel_vel := frame.relative_velocity(ship.velocity)

	# Determine intended burn direction vector in OrbitalFrame
	match active_maneuver.direction:
		Maneuver.Direction.RETROGRADE:
			_burn_axis = frame.retrograde(rel_pos, rel_vel)
		Maneuver.Direction.RADIAL_OUT:
			_burn_axis = frame.radial_out(rel_pos)
		Maneuver.Direction.RADIAL_IN:
			_burn_axis = frame.radial_in(rel_pos)
		_:
			_burn_axis = frame.prograde(rel_pos, rel_vel)

	desired_heading = _burn_axis.angle()

	var aligned := AttitudeController.is_aligned(
		ship.rotation,
		ship.angular_velocity,
		desired_heading,
		0.06,
		0.03
	)

	# Check timing condition to light the engine
	var accel := maxf(ControlModel.main_acceleration(ship), 0.1)
	var burn_duration := active_maneuver.remaining_delta_v / accel
	var burn_lead := burn_duration * 0.5

	var time_to_burn := 0.0
	if active_maneuver.trigger_type == Maneuver.TriggerType.PERIAPSIS:
		time_to_burn = orbit_state.time_to_pe
	elif active_maneuver.trigger_type == Maneuver.TriggerType.APOAPSIS:
		time_to_burn = orbit_state.time_to_ap

	var ready_to_fire := false
	if active_maneuver.trigger_type == Maneuver.TriggerType.IMMEDIATE:
		ready_to_fire = aligned
	else:
		ready_to_fire = aligned and (time_to_burn <= burn_lead + 0.1 or is_nan(time_to_burn))

	if ready_to_fire:
		_burn_start_rel_velocity = frame.relative_velocity(ship.velocity)
		_initial_maneuver_dv = active_maneuver.remaining_delta_v
		state = State.BURN
		_time_in_state = 0.0


func _tick_burn(ship: SurveyShip, orbit_state: OrbitState, dt: float) -> void:
	desired_heading = _burn_axis.angle()

	# If ship diverges from burn axis, cut throttle to prevent off-axis steering errors
	var heading_err := absf(angle_difference(ship.rotation, desired_heading))
	if heading_err > 0.2:
		desired_throttle = 0.0
		return

	var current_rel_vel := frame.relative_velocity(ship.velocity)
	var delivered_dv := (current_rel_vel - _burn_start_rel_velocity).dot(_burn_axis)
	if delivered_dv > 0.0:
		active_maneuver.remaining_delta_v = maxf(0.0, _initial_maneuver_dv - delivered_dv)

	var rem_dv := active_maneuver.remaining_delta_v
	var accel := maxf(ControlModel.main_acceleration(ship), 0.1)
	var stopping_dv := accel * dt * 2.0

	# Progressive throttle policy
	if rem_dv <= active_maneuver.tolerance_delta_v or rem_dv <= stopping_dv * 0.5:
		desired_throttle = 0.0
		state = State.VERIFY
		_time_in_state = 0.0
	elif rem_dv > 20.0:
		desired_throttle = 1.0
	elif rem_dv > 5.0:
		desired_throttle = 0.5
	else:
		desired_throttle = 0.15


func _tick_verify(ship: SurveyShip, orbit_state: OrbitState, dt: float) -> void:
	desired_throttle = 0.0
	# Evaluate if plan has more maneuvers
	if plan.advance_maneuver():
		active_maneuver = plan.current_maneuver()
		state = State.WAIT_FOR_TRIGGER
		_time_in_state = 0.0
	else:
		state = State.COMPLETE
		plan.status = "COMPLETED"


func _fail(reason: String) -> void:
	state = State.FAILED
	desired_throttle = 0.0
	failure_reason = reason
	if plan != null:
		plan.status = "FAILED"
		plan.failure_reason = reason

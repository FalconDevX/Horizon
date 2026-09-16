class_name AutopilotController
extends RefCounted

var ship: SurveyShip = null
var target_planet: ProcPlanet = null
var frame: OrbitalFrame = null
var current_plan: AutopilotPlan = null
var executor: AutopilotExecutor = null
var orbit_state: OrbitState = null

var active: bool = false
var desired_heading: float = 0.0
var desired_throttle: float = 0.0

var telemetry: Dictionary = {}


func _init(p_ship: SurveyShip) -> void:
	ship = p_ship
	executor = AutopilotExecutor.new()
	frame = OrbitalFrame.new()


func engage(target: ProcPlanet) -> void:
	if target == null:
		cancel()
		return

	target_planet = target
	active = true
	frame = OrbitalFrame.new(target, ship.universe if is_instance_valid(ship) else null)
	current_plan = null
	executor.cancel()
	desired_throttle = 0.0
	_update_telemetry("ENGAGING")


func cancel() -> void:
	active = false
	target_planet = null
	desired_throttle = 0.0
	if executor != null:
		executor.cancel()
	current_plan = null
	_update_telemetry("OFF")


func tick(dt: float) -> void:
	if not active or not is_instance_valid(ship) or not is_instance_valid(target_planet):
		cancel()
		return

	if ship.fuel <= 0.0:
		desired_throttle = 0.0
		if executor != null:
			executor._fail("Brak paliwa")
		_update_telemetry("FAILED")
		return

	frame.update(ship.universe if is_instance_valid(ship) else null)

	var rel_p := frame.relative_position(ship.global_position)
	var rel_v := frame.relative_velocity(ship.velocity)
	orbit_state = OrbitalPhysics.calculate_state(rel_p, rel_v, frame.mu, frame.body_radius)

	var target_alt := ship.get_target_orbit_altitude(target_planet)
	var target_radius := target_planet.radius + target_alt

	# Generate plan if none exists or if plan completed but orbit drifted
	if current_plan == null:
		current_plan = OrbitPlanner.plan_circular_orbit(frame, orbit_state, target_radius)
		if current_plan.status == "COMPLETED":
			desired_throttle = 0.0
			_update_telemetry("ORBIT_HOLD")
			return
		elif current_plan.status == "FAILED":
			desired_throttle = 0.0
			_update_telemetry("FAILED")
			return
		executor.start(current_plan, frame)

	# Run executor
	executor.tick(ship, orbit_state, dt)

	desired_heading = executor.desired_heading
	desired_throttle = executor.desired_throttle

	# Steer the ship using AttitudeController
	if executor.state == AutopilotExecutor.State.ORIENT or executor.state == AutopilotExecutor.State.BURN:
		var yaw_accel := ControlModel.yaw_acceleration(ship)
		ship.angular_velocity = AttitudeController.calculate_angular_velocity(
			ship.rotation,
			ship.angular_velocity,
			desired_heading,
			yaw_accel,
			dt
		)
		ship.rotation += ship.angular_velocity * dt

	if executor.state == AutopilotExecutor.State.COMPLETE:
		desired_throttle = 0.0
		# Check if final orbit matches requested
		var pe_err := absf(orbit_state.periapsis_radius - target_radius)
		var ap_err := absf(orbit_state.apoapsis_radius - target_radius)
		if pe_err < 1500.0 and ap_err < 1500.0 and orbit_state.eccentricity < 0.03:
			_update_telemetry("ORBIT_HOLD")
		else:
			# Minor replan to fine-tune
			current_plan = null
	elif executor.state == AutopilotExecutor.State.FAILED:
		desired_throttle = 0.0
		_update_telemetry("FAILED")
	else:
		_update_telemetry(_state_name(executor.state))


func _state_name(state: AutopilotExecutor.State) -> String:
	match state:
		AutopilotExecutor.State.WAIT_FOR_TRIGGER:
			return "WAIT_FOR_TRIGGER"
		AutopilotExecutor.State.ORIENT:
			return "ORIENT"
		AutopilotExecutor.State.BURN:
			return "BURN"
		AutopilotExecutor.State.VERIFY:
			return "VERIFY"
		AutopilotExecutor.State.COMPLETE:
			return "COMPLETE"
		AutopilotExecutor.State.FAILED:
			return "FAILED"
		_:
			return "IDLE"


func _update_telemetry(phase_text: String) -> void:
	var m := executor.active_maneuver if executor else null
	telemetry = {
		"active": active,
		"phase": phase_text,
		"state": _state_name(executor.state) if executor else "OFF",
		"target": target_planet,
		"reference_body": frame.body if frame else null,
		"remaining_delta_v": m.remaining_delta_v if m else 0.0,
		"total_remaining_delta_v": current_plan.remaining_delta_v() if current_plan else 0.0,
		"maneuver_label": m.label if m else "",
		"orbit_state": orbit_state,
		"desired_heading": desired_heading,
		"desired_throttle": desired_throttle,
		"failure_reason": executor.failure_reason if executor else "",
	}

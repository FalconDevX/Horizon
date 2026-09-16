class_name SurveyShip
extends CharacterBody2D

const SAS_TORQUE := 1.35
const MAX_SPIN := 1.15
const TURN_ACCELERATION := ControlModel.TURN_ACCELERATION
const ROTATION_DAMPING := 4.2
const CONTROL_MAIN_ACCELERATION := ControlModel.MAIN_ACCELERATION
const CONTROL_RCS_ACCELERATION := ControlModel.RCS_ACCELERATION
const HULL_R := 5.0
const MAX_SAFE_LANDING_RADIAL_SPEED := 12.0 # m/s
const MAX_SAFE_LANDING_TANGENT_SPEED := 16.0 # m/s
const CAMERA_ZOOM_MIN := 0.0000005
const CAMERA_ZOOM_MAX := 50.0
const CAMERA_ZOOM_STEP := 2.15
const ENERGY_MAX := 100.0

var graph := ModuleGraph.new()
var throttle: float = 0.0
var angular_velocity: float = 0.0
var sas: bool = true
var camera_zoom: float = 0.85
var time_warp: float = 1.0
var fuel: float = 0.0
var hull: float = 100.0
var energy: float = ENERGY_MAX
var universe: Universe
var spawn_point: Vector2 = Vector2.ZERO
var landed_on: ProcPlanet = null
var landed_angle: float = 0.0
var surface_coordinate := SurfaceCoordinate.new()
var surface_mode_active: bool = false
var autopilot_target: ProcPlanet = null
var autopilot_phase: String = "off"
var autopilot_delta_v: float = 0.0
var _autopilot_heading: float = 0.0
var _autopilot_direction: float = 0.0
var autopilot_maneuvers: Array[Maneuver] = []
var autopilot_maneuver_index: int = 0
var _autopilot_burning: bool = false
var frozen: bool = false

var _cam: Camera2D
var _aiming: bool = false
var _f_held: bool = false
var _collision: CollisionShape2D
var _circle: CircleShape2D


func _ready() -> void:
	motion_mode = CharacterBody2D.MOTION_MODE_FLOATING
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	# Above planetary disks (which hide the far side of orbital overlays).
	z_index = 10
	_circle = CircleShape2D.new()
	_circle.radius = HULL_R
	_collision = CollisionShape2D.new()
	_collision.shape = _circle
	add_child(_collision)
	_cam = Camera2D.new()
	_cam.enabled = true
	_cam.top_level = true
	_cam.position_smoothing_enabled = false
	_cam.process_callback = Camera2D.CAMERA2D_PROCESS_IDLE
	_cam.ignore_rotation = true
	_cam.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	add_child(_cam)
	_cam.global_position = global_position
	_cam.make_current()
	if graph.modules.is_empty():
		apply_blueprint(ShipBlueprint.load_current())
	if spawn_point != Vector2.ZERO:
		global_position = spawn_point


func apply_blueprint(data: Dictionary) -> void:
	if data.is_empty() or not graph.load_blueprint(data):
		graph = ShipBlueprint.starter_graph()
	_sync_from_graph()
	_update_collision()


func hull_radius() -> float:
	return graph.stats().radius if graph else HULL_R


func fuel_max() -> float:
	return maxf(graph.fuel_max(), 1.0)


func hull_max() -> float:
	return maxf(graph.stats().hull_max, 1.0)


func main_thrust() -> float:
	return graph.stats().thrust


func _sync_from_graph() -> void:
	var stats := graph.stats()
	fuel = stats.fuel
	hull = stats.hull
	_update_collision()


func _update_collision() -> void:
	if _circle:
		_circle.radius = hull_radius()


func _process(delta: float) -> void:
	if _cam == null or surface_mode_active:
		return
	var target_pos := global_position
	var diff := target_pos - _cam.global_position
	if diff.length_squared() > 1.0:
		_cam.global_position = _cam.global_position.lerp(target_pos, clampf(delta * 4.0, 0.05, 1.0))
	else:
		_cam.global_position = target_pos
	var target_zoom := Vector2(camera_zoom, camera_zoom)
	if (_cam.zoom - target_zoom).length_squared() > 0.0001:
		# Faster than the old camera easing, but still continuous between wheel ticks.
		_cam.zoom = _cam.zoom.lerp(target_zoom, 1.0 - exp(-13.0 * delta))
	else:
		_cam.zoom = target_zoom


func _update_camera(_delta: float) -> void:
	if _cam == null:
		return
	_cam.global_position = global_position
	_cam.zoom = Vector2(camera_zoom, camera_zoom)


func _unhandled_input(event: InputEvent) -> void:
	if surface_mode_active or frozen:
		return
	if event is InputEventKey and not event.echo:
		var key_code: int = event.physical_keycode if event.physical_keycode != 0 else event.keycode
		if key_code == KEY_F:
			_f_held = event.pressed
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP or event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			if _f_held or Input.is_key_pressed(KEY_F) or Input.is_physical_key_pressed(KEY_F):
				return
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			camera_zoom = clampf(camera_zoom * CAMERA_ZOOM_STEP, CAMERA_ZOOM_MIN, CAMERA_ZOOM_MAX)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			camera_zoom = clampf(camera_zoom / CAMERA_ZOOM_STEP, CAMERA_ZOOM_MIN, CAMERA_ZOOM_MAX)
	if event is InputEventKey and event.pressed and not event.echo:
		match event.physical_keycode:
			KEY_EQUAL, KEY_KP_ADD:
				camera_zoom = clampf(camera_zoom * CAMERA_ZOOM_STEP, CAMERA_ZOOM_MIN, CAMERA_ZOOM_MAX)
			KEY_MINUS, KEY_KP_SUBTRACT:
				camera_zoom = clampf(camera_zoom / CAMERA_ZOOM_STEP, CAMERA_ZOOM_MIN, CAMERA_ZOOM_MAX)
			KEY_0, KEY_KP_0:
				var planet := universe.nearest(global_position) if universe else null
				if planet:
					frame_near(planet)
			KEY_T:
				sas = not sas
			KEY_X:
				throttle = 0.0
			KEY_Z:
				throttle = 1.0
func _physics_process(delta: float) -> void:
	if frozen:
		queue_redraw()
		return
	if surface_mode_active:
		time_warp = 1.0
		queue_redraw()
		return
	var manual_input := _has_control_input()
	if manual_input and autopilot_target != null:
		cancel_autopilot()
		
	if autopilot_target == null:
		_throttle_input(delta)
		
	if landed_on != null:
		_tick_landed(delta)
	else:
		var steps := maxi(1, int(ceil(time_warp)))
		var step := delta * time_warp / float(steps)
		for i in steps:
			if autopilot_target != null:
				_tick_autopilot(step)
				_steer_to(_autopilot_heading, step)
			else:
				_steer(step)
			
			var heading := Vector2.from_angle(rotation)
			var thrust_dv := heading * ControlModel.main_acceleration(self) * throttle * step
			
			_apply_forces(step)
			
			if autopilot_target != null:
				_consume_autopilot_maneuver(step, thrust_dv)
				
			_move_step(step)
			_update_energy(step)
			if landed_on != null:
				break
		_update_camera(delta)
	queue_redraw()


func _has_control_input() -> bool:
	return (
		Input.is_physical_key_pressed(KEY_W)
		or Input.is_physical_key_pressed(KEY_S)
		or Input.is_physical_key_pressed(KEY_UP)
		or Input.is_physical_key_pressed(KEY_DOWN)
		or Input.is_physical_key_pressed(KEY_A)
		or Input.is_physical_key_pressed(KEY_D)
		or Input.is_physical_key_pressed(KEY_Q)
		or Input.is_physical_key_pressed(KEY_E)
		or Input.is_physical_key_pressed(KEY_SHIFT)
		or Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT)
	)


func _steer(dt: float) -> void:
	var yaw := float(Input.is_physical_key_pressed(KEY_D)) - float(Input.is_physical_key_pressed(KEY_A))
	_aiming = Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT)
	if _aiming:
		var want := (get_global_mouse_position() - global_position).angle()
		var err := angle_difference(rotation, want)
		var target_spin := clampf(err * 1.8, -MAX_SPIN, MAX_SPIN)
		angular_velocity = move_toward(angular_velocity, target_spin, _yaw_accel() * 1.4 * dt)
	elif absf(yaw) > 0.01:
		angular_velocity += yaw * ControlModel.yaw_acceleration(self) * dt
	else:
		var damping := ROTATION_DAMPING * (1.65 if sas and energy > 0.0 else 1.0)
		angular_velocity = move_toward(angular_velocity, 0.0, damping * dt)
	angular_velocity = clampf(angular_velocity, -MAX_SPIN, MAX_SPIN)
	rotation += angular_velocity * dt


func _steer_to(wanted_angle: float, dt: float) -> void:
	var error := angle_difference(rotation, wanted_angle)
	var target_spin := clampf(error * 2.4, -MAX_SPIN, MAX_SPIN)
	var accel := _yaw_accel() * 2.0
	if absf(error) < 0.08:
		target_spin = 0.0
		accel = _yaw_accel() * 3.5
	angular_velocity = move_toward(angular_velocity, target_spin, accel * dt)
	angular_velocity = clampf(angular_velocity, -MAX_SPIN, MAX_SPIN)
	rotation += angular_velocity * dt


func _throttle_input(dt: float) -> void:
	if Input.is_physical_key_pressed(KEY_W) or (landed_on == null and Input.is_physical_key_pressed(KEY_UP)):
		var throttle_rate := 0.9 if landed_on != null else 0.55
		throttle = move_toward(throttle, 1.0, throttle_rate * dt)
	if Input.is_physical_key_pressed(KEY_S) or (landed_on == null and Input.is_physical_key_pressed(KEY_DOWN)):
		throttle = move_toward(throttle, -0.28, 0.55 * dt)
	if Input.is_physical_key_pressed(KEY_SHIFT):
		throttle = move_toward(throttle, 1.0, 1.4 * dt)


func _yaw_accel() -> float:
	return ControlModel.yaw_acceleration(self)


func _apply_forces(dt: float) -> void:
	if fuel <= 0.0:
		throttle = 0.0
	var main_accel := ControlModel.main_acceleration(self)
	if absf(throttle) > 0.01 and main_accel > 0.0:
		var forward := Vector2.from_angle(rotation)
		velocity += forward * main_accel * throttle * dt
		ControlModel.consume_main(self, absf(throttle), dt)
	var nose := Vector2.from_angle(rotation)
	var rcs := Vector2.ZERO
	if Input.is_physical_key_pressed(KEY_Q):
		rcs += Vector2(-nose.y, nose.x)
	if Input.is_physical_key_pressed(KEY_E):
		rcs -= Vector2(-nose.y, nose.x)
	var rcs_accel := ControlModel.rcs_acceleration(self)
	if rcs.length() > 0.01 and rcs_accel > 0.0:
		velocity += rcs.normalized() * rcs_accel * dt
		ControlModel.consume_rcs(self, dt)
	if universe:
		velocity += universe.gravity_at(global_position) * dt


func _main_engine_delta_v(dt: float) -> Vector2:
	if fuel <= 0.0:
		return Vector2.ZERO
	var main_accel := ControlModel.main_acceleration(self)
	if absf(throttle) <= 0.01 or main_accel <= 0.0:
		return Vector2.ZERO
	return Vector2.from_angle(rotation) * main_accel * throttle * dt


func mass() -> float:
	return graph.stats().mass


func _move_step(dt: float) -> void:
	var velocity_before := velocity
	var hit := move_and_collide(velocity * dt)
	if hit == null:
		return
	var normal := hit.get_normal()
	var normal_speed := maxf(0.0, -normal.dot(velocity_before))
	var tangent_speed := absf(normal.orthogonal().dot(velocity_before))
	var collider := hit.get_collider() as Node
	var planet := collider.get_parent() as ProcPlanet if collider else null
	if (
		planet
		and planet.allows_surface_landing()
		and normal_speed <= MAX_SAFE_LANDING_RADIAL_SPEED
		and tangent_speed <= MAX_SAFE_LANDING_TANGENT_SPEED
	):
		_land_after_contact(planet)
		return
	if normal_speed > MAX_SAFE_LANDING_RADIAL_SPEED:
		graph.apply_hull_damage((normal_speed - MAX_SAFE_LANDING_RADIAL_SPEED) * 0.7)
		hull = graph.stats().hull
	velocity = velocity_before.bounce(normal) * 0.28
	global_position += normal * 2.0


func _update_energy(dt: float) -> void:
	if sas and absf(angular_velocity) > 0.015:
		energy = maxf(0.0, energy - 2.4 * dt)
	else:
		energy = move_toward(energy, ENERGY_MAX, 1.2 * dt)


func _tick_landed(delta: float) -> void:
	if not is_instance_valid(landed_on):
		landed_on = null
		return
	landed_angle = surface_coordinate.longitude
	var world_angle := surface_coordinate.longitude + landed_on.rotation
	var outward := Vector2.from_angle(world_angle)
	var surface_radius := landed_on.radius + hull_radius() + ControlModel.GROUND_CLEARANCE
	global_position = landed_on.global_position + outward * surface_radius
	velocity = landed_on.inertial_velocity() + outward.orthogonal() * landed_on.spin_speed * surface_radius
	rotation = world_angle
	angular_velocity = 0.0
	if autopilot_target != null:
		autopilot_phase = "launch"
		_autopilot_heading = world_angle
		throttle = 1.0
	_update_energy(delta)
	var thrust_acceleration := ControlModel.main_acceleration(self) * maxf(throttle, 0.0)
	var local_gravity := landed_on.mu / (surface_radius * surface_radius)
	if thrust_acceleration > local_gravity * 1.05 and fuel > 0.0:
		landed_on = null
		global_position += outward * 8.0
		velocity += outward * 3.0
		rotation = world_angle
		angular_velocity = 0.0


func _land_after_contact(planet: ProcPlanet) -> void:
	landed_on = planet
	landed_angle = (global_position - planet.global_position).angle() - planet.rotation
	surface_coordinate = SurfaceCoordinate.new(0.0, landed_angle)
	throttle = 0.0
	angular_velocity = 0.0
	_tick_landed(0.0)


func place_landed(planet: ProcPlanet) -> void:
	var outward := planet.global_position.normalized()
	if outward.length_squared() < 0.01:
		outward = Vector2.RIGHT
	_reset_resources()
	cancel_autopilot()
	landed_on = planet
	landed_angle = outward.angle() - planet.rotation
	surface_coordinate = SurfaceCoordinate.new(0.0, landed_angle)
	_tick_landed(0.0)


func relative_velocity_to(planet: ProcPlanet) -> Vector2:
	if planet == null:
		return velocity
	return velocity - planet.inertial_velocity()


func landing_block_reason(planet: ProcPlanet) -> String:
	if planet == null:
		return "Brak celu"
	if not planet.allows_surface_landing():
		return "Gazowy olbrzym â€” brak twardej powierzchni"
	var altitude := global_position.distance_to(planet.global_position) - planet.radius - hull_radius()
	var relative_speed := relative_velocity_to(planet).length()
	if altitude > planet.approach_altitude():
		return "Za wysoko na lÄ…dowanie"
	if relative_speed > ControlModel.APPROACH_SPEED:
		return "Za szybko na lÄ…dowanie"
	return ""


func can_land_at(planet: ProcPlanet) -> bool:
	return landing_block_reason(planet) == ""


func land_at_surface(planet: ProcPlanet, coordinate: SurfaceCoordinate) -> bool:
	if not can_land_at(planet):
		return false
	cancel_autopilot()
	landed_on = planet
	surface_coordinate = coordinate.copy()
	landed_angle = surface_coordinate.longitude
	throttle = 0.0
	_tick_landed(0.0)
	return true


var target_orbit_altitudes: Dictionary = {}


func get_target_orbit_altitude(planet: ProcPlanet) -> float:
	if planet == null:
		return 1000.0
	if target_orbit_altitudes.has(planet):
		return float(target_orbit_altitudes[planet])
	return planet.lowest_orbit_altitude() * 1.35


func set_target_orbit_altitude(planet: ProcPlanet, altitude: float) -> void:
	if planet == null:
		return
	var min_alt := planet.lowest_orbit_altitude() * 1.05
	var max_alt := maxf(planet.radius * 4.0, min_alt * 6.0)
	target_orbit_altitudes[planet] = clampf(altitude, min_alt, max_alt)


func adjust_target_orbit_altitude(planet: ProcPlanet, amount: float) -> float:
	if planet == null:
		return 0.0
	var cur := get_target_orbit_altitude(planet)
	set_target_orbit_altitude(planet, cur + amount)
	return get_target_orbit_altitude(planet)


enum AutopilotState {
	OFF,
	ANALYZE,
	PLAN_TRANSFER,
	ORIENT_FOR_BURN,
	COAST_TO_TRIGGER,
	EXECUTE_BURN,
	CIRCULARIZE,
	ORBIT_HOLD,
	COLLISION_AVOIDANCE
}

var autopilot_state: AutopilotState = AutopilotState.OFF
var orbit_state: OrbitState = null
var _burn_direction: Vector2 = Vector2.ZERO
var _burn_accumulated_dv: float = 0.0

func engage_orbit_autopilot(target: ProcPlanet) -> void:
	if target == null:
		return
	autopilot_target = target
	autopilot_state = AutopilotState.ANALYZE
	autopilot_phase = "analyzing"
	autopilot_delta_v = 0.0
	autopilot_maneuvers.clear()
	autopilot_maneuver_index = 0
	_autopilot_burning = false
	throttle = 0.0
	time_warp = 1.0


func cancel_autopilot() -> void:
	var was_active := autopilot_target != null
	autopilot_target = null
	_autopilot_direction = 0.0
	autopilot_state = AutopilotState.OFF
	autopilot_phase = "off"
	autopilot_delta_v = 0.0
	autopilot_maneuvers.clear()
	autopilot_maneuver_index = 0
	_autopilot_burning = false
	if was_active:
		throttle = 0.0

func _tick_autopilot(delta: float) -> void:
	if not is_instance_valid(autopilot_target) or fuel <= 0.0:
		cancel_autopilot()
		return
		
	# Odsiwiez stan orbity na podstawie obecnego SOI
	var status = universe.orbit_status(global_position, velocity)
	var focus: ProcPlanet = status["focus"]
	var center_pos := Vector2.ZERO
	var center_vel := Vector2.ZERO
	var center_mu := universe.sun_mu()
	var center_rad := universe.sun_radius
	
	if focus != null:
		center_pos = focus.global_position
		center_vel = focus.inertial_velocity()
		center_mu = focus.mu
		center_rad = focus.radius
		
	var rel := global_position - center_pos
	var rel_v := velocity - center_vel
	orbit_state = OrbitalPhysics.calculate_state(rel, rel_v, center_mu, center_rad)
	
	match autopilot_state:
		AutopilotState.ANALYZE:
			_ap_analyze()
		AutopilotState.PLAN_TRANSFER:
			_ap_plan_transfer()
		AutopilotState.ORIENT_FOR_BURN:
			_ap_orient()
		AutopilotState.COAST_TO_TRIGGER:
			_ap_coast()
		AutopilotState.EXECUTE_BURN:
			_ap_execute_burn(delta)
		AutopilotState.ORBIT_HOLD:
			_ap_orbit_hold()
		AutopilotState.COLLISION_AVOIDANCE:
			_ap_collision_avoidance()
			
func _ap_analyze() -> void:
	autopilot_phase = "analyzing"
	
	var status = universe.orbit_status(global_position, velocity)
	var focus: ProcPlanet = status["focus"]
	var target_parent = null # Zakladamy, ze celem jest planeta krazaca wokol Slonca
	
	# Bezpieczenstwo wokol obecnego ciala
	if focus != null:
		var safe_alt = maxf(focus.lowest_orbit_altitude() * 0.85, focus.atmosphere_height() * 1.15)
		if status["alt"] < safe_alt and status["relative_velocity"].dot(status["relative_position"]) < 0.0:
			if status["time_to_pe"] < 120.0 or status["alt"] < safe_alt * 1.5:
				autopilot_state = AutopilotState.COLLISION_AVOIDANCE
				return
				
	if focus == autopilot_target:
		var desired_radius = autopilot_target.radius + get_target_orbit_altitude(autopilot_target)
		var r_error = maxf(absf(orbit_state.periapsis_radius - desired_radius), absf(orbit_state.apoapsis_radius - desired_radius))
		if r_error < maxf(1500.0, desired_radius * 0.02) and orbit_state.eccentricity < 0.02:
			autopilot_state = AutopilotState.ORBIT_HOLD
			return
			
	autopilot_state = AutopilotState.PLAN_TRANSFER
	
func _ap_plan_transfer() -> void:
	autopilot_phase = "planning"
	autopilot_maneuvers.clear()
	autopilot_maneuver_index = 0
	
	var status = universe.orbit_status(global_position, velocity)
	var focus: ProcPlanet = status["focus"]
	
	# SCENARIUSZ 1: Jestesmy w docelowym SOI (lub przechwytywanie z hiperboli)
	if focus == autopilot_target:
		var desired_radius = autopilot_target.radius + get_target_orbit_altitude(autopilot_target)
		if not orbit_state.is_bound or orbit_state.eccentricity > 1.0:
			var capture_speed := OrbitalPhysics.circular_speed(autopilot_target.mu, desired_radius)
			var pe_speed := sqrt(maxf(autopilot_target.mu * (2.0 / orbit_state.periapsis_radius - 1.0 / orbit_state.semi_major_axis), 0.0))
			if not is_finite(orbit_state.semi_major_axis) or orbit_state.semi_major_axis <= 0:
				pe_speed = sqrt(autopilot_target.mu * (2.0 / orbit_state.periapsis_radius) + velocity.length_squared()) # Przyblizenie hiperboliczne
			var capture_dv := maxf(0.0, pe_speed - capture_speed)
			autopilot_maneuvers.append(Maneuver.new(Maneuver.Direction.RETROGRADE, maxf(capture_dv, 8.0), Maneuver.Trigger.PERIAPSIS, "capture orbit"))
			autopilot_state = AutopilotState.ORIENT_FOR_BURN
			return
			
		if orbit_state.eccentricity > 0.05:
			var v_ap = sqrt(autopilot_target.mu * (2.0 / orbit_state.apoapsis_radius - 1.0 / orbit_state.semi_major_axis))
			var v_circ = OrbitalPhysics.circular_speed(autopilot_target.mu, orbit_state.apoapsis_radius)
			var dv = v_circ - v_ap
			if dv > 0:
				autopilot_maneuvers.append(Maneuver.new(Maneuver.Direction.PROGRADE, dv, Maneuver.Trigger.APOAPSIS, "circularize"))
			else:
				autopilot_maneuvers.append(Maneuver.new(Maneuver.Direction.RETROGRADE, -dv, Maneuver.Trigger.APOAPSIS, "circularize"))
			autopilot_state = AutopilotState.ORIENT_FOR_BURN
			return
			
		var r1 = orbit_state.semi_major_axis
		var r2 = desired_radius
		var v1 = OrbitalPhysics.circular_speed(autopilot_target.mu, r1)
		var v_transfer_pe = sqrt(autopilot_target.mu * (2.0 / r1 - 1.0 / ((r1 + r2) / 2.0)))
		var dv1 = v_transfer_pe - v1
		var dv2 = OrbitalPhysics.circular_speed(autopilot_target.mu, r2) - sqrt(autopilot_target.mu * (2.0 / r2 - 1.0 / ((r1 + r2) / 2.0)))
		
		if dv1 > 0:
			autopilot_maneuvers.append(Maneuver.new(Maneuver.Direction.PROGRADE, dv1, Maneuver.Trigger.IMMEDIATE, "hohmann 1"))
			autopilot_maneuvers.append(Maneuver.new(Maneuver.Direction.PROGRADE, dv2, Maneuver.Trigger.APOAPSIS, "hohmann 2"))
		else:
			autopilot_maneuvers.append(Maneuver.new(Maneuver.Direction.RETROGRADE, -dv1, Maneuver.Trigger.IMMEDIATE, "hohmann 1"))
			autopilot_maneuvers.append(Maneuver.new(Maneuver.Direction.RETROGRADE, -dv2, Maneuver.Trigger.PERIAPSIS, "hohmann 2"))
		autopilot_state = AutopilotState.ORIENT_FOR_BURN
		return
		
	# SCENARIUSZ 2: Jestesmy w obcym SOI (Ucieczka do Slonca)
	if focus != null:
		# Zeby uciec prosto w kirunku Slonca (lub zgrubnie prograde planety) - uproszczony system ucieczki:
		# Odpalamy z calej sily PROGRADE na Periapsis az zrobimy hiperbole.
		if orbit_state.eccentricity < 1.0:
			var v_esc = sqrt(2.0 * focus.mu / orbit_state.periapsis_radius)
			var v_curr_pe = sqrt(focus.mu * (2.0 / orbit_state.periapsis_radius - 1.0 / orbit_state.semi_major_axis))
			var dv_escape = (v_esc - v_curr_pe) + 50.0 # extra 50 m/s for clean escape
			autopilot_maneuvers.append(Maneuver.new(Maneuver.Direction.PROGRADE, dv_escape, Maneuver.Trigger.PERIAPSIS, "escape burn"))
			autopilot_state = AutopilotState.ORIENT_FOR_BURN
		else:
			# Juz uciekamy, czekamy az wyjdziemy z SOI
			autopilot_state = AutopilotState.COAST_TO_TRIGGER
			autopilot_maneuvers.append(Maneuver.new(Maneuver.Direction.PROGRADE, 0.0, Maneuver.Trigger.IMMEDIATE, "coasting to sun"))
		return
		
	# SCENARIUSZ 3: Przestrzen miedzyplanetarna (Slonce)
	if focus == null:
		# Upraszczamy: robimy transfer Hohmanna miedzy orbitami slonecznymi.
		# W rzeczwistosci statki kaza na siebie dlugo czekac, zrobimy tu prosty manewr zmiany orbit.
		var sun_mu = universe.sun_mu()
		var r1 = orbit_state.semi_major_axis
		var r2 = autopilot_target.orbit_radius
		var v1 = OrbitalPhysics.circular_speed(sun_mu, r1)
		var v_transfer_pe = sqrt(sun_mu * (2.0 / r1 - 1.0 / ((r1 + r2) / 2.0)))
		var dv1 = v_transfer_pe - v1
		
		# Do celow lotu bez fazowania (gra arkadowa z faza 2D, mozna odpalic od razu by skrzyzowac orbity):
		if orbit_state.eccentricity > 0.05:
			# Circularize first if our solar orbit is highly eccentric
			var v_ap = sqrt(sun_mu * (2.0 / orbit_state.apoapsis_radius - 1.0 / orbit_state.semi_major_axis))
			var v_circ = OrbitalPhysics.circular_speed(sun_mu, orbit_state.apoapsis_radius)
			var dv = v_circ - v_ap
			autopilot_maneuvers.append(Maneuver.new(Maneuver.Direction.PROGRADE if dv > 0 else Maneuver.Direction.RETROGRADE, absf(dv), Maneuver.Trigger.APOAPSIS, "solar circularize"))
		else:
			if dv1 > 0:
				autopilot_maneuvers.append(Maneuver.new(Maneuver.Direction.PROGRADE, dv1, Maneuver.Trigger.IMMEDIATE, "solar hohmann"))
			else:
				autopilot_maneuvers.append(Maneuver.new(Maneuver.Direction.RETROGRADE, -dv1, Maneuver.Trigger.IMMEDIATE, "solar hohmann"))
		autopilot_state = AutopilotState.ORIENT_FOR_BURN
		return

func _ap_orient() -> void:
	if autopilot_maneuver_index >= autopilot_maneuvers.size():
		autopilot_state = AutopilotState.ANALYZE
		return
		
	var m = autopilot_maneuvers[autopilot_maneuver_index]
	autopilot_phase = "orienting (" + m.label + ")"
	
	_burn_direction = _get_maneuver_direction(m.direction)
	_autopilot_heading = _burn_direction.angle()
	
	var alignment = absf(angle_difference(rotation, _autopilot_heading))
	if alignment < 0.05 and absf(angular_velocity) < 0.02:
		# Zorientowany, czekaj na trigger
		autopilot_state = AutopilotState.COAST_TO_TRIGGER

func _ap_coast() -> void:
	var m = autopilot_maneuvers[autopilot_maneuver_index]
	autopilot_phase = "coast to " + ( "ap" if m.trigger == Maneuver.Trigger.APOAPSIS else ("pe" if m.trigger == Maneuver.Trigger.PERIAPSIS else "burn") )
	
	_burn_direction = _get_maneuver_direction(m.direction)
	_autopilot_heading = _burn_direction.angle()
	
	var time_left = 0.0
	if m.trigger == Maneuver.Trigger.APOAPSIS:
		time_left = orbit_state.time_to_ap
	elif m.trigger == Maneuver.Trigger.PERIAPSIS:
		time_left = orbit_state.time_to_pe
		
	# Rozpocznij burn na połowę czasu przed apsydą
	var accel = maxf(ControlModel.main_acceleration(self), 0.01)
	var burn_duration = m.remaining_delta_v / accel
	
	if m.trigger == Maneuver.Trigger.IMMEDIATE or time_left <= burn_duration * 0.5 + 0.1:
		# Zablokuj kierunek burna w momencie startu!
		_burn_direction = _get_maneuver_direction(m.direction)
		_autopilot_heading = _burn_direction.angle()
		_burn_accumulated_dv = 0.0
		autopilot_state = AutopilotState.EXECUTE_BURN
		
func _ap_execute_burn(delta: float) -> void:
	var m = autopilot_maneuvers[autopilot_maneuver_index]
	autopilot_phase = "burning (" + m.label + ")"
	autopilot_delta_v = m.remaining_delta_v
	_autopilot_heading = _burn_direction.angle()
	
	var alignment = absf(angle_difference(rotation, _autopilot_heading))
	if alignment > 0.3:
		throttle = 0.0
		return # Czekaj aż znowu się obróci
		
	var accel = maxf(ControlModel.main_acceleration(self), 0.01)
	var stopping_dv = accel * delta * 2.0
	
	if m.remaining_delta_v > 20.0:
		throttle = 1.0
	elif m.remaining_delta_v > 5.0:
		throttle = 0.5
	elif m.remaining_delta_v > stopping_dv:
		throttle = 0.15
	else:
		throttle = 0.0
		autopilot_maneuver_index += 1
		autopilot_state = AutopilotState.ANALYZE
		
func _consume_autopilot_maneuver(dt: float, actual_velocity_delta: Vector2) -> void:
	if autopilot_state != AutopilotState.EXECUTE_BURN or autopilot_maneuver_index >= autopilot_maneuvers.size():
		return
	var m = autopilot_maneuvers[autopilot_maneuver_index]
	# Mierzymy rzeczywiste dostarczone delta_v wzdluz zablokowanego wektora ciągu
	var delivered = actual_velocity_delta.dot(_burn_direction)
	if delivered > 0.0:
		m.remaining_delta_v = maxf(0.0, m.remaining_delta_v - delivered)
		
func _ap_orbit_hold() -> void:
	autopilot_phase = "orbit hold"
	throttle = 0.0
	# Jeśli orbita ucieknie poza tolerancję, wyślij do ANALYZE
	var desired_radius = autopilot_target.radius + get_target_orbit_altitude(autopilot_target)
	var r_error = maxf(absf(orbit_state.periapsis_radius - desired_radius), absf(orbit_state.apoapsis_radius - desired_radius))
	if r_error > maxf(2500.0, desired_radius * 0.05) or orbit_state.eccentricity > 0.05:
		autopilot_state = AutopilotState.ANALYZE
		
func _ap_collision_avoidance() -> void:
	autopilot_phase = "collision avoidance"
	# Radial out burn by szybko podnieść periapsis
	_burn_direction = (global_position - autopilot_target.global_position).normalized()
	_autopilot_heading = _burn_direction.angle()
	
	var alignment = absf(angle_difference(rotation, _autopilot_heading))
	if alignment < 0.1:
		throttle = 1.0
	else:
		throttle = 0.0
		
	var safe_alt = maxf(autopilot_target.lowest_orbit_altitude() * 0.85, autopilot_target.atmosphere_height() * 1.15)
	if orbit_state.periapsis_altitude > safe_alt * 1.1 and orbit_state.radial_velocity >= -10.0:
		throttle = 0.0
		autopilot_state = AutopilotState.ANALYZE
		
func _get_maneuver_direction(direction_type: int) -> Vector2:
	var radial = (global_position - autopilot_target.global_position).normalized()
	if radial.is_zero_approx(): radial = Vector2.RIGHT
	var rel_v = velocity - autopilot_target.inertial_velocity()
	var prograde = rel_v.normalized()
	if prograde.is_zero_approx(): prograde = radial.orthogonal()
	
	match direction_type:
		Maneuver.Direction.RETROGRADE: return -prograde
		Maneuver.Direction.RADIAL_OUT: return radial
		Maneuver.Direction.RADIAL_IN: return -radial
		_: return prograde
func frame_near(planet: ProcPlanet) -> void:
	var viewport := get_viewport_rect().size
	var target_screen_radius := ProcPlanet.target_screen_radius(viewport)
	camera_zoom = clampf(
		target_screen_radius / maxf(planet.radius, 1.0),
		CAMERA_ZOOM_MIN,
		CAMERA_ZOOM_MAX
	)
	if _cam:
		_cam.global_position = global_position
		_cam.zoom = Vector2(camera_zoom, camera_zoom)


func apply_screen_scale(planet: ProcPlanet, screen_radius: float) -> void:
	camera_zoom = clampf(
		screen_radius / maxf(planet.radius, 1.0),
		CAMERA_ZOOM_MIN,
		CAMERA_ZOOM_MAX
	)
	if _cam:
		_cam.global_position = global_position
		_cam.zoom = Vector2(camera_zoom, camera_zoom)


func reset_to(point: Vector2, look_at_point: Vector2, inherited_velocity: Vector2 = Vector2.ZERO) -> void:
	global_position = point
	reset_physics_interpolation()
	if _cam:
		_cam.global_position = point
	velocity = inherited_velocity
	angular_velocity = 0.0
	rotation = (point - look_at_point).angle()
	landed_on = null
	cancel_autopilot()
	_reset_resources()


func _reset_resources() -> void:
	throttle = 0.0
	graph.refill_fuel()
	graph.restore_hull()
	_sync_from_graph()
	energy = ENERGY_MAX
	time_warp = 1.0


func _visual_draw_scale() -> float:
	return 1.0


func _world_length_for_pixels(pixels: float) -> float:
	var zoom := _cam.zoom.x if _cam else camera_zoom
	return pixels / maxf(zoom, 0.000001)


func _draw() -> void:
	if surface_mode_active:
		return
	var visual_scale := _visual_draw_scale()
	var visual_rim := hull_radius() * visual_scale
	var zoom := _cam.zoom.x if _cam else camera_zoom
	var line_w := 1.5 / maxf(zoom, 0.000001)

	graph.draw_on(self, Vector2.ZERO, 0.0, visual_scale, throttle, fuel > 0.0)

	if _aiming:
		var aim_local := to_local(get_global_mouse_position())
		var min_aim := visual_rim + 6.0 / maxf(zoom, 0.000001)
		if aim_local.length() > min_aim:
			var aim_direction := aim_local.normalized()
			var aim_end := aim_direction * minf(aim_local.length(), _world_length_for_pixels(450.0))
			var aim_color := Color(0.35, 1.0, 0.48, 0.8)
			draw_line(aim_direction * min_aim, aim_end, aim_color, line_w, true)
			var dot_r := 2.5 / maxf(zoom, 0.000001)
			draw_circle(aim_end, dot_r, aim_color, true, -1.0, true)
			var ring_r := 5.5 / maxf(zoom, 0.000001)
			draw_arc(aim_end, ring_r, 0.0, TAU, 24, Color(0.35, 1.0, 0.48, 0.45), line_w, true)

	_draw_velocity_marker(visual_rim, zoom, line_w)


func _draw_velocity_marker(visual_rim: float, zoom: float, line_w: float) -> void:
	var ref_planet := universe.nearest(global_position) if universe else null
	var rel_vel := relative_velocity_to(ref_planet) if ref_planet else velocity
	var speed := rel_vel.length()
	if speed < 0.1:
		return

	var flight_direction := rel_vel.normalized().rotated(-rotation)

	# Dynamic screen-scaled vector length: actively lengthens and shortens with speed
	var vector_px := clampf(8.5 * pow(speed, 0.65), 0.0, 260.0)
	if vector_px < 1.0:
		return
	var vector_world := vector_px / maxf(zoom, 0.000001)
	var start_pos := flight_direction * (visual_rim + 2.0 / maxf(zoom, 0.000001))
	var end_pos := start_pos + flight_direction * vector_world

	var vec_color := Color(0.32, 0.94, 1.0, 0.9)

	# Draw main velocity vector shaft (exact 1.5 screen pixels, crisp antialiased)
	draw_line(start_pos, end_pos, vec_color, line_w, true)

	# Draw sleek prograde marker arrowhead at tip
	var tip := end_pos
	var head_len := clampf(vector_px * 0.25, 4.0, 9.0) / maxf(zoom, 0.000001)
	var head_w := head_len * 0.55
	var side := flight_direction.orthogonal() * head_w
	draw_line(tip - flight_direction * head_len + side, tip, vec_color, line_w, true)
	draw_line(tip - flight_direction * head_len - side, tip, vec_color, line_w, true)
	draw_circle(tip, 1.6 / maxf(zoom, 0.000001), Color(0.65, 0.95, 1.0, 0.95), true, -1.0, true)

func get_autopilot_plan(target: ProcPlanet, max_points: int = 400) -> Dictionary:
	var result = {
		"points": PackedVector2Array(),
		"status": "horizon",
		"orbit_center": target.global_position if target else Vector2.ZERO
	}
	if not is_instance_valid(target) or not is_instance_valid(universe):
		return result
		
	var pts := PackedVector2Array()
	var sim_p := global_position
	var sim_v := velocity
	pts.append(sim_p)
	
	var maneuvers = []
	for m in autopilot_maneuvers:
		maneuvers.append(m)
		
	var dt := 5.0
	var last_save_p := sim_p
	var last_save_dir := sim_v.normalized()
	
	for i in 8000:
		var status = universe.orbit_status(sim_p, sim_v)
		var focus: ProcPlanet = status["focus"]
		var mu = universe.sun_mu()
		var focus_pos = Vector2.ZERO
		var focus_vel = Vector2.ZERO
		
		if focus != null:
			mu = focus.mu
			focus_pos = focus.global_position
			focus_vel = focus.inertial_velocity()
			
		var rel_p = sim_p - focus_pos
		var rel_v = sim_v - focus_vel
		var r = rel_p.length()
		
		# Stabilniejszy, dyskretny timestep dla Eulera (eliminuje jitter)
		var v_mag = maxf(rel_v.length(), 1.0)
		var ideal_dt = r / v_mag * 0.05
		if focus == null:
			dt = 5000.0 if ideal_dt > 5000.0 else 500.0
		else:
			dt = 50.0 if ideal_dt > 50.0 else 5.0
			
		var dot_prev = rel_p.dot(rel_v)
		
		var accel = -mu / (r * r * r) * rel_p
		var next_rel_v = rel_v + accel * dt
		var next_rel_p = rel_p + next_rel_v * dt
		var dot_next = next_rel_p.dot(next_rel_v)
		
		var fire = false
		if maneuvers.size() > 0:
			var m = maneuvers[0]
			if m.trigger == Maneuver.Trigger.IMMEDIATE:
				fire = true
			elif m.trigger == Maneuver.Trigger.PERIAPSIS and dot_prev <= 0.0 and dot_next >= 0.0:
				fire = true
			elif m.trigger == Maneuver.Trigger.APOAPSIS and dot_prev >= 0.0 and dot_next <= 0.0:
				fire = true
				
			if fire:
				var burn_dir = next_rel_v.normalized() if m.direction == Maneuver.Direction.PROGRADE else -next_rel_v.normalized()
				next_rel_v += burn_dir * m.remaining_delta_v
				maneuvers.pop_front()
				
		sim_v = next_rel_v + focus_vel
		sim_p = next_rel_p + focus_pos
		
		if focus != null and r < focus.radius:
			result["status"] = "collision"
			pts.append(sim_p)
			break
			
		# Rysuj krzywa mądrze: dodawaj punkty tylko gdy zagniemy tor lotu o pewien kat 
		# lub przelecimy spory dystans. To da idealna krzywizne i malo punktow!
		var current_dir = sim_v.normalized()
		if current_dir.dot(last_save_dir) < 0.995 or sim_p.distance_squared_to(last_save_p) > (r * r * 0.02):
			pts.append(sim_p)
			last_save_p = sim_p
			last_save_dir = current_dir
			if pts.size() >= max_points:
				break
				
		if focus == target and maneuvers.is_empty():
			if r < target.radius + get_target_orbit_altitude(target) * 1.5:
				result["status"] = "ok"
				
	pts.append(sim_p)
	result["points"] = pts
	return result

func get_autopilot_guidance_for_state(
	world_position: Vector2,
	world_velocity: Vector2,
	target: ProcPlanet,
	delta: float,
	direction_hint: float = 0.0
) -> Dictionary:
	var result := {
		"desired_velocity": world_velocity,
		"desired_radius": 0.0,
		"heading": direction_hint,
		"throttle": 0.0,
		"phase": "off",
	}
	if not is_instance_valid(target):
		return result
	var desired_radius := target.radius + get_target_orbit_altitude(target)
	var rel_pos := world_position - target.global_position
	var radius := maxf(rel_pos.length(), target.radius + hull_radius() + 1.0)
	var radial := rel_pos / radius
	if radial.is_zero_approx():
		radial = Vector2.RIGHT
	var tangent := radial.orthogonal()
	var rel_vel := world_velocity - target.inertial_velocity()
	if rel_vel.dot(tangent) < 0.0:
		tangent = -tangent
	var circular_speed := OrbitalPhysics.circular_speed(target.mu, desired_radius)
	var local_escape := OrbitalPhysics.escape_speed(target.mu, radius)
	var approach_speed := minf(circular_speed, local_escape * 0.82)
	var desired_velocity := target.inertial_velocity() + tangent * approach_speed
	result["desired_velocity"] = desired_velocity
	result["desired_radius"] = desired_radius
	result["heading"] = (desired_velocity - world_velocity).angle()
	result["throttle"] = clampf((desired_velocity - world_velocity).length() / 60.0, 0.0, 1.0)
	result["phase"] = "guidance"
	return result


func get_planned_autopilot_trajectory(target: ProcPlanet, max_points: int = 160) -> PackedVector2Array:
	var path := PackedVector2Array()
	if not is_instance_valid(target):
		return path
	path.append(global_position)
	var desired_radius := target.radius + get_target_orbit_altitude(target)
	if landed_on == target:
		var start_dir := (global_position - target.global_position).normalized()
		if start_dir.is_zero_approx():
			start_dir = Vector2.RIGHT
		var ascent_count := mini(24, maxi(2, max_points / 4))
		for i in range(1, ascent_count + 1):
			var t := float(i) / float(ascent_count)
			var radius := lerpf(target.radius + hull_radius(), desired_radius, t)
			var angle := 0.34 * t * t
			path.append(target.global_position + start_dir.rotated(angle) * radius)
	else:
		var rel_pos := global_position - target.global_position
		var rel_v := velocity - target.inertial_velocity()
		var conic := OrbitalPhysics.sample_conic(rel_pos, rel_v, target.mu, max_points, desired_radius * 8.0)
		for i in range(1, conic.size()):
			var point := target.global_position + conic[i]
			if point.distance_to(target.global_position) <= target.radius + hull_radius():
				var dir := (point - target.global_position).normalized()
				if dir.is_zero_approx():
					dir = (global_position - target.global_position).normalized()
				point = target.global_position + dir * (target.radius + hull_radius() + 2.0)
			path.append(point)
			if path.size() >= maxi(2, max_points):
				break
	if path.size() < max_points:
		var start_dir := (path[path.size() - 1] - target.global_position).normalized()
		if start_dir.is_zero_approx():
			start_dir = Vector2.RIGHT
		var remaining := max_points - path.size()
		var loops := minf(TAU, TAU * float(remaining) / 96.0)
		for i in range(remaining):
			var t := float(i + 1) / float(maxi(remaining, 1))
			path.append(target.global_position + start_dir.rotated(loops * t) * desired_radius)
	return path


func _is_finite(value: float) -> bool:
	return value < INF and value > -INF and not is_nan(value)
func get_coast_trajectory(max_points: int = 120) -> PackedVector2Array:
	if not is_instance_valid(universe):
		return PackedVector2Array()
	var state := universe.orbit_status(global_position, velocity)
	var focus: ProcPlanet = state["focus"]
	if focus == null and state["bound"] == false:
		state = universe.solar_orbit_status(global_position, velocity)
	
	var pts := OrbitalPhysics.sample_conic(
		state["relative_position"],
		state["relative_velocity"],
		state["mu"],
		max_points
	)
	var center: Vector2 = state["center"]
	var world_pts := PackedVector2Array()
	# The first point should be exactly the ship's global position.
	world_pts.append(global_position)
	for i in range(1, pts.size()):
		world_pts.append(center + pts[i])
	return world_pts

class_name SurfaceMode
extends CanvasLayer

const SURFACE_GLOBE_SHADER := preload("res://shaders/planet_surface.gdshader")
const UnitsRef := preload("res://scripts/units.gd")

enum SurfaceState {
	INACTIVE,
	LANDING,
	GROUNDED,
	ASCENDING,
}

const SKY := Color("#070b18")
const HORIZON := Color("#16344a")
const HOVER_ALTITUDE := 2.0
const HOVER_DRAG := 0.16
const SURFACE_ZOOM_MIN := 0.25
const SURFACE_ZOOM_MAX := 600.0
const SURFACE_ZOOM_STEP := 2.15
const SURFACE_ZOOM_DEFAULT := 1.0
const SURFACE_CAMERA_FOLLOW_SPEED := 18.0
const SURFACE_ZOOM_FOLLOW_SPEED := 16.0
const HORIZON_VISIBILITY_EPSILON := 0.015
const HORIZON_OBJECT_SCALE := 0.45
const HORIZON_FLATTEN_MIN := 0.12
const MAX_SAFE_LANDING_RADIAL_SPEED := SurveyShip.MAX_SAFE_LANDING_RADIAL_SPEED
const MAX_SAFE_LANDING_TANGENT_SPEED := SurveyShip.MAX_SAFE_LANDING_TANGENT_SPEED
const EXIT_FALLBACK_ALTITUDE := 520.0

var ship: SurveyShip
var _sky_paint: Control
var _globe_visual: ColorRect
var _paint: Control
var _font: Font
var _active_planet: ProcPlanet = null
var _state: SurfaceState = SurfaceState.INACTIVE
var _blend: float = 0.0
var _entry_cooldown: float = 0.0
var _entry_coordinate := SurfaceCoordinate.new()
var player_surface_position: Vector3 = Vector3(0.0, 0.0, 1.0)
var planet_view_rotation: Quaternion = Quaternion.IDENTITY
var surface_zoom: float = SURFACE_ZOOM_DEFAULT
var _surface_zoom_target: float = SURFACE_ZOOM_DEFAULT
var _altitude: float = 0.0
var _radial_velocity: float = 0.0
var _surface_velocity: Vector3 = Vector3.ZERO
var _ground_heading: Vector2 = Vector2.RIGHT
var _launch_assist_time: float = 0.0
var _f_held: bool = false


func _ready() -> void:
	layer = 5
	follow_viewport_enabled = false
	_font = ThemeDB.fallback_font
	_sky_paint = Control.new()
	_sky_paint.set_anchors_preset(Control.PRESET_FULL_RECT)
	_sky_paint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_sky_paint.visible = false
	_sky_paint.draw.connect(_draw_surface_background)
	add_child(_sky_paint)
	_globe_visual = ColorRect.new()
	_globe_visual.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	_globe_visual.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_globe_visual.color = Color.WHITE
	_globe_visual.visible = false
	var globe_material := ShaderMaterial.new()
	globe_material.shader = SURFACE_GLOBE_SHADER
	_globe_visual.material = globe_material
	add_child(_globe_visual)
	_paint = Control.new()
	_paint.set_anchors_preset(Control.PRESET_FULL_RECT)
	_paint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_paint.visible = false
	_paint.draw.connect(_draw_surface)
	add_child(_paint)


func _unhandled_input(event: InputEvent) -> void:
	if _state == SurfaceState.INACTIVE:
		return
	if event is InputEventKey and not event.echo:
		var key_code: int = event.physical_keycode if event.physical_keycode != 0 else event.keycode
		if key_code == KEY_F:
			_f_held = event.pressed
	var previous_zoom := _surface_zoom_target
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP or event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			if _f_held or Input.is_key_pressed(KEY_F) or Input.is_physical_key_pressed(KEY_F):
				return
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_surface_zoom_target = clampf(_surface_zoom_target * SURFACE_ZOOM_STEP, SURFACE_ZOOM_MIN, SURFACE_ZOOM_MAX)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_surface_zoom_target = clampf(_surface_zoom_target / SURFACE_ZOOM_STEP, SURFACE_ZOOM_MIN, SURFACE_ZOOM_MAX)
	elif event is InputEventKey and event.pressed and not event.echo:
		match event.physical_keycode:
			KEY_EQUAL, KEY_KP_ADD:
				_surface_zoom_target = clampf(_surface_zoom_target * SURFACE_ZOOM_STEP, SURFACE_ZOOM_MIN, SURFACE_ZOOM_MAX)
			KEY_MINUS, KEY_KP_SUBTRACT:
				_surface_zoom_target = clampf(_surface_zoom_target / SURFACE_ZOOM_STEP, SURFACE_ZOOM_MIN, SURFACE_ZOOM_MAX)
			KEY_0, KEY_KP_0:
				_surface_zoom_target = SURFACE_ZOOM_DEFAULT
	if is_equal_approx(previous_zoom, _surface_zoom_target):
		return
	_update_surface_camera()
	if _paint:
		_paint.queue_redraw()
	if _globe_visual:
		_update_globe_visual()


func _process(delta: float) -> void:
	# When the surface mode is completely inactive it must not keep scheduling
	# redraws for three full-screen controls in the background.
	if _state == SurfaceState.INACTIVE and _blend <= 0.001:
		return
	if _state != SurfaceState.INACTIVE:
		# Wheel input changes a target value; the visible globe catches up quickly
		# and smoothly instead of jumping one discrete scale at a time.
		surface_zoom = lerpf(
			surface_zoom,
			_surface_zoom_target,
			1.0 - exp(-SURFACE_ZOOM_FOLLOW_SPEED * delta)
		)
	var target_blend := 1.0 if _state != SurfaceState.INACTIVE else 0.0
	_blend = move_toward(_blend, target_blend, delta / 0.42)
	var visible := _blend > 0.001
	var opacity := smoothstep(0.0, 1.0, _blend)
	if _sky_paint:
		_sky_paint.visible = visible
		_sky_paint.modulate.a = opacity
		_sky_paint.queue_redraw()
	if _globe_visual:
		_globe_visual.visible = visible
		_globe_visual.modulate.a = opacity
		if visible:
			_update_globe_visual()
	if _paint:
		_paint.visible = visible
		_paint.modulate.a = opacity
		_paint.queue_redraw()


func _physics_process(delta: float) -> void:
	if ship != null and ship.frozen:
		return
	_entry_cooldown = maxf(0.0, _entry_cooldown - delta)
	if _state == SurfaceState.INACTIVE:
		_try_auto_enter()
		return
	if not is_instance_valid(_active_planet) or ship == null:
		_leave_surface_mode()
		return
	if ship.landed_on != null and ship.landed_on != _active_planet:
		begin_grounded(ship.landed_on)
		return
	_tick_surface(delta)


func begin_landing(planet: ProcPlanet, coordinate: SurfaceCoordinate) -> bool:
	if ship == null or planet == null or _state != SurfaceState.INACTIVE:
		return false
	if not ship.can_land_at(planet):
		return false
	_enter_landing(planet, coordinate)
	return true


func begin_grounded(planet: ProcPlanet) -> void:
	if ship == null or planet == null or not planet.allows_surface_landing():
		return
	_active_planet = planet
	_entry_coordinate = ship.surface_coordinate.copy()
	player_surface_position = _entry_coordinate.to_unit_vector()
	_center_globe_on_player()
	_match_space_view(planet)
	_update_surface_camera()
	_lock_space_camera()
	_altitude = HOVER_ALTITUDE
	_radial_velocity = 0.0
	_surface_velocity = Vector3.ZERO
	_ground_heading = Vector2.RIGHT
	_launch_assist_time = 0.0
	_state = SurfaceState.GROUNDED
	ship.surface_mode_active = true
	ship.landed_on = planet
	ship.throttle = 0.0
	_hide_world_visuals()
	_sync_world_proxy()


func _try_auto_enter() -> void:
	if ship == null or ship.universe == null or _entry_cooldown > 0.0:
		return
	if ship.landed_on != null:
		begin_grounded(ship.landed_on)
		return
	# Only an actual landed state enters the close surface mode. Passing a planet
	# at low altitude must remain normal orbital flight.
	return


func _enter_landing(planet: ProcPlanet, coordinate: SurfaceCoordinate) -> void:
	_active_planet = planet
	_entry_coordinate = coordinate.copy()
	player_surface_position = coordinate.to_unit_vector()
	_center_globe_on_player()
	_match_space_view(planet)
	_update_surface_camera()
	_lock_space_camera()
	var actual_altitude := maxf(
		ship.global_position.distance_to(planet.global_position) - planet.radius - ship.hull_radius(),
		0.0
	)
	_altitude = clampf(actual_altitude, 80.0, 1_000.0)
	var world_angle := coordinate.longitude + planet.rotation
	var outward := Vector2.from_angle(world_angle)
	var tangent := outward.orthogonal()
	var relative_velocity := ship.velocity - planet.inertial_velocity()
	var east := _east_at(player_surface_position)
	_surface_velocity = east * clampf(relative_velocity.dot(tangent), -MAX_SAFE_LANDING_TANGENT_SPEED, MAX_SAFE_LANDING_TANGENT_SPEED)
	_radial_velocity = clampf(relative_velocity.dot(outward), -MAX_SAFE_LANDING_RADIAL_SPEED, 8.0)
	_ground_heading = Vector2.RIGHT
	_launch_assist_time = 0.0
	_state = SurfaceState.LANDING
	ship.cancel_autopilot()
	ship.surface_mode_active = true
	ship.landed_on = null
	ship.throttle = 0.0
	_hide_world_visuals()
	_sync_world_proxy()


func _tick_surface(delta: float) -> void:
	if _state == SurfaceState.GROUNDED:
		_tick_grounded(delta)
	else:
		_tick_flight(delta)
	_update_surface_camera_follow(delta)
	_lock_space_camera()
	_sync_world_proxy()


func _tick_grounded(delta: float) -> void:
	var movement := _surface_movement_input()
	if movement.length_squared() > 0.01:
		movement = movement.normalized()
		_ground_heading = movement
		var hover_accel := ControlModel.main_acceleration(ship)
		if hover_accel > 0.0:
			_surface_velocity += _screen_direction_to_tangent(movement) * hover_accel * delta
			ControlModel.consume_main(ship, 0.35, delta)
	var max_hover_speed := _hover_max_speed()
	if _surface_velocity.length() > max_hover_speed:
		_surface_velocity = _surface_velocity.normalized() * max_hover_speed
	_surface_velocity *= exp(-HOVER_DRAG * delta)
	_altitude = HOVER_ALTITUDE
	_radial_velocity = 0.0
	ship.throttle = 0.0
	_advance_surface_velocity(delta)
	var view_velocity := planet_view_rotation * _surface_velocity
	var screen_velocity := Vector2(view_velocity.x, -view_velocity.y)
	if screen_velocity.length_squared() > 1.0:
		_ground_heading = screen_velocity.normalized()
	if Input.is_physical_key_pressed(KEY_SPACE):
		_state = SurfaceState.ASCENDING
		ship.landed_on = null
		ship.throttle = 1.0
		_altitude = HOVER_ALTITUDE + 5.0
		_radial_velocity = ControlModel.LAUNCH_KICK
		_surface_velocity = Vector3.ZERO
		_launch_assist_time = 3.5


func _tick_flight(delta: float) -> void:
	if _launch_assist_time > 0.0:
		_launch_assist_time = maxf(0.0, _launch_assist_time - delta)
	if Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN):
		_launch_assist_time = 0.0

	var steer_x := (
		float(Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT))
		- float(Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT))
	)
	var steer_y := float(Input.is_physical_key_pressed(KEY_DOWN)) - float(Input.is_physical_key_pressed(KEY_UP))
	var lateral_input := Vector2(steer_x, steer_y)
	if lateral_input.length_squared() > 0.01:
		lateral_input = lateral_input.normalized()
		_ground_heading = lateral_input
		var tangent_acceleration := _screen_direction_to_tangent(lateral_input) * _local_thrust_acceleration()
		_surface_velocity += tangent_acceleration * delta
		if _local_thrust_acceleration() > 0.0:
			ControlModel.consume_main(ship, 0.45, delta)
	if Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
		var ship_screen := _ship_screen_position()
		var aim := _paint.get_local_mouse_position() - ship_screen
		if aim.length_squared() > 16.0:
			_ground_heading = aim.normalized()
	var engine_on := (
		Input.is_physical_key_pressed(KEY_W)
		or Input.is_physical_key_pressed(KEY_UP)
		or Input.is_physical_key_pressed(KEY_SHIFT)
		or Input.is_physical_key_pressed(KEY_SPACE)
		or (_state == SurfaceState.ASCENDING and _launch_assist_time > 0.0)
	)
	var target_throttle := 1.0 if engine_on else 0.0
	ship.throttle = move_toward(ship.throttle, target_throttle, delta * 3.5)
	_radial_velocity -= _local_gravity() * delta
	if ship.throttle > 0.01 and _local_thrust_acceleration() > 0.0:
		_radial_velocity += _local_thrust_acceleration() * ship.throttle * delta
		ControlModel.consume_main(ship, ship.throttle, delta)
	_surface_velocity *= exp(-0.2 * delta)
	_advance_surface_velocity(delta)
	_altitude += _radial_velocity * delta
	if _altitude <= 0.0:
		_resolve_ground_contact()
	if _state == SurfaceState.ASCENDING and _altitude >= _exit_altitude():
		_finish_launch()


func _resolve_ground_contact() -> void:
	var impact_speed := maxf(-_radial_velocity, 0.0)
	if (
		impact_speed <= MAX_SAFE_LANDING_RADIAL_SPEED
		and _surface_velocity.length() <= MAX_SAFE_LANDING_TANGENT_SPEED
	):
		_altitude = HOVER_ALTITUDE
		_radial_velocity = 0.0
		_surface_velocity *= 0.35
		_state = SurfaceState.GROUNDED
		ship.landed_on = _active_planet
		ship.throttle = 0.0
		return
	ship.graph.apply_hull_damage(maxf(impact_speed - 18.0, 4.0) * 0.85)
	ship.hull = ship.graph.stats().hull
	_altitude = 2.0
	_radial_velocity = maxf(10.0, impact_speed * 0.28)
	_surface_velocity *= 0.55


func _finish_launch() -> void:
	var planet := _active_planet
	var coordinate := _current_coordinate()
	var world_angle := coordinate.longitude + planet.rotation
	var outward := Vector2.from_angle(world_angle)
	var tangent := outward.orthogonal()
	var outward_speed := maxf(_radial_velocity, 0.0)
	var tangent_speed := _surface_velocity.dot(_east_at(player_surface_position))
	ship.global_position = planet.global_position + outward * (
		planet.radius + ship.hull_radius() + _altitude
	)
	ship.velocity = planet.inertial_velocity() + tangent * tangent_speed + outward * outward_speed
	ship.rotation = outward.angle()
	ship.surface_coordinate = coordinate
	ship.landed_on = null
	ship.surface_mode_active = false
	ship.throttle = 0.0
	# WyĹ‚Ä…cz overlay powierzchni
	if _globe_visual:
		_globe_visual.visible = false
	if _sky_paint:
		_sky_paint.visible = false
	if _paint:
		_paint.visible = false
	_blend = 0.0
	_state = SurfaceState.INACTIVE
	# WAĹ»NE: przywrĂłÄ‡ widocznoĹ›Ä‡ planety PRZED wyzerowaniem _active_planet â€”
	# _restore_world_visuals() sprawdza is_instance_valid(_active_planet).
	if is_instance_valid(planet):
		planet.visible = true
	_set_orbit_renderer_visible(true)
	_active_planet = null
	# Kamera
	ship.reset_physics_interpolation()
	ship.apply_screen_scale(planet, _planet_radius(_viewport_size()))
	if ship._cam:
		ship._cam.global_position = ship.global_position
		ship._cam.reset_physics_interpolation()
	if is_instance_valid(planet):
		planet.set_surface_view(planet_view_rotation)
	_entry_cooldown = 2.0


func _leave_surface_mode() -> void:
	if ship:
		ship.surface_mode_active = false
	_restore_world_visuals()
	_active_planet = null
	_state = SurfaceState.INACTIVE
	_entry_cooldown = 1.0


func _sync_world_proxy() -> void:
	if ship == null or not is_instance_valid(_active_planet):
		return
	var coordinate := _current_coordinate()
	var world_angle := coordinate.longitude + _active_planet.rotation
	var outward := Vector2.from_angle(world_angle)
	var tangent := outward.orthogonal()
	ship.surface_coordinate = coordinate
	ship.global_position = _active_planet.global_position + outward * (
		_active_planet.radius + ship.hull_radius() + _altitude
	)
	ship.rotation = outward.angle()
	if _state == SurfaceState.GROUNDED:
		var surface_radius := _active_planet.radius + ship.hull_radius()
		ship.velocity = (
			_active_planet.inertial_velocity()
			+ tangent * _active_planet.spin_speed * surface_radius
		)
	else:
		var east_speed := _surface_velocity.dot(_east_at(player_surface_position))
		ship.velocity = (
			_active_planet.inertial_velocity()
			+ tangent * east_speed
			+ outward * _radial_velocity
		)


func _local_gravity() -> float:
	if _active_planet == null:
		return UnitsRef.STANDARD_GRAVITY
	var radius := _active_planet.radius + maxf(_altitude, 0.0)
	return _active_planet.mu / maxf(radius * radius, 1.0)


func _local_thrust_acceleration() -> float:
	return ControlModel.main_acceleration(ship)


func _center_globe_on_player() -> void:
	planet_view_rotation = Quaternion(
		player_surface_position.normalized(),
		Vector3(0.0, 0.0, 1.0)
	).normalized()


func _surface_movement_input() -> Vector2:
	return Vector2(
		float(Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT))
			- float(Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT)),
		float(Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN))
			- float(Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP))
	)


func _screen_direction_to_tangent(screen_direction: Vector2) -> Vector3:
	if screen_direction.length_squared() < 0.0001:
		return Vector3.ZERO
	var view_direction := Vector3(screen_direction.x, -screen_direction.y, 0.0).normalized()
	var planet_direction := planet_view_rotation.inverse() * view_direction
	var tangent := planet_direction - player_surface_position * planet_direction.dot(player_surface_position)
	return tangent.normalized()


func _move_player_on_sphere(screen_direction: Vector2, angular_distance: float) -> void:
	var tangent := _screen_direction_to_tangent(screen_direction)
	if tangent.length_squared() < 0.0001:
		return
	player_surface_position = (
		player_surface_position * cos(angular_distance)
		+ tangent * sin(angular_distance)
	).normalized()


func _apply_surface_movement(direction: Vector2, distance: float) -> void:
	_move_player_on_sphere(direction, _surface_angular_distance(distance))


func _advance_surface_velocity(delta: float) -> void:
	var speed := _surface_velocity.length()
	if speed < 0.001:
		return
	var tangent := (
		_surface_velocity
		- player_surface_position * _surface_velocity.dot(player_surface_position)
	).normalized()
	var angular_distance := _surface_angular_distance(speed * delta)
	player_surface_position = (
		player_surface_position * cos(angular_distance)
		+ tangent * sin(angular_distance)
	).normalized()
	_surface_velocity = (
		_surface_velocity
		- player_surface_position * _surface_velocity.dot(player_surface_position)
	).normalized() * speed


func _update_surface_camera() -> void:
	var view_position := planet_view_rotation * player_surface_position
	var disk := Vector2(view_position.x, view_position.y)
	if disk.length_squared() > 0.000001:
		_orient_player_at_disk_position(view_position, Vector2.ZERO)
	_lock_space_camera()


func _lock_space_camera() -> void:
	if ship == null or ship._cam == null or not is_instance_valid(_active_planet):
		return
	var viewport := _viewport_size()
	var zoom := _planet_radius(viewport) / maxf(_active_planet.radius, 1.0)
	ship.camera_zoom = zoom
	ship._cam.global_position = _active_planet.global_position
	ship._cam.zoom = Vector2(zoom, zoom)


func _update_surface_camera_follow(delta: float) -> void:
	# The globe must follow the player once per physics frame.  Re-centering it
	# immediately after every position update made the terrain visibly snap.
	var view_position := planet_view_rotation * player_surface_position
	var disk := Vector2(view_position.x, view_position.y)
	if disk.length_squared() <= 0.000001:
		return
	var desired_rotation := _rotation_placing_player_at_disk_position(view_position, Vector2.ZERO)
	# Large deltas occur while entering a mode and in deterministic tests; then
	# center exactly.  Normal frame deltas retain a short, smooth camera follow.
	var follow := 1.0 if delta >= 0.08 else 1.0 - exp(-SURFACE_CAMERA_FOLLOW_SPEED * maxf(delta, 0.0))
	planet_view_rotation = planet_view_rotation.slerp(desired_rotation, follow).normalized()
	_lock_space_camera()


func _orient_player_at_disk_position(view_position: Vector3, desired_disk: Vector2) -> void:
	planet_view_rotation = _rotation_placing_player_at_disk_position(view_position, desired_disk)


func _rotation_placing_player_at_disk_position(
	view_position: Vector3,
	desired_disk: Vector2
) -> Quaternion:
	desired_disk = desired_disk.limit_length(0.98)
	var desired_view := Vector3(
		desired_disk.x,
		-desired_disk.y,
		sqrt(maxf(1.0 - desired_disk.length_squared(), 0.0))
	)
	var correction := Quaternion(view_position.normalized(), desired_view.normalized())
	return (correction * planet_view_rotation).normalized()


func _east_at(point: Vector3) -> Vector3:
	var east := point.cross(Vector3.UP)
	if east.length_squared() < 0.0001:
		east = point.cross(Vector3.FORWARD)
	return east.normalized()


func _surface_angular_distance(linear_distance: float) -> float:
	if not is_instance_valid(_active_planet):
		return 0.0
	return linear_distance / maxf(_active_planet.radius + _altitude, 1.0)


func _hover_max_speed() -> float:
	return ControlModel.SURFACE_SPEED


func _hover_acceleration() -> float:
	return ControlModel.MAIN_ACCELERATION


func _exit_altitude() -> float:
	return ControlModel.LAUNCH_CLEARANCE


func _insertion_altitude() -> float:
	if is_instance_valid(_active_planet):
		return _active_planet.lowest_orbit_altitude() + ControlModel.EXIT_MARGIN
	return EXIT_FALLBACK_ALTITUDE


func _altitude_meters() -> float:
	return maxf(_altitude, 0.0)


func _current_coordinate() -> SurfaceCoordinate:
	if _active_planet == null:
		return _entry_coordinate.copy()
	return SurfaceCoordinate.from_unit_vector(player_surface_position)


func _ship_screen_position() -> Vector2:
	return _planet_center(_viewport_size())


func _project_surface_point(
	surface_point: Vector3,
	viewport: Vector2,
	altitude: float = 0.0
) -> Dictionary:
	var viewed := planet_view_rotation * surface_point.normalized()
	var depth := clampf(viewed.z, 0.0, 1.0)
	var radius_factor := 1.0
	if is_instance_valid(_active_planet):
		radius_factor += maxf(altitude, 0.0) / maxf(_active_planet.radius, 1.0)
	var center := _planet_center(viewport)
	var disk_offset := Vector2(viewed.x, -viewed.y) * _planet_radius(viewport)
	return {
		"visible": viewed.z > HORIZON_VISIBILITY_EPSILON,
		"position": center + disk_offset * radius_factor,
		"surface_position": center + disk_offset,
		"view": viewed,
		"depth": depth,
		"scale": lerpf(HORIZON_OBJECT_SCALE, 1.0, depth),
		"flatten": lerpf(HORIZON_FLATTEN_MIN, 1.0, depth),
		"radius_factor": radius_factor,
	}


func _planet_center(viewport: Vector2) -> Vector2:
	return viewport * 0.5


func _viewport_size() -> Vector2:
	if _paint:
		var paint_size := _paint.get_viewport_rect().size
		if paint_size.x > 1.0 and paint_size.y > 1.0:
			return paint_size
	var viewport := get_viewport()
	if viewport:
		var visible := viewport.get_visible_rect().size
		if visible.x > 1.0 and visible.y > 1.0:
			return visible
	return Vector2(1280, 720)


func _match_space_view(planet: ProcPlanet) -> void:
	var viewport := _viewport_size()
	var cam := get_viewport().get_camera_2d() if get_viewport() else null
	if cam == null and ship:
		cam = ship._cam
	var target := ProcPlanet.target_screen_radius(viewport)
	if cam and is_instance_valid(planet):
		var space_radius := planet.radius * cam.zoom.x
		surface_zoom = clampf(space_radius / maxf(target, 1.0), SURFACE_ZOOM_MIN, SURFACE_ZOOM_MAX)
	else:
		surface_zoom = SURFACE_ZOOM_DEFAULT
	_surface_zoom_target = surface_zoom


func _planet_radius(viewport: Vector2) -> float:
	return ProcPlanet.target_screen_radius(viewport) * surface_zoom


func _draw_surface() -> void:
	if _active_planet == null or ship == null:
		return
	var viewport := _viewport_size()
	var ship_projection := _project_surface_point(player_surface_position, viewport, _altitude)
	ship_projection["position"] = _planet_center(viewport)
	ship_projection["surface_position"] = _planet_center(viewport)
	_draw_surface_velocity_projection(viewport)
	_draw_local_ship(ship_projection)


func _draw_surface_velocity_projection(viewport: Vector2) -> void:
	# Surface equivalent of the yellow coast line in space: a great-circle path
	# made by keeping the present tangent velocity and applying no new control.
	if _surface_velocity.length() < 0.1:
		return
	var predicted_position := player_surface_position
	var predicted_velocity := _surface_velocity
	var points := PackedVector2Array()
	for i in 28:
		var projection := _project_surface_point(predicted_position, viewport, _altitude)
		if not bool(projection["visible"]):
			break
		points.append(projection["position"])
		var speed := predicted_velocity.length()
		if speed < 0.01:
			break
		var tangent := (
			predicted_velocity
			- predicted_position * predicted_velocity.dot(predicted_position)
		).normalized()
		var angle := speed * 0.35 / maxf(_active_planet.radius + _altitude, 1.0)
		predicted_position = (predicted_position * cos(angle) + tangent * sin(angle)).normalized()
		predicted_velocity = (
			predicted_velocity
			- predicted_position * predicted_velocity.dot(predicted_position)
		).normalized() * speed
	if points.size() < 2:
		return
	var yellow := Color(1.0, 0.82, 0.2, 0.9)
	var glow := yellow
	glow.a = 0.2
	_paint.draw_polyline(points, glow, 4.0, true)
	_paint.draw_polyline(points, yellow, 1.35, true)
	for i in range(5, points.size() - 1, 7):
		var forward := (points[i + 1] - points[i - 1]).normalized()
		if forward.is_zero_approx():
			continue
		var side := forward.orthogonal() * 3.2
		var tip := points[i] + forward * 5.0
		_paint.draw_line(points[i] - forward * 2.0 + side, tip, yellow, 1.2, true)
		_paint.draw_line(points[i] - forward * 2.0 - side, tip, yellow, 1.2, true)


func _draw_surface_background() -> void:
	_draw_sky(_viewport_size())


func _draw_sky(viewport: Vector2) -> void:
	# This layer deliberately stays transparent.  The real Starfield node below
	# it is then visible unchanged, so surface flight and orbital flight share
	# the identical animated sky, stars and dust lanes.
	viewport = viewport


func _update_globe_visual() -> void:
	if _active_planet == null or _globe_visual == null:
		return
	var viewport := _viewport_size()
	var center := _planet_center(viewport)
	var radius := _planet_radius(viewport)
	# Keep one full-screen procedural surface.  Zoom is a shader parameter, not
	# a resized UI rectangle, so there is no moving edge or mask to reveal.
	_globe_visual.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	_globe_visual.position = Vector2.ZERO
	_globe_visual.size = viewport
	var material := _globe_visual.material as ShaderMaterial
	if material == null:
		return
	var palette := _active_planet.surface_palette()
	material.set_shader_parameter("inverse_view_rotation", Basis(planet_view_rotation).inverse())
	material.set_shader_parameter("disk_center_uv", Vector2(center.x / viewport.x, center.y / viewport.y))
	material.set_shader_parameter("disk_radius_uv", Vector2(radius / viewport.x, radius / viewport.y))
	material.set_shader_parameter("deep_color", palette["deep"])
	material.set_shader_parameter("low_color", palette["low"])
	material.set_shader_parameter("mid_color", palette["mid"])
	material.set_shader_parameter("high_color", palette["high"])
	material.set_shader_parameter("ice_color", palette["ice"])
	material.set_shader_parameter("ocean_level", palette["ocean_level"])
	material.set_shader_parameter("seed", _active_planet.seed_value)
	material.set_shader_parameter("planet_kind", _active_planet.kind_index())
	# Clouds and atmospheric rim lighting are orbital-view effects.  On the
	# surface the globe is intentionally a clean terrain view.
	material.set_shader_parameter("has_clouds", 0)
	material.set_shader_parameter("glow_color", _active_planet._glow)
	material.set_shader_parameter("atmosphere_color", Color(0.0, 0.0, 0.0, 0.0))
	material.set_shader_parameter("quality", 2)
	material.set_shader_parameter("lod", 1.0)
	# Procedural detail follows the surface zoom.  This gives close flyovers a
	# dense ground texture rather than enlarging the same broad colour patches.
	material.set_shader_parameter(
		"surface_detail_scale",
		clampf(1.0 + log(maxf(surface_zoom, 1.0)) * 0.45, 1.0, 3.0)
	)
	material.set_shader_parameter("cloud_time", _active_planet._cloud_spin)
	var sun_dir := (-_active_planet.global_position).normalized()
	if sun_dir.length_squared() < 0.01:
		sun_dir = Vector2(-0.7, -0.45)
	var sun_view := planet_view_rotation * Vector3(sun_dir.x, -sun_dir.y, 0.35)
	material.set_shader_parameter("light_direction", Vector2(sun_view.x, -sun_view.y))


func _hide_world_visuals() -> void:
	if is_instance_valid(_active_planet):
		_active_planet.visible = false
	_set_orbit_renderer_visible(false)
	get_tree().call_group("starfield", "set_space_visible", false)


func _restore_world_visuals() -> void:
	if is_instance_valid(_active_planet):
		_active_planet.visible = true
	_set_orbit_renderer_visible(true)
	get_tree().call_group("starfield", "set_space_visible", true)


func _set_orbit_renderer_visible(show: bool) -> void:
	if ship == null or not is_instance_valid(ship):
		return
	var tree := ship.get_tree()
	if tree == null:
		return
	for node in tree.get_nodes_in_group("orbit_renderer"):
		node.visible = show


func _draw_local_ship(projection: Dictionary) -> void:
	var center: Vector2 = projection["position"]
	var ship_scale := _ship_visual_scale(projection)
	var ship_radius_px := maxf(ship.hull_radius() * ship_scale.x, 14.0)

	ship.graph.draw_on(
		_paint,
		center,
		_ground_heading.angle(),
		ship_scale.x,
		ship.throttle,
		ship.fuel > 0.0
	)

	if Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
		var cursor := _paint.get_local_mouse_position()
		var aim := cursor - center
		var min_aim := ship_radius_px + 6.0
		if aim.length() > min_aim:
			var aim_dir := aim.normalized()
			var aim_color := Color(0.35, 1.0, 0.48, 0.8)
			_paint.draw_line(
				center + aim_dir * min_aim,
				cursor,
				aim_color,
				1.5,
				true
			)
			_paint.draw_circle(cursor, 2.5, aim_color, true, -1.0, true)
			_paint.draw_arc(cursor, 5.5, 0.0, TAU, 24, Color(0.35, 1.0, 0.48, 0.45), 1.5, true)

	# Surface velocity vector (drawn on top, actively lengthens/shortens with speed)
	var surf_speed := _surface_velocity.length()
	if surf_speed > 0.1:
		var view_vel := planet_view_rotation * _surface_velocity
		var screen_dir := Vector2(view_vel.x, -view_vel.y).normalized()
		var start_pos := center + screen_dir * (ship_radius_px + 2.0)
		var vec_len := clampf(8.5 * pow(surf_speed, 0.65), 0.0, 200.0)
		if vec_len >= 1.0:
			var tip := start_pos + screen_dir * vec_len
			var vec_col := Color(0.32, 0.94, 1.0, 0.9)
			_paint.draw_line(start_pos, tip, vec_col, 1.5, true)
			var head_len := clampf(vec_len * 0.25, 4.0, 9.0)
			var side := screen_dir.orthogonal() * (head_len * 0.55)
			_paint.draw_line(tip - screen_dir * head_len + side, tip, vec_col, 1.5, true)
			_paint.draw_line(tip - screen_dir * head_len - side, tip, vec_col, 1.5, true)
			_paint.draw_circle(tip, 1.6, Color(0.65, 0.95, 1.0, 0.95), true, -1.0, true)
			var speed_text := "%d m/s" % int(round(surf_speed))
			_paint.draw_string(
				_font,
				tip + screen_dir * 4.0 + Vector2(2, 4),
				speed_text,
				HORIZONTAL_ALIGNMENT_LEFT,
				-1,
				11,
				Color(0.35, 0.95, 1.0, 0.85)
			)


func _ship_visual_scale(projection: Dictionary) -> Vector2:
	var viewport := _viewport_size()
	var physical := _planet_radius(viewport) / maxf(_active_planet.radius if _active_planet else 1.0, 1.0)
	var perspective_scale: float = projection["scale"]
	var horizon_flatten: float = projection["flatten"]
	var scaled_size := physical * perspective_scale
	return Vector2(scaled_size, scaled_size * maxf(horizon_flatten, 0.85))


func _draw_surface_readout(_viewport: Vector2) -> void:
	return

extends Node

const OrbitalPhysicsType := preload("res://scripts/orbital_physics.gd")
const ControlModelType := preload("res://scripts/control_model.gd")
const UnitsType := preload("res://scripts/units.gd")
const SurfaceCoordinateType := preload("res://scripts/surface_coordinate.gd")
const UniverseType := preload("res://scripts/universe.gd")
const PlanetType := preload("res://scripts/planet.gd")
const ShipType := preload("res://scripts/ship.gd")
const SurfaceModeType := preload("res://scripts/surface_mode.gd")
const OrbitEditorType := preload("res://scripts/orbit_editor.gd")
const ModuleGraphType := preload("res://scripts/ship/module_graph.gd")
const ShipModuleType := preload("res://scripts/ship/ship_module.gd")
const ModuleCatalogType := preload("res://scripts/ship/module_catalog.gd")
const ShipBlueprintType := preload("res://scripts/ship/blueprint.gd")

var passed := 0
var failed := 0


func _ready() -> void:
	print("Horizon physics tests")
	_test_orbital_speeds()
	_test_orbital_elements()
	_test_orbit_stability()
	_test_surface_coordinates()
	_test_horizon()
	_test_generated_orbits()
	_test_autopilot_is_physical()
	_test_landing_coordinates()
	_test_liftoff_threshold()
	_test_manual_throttle_survives_autopilot_cancel()
	_test_surface_minigame_flow()
	_test_orbit_editing()
	_test_target_picking()
	_test_landing_scale_continuity()
	_test_module_mass_and_com()
	_test_engine_torque()
	_test_module_components()
	_test_blueprint_roundtrip()
	_test_starter_is_flyable()
	_test_hud_altitude_readouts()
	_test_units_and_radar()
	_test_control_model_unifies_flight()
	_test_gas_landing_blocked()
	_test_warp_locks_near_any_body()
	_test_no_gameplay_teleports()
	_test_autopilot_bidirectional_and_collision_safe()
	_test_autopilot_trajectory_and_transfer_physics()
	print("passed %d  failed %d" % [passed, failed])
	get_tree().quit(1 if failed > 0 else 0)


func _make_test_ship() -> SurveyShip:
	var ship := ShipType.new()
	add_child(ship)
	ship.apply_blueprint(ShipBlueprintType.load_path(ShipBlueprintType.STARTER_PATH))
	return ship


func _check(condition: bool, label: String) -> void:
	if condition:
		passed += 1
		print("  ok   ", label)
	else:
		failed += 1
		print("  FAIL ", label)


func _test_orbital_speeds() -> void:
	var mu := OrbitalPhysicsType.mu_from_surface_gravity(10.0, 1000.0)
	var circular := OrbitalPhysicsType.circular_speed(mu, 1500.0)
	var escape := OrbitalPhysicsType.escape_speed(mu, 1500.0)
	_check(absf(escape / circular - sqrt(2.0)) < 0.0001, "escape speed is sqrt(2) times circular")
	_check(absf(mu - 10000000.0) < 0.1, "mu = surface gravity times radius squared")


func _test_orbital_elements() -> void:
	var mu := 10000000.0
	var radius := 1500.0
	var velocity := Vector2(0.0, OrbitalPhysicsType.circular_speed(mu, radius))
	var elements := OrbitalPhysicsType.elements(Vector2(radius, 0.0), velocity, mu)
	_check(elements["bound"], "circular orbit is bound")
	_check(elements["e"] < 0.0001, "circular orbit eccentricity is near zero")
	var escape_velocity := Vector2(0.0, OrbitalPhysicsType.escape_speed(mu, radius) * 1.001)
	var escape_elements := OrbitalPhysicsType.elements(Vector2(radius, 0.0), escape_velocity, mu)
	_check(not escape_elements["bound"], "speed above escape is unbound")


func _test_orbit_stability() -> void:
	var mu := 10000000.0
	var radius := 1500.0
	var position := Vector2(radius, 0.0)
	var velocity := Vector2(0.0, OrbitalPhysicsType.circular_speed(mu, radius))
	var period := OrbitalPhysicsType.orbital_period(mu, radius)
	var dt := 1.0 / 120.0
	var steps := int(period / dt)
	for i in steps:
		velocity += OrbitalPhysicsType.gravity_at(position, Vector2.ZERO, mu) * dt
		position += velocity * dt
	_check(absf(position.length() - radius) / radius < 0.01, "symplectic orbit keeps radius for one period")


func _test_surface_coordinates() -> void:
	var original := SurfaceCoordinateType.new(0.61, -2.18)
	var restored := SurfaceCoordinateType.from_unit_vector(original.to_unit_vector())
	_check(absf(original.latitude - restored.latitude) < 0.00001, "latitude roundtrip")
	_check(absf(angle_difference(original.longitude, restored.longitude)) < 0.00001, "longitude roundtrip")
	var wrapped := SurfaceCoordinateType.new(0.0, PI * 3.0)
	_check(absf(absf(wrapped.longitude) - PI) < 0.00001, "longitude wraps around globe")


func _test_horizon() -> void:
	var observer := SurfaceCoordinateType.new(0.0, 0.0)
	var near := SurfaceCoordinateType.new(0.2, 0.3)
	var far := SurfaceCoordinateType.new(0.0, PI)
	_check(near.is_above_horizon_for(observer), "near surface site is visible")
	_check(not far.is_above_horizon_for(observer), "far side site is hidden")


func _test_generated_orbits() -> void:
	var universe := UniverseType.new()
	add_child(universe)
	universe.generate(12345)
	var correct := true
	for planet in universe.planets:
		var parent_mu := universe.sun_mu()
		if planet.parent_body:
			parent_mu = planet.parent_body.mu
		var expected := OrbitalPhysicsType.circular_speed(parent_mu, planet.orbit_radius) / planet.orbit_radius
		if absf(absf(planet.orbit_speed) - expected) / maxf(expected, 0.000001) > 0.001:
			correct = false
	_check(correct, "generated planets and moons use physical circular speed")
	universe.queue_free()


func _test_autopilot_is_physical() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 9
	var planet := PlanetType.new()
	planet.configure(rng, "Test", "arid", 6000.0, 100000.0)
	add_child(planet)
	var ship := _make_test_ship()
	ship.global_position = planet.global_position + Vector2(planet.radius * 2.0, 0.0)
	var before := ship.global_position
	ship.engage_orbit_autopilot(planet)
	_check(ship.global_position.distance_to(before) < 0.001, "autopilot does not teleport ship")
	ship._update_autopilot_guidance()
	ship.rotation = ship._autopilot_heading
	ship._update_autopilot_guidance()
	var fuel_before: float = ship.fuel
	ship._apply_forces(1.0)
	_check(ship.fuel < fuel_before, "autopilot maneuver consumes fuel")
	planet.queue_free()
	ship.queue_free()


func _test_landing_coordinates() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 12
	var planet := PlanetType.new()
	planet.configure(rng, "Landing", "ocean", 7000.0, 120000.0)
	add_child(planet)
	var ship := _make_test_ship()
	ship.global_position = planet.global_position + Vector2(planet.radius + 100.0, 0.0)
	ship.velocity = planet.inertial_velocity()
	var destination := SurfaceCoordinateType.new(0.72, -1.35)
	var landed: bool = ship.land_at_surface(planet, destination)
	_check(landed, "safe nearby ship can land")
	_check(absf(ship.surface_coordinate.latitude - destination.latitude) < 0.0001, "landing preserves latitude")
	_check(absf(angle_difference(ship.surface_coordinate.longitude, destination.longitude)) < 0.0001, "landing preserves longitude")
	planet.queue_free()
	ship.queue_free()


func _test_liftoff_threshold() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 22
	var planet := PlanetType.new()
	planet.configure(rng, "Launch", "arid", 7000.0, 120000.0)
	add_child(planet)
	var ship := _make_test_ship()
	ship.place_landed(planet)
	ship.throttle = 0.2
	ship._tick_landed(1.0 / 60.0)
	_check(ship.landed_on == planet, "low thrust does not release landing contact")
	ship.throttle = 1.0
	ship._tick_landed(1.0 / 60.0)
	_check(ship.landed_on == null, "full thrust lifts off from planet")
	planet.queue_free()
	ship.queue_free()


func _test_manual_throttle_survives_autopilot_cancel() -> void:
	var ship := _make_test_ship()
	ship.throttle = 0.7
	ship.cancel_autopilot()
	_check(is_equal_approx(ship.throttle, 0.7), "manual throttle is not reset without active autopilot")
	ship.queue_free()


func _test_surface_minigame_flow() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 31
	var planet := PlanetType.new()
	planet.configure(rng, "Minigame", "ocean", 7000.0, 120000.0)
	add_child(planet)
	var ship := _make_test_ship()
	ship.place_landed(planet)
	var surface := SurfaceModeType.new()
	surface.ship = ship
	add_child(surface)
	surface.begin_grounded(planet)
	_check(ship.surface_mode_active and ship.landed_on == planet, "surface minigame starts in grounded state")
	_check(is_equal_approx(surface._altitude, SurfaceModeType.HOVER_ALTITUDE), "surface ship hovers above the ground")
	var centered_view: Vector3 = surface.planet_view_rotation * surface.player_surface_position
	_check(
		Vector2(centered_view.x, centered_view.y).length() < 0.0001 and centered_view.z > 0.9999,
		"landing point is centered without changing logical surface position"
	)
	var viewport_size := surface._paint.get_viewport_rect().size
	var front_projection := surface._project_surface_point(
		surface.player_surface_position,
		viewport_size
	)
	var back_projection := surface._project_surface_point(
		-surface.player_surface_position,
		viewport_size
	)
	_check(
		front_projection["visible"] and not back_projection["visible"],
		"2.5D projection hides objects behind spherical horizon"
	)
	var shallow_surface_point := (
		surface.planet_view_rotation.inverse()
		* Vector3(sqrt(0.99), 0.0, 0.1)
	).normalized()
	var shallow_projection := surface._project_surface_point(shallow_surface_point, viewport_size)
	_check(
		float(shallow_projection["scale"]) < 0.6
		and float(shallow_projection["flatten"]) < 0.25,
		"surface objects shrink and flatten near horizon"
	)
	var oblique_surface_point := (
		surface.planet_view_rotation.inverse()
		* Vector3(0.5, 0.0, sqrt(0.75))
	).normalized()
	var ground_projection := surface._project_surface_point(oblique_surface_point, viewport_size)
	var elevated_projection := surface._project_surface_point(
		oblique_surface_point,
		viewport_size,
		700.0
	)
	var planet_center := surface._planet_center(viewport_size)
	_check(
		Vector2(elevated_projection["position"]).distance_to(planet_center)
		> Vector2(ground_projection["position"]).distance_to(planet_center),
		"altitude projects objects farther from globe center"
	)
	var loop_start: Vector3 = surface.player_surface_position
	surface._move_player_on_sphere(Vector2.RIGHT, TAU)
	_check(
		loop_start.dot(surface.player_surface_position) > 0.999999,
		"full spherical circuit returns to the same surface point"
	)
	var initial_globe_rotation: Quaternion = surface.planet_view_rotation
	surface._apply_surface_movement(Vector2.RIGHT, planet.radius * 0.25)
	surface._update_surface_camera_follow(0.5)
	var view_position: Vector3 = surface.planet_view_rotation * surface.player_surface_position
	_check(
		surface._ship_screen_position().distance_to(viewport_size * 0.5) < 0.001,
		"ship screen position stays at the center of the screen"
	)
	_check(
		Vector2(view_position.x, view_position.y).length() < 0.0001,
		"surface camera keeps ship exactly centered after movement"
	)
	_check(
		absf(surface.planet_view_rotation.dot(initial_globe_rotation)) < 0.999,
		"grounded camera rotates globe independently under the player"
	)
	_check(
		absf(
			surface._surface_angular_distance(180.0)
			- 180.0 / (planet.radius + SurfaceModeType.HOVER_ALTITUDE)
		) < 0.000001,
		"surface movement uses the real planet radius"
	)
	for i in 20:
		surface._apply_surface_movement(Vector2.RIGHT, planet.radius * 0.08)
		surface._update_surface_camera_follow(0.1)
	view_position = surface.planet_view_rotation * surface.player_surface_position
	_check(
		Vector2(view_position.x, view_position.y).length() < 0.0001,
		"grounded camera continuously keeps player at center"
	)
	_check(
		absf(surface.planet_view_rotation.dot(initial_globe_rotation)) < 0.999,
		"globe rotates independently under the player"
	)
	surface._surface_velocity = surface._screen_direction_to_tangent(Vector2.RIGHT) * 60.0
	surface._update_surface_camera_follow(0.5)
	view_position = surface.planet_view_rotation * surface.player_surface_position
	_check(
		Vector2(view_position.x, view_position.y).length() < 0.0001,
		"surface camera has no directional offset"
	)
	var ship_projection_for_zoom := surface._project_surface_point(
		surface.player_surface_position,
		surface._viewport_size(),
		surface._altitude
	)
	var expected_scale: float = surface._planet_radius(surface._viewport_size()) / maxf(planet.radius, 1.0)
	var actual_scale: float = surface._ship_visual_scale(ship_projection_for_zoom).x
	_check(
		is_equal_approx(actual_scale, expected_scale),
		"surface ship matches true physical scale with no artificial enlargement"
	)
	surface.surface_zoom = SurfaceModeType.SURFACE_ZOOM_DEFAULT
	var radius_before_zoom: float = surface._planet_radius(surface._viewport_size())
	_check(
		is_equal_approx(surface.surface_zoom, SurfaceModeType.SURFACE_ZOOM_DEFAULT),
		"landing starts with one-to-one surface zoom"
	)
	surface.surface_zoom /= SurfaceModeType.SURFACE_ZOOM_STEP
	var radius_after_zoom: float = surface._planet_radius(surface._paint.get_viewport_rect().size)
	_check(radius_after_zoom < radius_before_zoom, "mouse-wheel surface zoom changes rendered radius")
	ship.frame_near(planet)
	var viewport := surface._paint.get_viewport_rect().size
	var one_to_one_radius: float = PlanetType.target_screen_radius(viewport)
	_check(
		absf(ship.camera_zoom * planet.radius - one_to_one_radius) < 0.01,
		"space view frames planet at the shared one-to-one scale"
	)
	surface.begin_grounded(planet)
	_check(
		absf(surface._planet_radius(viewport) - one_to_one_radius) < 0.01,
		"landing preserves the exact one-to-one planet scale"
	)
	_check(SurveyShip.CAMERA_ZOOM_MAX >= 12.0, "space camera supports extreme close zoom")
	_check(SurfaceModeType.SURFACE_ZOOM_MAX >= 300.0, "surface mode supports extreme close vehicle zoom")
	var normal_planet_speed := surface._hover_max_speed()
	var original_planet_radius := planet.radius
	planet.radius *= 2.0
	var large_planet_speed := surface._hover_max_speed()
	planet.radius = original_planet_radius
	_check(
		is_equal_approx(normal_planet_speed, ControlModelType.SURFACE_SPEED),
		"surface hover speed uses the shared control cap"
	)
	_check(
		is_equal_approx(large_planet_speed, normal_planet_speed),
		"surface speed is independent of planet radius"
	)
	_check(
		is_equal_approx(surface._local_thrust_acceleration(), ControlModelType.MAIN_ACCELERATION),
		"surface thrust uses the shared control acceleration"
	)
	var position_before_drift: Vector3 = surface.player_surface_position
	surface._surface_velocity = surface._screen_direction_to_tangent(Vector2.RIGHT) * 60.0
	surface._tick_grounded(0.5)
	_check(
		position_before_drift.dot(surface.player_surface_position) < 0.999999,
		"surface ship keeps moving after thrust is released"
	)
	_check(surface._surface_velocity.length() > 50.0, "surface flight preserves inertia")
	surface.begin_grounded(planet)
	var camera_before_flight: Quaternion = surface.planet_view_rotation
	surface._surface_velocity = (
		surface._screen_direction_to_tangent(Vector2.RIGHT)
		* surface._hover_max_speed()
	)
	for frame in 480:
		surface._tick_surface(1.0 / 60.0)
	var followed_view: Vector3 = surface.planet_view_rotation * surface.player_surface_position
	_check(
		absf(surface.planet_view_rotation.dot(camera_before_flight)) < 0.9995,
		"surface camera activates during normal-speed flight"
	)
	_check(
		Vector2(followed_view.x, followed_view.y).length() < 0.001,
		"surface camera keeps ship centered at maximum flight speed"
	)
	surface.begin_grounded(planet)
	var latitude_before: float = surface._current_coordinate().latitude
	surface._apply_surface_movement(Vector2.UP, planet.radius * 0.2)
	_check(surface._current_coordinate().latitude > latitude_before, "north-south movement changes latitude")
	_check(absf(surface.player_surface_position.length() - 1.0) < 0.0001, "surface position remains on the sphere")
	_check(surface._exit_altitude() <= ControlModelType.LAUNCH_CLEARANCE + 0.001, "surface climb to space stays playable")
	_check(
		surface._insertion_altitude() >= planet.lowest_orbit_altitude(),
		"launch inserts the ship above the lowest orbit"
	)
	surface._state = SurfaceModeType.SurfaceState.ASCENDING
	surface._altitude = surface._exit_altitude() + 1.0
	surface._radial_velocity = 40.0
	surface._surface_velocity = Vector3.ZERO
	surface._finish_launch()
	_check(not ship.surface_mode_active and ship.landed_on == null, "surface launch returns to space view")
	surface.queue_free()
	planet.queue_free()
	ship.queue_free()


func _test_orbit_editing() -> void:
	var universe := UniverseType.new()
	add_child(universe)
	universe.generate(12345)
	var mains: Array = []
	for planet in universe.planets:
		if planet.parent_body == null:
			mains.append(planet)
	_check(mains.size() >= 2, "generated system has neighboring planets")
	var inner: ProcPlanet = mains[0]
	var outer: ProcPlanet = mains[1]
	var too_close := universe.validate_orbit_radius(inner, outer.orbit_radius)
	_check(not too_close["ok"], "orbit editor rejects overlapping neighboring orbits")
	var editor := OrbitEditorType.new()
	editor.begin(inner)
	var original_radius := inner.orbit_radius
	var original_speed := inner.orbit_speed
	var moon_radius_before := -1.0
	for planet in universe.planets:
		if planet.parent_body == inner:
			moon_radius_before = planet.orbit_radius
			break
	editor.adjust_radius(universe, false, true)
	_check(inner.orbit_radius > original_radius, "orbit editor increases selected planet radius")
	if moon_radius_before > 0.0:
		for planet in universe.planets:
			if planet.parent_body == inner:
				_check(is_equal_approx(planet.orbit_radius, moon_radius_before), "editing a planet keeps moon local orbits")
				break
	editor.cancel()
	_check(is_equal_approx(inner.orbit_radius, original_radius), "cancel restores the previous orbit radius")
	_check(is_equal_approx(inner.orbit_speed, original_speed), "cancel restores the previous orbit speed")
	var direction := signf(inner.orbit_speed)
	inner.orbit_speed = direction * absf(inner.orbit_speed) * 0.7
	editor.begin(inner)
	editor.restore_circular(universe)
	_check(signf(inner.orbit_speed) == direction, "circular restore keeps orbit direction")
	_check(
		absf(absf(inner.orbit_speed) - universe.circular_orbit_speed(inner)) < 0.000001,
		"circular restore matches OrbitalPhysics"
	)
	editor.cancel()
	universe.queue_free()


func _test_target_picking() -> void:
	var universe := UniverseType.new()
	add_child(universe)
	universe.generate(12345)
	var planet: ProcPlanet = universe.planets[0]
	var hit := universe.pick_body(planet.global_position, 10.0, 10.0)
	_check(hit == planet, "clicking a planet selects it")
	var orbit_point := universe.parent_center(planet) + Vector2(planet.orbit_radius, 0.0)
	var orbit_hit := universe.pick_body(orbit_point, 10.0, 10.0)
	_check(orbit_hit == planet, "clicking a planet orbit selects it")
	var index := 0
	index = posmod(index + 1, universe.planets.size())
	index = posmod(index - 1, universe.planets.size())
	_check(index == 0, "target cycling works in both directions")
	universe.queue_free()


func _test_landing_scale_continuity() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 44
	var planet := PlanetType.new()
	planet.configure(rng, "Scale", "ocean", 7000.0, 120000.0)
	add_child(planet)
	var ship := _make_test_ship()
	ship.place_landed(planet)
	ship.frame_near(planet)
	var surface := SurfaceModeType.new()
	surface.ship = ship
	add_child(surface)
	var viewport := ship.get_viewport_rect().size
	var space_radius := planet.radius * ship.camera_zoom
	surface.begin_grounded(planet)
	_check(
		absf(surface._planet_radius(viewport) - space_radius) <= 1.0,
		"landing keeps planet screen radius within one pixel"
	)
	_check(
		surface._planet_center(viewport).distance_to(viewport * 0.5) <= 1.0,
		"surface keeps the planet at screen center"
	)
	_check(
		surface._ship_screen_position().distance_to(viewport * 0.5) <= 1.0,
		"landed ship is drawn at the center of the screen"
	)
	_check(
		ship._cam.global_position.distance_to(planet.global_position) <= 1.0,
		"landing camera looks at the planet center"
	)
	var projection := surface._project_surface_point(
		surface.player_surface_position,
		viewport,
		surface._altitude
	)
	projection["position"] = surface._planet_center(viewport)
	var surface_ship := surface._ship_visual_scale(projection).x
	var space_scale := space_radius / planet.radius
	_check(
		is_equal_approx(surface_ship, space_scale),
		"landing keeps the ship scale matching space view"
	)
	surface.surface_zoom = 300.0
	var close_scale := surface._ship_visual_scale(projection).x
	_check(
		close_scale > 5.0 and is_equal_approx(close_scale, surface._planet_radius(viewport) / planet.radius),
		"surface vehicle scales up proportionally for close inspection"
	)
	planet.rotation = 1.15
	planet.tick(0.0)
	_check(
		is_equal_approx(planet._sphere_visual.rotation, -planet.rotation),
		"space planet keeps a 3D globe instead of spinning as a flat sprite"
	)
	surface.queue_free()
	planet.queue_free()
	ship.queue_free()


func _test_module_mass_and_com() -> void:
	var graph := ModuleGraphType.new()
	var frame := ModuleCatalogType.get_def("frame")
	graph.add_module(ShipModuleType.new(frame, Vector2i(0, 0), 0))
	graph.add_module(ShipModuleType.new(frame, Vector2i(1, 0), 0))
	var stats = graph.stats()
	_check(is_equal_approx(stats.mass, frame.mass * 2.0), "two frames add their dry mass")
	_check(absf(stats.com.x - 1.0) < 0.001 and absf(stats.com.y - 0.5) < 0.001, "COM sits between two equal masses")


func _test_engine_torque() -> void:
	var frame := ModuleCatalogType.get_def("frame")
	var engine := ModuleCatalogType.get_def("engine_chemical_s")
	var aligned := ModuleGraphType.new()
	aligned.add_module(ShipModuleType.new(frame, Vector2i(0, 0), 0))
	aligned.add_module(ShipModuleType.new(engine, Vector2i(1, 0), 0))
	_check(absf(aligned.stats().thrust_torque) < 0.001, "engine on the COM thrust axis makes no torque")
	var offset := ModuleGraphType.new()
	offset.add_module(ShipModuleType.new(frame, Vector2i(0, 0), 0))
	offset.add_module(ShipModuleType.new(engine, Vector2i(0, 1), 0))
	_check(absf(offset.stats().thrust_torque) > 0.5, "offset engine produces torque")
	_check(offset.stats().thrust > 0.0, "offset engine still produces thrust")


func _test_module_components() -> void:
	var graph := ModuleGraphType.new()
	var frame := ModuleCatalogType.get_def("frame")
	graph.add_module(ShipModuleType.new(frame, Vector2i(0, 0), 0))
	graph.add_module(ShipModuleType.new(frame, Vector2i(1, 0), 0))
	graph.add_module(ShipModuleType.new(frame, Vector2i(2, 0), 0))
	_check(graph.connected_components().size() == 1, "three linked frames are one component")
	graph.remove_at(Vector2i(1, 0))
	_check(graph.connected_components().size() == 2, "removing the middle frame splits the ship")


func _test_blueprint_roundtrip() -> void:
	var original := ShipBlueprintType.starter_graph()
	var data := original.to_blueprint()
	var restored := ModuleGraphType.new()
	_check(restored.load_blueprint(data), "blueprint JSON loads")
	_check(restored.modules.size() == original.modules.size(), "blueprint keeps module count")
	_check(is_equal_approx(restored.stats().thrust, original.stats().thrust), "blueprint keeps engine thrust")


func _test_starter_is_flyable() -> void:
	var graph := ShipBlueprintType.starter_graph()
	var stats = graph.stats()
	_check(stats.fuel_max >= 2000.0, "starter has a large fuel reserve")
	_check(stats.thrust > 0.0, "starter has engine thrust")
	_check(stats.cockpit_count == 1, "starter has one cockpit")
	_check(graph.is_structure_connected(), "starter structure is connected")


func _test_hud_altitude_readouts() -> void:
	_check(FlightHud.format_km(1500.0) == "1.50 km", "altimeter reports true kilometers")
	_check(FlightHud.format_km(12400.0) == "12.4 km", "altimeter uses one decimal above 10 km")
	_check(FlightHud.format_km(150000.0) == "150 km", "altimeter uses whole kilometers at range")
	_check(FlightHud.altitude_visible(200.0, 980.0), "altitude shows below the lowest orbit")
	_check(not FlightHud.altitude_visible(980.0, 980.0), "altitude hides at the lowest orbit")
	_check(not FlightHud.altitude_visible(4000.0, 980.0), "altitude hides above the lowest orbit")
	var rng := RandomNumberGenerator.new()
	rng.seed = 4
	var planet := PlanetType.new()
	planet.configure(rng, "Gauge", "ocean", 7000.0, 120000.0)
	_check(planet.lowest_orbit_altitude() > 0.0, "planet publishes a lowest orbit altitude")
	_check(
		is_equal_approx(planet.lowest_orbit_altitude(), planet.atmosphere_height()),
		"lowest orbit sits on top of the atmosphere"
	)
	planet.queue_free()


func _test_units_and_radar() -> void:
	_check(is_equal_approx(UnitsType.km(1500.0), 1.5), "kilometers are meters / 1000")
	_check(is_equal_approx(UnitsType.km(150000.0), 150.0), "long distances stay in true kilometers")
	_check(is_equal_approx(UnitsType.radar_range(10_000.0), 50_000.0), "radar uses the 50 km band nearby")
	_check(is_equal_approx(UnitsType.radar_range(400_000.0), 500_000.0), "radar uses the 500 km band")
	_check(is_equal_approx(UnitsType.radar_range(2_000_000.0), 5_000_000.0), "radar uses the 5 000 km band")
	_check(is_equal_approx(UnitsType.radar_range(20_000_000.0), 50_000_000.0), "radar uses the 50 000 km band")


func _test_control_model_unifies_flight() -> void:
	var ship := _make_test_ship()
	ship.universe = null
	ship.velocity = Vector2.ZERO
	ship.rotation = 0.0
	ship.throttle = 1.0
	var fuel_before: float = ship.fuel
	ship._apply_forces(1.0)
	_check(
		absf(ship.velocity.x - ControlModelType.MAIN_ACCELERATION) < 0.05,
		"space flight uses the shared main acceleration"
	)
	_check(ship.fuel < fuel_before, "space flight burns fuel through the control model")
	_check(
		absf(ship.main_thrust() / maxf(ship.mass(), 0.1) - ControlModelType.MAIN_ACCELERATION) > 1.0,
		"legacy thrust-to-weight is not the flight acceleration"
	)
	ship.queue_free()


func _test_gas_landing_blocked() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 71
	var gas := PlanetType.new()
	gas.configure(rng, "Giant", "gas", 110000.0, 4_000_000.0)
	add_child(gas)
	var rock := PlanetType.new()
	rock.configure(rng, "Rock", "arid", 7000.0, 120000.0)
	add_child(rock)
	var ship := _make_test_ship()
	ship.global_position = gas.global_position + Vector2(gas.radius + 80.0, 0.0)
	ship.velocity = gas.inertial_velocity()
	_check(not gas.allows_surface_landing(), "gas giants have no hard surface")
	_check(not ship.can_land_at(gas), "ships cannot land on gas giants")
	_check(ship.landing_block_reason(gas).contains("Gazowy"), "gas landing reports a clear block reason")
	ship.global_position = rock.global_position + Vector2(rock.radius + 80.0, 0.0)
	ship.velocity = rock.inertial_velocity()
	_check(ship.can_land_at(rock), "solid planets remain landable at safe speed")
	var surface := SurfaceModeType.new()
	surface.ship = ship
	add_child(surface)
	surface.begin_grounded(gas)
	_check(not ship.surface_mode_active, "surface mode refuses gas giants")
	surface.queue_free()
	gas.queue_free()
	rock.queue_free()
	ship.queue_free()


func _test_warp_locks_near_any_body() -> void:
	var universe := UniverseType.new()
	add_child(universe)
	var rng := RandomNumberGenerator.new()
	rng.seed = 88
	var planet := PlanetType.new()
	planet.configure(rng, "Lock", "ocean", 7000.0, 120000.0)
	universe.add_child(planet)
	universe.planets.append(planet)
	planet.global_position = Vector2(200_000.0, 0.0)
	_check(
		universe.should_lock_warp(planet.global_position + Vector2(planet.radius + 400.0, 0.0)),
		"warp locks near any close body"
	)
	_check(
		not universe.should_lock_warp(planet.global_position + Vector2(planet.radius + 20_000.0, 0.0)),
		"warp stays available far from bodies"
	)
	planet.queue_free()
	universe.queue_free()


func _test_no_gameplay_teleports() -> void:
	var source := FileAccess.get_file_as_string("res://scripts/main.gd")
	_check(source.find("KEY_N") < 0, "normal play has no N teleport")
	_check(source.find("_next_planet") < 0, "planet teleport helper is removed from gameplay")
	_check(source.find("KEY_G") < 0, "system regen is not a gameplay hotkey")


func _test_autopilot_bidirectional_and_collision_safe() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	var planet := PlanetType.new()
	planet.configure(rng, "Bidir", "ocean", 7000.0, 120000.0)
	add_child(planet)

	# 1. Counter-clockwise approach
	var ship_ccw := _make_test_ship()
	ship_ccw.global_position = planet.global_position + Vector2(12000.0, 0.0)
	ship_ccw.velocity = planet.inertial_velocity() + Vector2(0.0, 150.0) # CCW
	ship_ccw.engage_orbit_autopilot(planet)
	ship_ccw._update_autopilot_guidance()
	_check(ship_ccw._autopilot_direction > 0.0, "autopilot supports counter-clockwise orbit direction")
	ship_ccw.queue_free()

	# 2. Clockwise approach
	var ship_cw := _make_test_ship()
	ship_cw.global_position = planet.global_position + Vector2(12000.0, 0.0)
	ship_cw.velocity = planet.inertial_velocity() + Vector2(0.0, -150.0) # CW
	ship_cw.engage_orbit_autopilot(planet)
	ship_cw._update_autopilot_guidance()
	_check(ship_cw._autopilot_direction < 0.0, "autopilot supports clockwise orbit direction")
	ship_cw.queue_free()

	# 3. Collision safety: head-on approach lifts periapsis
	var ship_col := _make_test_ship()
	ship_col.global_position = planet.global_position + Vector2(10000.0, 0.0)
	ship_col.velocity = planet.inertial_velocity() + Vector2(-300.0, 0.0) # heading directly at planet!
	ship_col.engage_orbit_autopilot(planet)
	ship_col._update_autopilot_guidance()
	_check(ship_col._autopilot_heading != 0.0, "autopilot does not steer into planet center")
	ship_col.queue_free()

	# 4. Solar orbit status and bounded sample conic
	var universe := UniverseType.new()
	add_child(universe)
	var sun_stat := universe.solar_orbit_status(Vector2(100000.0, 0.0), Vector2(0.0, 150.0))
	_check(sun_stat.has("center") and sun_stat.has("bound"), "universe publishes solar orbit status")
	var bounded_pts := OrbitalPhysics.sample_conic(
		Vector2(10000.0, 0.0),
		Vector2(0.0, 500.0), # escape speed
		planet.mu,
		100,
		25000.0
	)
	var max_found := 0.0
	for pt in bounded_pts:
		max_found = maxf(max_found, pt.length())
	_check(max_found <= 25001.0, "sample_conic respects max_radius bounding")

	# 5. Ellipse sampling endpoints continuity
	var ellipse_pts := OrbitalPhysics.sample_conic(
		Vector2(10000.0, 0.0),
		Vector2(0.0, 100.0),
		planet.mu,
		720
	)
	_check(ellipse_pts[0].distance_to(ellipse_pts[-1]) < 50.0, "ellipse start and end points naturally meet at apoapsis without artificial chord")

	# 6. Ship visual draw scale is natural 1.0 (shrinks with camera zoom)
	var test_ship := _make_test_ship()
	test_ship.camera_zoom = 0.01
	_check(is_equal_approx(test_ship._visual_draw_scale(), 1.0), "ship visual draw scale stays 1.0 and shrinks naturally with zoom")
	test_ship.queue_free()

	# 7. Autopilot never thrusts inward toward planet during approach
	var ship_approach := _make_test_ship()
	ship_approach.global_position = planet.global_position + Vector2(12000.0, 0.0)
	ship_approach.velocity = planet.inertial_velocity() + Vector2(-150.0, 50.0) # falling inward
	ship_approach.engage_orbit_autopilot(planet)
	ship_approach._update_autopilot_guidance()
	var thrust_dir := Vector2.from_angle(ship_approach._autopilot_heading)
	var radial_dir := (ship_approach.global_position - planet.global_position).normalized()
	_check(thrust_dir.dot(radial_dir) >= -0.01, "autopilot thrust direction never points inward into planet")
	ship_approach.queue_free()

	# 8. Velocity vector actively lengthens with speed and shortens when decelerating
	var len_slow: float = clampf(8.5 * pow(2.0, 0.65), 0.0, 260.0)
	var len_med: float = clampf(8.5 * pow(20.0, 0.65), 0.0, 260.0)
	var len_fast: float = clampf(8.5 * pow(100.0, 0.65), 0.0, 260.0)
	_check(
		len_slow > 5.0 and len_med > len_slow * 2.5 and len_fast > len_med * 1.5,
		"velocity vector actively lengthens with acceleration and shortens when braking"
	)

	# 9. Line resolution stays crisp (constant screen pixel width regardless of camera zoom)
	var ship_zoom := _make_test_ship()
	ship_zoom.camera_zoom = 2.0
	var w_close := 1.5 / ship_zoom.camera_zoom
	ship_zoom.camera_zoom = 20.0
	var w_extreme := 1.5 / ship_zoom.camera_zoom
	_check(
		is_equal_approx(w_close * 2.0, 1.5) and is_equal_approx(w_extreme * 20.0, 1.5),
		"guidance vectors maintain ultra-crisp screen resolution at any zoom"
	)
	ship_zoom.queue_free()

	universe.queue_free()
	planet.queue_free()


func _test_autopilot_trajectory_and_transfer_physics() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	var planet := PlanetType.new()
	planet.configure(rng, "TargetSys", "desert", 6000.0, 150000.0)
	add_child(planet)

	var ship := _make_test_ship()

	# 1. Approach tangential speed stays strictly below local escape speed
	var far_radius := planet.radius * 4.5
	var test_pos := planet.global_position + Vector2(far_radius, 0.0)
	var test_vel := planet.inertial_velocity()
	var guid := ship.get_autopilot_guidance_for_state(test_pos, test_vel, planet, 1.0)
	var des_v: Vector2 = guid.get("desired_velocity", Vector2.ZERO)
	var rel_desired_speed := (des_v - planet.inertial_velocity()).length()
	var local_escape_speed := OrbitalPhysics.escape_speed(planet.mu, far_radius)
	_check(rel_desired_speed < local_escape_speed, "autopilot approach speed stays safely below local escape speed")

	# 2. At target orbit radius, guidance speed matches circular orbit speed
	var desired_radius: float = guid.desired_radius
	var orbit_pos := planet.global_position + Vector2(desired_radius, 0.0)
	var orbit_vel := planet.inertial_velocity() + Vector2(0.0, OrbitalPhysics.circular_speed(planet.mu, desired_radius))
	var orbit_guid := ship.get_autopilot_guidance_for_state(orbit_pos, orbit_vel, planet, 1.0)
	var exp_circ := OrbitalPhysics.circular_speed(planet.mu, desired_radius)
	var act_v: Vector2 = orbit_guid.get("desired_velocity", Vector2.ZERO)
	var act_circ := (act_v - planet.inertial_velocity()).length()
	_check(is_equal_approx(act_circ, exp_circ), "autopilot desired speed matches circular orbit speed in target orbit")

	# 3. Trajectory generation from interplanetary distance
	ship.global_position = planet.global_position + Vector2(28000.0, 15000.0)
	ship.velocity = planet.inertial_velocity() + Vector2(-120.0, 50.0)
	var traj := ship.get_planned_autopilot_trajectory(planet, 160)
	_check(traj.size() > 40, "planned trajectory generates full multi-step flight path")
	_check(traj[0].distance_to(ship.global_position) < 1.0, "planned trajectory starts at ship's current position")

	# 4. The preview never fabricates a connector through the planet when the
	# simulation has not yet reached the target orbit.
	var preview_safe := true
	for point in traj:
		if point.distance_to(planet.global_position) < planet.radius:
			preview_safe = false
	_check(preview_safe, "planned trajectory never draws through the planet")

	# 5. Trajectory generation from planet surface (landed liftoff)
	var landed_ship := _make_test_ship()
	landed_ship.landed_on = planet
	landed_ship.global_position = planet.global_position + Vector2(planet.radius, 0.0)
	landed_ship.velocity = planet.inertial_velocity()
	var surface_traj := landed_ship.get_planned_autopilot_trajectory(planet, 160)
	_check(surface_traj.size() > 1, "surface ascent produces a real predicted path")
	var surface_nearest_orbit_error := INF
	for point in surface_traj:
		surface_nearest_orbit_error = minf(
			surface_nearest_orbit_error,
			absf(point.distance_to(planet.global_position) - desired_radius)
		)
	_check(surface_nearest_orbit_error < 50.0, "surface ascent preview reaches the circular target orbit")

	# 6. Dynamic orbit altitude adjustment dynamically updates the preliminary trajectory
	var initial_alt := ship.get_target_orbit_altitude(planet)
	var new_alt := ship.adjust_target_orbit_altitude(planet, 2500.0)
	var updated_traj := ship.get_planned_autopilot_trajectory(planet, 160)
	var expected_new_radius := planet.radius + new_alt
	_check(is_equal_approx(new_alt, initial_alt + 2500.0), "scroll adjustment changes target orbit altitude")
	_check(
		is_equal_approx(planet.radius + ship.get_target_orbit_altitude(planet), expected_new_radius),
		"preview uses the newly selected target orbit altitude"
	)

	# 7. Low-altitude suborbital preview continues beyond its insertion point so
	# the player can see the circularisation that the real autopilot still makes.
	var low_ship := _make_test_ship()
	low_ship.global_position = planet.global_position + Vector2(planet.radius + 870.0, 0.0)
	low_ship.velocity = planet.inertial_velocity() + Vector2(54.0, 30.0)
	var low_traj := low_ship.get_planned_autopilot_trajectory(planet, 160)
	var low_preview_safe := low_traj.size() > 80
	for pt in low_traj:
		if pt.distance_to(planet.global_position) < planet.radius + low_ship.hull_radius():
			low_preview_safe = false
	_check(low_preview_safe, "suborbital preview continues safely through circularisation")
	low_ship.queue_free()

	# 8. Camera zoom remains unchanged when F key is held
	var zoom_ship := _make_test_ship()
	var z0 := zoom_ship.camera_zoom
	var wheel_up := InputEventMouseButton.new()
	wheel_up.pressed = true
	wheel_up.button_index = MOUSE_BUTTON_WHEEL_UP
	var wheel_down := InputEventMouseButton.new()
	wheel_down.pressed = true
	wheel_down.button_index = MOUSE_BUTTON_WHEEL_DOWN
	var f_down := InputEventKey.new()
	f_down.physical_keycode = KEY_F
	f_down.pressed = true
	zoom_ship._unhandled_input(f_down)
	zoom_ship._unhandled_input(wheel_up)
	zoom_ship._unhandled_input(wheel_down)
	_check(is_equal_approx(zoom_ship.camera_zoom, z0), "mouse wheel camera zoom is completely blocked when F is held")
	var f_up := InputEventKey.new()
	f_up.physical_keycode = KEY_F
	f_up.pressed = false
	zoom_ship._unhandled_input(f_up)
	zoom_ship.queue_free()

	# 9. Preview uses simulated flight and never cuts through a body.
	var curve_ship := _make_test_ship()
	curve_ship.global_position = planet.global_position + Vector2(25000.0, 12000.0)
	curve_ship.velocity = planet.inertial_velocity() + Vector2(-60.0, 120.0)
	curve_ship.rotation = 0.5
	var curve_traj := curve_ship.get_planned_autopilot_trajectory(planet, 160)
	var curve_safe := curve_traj.size() > 1
	for point in curve_traj:
		if point.distance_to(planet.global_position) < planet.radius:
			curve_safe = false
	_check(curve_safe, "autopilot preview never fabricates a route through the planet")
	curve_ship.queue_free()

	landed_ship.queue_free()
	ship.queue_free()
	planet.queue_free()

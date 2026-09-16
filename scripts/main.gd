extends Node2D

const StarfieldScene := preload("res://scripts/starfield.gd")
const OrbitRendererScene := preload("res://scripts/orbit_renderer.gd")
const SurfaceModeScene := preload("res://scripts/surface_mode.gd")

var universe: Universe
var ship: SurveyShip
var hud: FlightHud
var orbit_renderer: Node2D
var surface_mode: SurfaceMode
var system_seed: int = 1
var _planet_index: int = 0
var selected_target: ProcPlanet = null
var show_orbits: bool = false
var orbit_edit := OrbitEditor.new()


func _ready() -> void:
	system_seed = randi_range(1, 99999)
	RenderingServer.set_default_clear_color(Color("#070814"))
	var stars := StarfieldScene.new()
	stars.name = "Starfield"
	add_child(stars)
	universe = Universe.new()
	universe.name = "Universe"
	add_child(universe)
	universe.generate(system_seed)
	selected_target = universe.planets[0] if not universe.planets.is_empty() else null
	ship = SurveyShip.new()
	ship.name = "Ship"
	ship.universe = universe
	add_child(ship)
	_place_ship()
	surface_mode = SurfaceModeScene.new()
	surface_mode.ship = ship
	surface_mode.add_to_group("surface_mode")
	add_child(surface_mode)
	orbit_renderer = OrbitRendererScene.new()
	orbit_renderer.universe = universe
	orbit_renderer.ship = ship
	orbit_renderer.selected_target = selected_target
	orbit_renderer.show_all = show_orbits
	orbit_renderer.add_to_group("orbit_renderer")
	add_child(orbit_renderer)
	hud = FlightHud.new()
	hud.universe = universe
	hud.ship = ship
	hud.system_seed = system_seed
	hud.selected_target = selected_target
	hud.show_orbits = show_orbits
	hud.orbit_edit = orbit_edit
	add_child(hud)
	print("Horizon 2D  ziarno %s  ciał %s" % [system_seed, universe.planets.size()])


func request_regen() -> void:
	_regen()


func _place_ship() -> void:
	if universe.planets.is_empty():
		return
	var planet := universe.first_landable_planet()
	if planet == null:
		planet = universe.planets[0]
	ship.place_landed(planet)
	ship.frame_near(planet)
	if surface_mode:
		surface_mode.begin_grounded(planet)


func _physics_process(delta: float) -> void:
	var frozen := hud != null and hud.simulation_locked()
	if ship:
		ship.frozen = frozen
	if frozen:
		return
	if universe:
		var warp := ship.time_warp if ship else 1.0
		universe.tick(delta * warp)


var _f_pressed: bool = false
var _f_pressed_time: int = 0
var _f_scrolled: bool = false


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		var mb := event as InputEventMouseButton
		if hud and (hud.help_open or hud.pause_open or hud.map_open):
			return
		if _f_pressed or Input.is_key_pressed(KEY_F):
			if mb.button_index == MOUSE_BUTTON_WHEEL_UP or mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				get_viewport().set_input_as_handled()
				var target_planet := _find_planet_under_cursor(get_global_mouse_position())
				if target_planet == null:
					target_planet = selected_target
				if target_planet != null:
					if selected_target != target_planet:
						_set_selected_target(target_planet)
					_f_scrolled = true
					var is_up: bool = (mb.button_index == MOUSE_BUTTON_WHEEL_UP)
					var step := maxf(target_planet.lowest_orbit_altitude() * 0.1, 500.0)
					var new_alt := ship.adjust_target_orbit_altitude(target_planet, step if is_up else -step)
					hud.notify("Wysokość orbity %s: %s (Wstępna trajektoria)" % [target_planet.planet_name, FlightHud.format_km(new_alt)])
				return
		if mb.button_index == MOUSE_BUTTON_LEFT:
			_select_at_cursor()
			return
		if mb.shift_pressed and selected_target:
			if mb.button_index == MOUSE_BUTTON_WHEEL_UP:
				var step := maxf(selected_target.lowest_orbit_altitude() * 0.1, 500.0)
				var new_alt := ship.adjust_target_orbit_altitude(selected_target, step)
				hud.notify("Wysokość orbity celu %s: %s" % [selected_target.planet_name, FlightHud.format_km(new_alt)])
				get_viewport().set_input_as_handled()
				return
			elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				var step := maxf(selected_target.lowest_orbit_altitude() * 0.1, 500.0)
				var new_alt := ship.adjust_target_orbit_altitude(selected_target, -step)
				hud.notify("Wysokość orbity celu %s: %s" % [selected_target.planet_name, FlightHud.format_km(new_alt)])
				get_viewport().set_input_as_handled()
				return

	if event is InputEventMouseMotion:
		if _f_pressed or Input.is_key_pressed(KEY_F):
			var hovered := _find_planet_under_cursor(get_global_mouse_position())
			if hovered != null and hovered != selected_target:
				_set_selected_target(hovered)
				hud.notify("Cel: %s — Rolka [F]: wysokość orbity" % hovered.planet_name)

	if event is InputEventKey and not event.echo:
		var key_event := event as InputEventKey
		var key: int = key_event.physical_keycode
		if key == KEY_F:
			if key_event.pressed:
				_f_pressed = true
				_f_pressed_time = Time.get_ticks_msec()
				_f_scrolled = false
				var hovered := _find_planet_under_cursor(get_global_mouse_position())
				if hovered != null:
					_set_selected_target(hovered)
					hud.notify("Cel: %s — Rolka [F]: wysokość orbity" % hovered.planet_name)
				elif selected_target != null:
					hud.notify("Rolka [F]: wysokość orbity %s" % selected_target.planet_name)
			else:
				var was_f := _f_pressed
				_f_pressed = false
				if was_f:
					var hold_ms := Time.get_ticks_msec() - _f_pressed_time
					if _f_scrolled:
						hud.notify("Wstępna trajektoria gotowa — [F] aktywuj autopilot")
					elif hold_ms < 350:
						if selected_target:
							if ship.autopilot_target == selected_target:
								ship.cancel_autopilot()
								hud.notify("Autopilot wyłączony")
							else:
								ship.engage_orbit_autopilot(selected_target)
								hud.notify("Autopilot włączony (%s)" % selected_target.planet_name)
					else:
						if selected_target:
							hud.notify("Cel: %s — [F] aktywuj autopilot" % selected_target.planet_name)
			return

		if not key_event.pressed:
			return

		if key == KEY_H or key == KEY_F1:
			hud.help_open = not hud.help_open
			hud.pause_open = false
			hud.map_open = false
			return
		if key == KEY_ESCAPE:
			_handle_escape()
			return
		if hud.help_open or hud.pause_open:
			return
		if key == KEY_M:
			hud.map_open = not hud.map_open
			if hud.map_open:
				hud.reset_map_view()
			return
		if hud.map_open:
			return
		if orbit_edit.active:
			_handle_edit_keys(key_event)
			return

		match key:
			KEY_R:
				if event.ctrl_pressed:
					_restore_selected_circular()
			KEY_O:
				show_orbits = not show_orbits
				hud.show_orbits = show_orbits
				orbit_renderer.show_all = show_orbits
			KEY_TAB:
				if event.shift_pressed:
					_select_target(-1)
				else:
					_select_target(1)
			KEY_BRACKETLEFT:
				if selected_target:
					var step := maxf(selected_target.lowest_orbit_altitude() * 0.15, 500.0)
					var new_alt := ship.adjust_target_orbit_altitude(selected_target, -step)
					hud.notify("Wysokość orbity celu %s: %s" % [selected_target.planet_name, FlightHud.format_km(new_alt)])
			KEY_BRACKETRIGHT:
				if selected_target:
					var step := maxf(selected_target.lowest_orbit_altitude() * 0.15, 500.0)
					var new_alt := ship.adjust_target_orbit_altitude(selected_target, step)
					hud.notify("Wysokość orbity celu %s: %s" % [selected_target.planet_name, FlightHud.format_km(new_alt)])
			KEY_L:
				_try_land_at_cursor()
			KEY_P:
				_begin_orbit_edit()
			KEY_B:
				if _can_enter_hangar():
					get_tree().change_scene_to_file("res://scenes/hangar.tscn")
				else:
					hud.notify("Hangar tylko na powierzchni lub w spokoju")


func _handle_escape() -> void:
	if orbit_edit.active:
		orbit_edit.cancel()
		_sync_edit_renderer()
		hud.notify("Edycja anulowana")
		return
	if hud.map_open:
		hud.map_open = false
		return
	if hud.help_open:
		hud.help_open = false
		return
	hud.pause_open = not hud.pause_open


func _handle_edit_keys(event: InputEventKey) -> void:
	match event.physical_keycode:
		KEY_ENTER, KEY_KP_ENTER:
			if orbit_edit.commit():
				hud.notify("Orbita zatwierdzona")
				_sync_edit_renderer()
		KEY_BRACKETLEFT:
			if not orbit_edit.adjust_radius(universe, event.shift_pressed, false):
				hud.notify(orbit_edit.last_error)
			_sync_edit_renderer()
		KEY_BRACKETRIGHT:
			if not orbit_edit.adjust_radius(universe, event.shift_pressed, true):
				hud.notify(orbit_edit.last_error)
			_sync_edit_renderer()
		KEY_SEMICOLON:
			orbit_edit.adjust_speed(event.shift_pressed, false)
			_sync_edit_renderer()
		KEY_APOSTROPHE:
			orbit_edit.adjust_speed(event.shift_pressed, true)
			_sync_edit_renderer()
		KEY_R:
			if event.ctrl_pressed:
				orbit_edit.restore_circular(universe)
				hud.notify("Orbita przywrócona")
				_sync_edit_renderer()


func _begin_orbit_edit() -> void:
	if selected_target == null:
		return
	orbit_edit.begin(selected_target)
	_sync_edit_renderer()
	hud.notify("EDYCJA ORBITY")


func _restore_selected_circular() -> void:
	if selected_target == null:
		return
	var direction := 1.0 if selected_target.orbit_speed >= 0.0 else -1.0
	selected_target.orbit_speed = direction * universe.circular_orbit_speed(selected_target)
	selected_target.tick(0.0)
	hud.notify("Orbita przywrócona")


func _sync_edit_renderer() -> void:
	orbit_renderer.edit_active = orbit_edit.active
	orbit_renderer.edit_original_radius = orbit_edit.original_radius
	orbit_renderer.selected_target = selected_target


func _can_enter_hangar() -> bool:
	if ship == null:
		return false
	if ship.surface_mode_active or ship.landed_on != null:
		return true
	var near := universe.nearest(ship.global_position) if universe else null
	return ship.relative_velocity_to(near).length() < Units.HANGAR_REST_SPEED


func _select_target(step: int) -> void:
	if universe.planets.is_empty():
		return
	_planet_index = posmod(_planet_index + step, universe.planets.size())
	_set_selected_target(universe.planets[_planet_index])


func _select_at_cursor() -> void:
	if universe == null or ship == null:
		return
	var cam := get_viewport().get_camera_2d()
	var meters_per_pixel := 1.0 / maxf(cam.zoom.x if cam else 1.0, 0.000001)
	var picked := universe.pick_body(get_global_mouse_position(), meters_per_pixel, 14.0)
	if picked == null:
		picked = _find_planet_under_cursor(get_global_mouse_position())
	if picked == null:
		return
	_set_selected_target(picked)


func _set_selected_target(planet: ProcPlanet) -> void:
	if planet == null or universe == null:
		return
	selected_target = planet
	_planet_index = universe.planets.find(planet)
	if hud:
		hud.selected_target = selected_target
	if orbit_renderer:
		orbit_renderer.selected_target = selected_target


func _find_planet_under_cursor(mouse_world_pos: Vector2) -> ProcPlanet:
	if universe == null:
		return null
	var cam := get_viewport().get_camera_2d()
	var zoom := cam.zoom.x if cam else 1.0
	var best_planet: ProcPlanet = null
	var best_score := INF

	for planet in universe.planets:
		var world_dist := mouse_world_pos.distance_to(planet.global_position)
		var screen_dist := world_dist * zoom
		var body_screen_r := planet.radius * zoom
		var target_alt := ship.get_target_orbit_altitude(planet) if ship else 2000.0
		var orbit_screen_r := (planet.radius + target_alt) * zoom
		var pick_limit := maxf(orbit_screen_r, maxf(body_screen_r, 36.0)) + 35.0

		if screen_dist <= pick_limit:
			var dist_to_orbit := absf(screen_dist - orbit_screen_r)
			var score := minf(screen_dist, dist_to_orbit)
			if score < best_score:
				best_score = score
				best_planet = planet

	return best_planet


func _try_land_at_cursor() -> void:
	if selected_target == null:
		return
	var reason := ship.landing_block_reason(selected_target)
	if reason != "":
		hud.notify(reason)
		return
	var coordinate := selected_target.surface_from_world(get_global_mouse_position())
	if surface_mode.begin_landing(selected_target, coordinate):
		hud.notify("Podejście do lądowania")
	else:
		hud.notify("Nie można wylądować")


func _regen() -> void:
	orbit_edit.cancel()
	system_seed = randi_range(1, 99999)
	universe.queue_free()
	universe = Universe.new()
	add_child(universe)
	universe.generate(system_seed)
	selected_target = universe.planets[0] if not universe.planets.is_empty() else null
	ship.universe = universe
	orbit_renderer.universe = universe
	orbit_renderer.selected_target = selected_target
	hud.universe = universe
	hud.system_seed = system_seed
	hud.selected_target = selected_target
	_planet_index = 0
	_place_ship()

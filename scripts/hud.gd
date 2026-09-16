class_name FlightHud
extends CanvasLayer

const CYAN := Color(0.38, 0.82, 0.94, 0.95)
const CYAN_DIM := Color(0.38, 0.82, 0.94, 0.45)
const PANEL := Color(0.04, 0.07, 0.12, 0.82)
const HULL_COL := Color(0.92, 0.32, 0.28, 0.95)
const ENERGY_COL := Color(0.32, 0.68, 1.0, 0.95)
const HEAT_COL := Color(1.0, 0.42, 0.18, 0.95)
const FUEL_COL := Color(1.0, 0.65, 0.25, 0.95)
const THRUST_COL := Color(0.82, 0.92, 1.0, 0.95)
const ALT_COL := Color(0.42, 0.9, 0.72, 0.95)
const SPEED_COL := Color(0.42, 0.78, 0.95)
const UnitsRef := preload("res://scripts/units.gd")
const WARP_STEPS := [1.0, 2.0, 5.0, 10.0]

const HELP_GROUPS := [
	["Lot", ["W / S — ciąg", "A / D — obrót", "Q / E — RCS", "T — SAS", "X — wyłącz silnik", "Z — pełny ciąg", "Kliknij HUD: x1 / x2 / x5 / x10"]],
	["Kamera", ["Kółko / +/- — zoom", "0 — kadr 1:1", "M — mapa"]],
	["Nawigacja", ["Tab / Shift+Tab — cel", "LPM — wybierz planetę", "Trzymaj F + Rolka — orbita", "F — autopilot", "[ / ] — wys. orbity", "L — lądowanie", "O — orbity"]],
	["Powierzchnia", ["WASD — jazda", "Spacja — start (trzymaj)", "W / Shift — ciąg po starcie"]],
	["Edycja układu", ["P — tryb edycji", "[ / ] — promień", "Enter — zatwierdź", "Esc — anuluj"]],
	["Hangar", ["B — hangar", "LPM — stawianie", "PPM — usuwanie", "R — obrót"]],
]

var universe: Universe
var ship: SurveyShip
var system_seed: int = 0
var selected_target: ProcPlanet = null
var show_orbits: bool = false
var help_open: bool = false
var pause_open: bool = false
var map_open: bool = false
var orbit_edit: OrbitEditor = null
var hud_intensity: float = 1.0
var surface_quality: int = 1
var notifications: Array[Dictionary] = []
var map_pan := Vector2.ZERO
var map_zoom: float = 1.0

var _paint: Control
var _font: Font
var _pause_buttons: Array[Dictionary] = []
var _warp_buttons: Array[Dictionary] = []
var _warp_controls: Array[Button] = []
var _map_dragging: bool = false
var _map_drag_last := Vector2.ZERO
var _redraw_elapsed := 0.0
const REDRAW_INTERVAL := 0.066


func _ready() -> void:
	layer = 10
	process_mode = Node.PROCESS_MODE_ALWAYS
	_font = ThemeDB.fallback_font
	_paint = Control.new()
	_paint.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_paint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_paint.draw.connect(_on_draw)
	add_child(_paint)
	for step in WARP_STEPS:
		var button := Button.new()
		button.flat = true
		button.text = ""
		button.mouse_filter = Control.MOUSE_FILTER_STOP
		button.tooltip_text = "Ustaw przyspieszenie czasu x%d" % int(step)
		button.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
		button.add_theme_stylebox_override("hover", StyleBoxEmpty.new())
		button.add_theme_stylebox_override("pressed", StyleBoxEmpty.new())
		button.pressed.connect(_set_time_warp.bind(step))
		add_child(button)
		_warp_controls.append(button)
	Input.mouse_mode = Input.MOUSE_MODE_HIDDEN


func notify(text: String) -> void:
	notifications.append({"text": text, "age": 0.0})
	if notifications.size() > 4:
		notifications.pop_front()


func simulation_locked() -> bool:
	return help_open or pause_open or map_open or (orbit_edit != null and orbit_edit.active)


func _process(delta: float) -> void:
	for note in notifications:
		note["age"] = float(note["age"]) + delta
	while notifications.size() > 0 and float(notifications[0]["age"]) > 3.2:
		notifications.pop_front()
	if map_open:
		_tick_map_pan(delta)
	_redraw_elapsed += delta
	if _paint and _redraw_elapsed >= REDRAW_INTERVAL:
		_redraw_elapsed = 0.0
		var vp := _hud_size()
		if _paint.size != vp:
			_paint.size = vp
		_paint.queue_redraw()
	var cursor_over_warp := false
	if not help_open and not pause_open and not map_open:
		var cursor := get_viewport().get_mouse_position()
		for button in _warp_buttons:
			if (button["rect"] as Rect2).has_point(cursor):
				cursor_over_warp = true
				break
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if help_open or pause_open or map_open or cursor_over_warp else Input.MOUSE_MODE_HIDDEN


func reset_map_view() -> void:
	map_pan = Vector2.ZERO
	map_zoom = 1.0
	_map_dragging = false


func _input(event: InputEvent) -> void:
	if _handle_warp_input(event):
		if get_viewport(): get_viewport().set_input_as_handled()
		return
	if not map_open or pause_open or help_open:
		return
	if _handle_map_input(event):
		if get_viewport(): get_viewport().set_input_as_handled()


func _handle_warp_input(event: InputEvent) -> bool:
	if ship == null or ship.surface_mode_active or help_open or pause_open or map_open:
		return false
	if not (event is InputEventMouseButton):
		return false
	var mouse := event as InputEventMouseButton
	if mouse.button_index != MOUSE_BUTTON_LEFT or not mouse.pressed:
		return false
	var cursor := get_viewport().get_mouse_position()
	for button in _warp_buttons:
		var rect: Rect2 = button["rect"]
		if not rect.has_point(cursor):
			continue
		_set_time_warp(float(button["warp"]))
		return true
	return false


func _set_time_warp(requested: float) -> void:
	if ship == null:
		return
	ship.time_warp = requested
	notify("Czas: x%d" % int(requested))
	# The painted states are data-driven, so force an immediate refresh rather
	# than waiting for the regular HUD refresh cycle after a click.
	if _paint:
		_paint.queue_redraw()


func _handle_map_input(event: InputEvent) -> bool:
	if event is InputEventMouseButton:
		var mouse := event as InputEventMouseButton
		if mouse.button_index == MOUSE_BUTTON_WHEEL_UP and mouse.pressed:
			_zoom_map_at(_paint.get_local_mouse_position(), 1.18)
			return true
		if mouse.button_index == MOUSE_BUTTON_WHEEL_DOWN and mouse.pressed:
			_zoom_map_at(_paint.get_local_mouse_position(), 1.0 / 1.18)
			return true
		if mouse.button_index == MOUSE_BUTTON_LEFT or mouse.button_index == MOUSE_BUTTON_MIDDLE:
			_map_dragging = mouse.pressed
			_map_drag_last = _paint.get_local_mouse_position()
			return true
	if event is InputEventMouseMotion and _map_dragging:
		var now := _paint.get_local_mouse_position()
		map_pan += now - _map_drag_last
		_map_drag_last = now
		return true
	return false


func _zoom_map_at(cursor: Vector2, factor: float) -> void:
	var previous := map_zoom
	map_zoom = clampf(map_zoom * factor, 0.35, 12.0)
	var applied := map_zoom / maxf(previous, 0.0001)
	var center := _map_center()
	var local := cursor - center
	map_pan = local * (1.0 - applied) + map_pan * applied


func _tick_map_pan(delta: float) -> void:
	var move := Vector2(
		float(Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT))
		- float(Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT)),
		float(Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN))
		- float(Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP))
	)
	if move.length_squared() > 0.01:
		map_pan -= move.normalized() * (520.0 * delta)


func _map_center() -> Vector2:
	var vp := _hud_size()
	var panel := Rect2(vp.x * 0.06, vp.y * 0.08, vp.x * 0.88, vp.y * 0.84)
	return panel.position + panel.size * 0.5


func _unhandled_input(event: InputEvent) -> void:
	if not pause_open:
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var mouse := _paint.get_local_mouse_position()
		for button in _pause_buttons:
			var rect: Rect2 = button["rect"]
			if rect.has_point(mouse):
				_activate_pause_button(String(button["id"]))
				if get_viewport(): get_viewport().set_input_as_handled()
				return


func _hud_size() -> Vector2:
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


func _on_draw() -> void:
	if ship == null or universe == null:
		return
	for button in _warp_controls:
		button.visible = false
	_paint.modulate.a = hud_intensity
	var vp := _hud_size()
	if not ship.surface_mode_active:
		_draw_offscreen_target(vp)
	if not help_open and not pause_open and not map_open:
		_draw_resources_panel(vp)
		_draw_target_card(vp)
		_draw_telemetry_panel(vp)
		_draw_minimap(vp)
		_draw_crosshair(vp)
		_draw_warp_indicator(vp)
		_draw_autopilot_debug_panel(vp)
	_draw_notifications(vp)
	if map_open:
		_draw_system_map(vp)
	if help_open:
		_draw_help(vp)
	if pause_open:
		_draw_pause(vp)


func _draw_resources_panel(_vp: Vector2) -> void:
	var box := Rect2(24, 24, 392, 98)
	_paint.draw_rect(box, PANEL, true)
	_paint.draw_rect(box, CYAN_DIM, false, 1.0)
	var hull_max := maxf(ship.hull_max(), 1.0)
	var fuel_max := maxf(ship.fuel_max(), 1.0)
	var energy_max := SurveyShip.ENERGY_MAX
	_segment_bar(box.position + Vector2(14, 18), "HULL", ship.hull / hull_max, "%d / %d" % [int(ship.hull), int(hull_max)])
	_segment_bar(box.position + Vector2(14, 44), "FUEL", ship.fuel / fuel_max, "%d / %d" % [int(ship.fuel), int(fuel_max)])
	_segment_bar(box.position + Vector2(14, 70), "ENERGY", ship.energy / energy_max, "%d / %d" % [int(ship.energy), int(energy_max)])


func _draw_target_card(vp: Vector2) -> void:
	var box := Rect2(vp.x - 24 - 236, 24, 236, 108)
	_paint.draw_rect(box, PANEL, true)
	_paint.draw_rect(box, CYAN_DIM, false, 1.0)
	_paint.draw_string(_font, box.position + Vector2(12, 17), "CEL NAWIGACYJNY", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, CYAN_DIM)
	if selected_target:
		_paint.draw_string(_font, box.position + Vector2(12, 38), selected_target.planet_name, HORIZONTAL_ALIGNMENT_LEFT, 212.0, 15, CYAN)
		var dist := ship.global_position.distance_to(selected_target.global_position) - selected_target.radius
		var rel_v := ship.relative_velocity_to(selected_target).length()
		_paint.draw_string(_font, box.position + Vector2(12, 57), "Dystans: %s" % format_km(dist), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.85, 0.92, 1.0))
		_paint.draw_string(_font, box.position + Vector2(12, 72), "V rel:   %d m/s" % int(rel_v), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.7, 0.85, 0.95))
		var target_alt: float = ship.get_target_orbit_altitude(selected_target)
		_paint.draw_string(_font, box.position + Vector2(12, 87), "Orbita:  %s  (Trzymaj F + Rolka)" % format_km(target_alt), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.4, 0.95, 0.55))
		if ship.autopilot_target == selected_target:
			var ap_txt := "AP: %s" % ship.autopilot_phase
			if ship.autopilot_delta_v > 0.5:
				ap_txt += " (Δv %d m/s)" % int(ship.autopilot_delta_v)
			_paint.draw_string(_font, box.position + Vector2(12, 102), ap_txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.35, 1.0, 0.55))
		else:
			_paint.draw_string(_font, box.position + Vector2(12, 102), "[F] Start AP  [Trzymaj F] Orbita", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.5, 0.75, 0.85, 0.7))
	else:
		_paint.draw_string(_font, box.position + Vector2(12, 45), "Brak celu", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.6, 0.7, 0.8))
		_paint.draw_string(_font, box.position + Vector2(12, 68), "[Tab] Wybierz cel", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.5, 0.7, 0.8, 0.7))


func _draw_warp_indicator(vp: Vector2) -> void:
	if ship.surface_mode_active:
		for button in _warp_controls:
			button.visible = false
		return
	_warp_buttons.clear()
	# Pasek warpa dokładnie pod kartą celu (ta ma 236px szer., margin 24px)
	# 4 komórki × 55px + 3 odstępy × 7px = 220+21 = 241 → za dużo
	# 4 × 54px + 3 × 4px = 216+12 = 228 → bliżej, ale nie 236
	# Użyjmy tego samego x-start co karta: vp.x - 24 - 236, szer. 236
	const CARD_W := 236.0
	const H := 22.0
	const GAP := 4.0
	const LABELS := ["x1", "x2", "x5", "x10"]
	var cell_w := (CARD_W - 3.0 * GAP) / 4.0   # = (236-12)/4 = 56
	var x0 := vp.x - 24.0 - CARD_W
	var y0 := 24.0 + 108.0 + 5.0   # tuż pod kartą celu (karta: y=24, h=108)
	var warp := ship.time_warp
	for i in 4:
		var cx := x0 + i * (cell_w + GAP)
		var cell := Rect2(cx, y0, cell_w, H)
		_warp_buttons.append({"rect": cell, "warp": WARP_STEPS[i]})
		if i < _warp_controls.size():
			var click_button := _warp_controls[i]
			click_button.position = cell.position
			click_button.size = cell.size
			click_button.visible = true
		var is_active := absf(warp - WARP_STEPS[i]) < 0.1
		var bg_col: Color
		var txt_col: Color
		if is_active and warp > 1.01:
			bg_col = Color(0.72, 0.42, 0.08, 0.92)
			txt_col = Color(1.0, 0.88, 0.35, 1.0)
		elif is_active:
			bg_col = Color(0.06, 0.14, 0.26, 0.85)
			txt_col = Color(0.75, 0.90, 1.0, 0.95)
		else:
			bg_col = Color(0.03, 0.06, 0.10, 0.50)
			txt_col = Color(0.35, 0.52, 0.68, 0.50)
		_paint.draw_rect(cell, bg_col, true)
		_paint.draw_rect(cell, Color(txt_col, 0.35), false, 1.0)
		_paint.draw_string(_font, cell.position + Vector2(0, 16.0),
			LABELS[i], HORIZONTAL_ALIGNMENT_CENTER, cell_w, 12, txt_col)


func _draw_telemetry_panel(vp: Vector2) -> void:
	var box := Rect2(vp.x - 24 - 264, vp.y - 24 - 110, 264, 110)
	_paint.draw_rect(box, PANEL, true)
	_paint.draw_rect(box, CYAN_DIM, false, 1.0)
	if ship.surface_mode_active:
		_paint.draw_string(_font, box.position + Vector2(12, 17), "POWIERZCHNIA", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.4, 0.95, 0.6))
		_paint.draw_string(_font, box.position + Vector2(12, 40), "SPD  %d m/s" % int(_displayed_speed()), HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(0.9, 0.96, 1.0))
		_paint.draw_string(_font, box.position + Vector2(144, 40), "CIĄG %d%%" % int(absf(ship.throttle) * 100.0), HORIZONTAL_ALIGNMENT_LEFT, -1, 13, THRUST_COL)
		var planet := _reference_planet()
		var alt := _altitude_meters(planet)
		_paint.draw_string(_font, box.position + Vector2(12, 63), "ALT  %s" % (format_km(alt) if alt >= 1000.0 else "%.1f m" % alt), HORIZONTAL_ALIGNMENT_LEFT, -1, 13, ALT_COL)
		_paint.draw_string(_font, box.position + Vector2(12, 83), "V/S  %+.1f m/s" % _vertical_speed(planet), HORIZONTAL_ALIGNMENT_LEFT, -1, 13, CYAN)
		_paint.draw_string(_font, box.position + Vector2(12, 101), "WASD ruch | SPACJA start", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.6, 0.75, 0.85, 0.7))
	else:
		_paint.draw_string(_font, box.position + Vector2(12, 17), "TELEMETRIA LOTU", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, CYAN_DIM)
		_paint.draw_string(_font, box.position + Vector2(12, 40), "V☉   %d m/s" % int(ship.velocity.length()), HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(0.9, 0.96, 1.0))
		_paint.draw_string(_font, box.position + Vector2(144, 40), "CIĄG %d%%" % int(absf(ship.throttle) * 100.0), HORIZONTAL_ALIGNMENT_LEFT, -1, 13, THRUST_COL)
		var planet := _reference_planet()
		if planet:
			var alt := _altitude_meters(planet)
			var ceiling := planet.lowest_orbit_altitude()
			if altitude_visible(alt, ceiling):
				_paint.draw_string(_font, box.position + Vector2(12, 63), "ALT  %s" % format_km(maxf(alt, 0.0)), HORIZONTAL_ALIGNMENT_LEFT, -1, 13, ALT_COL)
				_paint.draw_string(_font, box.position + Vector2(12, 83), "V/S  %+.0f m/s" % _vertical_speed(planet), HORIZONTAL_ALIGNMENT_LEFT, -1, 13, CYAN)
			else:
				var state := universe.orbit_status(ship.global_position, ship.velocity)
				_paint.draw_string(_font, box.position + Vector2(12, 63), "AP %s   %s" % [format_km(maxf(float(state["ap"]), 0.0)), _orbit_eta(float(state["time_to_ap"]), "TAp")], HORIZONTAL_ALIGNMENT_LEFT, -1, 12, CYAN)
				_paint.draw_string(_font, box.position + Vector2(12, 83), "PE %s   %s" % [format_km(maxf(float(state["pe"]), 0.0)), _orbit_eta(float(state["time_to_pe"]), "TPe")], HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.95, 0.78, 0.42))


func _segment_bar(pos: Vector2, label: String, amount: float, readout: String) -> void:
	var fill_col := CYAN
	var empty_col := Color(0.18, 0.32, 0.42, 0.55)
	_paint.draw_string(_font, pos + Vector2(0, 12), label, HORIZONTAL_ALIGNMENT_LEFT, 64.0, 12, fill_col)
	var segments := 24
	var seg_w := 6.0
	var seg_h := 12.0
	var gap := 2.0
	var bar_x := pos.x + 68.0
	var filled := int(round(clampf(amount, 0.0, 1.0) * float(segments)))
	for i in segments:
		var rect := Rect2(bar_x + float(i) * (seg_w + gap), pos.y + 2.0, seg_w, seg_h)
		_paint.draw_rect(rect, fill_col if i < filled else empty_col, true)
	var value_x := bar_x + float(segments) * (seg_w + gap) + 8.0
	_paint.draw_string(_font, Vector2(value_x, pos.y + 12), readout, HORIZONTAL_ALIGNMENT_LEFT, 90.0, 12, fill_col)


func _status_line(pos: Vector2, label: String, amount: float, readout: String, color: Color) -> void:
	_segment_bar(pos, label, amount, readout)


func _reference_planet() -> ProcPlanet:
	if ship == null:
		return null
	if ship.landed_on:
		return ship.landed_on
	if universe:
		var dominant := universe.dominant_body(ship.global_position)
		if dominant:
			return dominant
		return universe.nearest(ship.global_position)
	return null


func _altitude_meters(planet: ProcPlanet) -> float:
	if planet == null or ship == null:
		return 0.0
	if ship.surface_mode_active:
		var surface := get_tree().get_first_node_in_group("surface_mode")
		if surface:
			return maxf(surface._altitude, 0.0)
	return (
		ship.global_position.distance_to(planet.global_position)
		- planet.radius
		- ship.hull_radius()
	)


func _vertical_speed(planet: ProcPlanet) -> float:
	if planet == null or ship == null:
		return 0.0
	if ship.surface_mode_active:
		var surface := get_tree().get_first_node_in_group("surface_mode")
		if surface:
			return surface._radial_velocity
	var relative := ship.global_position - planet.global_position
	if relative.length_squared() < 0.001:
		return 0.0
	var relative_velocity := ship.velocity - planet.inertial_velocity()
	return relative_velocity.dot(relative.normalized())


func _heat_fraction() -> float:
	var planet := _reference_planet()
	if planet == null or ship == null:
		return 0.0
	var altitude := _altitude_meters(planet)
	var ceiling := planet.lowest_orbit_altitude()
	if altitude >= ceiling:
		return 0.0
	var density := 1.0 - clampf(altitude / maxf(ceiling, 1.0), 0.0, 1.0)
	var speed := absf(_vertical_speed(planet)) + _displayed_speed() * 0.35
	return clampf(density * speed / 90.0, 0.0, 1.0)


func _orbit_eta(seconds: float, tag: String = "TPe") -> String:
	if not is_finite(seconds) or seconds < 0.0:
		return "—"
	if seconds < 60.0:
		return "%s %ds" % [tag, int(seconds)]
	if seconds < 3600.0:
		return "%s %d:%02d" % [tag, int(seconds / 60.0), int(seconds) % 60]
	return "%s %dh" % [tag, int(seconds / 3600.0)]


static func format_km(meters: float) -> String:
	var km := UnitsRef.km(meters)
	if absf(km) >= 100.0:
		return "%.0f km" % km
	if absf(km) >= 10.0:
		return "%.1f km" % km
	return "%.2f km" % km


static func altitude_visible(altitude: float, lowest_orbit: float) -> bool:
	return altitude < lowest_orbit


func _displayed_speed() -> float:
	if ship.surface_mode_active:
		var surface := get_tree().get_first_node_in_group("surface_mode")
		if surface:
			return surface._surface_velocity.length()
	var planet := _reference_planet()
	if planet:
		return ship.relative_velocity_to(planet).length()
	return ship.velocity.length()


func _draw_minimap(vp: Vector2) -> void:
	var r := 52.0
	var c := Vector2(24 + r + 8, vp.y - 24 - r - 26)
	_paint.draw_circle(c, r + 8, PANEL)
	_paint.draw_arc(c, r + 6, 0, TAU, 64, CYAN_DIM, 1.2, true)
	for ring in 3:
		_paint.draw_arc(c, r * float(ring + 1) / 3.0, 0, TAU, 48, Color(0.4, 0.75, 0.9, 0.16), 1.0, true)
	_paint.draw_line(c + Vector2(-r, 0), c + Vector2(r, 0), Color(0.4, 0.75, 0.9, 0.1), 1.0)
	_paint.draw_line(c + Vector2(0, -r), c + Vector2(0, r), Color(0.4, 0.75, 0.9, 0.1), 1.0)
	var range_m := _radar_range_meters()
	var scale := r / range_m
	for planet in universe.planets:
		_radar_dot(c, scale, r, planet.global_position, Color(0.55, 0.85, 1.0) if not planet.is_moon() else Color(0.7, 0.78, 0.82), planet == selected_target)
	_paint.draw_colored_polygon(PackedVector2Array([
		c + Vector2(0, -5), c + Vector2(-4, 4), c + Vector2(4, 4),
	]), Color(0.92, 0.96, 1.0))
	var near := selected_target if selected_target else universe.nearest(ship.global_position)
	if near:
		var dist := ship.global_position.distance_to(near.global_position) - near.radius
		_paint.draw_string(_font, Vector2(c.x - r, c.y + r + 13), near.planet_name, HORIZONTAL_ALIGNMENT_CENTER, r * 2.0, 12, Color(0.9, 0.95, 1.0))
		_paint.draw_string(_font, Vector2(c.x - r, c.y + r + 26), "%s | %s" % [format_km(dist), format_km(range_m)], HORIZONTAL_ALIGNMENT_CENTER, r * 2.0, 10, CYAN_DIM)


func _radar_range_meters() -> float:
	var nearest_distance := 0.0
	if universe and ship:
		var body := selected_target if selected_target else universe.nearest(ship.global_position)
		if body:
			nearest_distance = ship.global_position.distance_to(body.global_position)
	return UnitsRef.radar_range(nearest_distance)


func _radar_dot(c: Vector2, k: float, r: float, world: Vector2, col: Color, selected: bool) -> void:
	var rel := (world - ship.global_position) * k
	if rel.length() > r - 6.0:
		rel = rel.normalized() * (r - 6.0)
	_paint.draw_circle(c + rel, 5.0 if selected else 3.0, col)


func _draw_system_map(vp: Vector2) -> void:
	_paint.draw_rect(Rect2(Vector2.ZERO, vp), Color(0.02, 0.03, 0.06, 0.82), true)
	var panel := Rect2(vp.x * 0.06, vp.y * 0.08, vp.x * 0.88, vp.y * 0.84)
	_paint.draw_rect(panel, PANEL, true)
	_paint.draw_rect(panel, CYAN, false, 1.2)
	_paint.draw_string(_font, panel.position + Vector2(24, 32), "MAPA UKŁADU", HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(0.9, 0.96, 1.0))
	var map_center := panel.position + panel.size * 0.5 + map_pan
	var extent := 1.0
	for planet in universe.planets:
		extent = maxf(extent, planet.orbit_radius if planet.parent_body == null else planet.global_position.length())
	extent = maxf(extent, ship.global_position.length())
	var map_scale := minf(panel.size.x, panel.size.y) * 0.38 / maxf(extent, 1.0) * map_zoom
	_paint.draw_circle(map_center, 8.0, Color(1.0, 0.85, 0.4))
	for planet in universe.planets:
		if planet.parent_body == null:
			_paint.draw_arc(map_center, planet.orbit_radius * map_scale, 0, TAU, 160, Color(0.45, 0.7, 0.85, 0.22), 1.2, true)
		var pos := map_center + planet.global_position * map_scale
		var col := Color(0.4, 0.95, 1.0) if planet == selected_target else Color(0.65, 0.8, 0.9)
		_paint.draw_circle(pos, 4.0 + planet.radius * map_scale * 0.08, col)
		_paint.draw_string(_font, pos + Vector2(8, -4), planet.planet_name, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.85, 0.92, 1.0, 0.8))
	var ship_pos := map_center + ship.global_position * map_scale
	_paint.draw_colored_polygon(PackedVector2Array([
		ship_pos + Vector2(0, -7), ship_pos + Vector2(-5, 6), ship_pos + Vector2(5, 6),
	]), Color(0.95, 0.98, 1.0))


func _draw_offscreen_target(vp: Vector2) -> void:
	if selected_target == null:
		return
	var cam := _paint.get_viewport().get_camera_2d()
	if cam == null:
		return
	var scr := vp * 0.5 + (selected_target.global_position - cam.global_position) * cam.zoom
	if Rect2(Vector2.ZERO, vp).grow(-48.0).has_point(scr):
		return
	var dir := (scr - vp * 0.5).normalized()
	var edge := vp * 0.5 + dir * (minf(vp.x, vp.y) * 0.38)
	edge.x = clampf(edge.x, 36.0, vp.x - 36.0)
	edge.y = clampf(edge.y, 120.0, vp.y - 120.0)
	_paint.draw_colored_polygon(PackedVector2Array([
		edge, edge - dir * 14.0 + dir.orthogonal() * 6.0, edge - dir * 14.0 - dir.orthogonal() * 6.0,
	]), Color(0.35, 0.95, 1.0, 0.86))


func _draw_crosshair(_vp: Vector2) -> void:
	var c := _paint.get_local_mouse_position()
	_paint.draw_line(c + Vector2(-10, 0), c + Vector2(-3, 0), CYAN_DIM, 1.0, true)
	_paint.draw_line(c + Vector2(3, 0), c + Vector2(10, 0), CYAN_DIM, 1.0, true)
	_paint.draw_line(c + Vector2(0, -10), c + Vector2(0, -3), CYAN_DIM, 1.0, true)
	_paint.draw_line(c + Vector2(0, 3), c + Vector2(0, 10), CYAN_DIM, 1.0, true)


func _draw_notifications(vp: Vector2) -> void:
	var y := 28.0
	for note in notifications:
		var age := float(note["age"])
		var alpha := 1.0 if age < 2.2 else clampf(1.0 - (age - 2.2) / 1.0, 0.0, 1.0)
		_paint.draw_string(_font, Vector2(vp.x * 0.5 - 160.0, y), String(note["text"]), HORIZONTAL_ALIGNMENT_CENTER, 320.0, 14, Color(0.95, 0.9, 0.55, alpha))
		y += 20.0


func _draw_help(vp: Vector2) -> void:
	_paint.draw_rect(Rect2(Vector2.ZERO, vp), Color(0.02, 0.04, 0.08, 0.72), true)
	var two_columns := vp.x < 1180.0
	var panel := Rect2(vp.x * 0.08, vp.y * 0.08, vp.x * 0.84, vp.y * 0.84)
	_paint.draw_rect(panel, PANEL, true)
	_paint.draw_rect(panel, CYAN, false, 1.4)
	_paint.draw_string(_font, panel.position + Vector2(24, 36), "Horizon — sterowanie", HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color(0.92, 0.97, 1.0))
	var columns := 2 if two_columns else 3
	var col_w := panel.size.x / float(columns) - 12.0
	for i in HELP_GROUPS.size():
		var gx := panel.position.x + 24.0 + float(i % columns) * col_w
		var gy := panel.position.y + 70.0 + float(int(i / columns)) * (panel.size.y * 0.42)
		var group: Array = HELP_GROUPS[i]
		_paint.draw_string(_font, Vector2(gx, gy), String(group[0]), HORIZONTAL_ALIGNMENT_LEFT, -1, 16, CYAN)
		var rows: Array = group[1]
		for r in rows.size():
			_paint.draw_string(_font, Vector2(gx, gy + 22.0 + float(r) * 22.0), String(rows[r]), HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.88, 0.93, 1.0))


func _draw_pause(vp: Vector2) -> void:
	_paint.draw_rect(Rect2(Vector2.ZERO, vp), Color(0.02, 0.03, 0.06, 0.78), true)
	var labels := [
		["resume", "Wznów"],
		["help", "Sterowanie"],
		["hangar", "Hangar"],
		["quality", "Jakość powierzchni  %s" % ["niska", "średnia", "wysoka"][surface_quality]],
		["regen", "Nowy układ"],
		["quit", "Wyjście"],
	]
	_pause_buttons.clear()
	var box := Rect2(vp.x * 0.5 - 160, vp.y * 0.28, 320, 52.0 * labels.size() + 24.0)
	_paint.draw_rect(box, PANEL, true)
	_paint.draw_rect(box, CYAN, false, 1.3)
	_paint.draw_string(_font, box.position + Vector2(24, 28), "Pauza", HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color(0.92, 0.97, 1.0))
	for i in labels.size():
		var rect := Rect2(box.position.x + 24, box.position.y + 44 + i * 48, 272, 36)
		_pause_buttons.append({"id": labels[i][0], "rect": rect})
		_paint.draw_rect(rect, Color(0.08, 0.16, 0.24, 0.95), true)
		_paint.draw_rect(rect, CYAN_DIM, false, 1.0)
		_paint.draw_string(_font, rect.position + Vector2(16, 24), String(labels[i][1]), HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(0.9, 0.96, 1.0))


func _activate_pause_button(id: String) -> void:
	match id:
		"resume":
			pause_open = false
		"help":
			pause_open = false
			help_open = true
		"hangar":
			pause_open = false
			get_tree().change_scene_to_file("res://scenes/hangar.tscn")
		"quality":
			surface_quality = (surface_quality + 1) % 3
			if universe:
				for planet in universe.planets:
					planet.apply_surface_quality(surface_quality)
		"regen":
			pause_open = false
			get_tree().current_scene.call("request_regen")
		"quit":
			get_tree().quit()

func _draw_autopilot_debug_panel(vp: Vector2) -> void:
	if ship.autopilot_target == null:
		return
	var box := Rect2(24, 134, 392, 170)
	_paint.draw_rect(box, PANEL, true)
	_paint.draw_rect(box, Color(0.5, 0.9, 0.5, 0.5), false, 1.0)
	
	_paint.draw_string(_font, box.position + Vector2(12, 17), "AUTOPILOT DEBUG", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.5, 0.9, 0.5))
	
	var state_name = "OFF"
	match ship.autopilot_state:
		1: state_name = "ANALYZE"
		2: state_name = "PLAN_TRANSFER"
		3: state_name = "ORIENT_FOR_BURN"
		4: state_name = "COAST_TO_TRIGGER"
		5: state_name = "EXECUTE_BURN"
		6: state_name = "CIRCULARIZE"
		7: state_name = "ORBIT_HOLD"
		8: state_name = "COLLISION_AVOIDANCE"
		
	_paint.draw_string(_font, box.position + Vector2(12, 38), "State: " + state_name, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(1.0, 1.0, 1.0))
	_paint.draw_string(_font, box.position + Vector2(200, 38), "Phase: " + ship.autopilot_phase, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.8, 0.8, 0.8))
	
	if ship.orbit_state != null:
		var os = ship.orbit_state
		var r_err = 0.0
		var tgt_r = ship.autopilot_target.radius + ship.get_target_orbit_altitude(ship.autopilot_target)
		
		_paint.draw_string(_font, box.position + Vector2(12, 60), "Pe: %d km" % int(os.periapsis_altitude / 1000.0), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.9, 0.7, 0.3))
		_paint.draw_string(_font, box.position + Vector2(12, 75), "Ap: %d km" % int(os.apoapsis_altitude / 1000.0), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.4, 0.8, 0.9))
		_paint.draw_string(_font, box.position + Vector2(12, 90), "ecc: %.4f" % os.eccentricity, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.8, 0.8, 0.8))
		_paint.draw_string(_font, box.position + Vector2(12, 105), "Rad V: %+.1f m/s" % os.radial_velocity, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.8, 0.8, 0.8))
		
		_paint.draw_string(_font, box.position + Vector2(200, 60), "Target: %d km" % int(ship.get_target_orbit_altitude(ship.autopilot_target) / 1000.0), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.5, 0.9, 0.5))
		
	var err = absf(angle_difference(ship.rotation, ship._autopilot_heading))
	_paint.draw_string(_font, box.position + Vector2(200, 90), "H-Err: %.1f deg" % rad_to_deg(err), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.9, 0.5, 0.5) if err > 0.1 else Color(0.5, 0.9, 0.5))
	
	if ship.autopilot_maneuver_index < ship.autopilot_maneuvers.size():
		var m = ship.autopilot_maneuvers[ship.autopilot_maneuver_index]
		_paint.draw_string(_font, box.position + Vector2(12, 130), "Maneuver: " + m.label, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(1.0, 0.8, 0.2))
		_paint.draw_string(_font, box.position + Vector2(12, 145), "Rem dV: %.1f m/s" % m.remaining_delta_v, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(1.0, 0.8, 0.2))
		
	_paint.draw_string(_font, box.position + Vector2(200, 145), "Throttle: %d%%" % int(ship.throttle * 100.0), HORIZONTAL_ALIGNMENT_LEFT, -1, 14, THRUST_COL)
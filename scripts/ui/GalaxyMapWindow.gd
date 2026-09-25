class_name GalaxyMapWindow
extends Control
## Full-screen map of the galaxy (GalaxyMap), framed like the tech tree.
## The galaxy itself is galaxy_map.gdshader; over it go distance rings, the
## galaxy's systems (unexplored ones faint), the ones the player has been to
## (joined in the order they were reached, the current one pulsing), the
## course the hyperdrive is set to, and a card for the selected system.
## Clicking a system and then SET COURSE sends `course_set` with its seed;
## the jump itself is made from the flight HUD (WARP), past the outer belt.
## Toggled with M (solar_system.gd routes the keys while it is open); Esc,
## the X or a click outside closes it. Wheel zooms about the cursor, right or
## middle drag pans, CENTER goes back to the current system. The (i) button
## lists these controls.

signal course_set(system_seed: int)

const GALAXY_SHADER := preload("res://galaxy_map.gdshader")
const MARGIN := 36.0
## Far enough out to see the neighbouring galaxies.
const ZOOM_MIN := 0.06
const ZOOM_MAX := 40.0
const ZOOM_OPEN := 2.2
## How fast the view eases to where it is headed (per second).
const VIEW_EASE := 12.0
## Galaxy radius in light years, for the rings and the scale bar.
const RADIUS_LY := 50000.0
const MARKER_RADIUS := 6.0
const COLOR_ROUTE := Color(0.30, 0.78, 0.88, 0.55)
const COLOR_GRID := Color(0.55, 0.7, 0.9, 0.13)
const COLOR_UNEXPLORED := Color(0.62, 0.7, 0.82)
## Zoom past which unexplored systems are named without hovering.
const NAME_ZOOM := 3.0
## Unexplored systems fade out as the view pulls back past this zoom.
const SYSTEMS_FADE_ZOOM := Vector2(0.3, 0.7)
const COLOR_GALAXY_LABEL := Color(0.8, 0.76, 1.0)
const KIND_LABELS := {"spiral": "SPIRAL GALAXY", "elliptical": "ELLIPTICAL GALAXY", "irregular": "IRREGULAR GALAXY"}
const KIND_IDS := {"spiral": 0.0, "elliptical": 1.0, "irregular": 2.0}

var _hover_close: bool = false
var _hover_help: bool = false
var _help: HelpPopup
var _hover_center: bool = false
var _hover_seed: int = 0
var _has_hover: bool = false
var _selected_seed: int = 0
var _has_selected: bool = false
var _hover_warp: bool = false
## Neighbouring galaxy under the cursor / picked, as an index into
## GalaxyMap.NEIGHBOURS, or -1.
var _hover_galaxy: int = -1
var _selected_galaxy: int = -1
## seed -> GalaxyMap.star_class(), so markers don't re-roll it every frame.
var _star_cache: Dictionary = {}
var _mouse: Vector2 = Vector2.ZERO
## Shown view, and the one it eases toward.
var _zoom: float = 1.0
var _pan: Vector2 = Vector2.ZERO
var _zoom_goal: float = 1.0
var _pan_goal: Vector2 = Vector2.ZERO
var _dragging: bool = false
## Clips the map to its frame; holds the galaxy and the overlay drawn on it.
var _canvas: Control
var _galaxy: ColorRect
var _overlay: Control


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	_canvas = Control.new()
	_canvas.clip_contents = true
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_canvas)
	_galaxy = ColorRect.new()
	_galaxy.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var material := ShaderMaterial.new()
	material.shader = GALAXY_SHADER
	material.set_shader_parameter("arm_count", float(GalaxyMap.ARM_COUNT))
	material.set_shader_parameter("arm_twist", GalaxyMap.ARM_TWIST)
	var places := PackedVector4Array()
	var shapes := PackedVector4Array()
	var tints := PackedVector4Array()
	for nb: Dictionary in GalaxyMap.NEIGHBOURS:
		var at: Vector2 = nb["position"]
		var tint: Color = nb["tint"]
		places.append(Vector4(at.x, at.y, nb["radius"], nb["rotation"]))
		shapes.append(Vector4(nb["tilt"], nb["arms"], nb["twist"], KIND_IDS[nb["kind"]]))
		tints.append(Vector4(tint.r, tint.g, tint.b, nb["seed"]))
	material.set_shader_parameter("neighbour_count", GalaxyMap.NEIGHBOURS.size())
	material.set_shader_parameter("nb_place", places)
	material.set_shader_parameter("nb_shape", shapes)
	material.set_shader_parameter("nb_tint", tints)
	_galaxy.material = material
	_canvas.add_child(_galaxy)
	_overlay = Control.new()
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.draw.connect(_draw_overlay)
	_canvas.add_child(_overlay)
	_help = HelpPopup.new(PackedStringArray([
		"Mouse wheel: zoom in and out",
		"Right or middle drag: move the map",
		"Click a system: select it",
		"Zoom far out to see the neighbouring galaxies",
		"SET COURSE: aim the hyperdrive at the selected system",
		"Then fly past the outer asteroid belt and press WARP",
		"CENTER: back to the system you are in",
		"M or Esc: close the map",
	]))
	add_child(_help)
	resized.connect(queue_redraw)


func toggle() -> void:
	if visible:
		hide_window()
	else:
		open()


func open() -> void:
	visible = true
	move_to_front()
	_has_selected = false
	_selected_galaxy = -1
	_help.close()
	# Swoop in from the whole galaxy to where the player is.
	_zoom = 1.0
	_pan = Vector2.ZERO
	_center_on_current(ZOOM_OPEN)
	queue_redraw()


func hide_window() -> void:
	visible = false
	_dragging = false
	_help.close()


func _center_on_current(zoom: float) -> void:
	var here: int = GalaxyMap.index_of(GalaxyMap.current_seed())
	_pan_goal = -GalaxyMap.visits()[here]["position"] if here >= 0 else Vector2.ZERO
	_zoom_goal = zoom


func _process(delta: float) -> void:
	if not visible:
		return
	var k: float = 1.0 - exp(-VIEW_EASE * delta)
	# Ease zoom in log space so it feels even at every scale.
	_zoom = exp(lerpf(log(_zoom), log(_zoom_goal), k))
	_pan = _pan.lerp(_pan_goal, k)
	_update_hover()
	queue_redraw()


func _panel_rect() -> Rect2:
	return Rect2(Vector2.ONE * MARGIN, size - Vector2.ONE * MARGIN * 2.0)


func _close_rect() -> Rect2:
	var panel: Rect2 = _panel_rect()
	return Rect2(Vector2(panel.end.x - 36.0, panel.position.y + 12.0), Vector2(24.0, 24.0))


## Where the galaxy is drawn inside the frame.
func _map_rect() -> Rect2:
	var panel: Rect2 = _panel_rect()
	return Rect2(panel.position + Vector2(18.0, 60.0), panel.size - Vector2(36.0, 78.0))


func _center_rect() -> Rect2:
	var map: Rect2 = _map_rect()
	return Rect2(Vector2(map.end.x - 96.0, map.position.y + 12.0), Vector2(84.0, 24.0))


func _scale_for(zoom: float) -> float:
	var map: Rect2 = _map_rect()
	return minf(map.size.x, map.size.y) * 0.5 * 0.92 * zoom


func _scale() -> float:
	return _scale_for(_zoom)


func _to_screen(galaxy_pos: Vector2) -> Vector2:
	return _map_rect().get_center() + (galaxy_pos + _pan) * _scale()


func _info_rect() -> Rect2:
	var map: Rect2 = _map_rect()
	return Rect2(map.position + Vector2(12.0, map.size.y - 124.0), Vector2(280.0, 112.0))


func _warp_rect() -> Rect2:
	var info: Rect2 = _info_rect()
	return Rect2(info.position + Vector2(info.size.x - 96.0, info.size.y - 34.0), Vector2(84.0, 24.0))


func _system_at(screen_pos: Vector2) -> Dictionary:
	if not _map_rect().has_point(screen_pos):
		return {}
	var best: Dictionary = {}
	var best_d: float = MARKER_RADIUS + 8.0
	var unexplored_shown: bool = _systems_fade() > 0.2
	for system: Dictionary in GalaxyMap.systems():
		if not unexplored_shown and not GalaxyMap.is_visited(int(system["seed"])):
			continue
		var d: float = _to_screen(system["position"]).distance_to(screen_pos)
		if d < best_d:
			best_d = d
			best = system
	return best


## The neighbouring galaxy whose disc is under `screen_pos`, or -1.
func _galaxy_at(screen_pos: Vector2) -> int:
	if not _map_rect().has_point(screen_pos):
		return -1
	for i in GalaxyMap.NEIGHBOURS.size():
		var nb: Dictionary = GalaxyMap.NEIGHBOURS[i]
		var reach: float = maxf(float(nb["radius"]) * _scale() * 0.85, 10.0)
		if _to_screen(nb["position"]).distance_to(screen_pos) < reach:
			return i
	return -1


## 1 while unexplored systems are drawn in full, fading to 0 zoomed out.
func _systems_fade() -> float:
	return smoothstep(SYSTEMS_FADE_ZOOM.x, SYSTEMS_FADE_ZOOM.y, _zoom)


func _star(system_seed: int) -> Dictionary:
	if not _star_cache.has(system_seed):
		_star_cache[system_seed] = GalaxyMap.star_class(system_seed)
	return _star_cache[system_seed]


func _can_set_course() -> bool:
	return (
		_has_selected
		and not GalaxyMap.is_current(_selected_seed)
		and not (GalaxyMap.has_target() and GalaxyMap.target_seed() == _selected_seed)
	)


func _find_system(system_seed: int) -> Dictionary:
	for system: Dictionary in GalaxyMap.systems():
		if int(system["seed"]) == system_seed:
			return system
	return {}


func _update_hover() -> void:
	var over: Dictionary = _system_at(_mouse)
	_has_hover = not over.is_empty()
	_hover_seed = int(over.get("seed", 0))
	_hover_galaxy = -1 if _has_hover else _galaxy_at(_mouse)
	_hover_close = _close_rect().has_point(_mouse)
	_hover_help = HelpPopup.button_rect(_close_rect()).has_point(_mouse)
	_hover_center = _center_rect().has_point(_mouse)
	_hover_warp = _can_set_course() and _warp_rect().has_point(_mouse)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		_mouse = event.position
		if _dragging:
			_pan_goal += event.relative / _scale_for(_zoom_goal)
	elif event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP or mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			if mb.pressed:
				_zoom_about(mb.position, 1.25 if mb.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0 / 1.25)
		elif mb.button_index == MOUSE_BUTTON_RIGHT or mb.button_index == MOUSE_BUTTON_MIDDLE:
			_dragging = mb.pressed
		elif mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			_click(mb.position)
	accept_event()


func _click(pos: Vector2) -> void:
	var close: Rect2 = _close_rect()
	if HelpPopup.button_rect(close).has_point(pos):
		_help.toggle_at(Vector2(close.end.x, close.end.y + 10.0))
		return
	_help.close()
	if _close_rect().has_point(pos) or not _panel_rect().has_point(pos):
		hide_window()
		return
	if _center_rect().has_point(pos):
		_center_on_current(maxf(_zoom_goal, ZOOM_OPEN))
		return
	if _can_set_course() and _warp_rect().has_point(pos):
		GalaxyMap.set_target(_selected_seed)
		course_set.emit(_selected_seed)
		return
	if (_has_selected or _selected_galaxy >= 0) and _info_rect().has_point(pos):
		return
	var picked: Dictionary = _system_at(pos)
	_has_selected = not picked.is_empty()
	_selected_seed = int(picked.get("seed", 0))
	_selected_galaxy = -1 if _has_selected else _galaxy_at(pos)


## Zooms toward the goal, keeping the galaxy point under the cursor fixed.
func _zoom_about(screen_pos: Vector2, factor: float) -> void:
	var offset: Vector2 = screen_pos - _map_rect().get_center()
	var anchor: Vector2 = offset / _scale_for(_zoom_goal) - _pan_goal
	_zoom_goal = clampf(_zoom_goal * factor, ZOOM_MIN, ZOOM_MAX)
	_pan_goal = offset / _scale_for(_zoom_goal) - anchor


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.0, 0.0, 0.0, 0.8))
	var panel: Rect2 = _panel_rect()
	draw_set_transform(panel.position)
	HudPanelStyle.draw_chamfered(self, panel.size, HudPanelStyle.COLOR_CYAN, 18.0, 0.98)
	draw_set_transform(Vector2.ZERO)

	var font: Font = HudPanelStyle.get_font()
	draw_string(
		font, panel.position + Vector2(22.0, 36.0), "GALAXY MAP",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 20, HudPanelStyle.COLOR_TEXT_PRIMARY
	)
	var visited: int = GalaxyMap.visits().size()
	draw_string(
		font, panel.position + Vector2(190.0, 36.0),
		"%d %s VISITED" % [visited, "SYSTEM" if visited == 1 else "SYSTEMS"],
		HORIZONTAL_ALIGNMENT_LEFT, -1, 11, HudPanelStyle.COLOR_TEXT_MUTED
	)
	var close: Rect2 = _close_rect()
	HelpPopup.draw_button(self, HelpPopup.button_rect(close), _hover_help, _help.visible)
	draw_string(
		font, close.position + Vector2(5.0, 18.0), "X", HORIZONTAL_ALIGNMENT_LEFT, -1, 15,
		HudPanelStyle.COLOR_TEXT_PRIMARY if _hover_close else HudPanelStyle.COLOR_TEXT_MUTED
	)
	draw_line(
		panel.position + Vector2(18.0, 50.0), Vector2(panel.end.x - 18.0, panel.position.y + 50.0),
		Color(HudPanelStyle.COLOR_TEXT_FAINT, 0.8), 1.0
	)

	var map: Rect2 = _map_rect()
	_canvas.position = map.position
	_canvas.size = map.size
	_galaxy.size = map.size
	_overlay.size = map.size
	var material := _galaxy.material as ShaderMaterial
	material.set_shader_parameter("rect_size", map.size)
	material.set_shader_parameter("center", _to_screen(Vector2.ZERO) - map.position)
	material.set_shader_parameter("px_per_unit", _scale())
	_overlay.queue_redraw()


## Everything over the galaxy, drawn on the clipped overlay in this window's
## coordinates.
func _draw_overlay() -> void:
	var map: Rect2 = _map_rect()
	var font: Font = HudPanelStyle.get_font()
	_overlay.draw_set_transform(-map.position)
	_draw_grid(map, font)
	_draw_galaxies(map, font)
	_draw_route()
	_draw_course()
	_draw_unexplored(font)
	_draw_systems(font)
	_draw_scale_bar(map, font)
	_draw_legend(map, font)
	_draw_center_button(font)
	_draw_hover(font)
	_draw_info(font)
	_draw_galaxy_info(font)
	# Thin frame round the map.
	_overlay.draw_rect(map, HudPanelStyle.COLOR_BORDER_DEFAULT, false, 1.0)


## Rings every 10 000 ly out from the core, labelled, and the core itself.
func _draw_grid(map: Rect2, font: Font) -> void:
	var center: Vector2 = _to_screen(Vector2.ZERO)
	var s: float = _scale()
	for i in range(1, 6):
		var ring_r: float = float(i) / 5.0
		_overlay.draw_arc(center, ring_r * s, 0.0, TAU, 160, COLOR_GRID, 1.0, true)
		var label_at: Vector2 = center + Vector2(0.0, -ring_r * s)
		if _zoom > 0.5 and map.grow(-10.0).has_point(label_at):
			_overlay.draw_string(
				font, label_at + Vector2(4.0, -3.0), "%d kly" % (i * 10), HORIZONTAL_ALIGNMENT_LEFT, -1, 9,
				Color(COLOR_GRID, 0.5)
			)
	# Cross hairs through the core.
	var reach: float = s * 1.05
	_overlay.draw_line(center - Vector2(reach, 0.0), center + Vector2(reach, 0.0), Color(COLOR_GRID, 0.07), 1.0)
	_overlay.draw_line(center - Vector2(0.0, reach), center + Vector2(0.0, reach), Color(COLOR_GRID, 0.07), 1.0)
	if map.has_point(center) and _zoom < 8.0 and _zoom > 0.5:
		_overlay.draw_string(
			font, center + Vector2(-60.0, s * 0.16 + 14.0), "GALACTIC CORE", HORIZONTAL_ALIGNMENT_CENTER, 120, 10,
			Color(1.0, 0.9, 0.75, 0.45)
		)


## Names under the neighbouring galaxies (and ours, once zoomed out among
## them), with brackets on the hovered or picked one.
func _draw_galaxies(map: Rect2, font: Font) -> void:
	var s: float = _scale()
	var label_alpha: float = 1.0 - smoothstep(0.9, 1.6, _zoom)
	for i in GalaxyMap.NEIGHBOURS.size():
		var nb: Dictionary = GalaxyMap.NEIGHBOURS[i]
		var p: Vector2 = _to_screen(nb["position"])
		var rad: float = float(nb["radius"]) * s
		if not map.grow(rad + 80.0).has_point(p):
			continue
		var hovered: bool = i == _hover_galaxy
		var picked: bool = i == _selected_galaxy
		if hovered or picked:
			_draw_brackets(p, maxf(rad * 0.9, 12.0), Color(COLOR_GALAXY_LABEL, 0.9 if picked else 0.6))
		var alpha: float = 1.0 if hovered or picked else label_alpha
		if alpha <= 0.02:
			continue
		var below: float = maxf(rad * maxf(float(nb["tilt"]), 0.35), 6.0) + 16.0
		_draw_centered_shadowed(font, p + Vector2(0.0, below), String(nb["name"]).to_upper(), 11, Color(COLOR_GALAXY_LABEL, alpha))
		_draw_centered_shadowed(font, p + Vector2(0.0, below + 13.0), KIND_LABELS[nb["kind"]], 9, Color(COLOR_GALAXY_LABEL, 0.6 * alpha))
	# Our own galaxy, once it is small enough to sit among them.
	var home_alpha: float = 1.0 - smoothstep(0.35, 0.6, _zoom)
	if home_alpha > 0.02:
		var c: Vector2 = _to_screen(Vector2.ZERO) + Vector2(0.0, s * 1.05 + 16.0)
		_draw_centered_shadowed(font, c, GalaxyMap.HOME_GALAXY_NAME.to_upper(), 12, Color(HudPanelStyle.COLOR_AMBER, home_alpha))
		_draw_centered_shadowed(font, c + Vector2(0.0, 14.0), "HOME GALAXY", 9, Color(HudPanelStyle.COLOR_AMBER, 0.7 * home_alpha))


func _draw_centered_shadowed(font: Font, at: Vector2, text: String, font_size: int, color: Color) -> void:
	var w: float = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	_draw_text_shadowed(font, at - Vector2(w * 0.5, 0.0), text, font_size, color)


## The path taken: each visited system joined to the next, with an arrow
## halfway along showing the direction.
func _draw_route() -> void:
	var visits: Array[Dictionary] = GalaxyMap.visits()
	for i in range(1, visits.size()):
		var a: Vector2 = _to_screen(visits[i - 1]["position"])
		var b: Vector2 = _to_screen(visits[i]["position"])
		var length: float = a.distance_to(b)
		if length < MARKER_RADIUS * 3.0:
			continue
		var dir: Vector2 = (b - a) / length
		var a2: Vector2 = a + dir * (MARKER_RADIUS + 3.0)
		var b2: Vector2 = b - dir * (MARKER_RADIUS + 3.0)
		_overlay.draw_line(a2, b2, Color(COLOR_ROUTE, 0.12), 5.0, true)
		_overlay.draw_dashed_line(a2, b2, COLOR_ROUTE, 1.5, 7.0, true, true)
		var mid: Vector2 = (a + b) * 0.5
		var side: Vector2 = dir.orthogonal() * 4.5
		_overlay.draw_colored_polygon(
			PackedVector2Array([mid + dir * 6.0, mid - dir * 4.0 + side, mid - dir * 4.0 - side]),
			Color(COLOR_ROUTE, 0.9)
		)


## The jump the hyperdrive is set for: current system to the target, amber.
func _draw_course() -> void:
	if not GalaxyMap.has_target():
		return
	var here: Dictionary = _find_system(GalaxyMap.current_seed())
	var there: Dictionary = _find_system(GalaxyMap.target_seed())
	if here.is_empty() or there.is_empty():
		return
	var a: Vector2 = _to_screen(here["position"])
	var b: Vector2 = _to_screen(there["position"])
	var length: float = a.distance_to(b)
	if length < MARKER_RADIUS * 3.0:
		return
	var dir: Vector2 = (b - a) / length
	var a2: Vector2 = a + dir * (MARKER_RADIUS + 3.0)
	var b2: Vector2 = b - dir * (MARKER_RADIUS + 3.0)
	_overlay.draw_line(a2, b2, Color(HudPanelStyle.COLOR_AMBER, 0.15), 6.0, true)
	_overlay.draw_dashed_line(a2, b2, Color(HudPanelStyle.COLOR_AMBER, 0.9), 1.5, 10.0, true, true)


## Systems nobody has been to: small faint dots, named when hovered, picked,
## on the course, or once zoomed in far enough.
func _draw_unexplored(font: Font) -> void:
	var map: Rect2 = _map_rect()
	for system: Dictionary in GalaxyMap.systems():
		var system_seed: int = int(system["seed"])
		if GalaxyMap.is_visited(system_seed):
			continue
		var p: Vector2 = _to_screen(system["position"])
		if not map.grow(40.0).has_point(p):
			continue
		var hovered: bool = _has_hover and system_seed == _hover_seed
		var picked: bool = _has_selected and system_seed == _selected_seed
		var target: bool = GalaxyMap.has_target() and system_seed == GalaxyMap.target_seed()
		var fade: float = 1.0 if hovered or picked or target else _systems_fade()
		if fade <= 0.02:
			continue
		var star: Color = _star(system_seed)["color"]
		var color: Color = HudPanelStyle.COLOR_AMBER if target else COLOR_UNEXPLORED
		var alpha: float = (1.0 if hovered or picked or target else 0.8) * fade
		# Halo and core in the star's own colour, ringed so it reads as a
		# place and not just another star of the galaxy.
		_overlay.draw_circle(p, MARKER_RADIUS * 1.7, Color(star, 0.1 * alpha))
		_overlay.draw_circle(p, MARKER_RADIUS * 1.05, Color(0.0, 0.0, 0.0, 0.35 * alpha))
		_overlay.draw_arc(p, MARKER_RADIUS * (1.2 if hovered else 0.95), 0.0, TAU, 28, Color(color, 0.75 * alpha), 1.2, true)
		_overlay.draw_circle(p, 2.8, Color(star, 0.95 * alpha))
		_overlay.draw_circle(p, 1.2, Color(1.0, 1.0, 1.0, alpha))
		if picked:
			_draw_brackets(p, MARKER_RADIUS + 5.0, HudPanelStyle.COLOR_TEXT_PRIMARY)
		var name_fade: float = 1.0 if hovered or picked or target else smoothstep(NAME_ZOOM * 0.8, NAME_ZOOM, _zoom) * fade
		if name_fade > 0.02:
			var tag_at: Vector2 = p + Vector2(MARKER_RADIUS + 6.0, -2.0)
			_draw_text_shadowed(font, tag_at, String(system["name"]).to_upper(), 10, Color(color.lerp(Color.WHITE, 0.3), name_fade))
			if target:
				_draw_text_shadowed(font, tag_at + Vector2(0.0, 12.0), "COURSE SET", 9, Color(color, 0.85))


func _draw_systems(font: Font) -> void:
	var pulse: float = fmod(Time.get_ticks_msec() * 0.0006, 1.0)
	var visits: Array[Dictionary] = GalaxyMap.visits()
	for i in visits.size():
		var system: Dictionary = visits[i]
		var system_seed: int = int(system["seed"])
		var p: Vector2 = _to_screen(system["position"])
		var here: bool = GalaxyMap.is_current(system_seed)
		var hovered: bool = _has_hover and system_seed == _hover_seed
		var color: Color = HudPanelStyle.COLOR_AMBER if here else HudPanelStyle.COLOR_CYAN
		# Soft glow, then a ring with a bright dot.
		_overlay.draw_circle(p, MARKER_RADIUS * 2.4, Color(color, 0.06))
		_overlay.draw_circle(p, MARKER_RADIUS * 1.5, Color(color, 0.1))
		if here:
			for wave in 2:
				var t: float = fmod(pulse + wave * 0.5, 1.0)
				_overlay.draw_arc(
					p, MARKER_RADIUS + 2.0 + t * 18.0, 0.0, TAU, 48, Color(color, 0.8 * (1.0 - t)), 1.5, true
				)
		var ring: float = MARKER_RADIUS * (1.25 if hovered else 1.0)
		_overlay.draw_circle(p, ring, Color(0.0, 0.0, 0.0, 0.45))
		_overlay.draw_arc(p, ring, 0.0, TAU, 32, color, 1.5, true)
		_overlay.draw_circle(p, 2.8, Color(_star(system_seed)["color"], 0.95))
		_overlay.draw_circle(p, 1.2, Color(1.0, 1.0, 1.0, 0.95))
		if _has_selected and system_seed == _selected_seed:
			_draw_brackets(p, MARKER_RADIUS + 7.0, HudPanelStyle.COLOR_TEXT_PRIMARY)
		# Name tag with the visit number, dropped once the galaxy is small
		# among its neighbours and the tags would pile up.
		if not hovered and (_zoom < 0.2 or (_zoom < 0.4 and not here)):
			continue
		var label: String = String(system["name"]).to_upper()
		var tag_at: Vector2 = p + Vector2(MARKER_RADIUS + 9.0, -3.0)
		_draw_text_shadowed(font, tag_at, label, 11, HudPanelStyle.COLOR_TEXT_PRIMARY if hovered or here else HudPanelStyle.COLOR_TEXT_SECONDARY)
		var target: bool = GalaxyMap.has_target() and system_seed == GalaxyMap.target_seed()
		var sub: String = "YOU ARE HERE" if here else ("COURSE SET" if target else "VISIT %d" % (i + 1))
		_draw_text_shadowed(font, tag_at + Vector2(0.0, 12.0), sub, 9, Color(color, 0.85))


func _draw_text_shadowed(font: Font, at: Vector2, text: String, font_size: int, color: Color) -> void:
	_overlay.draw_string(font, at + Vector2(1.0, 1.0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color(0.0, 0.0, 0.0, 0.8))
	_overlay.draw_string(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)


func _draw_brackets(p: Vector2, r: float, color: Color) -> void:
	var l: float = r * 0.45
	for corner: Vector2 in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
		var c: Vector2 = p + corner * r
		_overlay.draw_line(c, c - Vector2(corner.x * l, 0.0), color, 1.5)
		_overlay.draw_line(c, c - Vector2(0.0, corner.y * l), color, 1.5)


## A bar a round number of light years long, bottom right.
func _draw_scale_bar(map: Rect2, font: Font) -> void:
	var ly_per_px: float = RADIUS_LY / _scale()
	var target: float = ly_per_px * 140.0
	var step: float = pow(10.0, floor(log(target) / log(10.0)))
	for m: float in [5.0, 2.0, 1.0]:
		if step * m <= target:
			step *= m
			break
	var w: float = step / ly_per_px
	var right: Vector2 = Vector2(map.end.x - 20.0, map.end.y - 22.0)
	var left: Vector2 = right - Vector2(w, 0.0)
	var c := Color(HudPanelStyle.COLOR_TEXT_SECONDARY, 0.8)
	_overlay.draw_line(left, right, c, 1.5)
	_overlay.draw_line(left - Vector2(0.0, 4.0), left + Vector2(0.0, 4.0), c, 1.5)
	_overlay.draw_line(right - Vector2(0.0, 4.0), right + Vector2(0.0, 4.0), c, 1.5)
	var text: String
	if step >= 1000000.0:
		text = "%s Mly" % _trim(step / 1000000.0)
	elif step >= 1000.0:
		text = "%s kly" % _trim(step / 1000.0)
	else:
		text = "%s ly" % _trim(step)
	_overlay.draw_string(font, left + Vector2(0.0, -7.0), text, HORIZONTAL_ALIGNMENT_CENTER, w, 10, c)


func _trim(value: float) -> String:
	return str(int(value)) if is_equal_approx(value, round(value)) else "%.1f" % value


func _draw_center_button(font: Font) -> void:
	var r: Rect2 = _center_rect()
	_overlay.draw_rect(r, Color(HudPanelStyle.COLOR_BG_SURFACE, 0.85))
	_overlay.draw_rect(r, HudPanelStyle.COLOR_CYAN if _hover_center else HudPanelStyle.COLOR_BORDER_HOVER, false, 1.0)
	_overlay.draw_string(
		font, r.position + Vector2(0.0, 16.0), "CENTER", HORIZONTAL_ALIGNMENT_CENTER, r.size.x, 11,
		HudPanelStyle.COLOR_TEXT_PRIMARY if _hover_center else HudPanelStyle.COLOR_TEXT_SECONDARY
	)


## Galaxy coordinates under the cursor, as a navigator's readout.
func _draw_hover(font: Font) -> void:
	var map: Rect2 = _map_rect()
	if not map.has_point(_mouse):
		return
	var g: Vector2 = (_mouse - map.get_center()) / _scale() - _pan
	var dist_ly: float = g.length() * RADIUS_LY
	var bearing: float = fposmod(rad_to_deg(atan2(g.y, g.x)), 360.0)
	var color := Color(HudPanelStyle.COLOR_TEXT_MUTED, 0.9)
	var at := Vector2(map.position.x + 14.0, map.position.y + 26.0)
	_overlay.draw_string(
		font, at, "%s kly from core" % _trim(snappedf(dist_ly / 1000.0, 0.1)), HORIZONTAL_ALIGNMENT_LEFT, -1, 10, color
	)
	_overlay.draw_string(font, at + Vector2(0.0, 14.0), "Bearing %03d°" % int(bearing), HORIZONTAL_ALIGNMENT_LEFT, -1, 10, color)


func _distance_ly(a: Vector2, b: Vector2) -> float:
	return a.distance_to(b) * RADIUS_LY


## Details of the selected system, with SET COURSE when it isn't the current
## one.
func _draw_info(font: Font) -> void:
	if not _has_selected:
		return
	var system: Dictionary = _find_system(_selected_seed)
	if system.is_empty():
		return
	var i: int = GalaxyMap.index_of(_selected_seed)
	var info: Rect2 = _info_rect()
	var here: bool = GalaxyMap.is_current(_selected_seed)
	var accent: Color = HudPanelStyle.COLOR_AMBER if here else HudPanelStyle.COLOR_CYAN
	_overlay.draw_rect(info, Color(HudPanelStyle.COLOR_BG_SURFACE, 0.94))
	_overlay.draw_rect(info, HudPanelStyle.COLOR_BORDER_HOVER, false, 1.0)
	_overlay.draw_rect(Rect2(info.position, Vector2(3.0, info.size.y)), accent)
	var x: Vector2 = info.position + Vector2(16.0, 0.0)
	_overlay.draw_string(
		font, x + Vector2(0.0, 24.0), String(system["name"]).to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, 15,
		HudPanelStyle.COLOR_TEXT_PRIMARY
	)
	var pos: Vector2 = system["position"]
	_overlay.draw_string(
		font, x + Vector2(0.0, 42.0), ("Visit %d" % (i + 1)) if i >= 0 else "Unexplored",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 10, HudPanelStyle.COLOR_TEXT_MUTED
	)
	var star: Dictionary = _star(_selected_seed)
	_overlay.draw_circle(x + Vector2(4.0, 52.5), 3.5, star["color"])
	_overlay.draw_string(
		font, x + Vector2(13.0, 56.0), "Class %s  %s" % [star["letter"], star["name"]],
		HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(star["color"], 0.9)
	)
	_overlay.draw_string(
		font, x + Vector2(0.0, 70.0), "%s kly from core" % _trim(snappedf(pos.length() * RADIUS_LY / 1000.0, 0.1)),
		HORIZONTAL_ALIGNMENT_LEFT, -1, 10, HudPanelStyle.COLOR_TEXT_MUTED
	)
	if here:
		_overlay.draw_string(font, x + Vector2(0.0, 96.0), "YOU ARE HERE", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, accent)
		return
	var current: Dictionary = _find_system(GalaxyMap.current_seed())
	if not current.is_empty():
		var d: float = _distance_ly(current["position"], pos)
		_overlay.draw_string(
			font, x + Vector2(0.0, 96.0), "%s kly away" % _trim(snappedf(d / 1000.0, 0.1)),
			HORIZONTAL_ALIGNMENT_LEFT, -1, 11, HudPanelStyle.COLOR_TEXT_SECONDARY
		)
	var warp: Rect2 = _warp_rect()
	if not _can_set_course():
		_overlay.draw_rect(warp, Color(HudPanelStyle.COLOR_AMBER, 0.12))
		_overlay.draw_rect(warp, Color(HudPanelStyle.COLOR_AMBER, 0.7), false, 1.0)
		_overlay.draw_string(
			font, warp.position + Vector2(0.0, 16.0), "COURSE SET", HORIZONTAL_ALIGNMENT_CENTER, warp.size.x, 10,
			HudPanelStyle.COLOR_AMBER
		)
		return
	_overlay.draw_rect(warp, Color(HudPanelStyle.COLOR_CYAN, 0.32 if _hover_warp else 0.12))
	_overlay.draw_rect(warp, HudPanelStyle.COLOR_CYAN, false, 1.0)
	_overlay.draw_string(
		font, warp.position + Vector2(0.0, 16.0), "SET COURSE", HORIZONTAL_ALIGNMENT_CENTER, warp.size.x, 10,
		HudPanelStyle.COLOR_TEXT_PRIMARY
	)


## Details of the picked neighbouring galaxy. No course: the hyperdrive only
## jumps between stars of our own galaxy.
func _draw_galaxy_info(font: Font) -> void:
	if _selected_galaxy < 0:
		return
	var nb: Dictionary = GalaxyMap.NEIGHBOURS[_selected_galaxy]
	var info: Rect2 = _info_rect()
	_overlay.draw_rect(info, Color(HudPanelStyle.COLOR_BG_SURFACE, 0.94))
	_overlay.draw_rect(info, HudPanelStyle.COLOR_BORDER_HOVER, false, 1.0)
	_overlay.draw_rect(Rect2(info.position, Vector2(3.0, info.size.y)), COLOR_GALAXY_LABEL)
	var x: Vector2 = info.position + Vector2(16.0, 0.0)
	_overlay.draw_string(
		font, x + Vector2(0.0, 24.0), String(nb["name"]).to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, 15,
		HudPanelStyle.COLOR_TEXT_PRIMARY
	)
	_overlay.draw_string(
		font, x + Vector2(0.0, 42.0), String(KIND_LABELS[nb["kind"]]).capitalize(),
		HORIZONTAL_ALIGNMENT_LEFT, -1, 10, COLOR_GALAXY_LABEL
	)
	var distance: float = (nb["position"] as Vector2).length() * RADIUS_LY
	_overlay.draw_string(
		font, x + Vector2(0.0, 56.0), "%s from our galaxy" % _light_years(distance),
		HORIZONTAL_ALIGNMENT_LEFT, -1, 10, HudPanelStyle.COLOR_TEXT_MUTED
	)
	_overlay.draw_string(
		font, x + Vector2(0.0, 70.0), "%s across" % _light_years(float(nb["radius"]) * 2.0 * RADIUS_LY),
		HORIZONTAL_ALIGNMENT_LEFT, -1, 10, HudPanelStyle.COLOR_TEXT_MUTED
	)
	_overlay.draw_string(
		font, x + Vector2(0.0, 96.0), "Beyond hyperdrive range", HORIZONTAL_ALIGNMENT_LEFT, -1, 11,
		Color(HudPanelStyle.COLOR_AMBER, 0.85)
	)


func _light_years(value: float) -> String:
	if value >= 1000000.0:
		return "%s Mly" % _trim(snappedf(value / 1000000.0, 0.01))
	return "%s kly" % _trim(snappedf(value / 1000.0, 1.0))


## What the marks mean, bottom right over the scale bar.
func _draw_legend(map: Rect2, font: Font) -> void:
	var box := Rect2(Vector2(map.end.x - 196.0, map.end.y - 168.0), Vector2(182.0, 128.0))
	_overlay.draw_rect(box, Color(HudPanelStyle.COLOR_BG_SURFACE, 0.8))
	_overlay.draw_rect(box, HudPanelStyle.COLOR_BORDER_DEFAULT, false, 1.0)
	var muted := HudPanelStyle.COLOR_TEXT_SECONDARY
	var x: float = box.position.x + 20.0
	var y: float = box.position.y + 18.0
	_overlay.draw_arc(Vector2(x, y), 5.0, 0.0, TAU, 24, HudPanelStyle.COLOR_AMBER, 1.5, true)
	_overlay.draw_circle(Vector2(x, y), 1.8, Color.WHITE)
	_overlay.draw_string(font, Vector2(x + 14.0, y + 4.0), "You are here", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, muted)
	y += 20.0
	_overlay.draw_arc(Vector2(x, y), 5.0, 0.0, TAU, 24, HudPanelStyle.COLOR_CYAN, 1.5, true)
	_overlay.draw_circle(Vector2(x, y), 1.8, Color.WHITE)
	_overlay.draw_string(font, Vector2(x + 14.0, y + 4.0), "Visited", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, muted)
	y += 20.0
	_overlay.draw_arc(Vector2(x, y), 5.0, 0.0, TAU, 24, Color(COLOR_UNEXPLORED, 0.75), 1.2, true)
	_overlay.draw_circle(Vector2(x, y), 1.8, Color(1.0, 0.9, 0.6))
	_overlay.draw_string(font, Vector2(x + 14.0, y + 4.0), "Unexplored", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, muted)
	y += 20.0
	_overlay.draw_dashed_line(Vector2(x - 7.0, y), Vector2(x + 7.0, y), HudPanelStyle.COLOR_AMBER, 1.5, 4.0, true, true)
	_overlay.draw_string(font, Vector2(x + 14.0, y + 4.0), "Course set", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, muted)
	y += 22.0
	# Star colours, hottest to coolest.
	var sx: float = x - 6.0
	for entry: Dictionary in GalaxyMap.STAR_CLASSES:
		_overlay.draw_circle(Vector2(sx + 3.0, y), 3.2, entry["color"])
		_overlay.draw_string(font, Vector2(sx - 1.0, y + 15.0), entry["letter"], HORIZONTAL_ALIGNMENT_LEFT, -1, 9, HudPanelStyle.COLOR_TEXT_MUTED)
		sx += 16.0
	_overlay.draw_string(font, Vector2(sx + 4.0, y + 4.0), "Star", HORIZONTAL_ALIGNMENT_LEFT, -1, 9, HudPanelStyle.COLOR_TEXT_MUTED)

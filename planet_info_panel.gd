extends Control

## Planet catalog: every body in the system, each with a live 3D view (the
## same shaders as in space - drag to turn it, scroll to zoom), its vital
## numbers read straight off the body, and a description and facts that
## PlanetLore writes from its kind and this world's roll. Toggled with I (solar_system.gd routes the keys while it is
## open), or opened on the current body by the (i) button in the left panel.
## Arrow keys step through the bodies.

const MARGIN := 36.0
const LIST_WIDTH := 230.0
const ROW_HEIGHT := 46.0
const TEXT_WIDTH := 400.0
const GAP := 20.0

## Orthographic view sizes, in body radii across the shorter side.
const VIEW_DEFAULT := 2.4
const VIEW_STAR := 4.2
const VIEW_CLOSEST := 0.35

## Radians per pixel of drag, and the idle spin in radians per second.
const DRAG_TURN := 0.008
const IDLE_SPIN := 0.12

## Where the preview planet sits relative to the sun's (global) position, so
## the planet shaders light it from the left, as the sun does in space.
const PREVIEW_OFFSET := Vector3(100000.0, 0.0, 0.0)

var _system: Node = null
var _bodies: Array[Node2D] = []
var _selected: int = 0
var _hovered: int = -1
var _hover_close: bool = false

var _viewport_container: SubViewportContainer
var _viewport: SubViewport
var _world_root: Node3D
var _camera: Camera3D
var _preview: Node3D = null
var _globe: Node3D = null
var _view_size: float = VIEW_DEFAULT
var _dragging: bool = false
var _idle_time: float = 0.0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	_build_viewport()
	resized.connect(_layout)
	# Over the rest of the HUD, which is added after this node in the scene.
	move_to_front.call_deferred()


## `system` is solar_system.gd: the catalog reads its sun, planets and orbits.
func setup(system: Node) -> void:
	_system = system
	_bodies.clear()
	_bodies.append(system.get("sun"))
	for planet: Node2D in system.get("planets"):
		_bodies.append(planet)


func toggle() -> void:
	if visible:
		hide_panel()
	else:
		open_on(null)


## Opens the catalog, on `body` if it is in it.
func open_on(body: Node2D) -> void:
	if _bodies.is_empty():
		return
	var index: int = _bodies.find(body)
	visible = true
	_select(index if index >= 0 else _selected)
	_layout()


## Moves the selection `offset` rows, wrapping round the list.
func step(offset: int) -> void:
	_select(posmod(_selected + offset, _bodies.size()))


func hide_panel() -> void:
	visible = false
	_clear_preview()


func _build_viewport() -> void:
	_viewport_container = SubViewportContainer.new()
	_viewport_container.stretch = true
	_viewport_container.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(_viewport_container)

	_viewport = SubViewport.new()
	_viewport.own_world_3d = true
	_viewport.transparent_bg = true
	_viewport.msaa_3d = Viewport.MSAA_4X
	_viewport.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE
	_viewport_container.add_child(_viewport)

	_world_root = Node3D.new()
	_viewport.add_child(_world_root)

	var environment := Environment.new()
	environment.background_mode = Environment.BG_CLEAR_COLOR
	environment.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	environment.glow_enabled = true
	environment.glow_intensity = 0.7
	environment.glow_bloom = 0.0
	environment.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE
	environment.glow_hdr_threshold = 1.0
	var world_environment := WorldEnvironment.new()
	world_environment.environment = environment
	_world_root.add_child(world_environment)

	# Looking straight down, like the game's own camera, so the planet
	# shaders' light lift works the same here.
	_camera = Camera3D.new()
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_camera.near = 1.0
	_camera.far = 200.0
	_world_root.add_child(_camera)


func _preview_origin() -> Vector3:
	# Mirrors the `sun_position` global solar_system.gd sets for the shaders
	# (reading the global back only works in the editor).
	var sun: Vector2 = (_system.get("sun") as Node2D).global_position
	return Vector3(sun.x, 0.0, sun.y) + PREVIEW_OFFSET


func _select(index: int) -> void:
	_selected = clampi(index, 0, _bodies.size() - 1)
	_clear_preview()

	var body: Node2D = _bodies[_selected]
	_preview = body.call("make_preview")
	_world_root.add_child(_preview)
	_preview.position = _preview_origin()
	_globe = _preview.get_child(0) if _preview.get_child_count() > 0 else null

	_view_size = VIEW_STAR if body.get("is_star") else VIEW_DEFAULT
	_camera.size = _view_size
	_camera.look_at_from_position(
		_preview.position + Vector3(0.0, 50.0, 0.0), _preview.position, Vector3(0.0, 0.0, -1.0)
	)
	_idle_time = 0.0
	queue_redraw()


func _clear_preview() -> void:
	if _preview != null:
		_preview.queue_free()
	_preview = null
	_globe = null


func _process(delta: float) -> void:
	if not visible:
		return

	# The live materials follow the game's clock; the preview turns on its
	# own until the player grabs it.
	if _globe != null and not _dragging:
		_idle_time += delta
		_turn(Vector3(0.0, 0.0, 1.0), IDLE_SPIN * delta * smoothstep(0.0, 1.5, _idle_time))

	# Keep lighting right even if the sun moved while the catalog was open.
	if _preview != null:
		var origin: Vector3 = _preview_origin()
		if not origin.is_equal_approx(_preview.position):
			_preview.position = origin
			_camera.look_at_from_position(origin + Vector3(0.0, 50.0, 0.0), origin, Vector3(0.0, 0.0, -1.0))


func _turn(axis: Vector3, angle: float) -> void:
	_globe.basis = (Basis(axis, angle) * _globe.basis).orthonormalized()


# ---- layout ---------------------------------------------------------------

func _panel_rect() -> Rect2:
	return Rect2(Vector2.ONE * MARGIN, size - Vector2.ONE * MARGIN * 2.0)


func _list_rect() -> Rect2:
	var panel: Rect2 = _panel_rect()
	return Rect2(panel.position + Vector2(18.0, 64.0), Vector2(LIST_WIDTH, panel.size.y - 82.0))


func _text_rect() -> Rect2:
	var panel: Rect2 = _panel_rect()
	var width: float = minf(TEXT_WIDTH, panel.size.x * 0.34)
	return Rect2(
		Vector2(panel.end.x - width - 22.0, panel.position.y + 64.0),
		Vector2(width, panel.size.y - 82.0)
	)


func _view_rect() -> Rect2:
	var list: Rect2 = _list_rect()
	var text: Rect2 = _text_rect()
	var left: float = list.end.x + GAP
	return Rect2(Vector2(left, list.position.y), Vector2(text.position.x - GAP - left, list.size.y))


func _close_rect() -> Rect2:
	var panel: Rect2 = _panel_rect()
	return Rect2(Vector2(panel.end.x - 36.0, panel.position.y + 12.0), Vector2(24.0, 24.0))


func _layout() -> void:
	if _viewport_container == null:
		return
	var view: Rect2 = _view_rect()
	_viewport_container.position = view.position
	_viewport_container.size = view.size
	queue_redraw()


func _row_at(point: Vector2) -> int:
	var list: Rect2 = _list_rect()
	if not list.has_point(point):
		return -1
	var index: int = int((point.y - list.position.y) / ROW_HEIGHT)
	return index if index < _bodies.size() else -1


# ---- input ----------------------------------------------------------------

func _gui_input(event: InputEvent) -> void:
	var view: Rect2 = _view_rect()

	if event is InputEventMouseMotion:
		var motion := event as InputEventMouseMotion
		if _dragging and _globe != null:
			# Drag sideways turns the globe about the screen's vertical, drag
			# up and down about its horizontal.
			_turn(Vector3(0.0, 0.0, -1.0), motion.relative.x * DRAG_TURN)
			_turn(Vector3(1.0, 0.0, 0.0), motion.relative.y * DRAG_TURN)
		var hovered: int = _row_at(motion.position)
		var hover_close: bool = _close_rect().has_point(motion.position)
		if hovered != _hovered or hover_close != _hover_close:
			_hovered = hovered
			_hover_close = hover_close
			queue_redraw()

	elif event is InputEventMouseButton:
		var button := event as InputEventMouseButton
		if button.button_index == MOUSE_BUTTON_LEFT:
			if button.pressed:
				if _close_rect().has_point(button.position) or not _panel_rect().has_point(button.position):
					hide_panel()
				elif _row_at(button.position) >= 0:
					_select(_row_at(button.position))
				elif view.has_point(button.position):
					_dragging = true
			else:
				_dragging = false
				_idle_time = 0.0
		elif button.pressed and view.has_point(button.position):
			var base: float = VIEW_STAR if _bodies[_selected].get("is_star") else VIEW_DEFAULT
			if button.button_index == MOUSE_BUTTON_WHEEL_UP:
				_view_size = maxf(_view_size * 0.88, VIEW_CLOSEST)
			elif button.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				_view_size = minf(_view_size / 0.88, base * 1.6)
			_camera.size = _view_size

	accept_event()


# ---- numbers ----------------------------------------------------------------

func _lore(body: Node2D) -> Dictionary:
	return PlanetLore.describe(body.get("terrain_kind"), body.get("terrain_params"), body.get("is_star"))


## Label/value rows for the body, all read live from the simulation.
func _stats(body: Node2D) -> Array:
	var gravity: float = _system.get_script().get_script_constant_map()["G"]
	var radius: float = body.get("radius")
	var mass: float = body.get("mass")
	var rows: Array = [
		["Diameter", "%.0f SU" % (radius * 2.0)],
		["Mass", "%.1f" % mass],
		["Surface gravity", "%.2f SU/s^2" % (gravity * mass / maxf(radius * radius, 1.0))],
		["Escape velocity", "%.1f SU/s" % sqrt(2.0 * gravity * mass / maxf(radius, 1.0))],
	]

	var sun: Node2D = _system.get("sun")
	if body != sun:
		var distance: float = body.position.distance_to(sun.position)
		var sun_mass: float = sun.get("mass")
		var period: float = TAU * sqrt(pow(distance, 3.0) / (gravity * sun_mass))
		rows.append(["Orbit radius", "%.0f SU" % distance])
		rows.append(["Year", _duration(period)])
		rows.append(["Sphere of influence", "%.0f SU" % _system.call("get_soi_radius", body)])

	var spin: float = absf(body.call("get_spin_rate"))
	rows.append(["Day", _duration(TAU / spin) if spin > 0.0001 else "-"])

	var params: Dictionary = body.get("terrain_params")
	var terrain: Dictionary = body.get("terrain_data")
	if not params.is_empty() and params.get("liquid", false) and not terrain.is_empty():
		rows.append(["Surface liquid", "%d%%" % roundi(params["coverage"] * 100.0)])
	if not params.is_empty() and params.get("clouds", 0.0) > 0.0:
		rows.append(["Cloud cover", "~%d%%" % roundi(params["clouds"] * 100.0)])

	rows.append(["Atmosphere", body.get("atmosphere")])
	return rows


## A span of simulated time on the game clock (see solar_system.gd's
## CLOCK_HOURS_PER_SIM_SECOND): hours up to a few days, then days.
func _duration(sim_seconds: float) -> String:
	var hours_per_second: float = _system.get_script().get_script_constant_map()["CLOCK_HOURS_PER_SIM_SECOND"]
	var hours: float = sim_seconds * hours_per_second
	if hours >= 72.0:
		return "%.0f days" % (hours / 24.0)
	return "%.1f h" % hours


# ---- drawing ----------------------------------------------------------------

func _draw() -> void:
	if _bodies.is_empty():
		return

	draw_rect(Rect2(Vector2.ZERO, size), Color(0.0, 0.0, 0.0, 0.8))
	var panel: Rect2 = _panel_rect()
	draw_set_transform(panel.position)
	HudPanelStyle.draw_chamfered(self, panel.size, HudPanelStyle.COLOR_CYAN, 18.0, 0.98)
	draw_set_transform(Vector2.ZERO)

	var font: Font = HudPanelStyle.get_font()
	draw_string(
		font, panel.position + Vector2(22.0, 36.0), "PLANETARY CATALOG",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 20, HudPanelStyle.COLOR_TEXT_PRIMARY
	)
	draw_string(
		font, panel.position + Vector2(260.0, 36.0), "VESPERIS SYSTEM   ·   I or Esc to close",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 11, HudPanelStyle.COLOR_TEXT_MUTED
	)
	var close: Rect2 = _close_rect()
	draw_string(
		font, close.position + Vector2(5.0, 18.0), "X", HORIZONTAL_ALIGNMENT_LEFT, -1, 15,
		HudPanelStyle.COLOR_TEXT_PRIMARY if _hover_close else HudPanelStyle.COLOR_TEXT_MUTED
	)
	draw_line(
		panel.position + Vector2(18.0, 50.0), Vector2(panel.end.x - 18.0, panel.position.y + 50.0),
		Color(HudPanelStyle.COLOR_TEXT_FAINT, 0.8), 1.0
	)

	_draw_list(font)
	_draw_view_frame(font)
	_draw_text(font)


func _draw_list(font: Font) -> void:
	var list: Rect2 = _list_rect()
	for i in range(_bodies.size()):
		var body: Node2D = _bodies[i]
		var row := Rect2(list.position + Vector2(0.0, i * ROW_HEIGHT), Vector2(list.size.x, ROW_HEIGHT - 4.0))
		if i == _selected:
			draw_rect(row, HudPanelStyle.COLOR_CYAN_GLOW)
			draw_rect(Rect2(row.position, Vector2(3.0, row.size.y)), HudPanelStyle.COLOR_CYAN)
		elif i == _hovered:
			draw_rect(row, Color(1.0, 1.0, 1.0, 0.04))

		var swatch: Color = body.get("color")
		draw_circle(row.position + Vector2(20.0, row.size.y * 0.5), 7.0, swatch)
		var name: String = body.get("body_name")
		var lore: Dictionary = _lore(body)
		draw_string(
			font, row.position + Vector2(38.0, 19.0), name.to_upper(), HORIZONTAL_ALIGNMENT_LEFT,
			row.size.x - 42.0, 14,
			HudPanelStyle.COLOR_TEXT_PRIMARY if i == _selected else HudPanelStyle.COLOR_TEXT_SECONDARY
		)
		draw_string(
			font, row.position + Vector2(38.0, 35.0), lore.get("class", ""), HORIZONTAL_ALIGNMENT_LEFT,
			row.size.x - 42.0, 10, HudPanelStyle.COLOR_TEXT_MUTED
		)


func _draw_view_frame(font: Font) -> void:
	var view: Rect2 = _view_rect()
	draw_rect(view, Color(HudPanelStyle.COLOR_BORDER_DEFAULT, 0.4), false, 1.0)
	draw_string(
		font, view.position + Vector2(10.0, view.size.y - 12.0), "DRAG TO ROTATE   ·   SCROLL TO ZOOM",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 10, HudPanelStyle.COLOR_TEXT_FAINT
	)


func _draw_text(font: Font) -> void:
	var text: Rect2 = _text_rect()
	var body: Node2D = _bodies[_selected]
	var name: String = body.get("body_name")
	var lore: Dictionary = _lore(body)
	var x: float = text.position.x
	var y: float = text.position.y + 18.0

	draw_string(font, Vector2(x, y), name.to_upper(), HORIZONTAL_ALIGNMENT_LEFT, text.size.x, 22, HudPanelStyle.COLOR_CYAN)
	y += 22.0
	draw_string(font, Vector2(x, y), lore.get("class", ""), HORIZONTAL_ALIGNMENT_LEFT, text.size.x, 12, HudPanelStyle.COLOR_AMBER)
	y += 22.0

	for row: Array in _stats(body):
		draw_string(font, Vector2(x, y), row[0], HORIZONTAL_ALIGNMENT_LEFT, text.size.x * 0.45, 11, HudPanelStyle.COLOR_TEXT_MUTED)
		draw_string(
			font, Vector2(x + text.size.x * 0.45, y), row[1], HORIZONTAL_ALIGNMENT_LEFT,
			text.size.x * 0.55, 11, HudPanelStyle.COLOR_TEXT_PRIMARY
		)
		y += 18.0

	y += 10.0
	y = _draw_paragraph(font, lore.get("description", ""), x, y, text.size.x, 12, HudPanelStyle.COLOR_TEXT_SECONDARY)

	var facts: Array = lore.get("facts", [])
	if not facts.is_empty():
		y += 14.0
		draw_string(font, Vector2(x, y), "DID YOU KNOW", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, HudPanelStyle.COLOR_EMERALD)
		y += 18.0
		for fact: String in facts:
			draw_string(font, Vector2(x, y), "›", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, HudPanelStyle.COLOR_EMERALD)
			y = _draw_paragraph(font, fact, x + 14.0, y, text.size.x - 14.0, 11, HudPanelStyle.COLOR_TEXT_SECONDARY)
			y += 6.0


## Word-wrapped text from its first baseline at `y`; returns the next free y.
func _draw_paragraph(font: Font, text: String, x: float, y: float, width: float, font_size: int, color: Color) -> float:
	var line_height: float = font.get_height(font_size) + 3.0
	var line := ""
	for word in text.split(" "):
		var attempt: String = word if line.is_empty() else line + " " + word
		if font.get_string_size(attempt, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x > width and not line.is_empty():
			draw_string(font, Vector2(x, y), line, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)
			y += line_height
			line = word
		else:
			line = attempt
	if not line.is_empty():
		draw_string(font, Vector2(x, y), line, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)
		y += line_height
	return y

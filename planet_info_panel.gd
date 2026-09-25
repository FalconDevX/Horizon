extends Control

## Planet catalog: every body in the system, each with a live 3D view (the
## same shaders as in space - drag to turn it, scroll to zoom), its vital
## numbers read straight off the body, and a description and facts that
## PlanetLore writes from its kind and this world's roll. Toggled with J (solar_system.gd routes the keys while it is
## open), or opened on the current body by the (i) button in the left panel.
## Arrow keys step through the bodies.
##
## A second tab lists the resources (ResourceDeposits.TYPES): each shown as a
## model, with where it turns up - which kinds of planet, where on them and on
## which variants - and how many this world has. Tab, or left / right, swaps.
##
## Only what the player knows is shown: a planet until the ship has charted it
## (solar_system.gd is_charted - flying near it), a resource until it has been
## found somewhere (is_resource_known), is a dark row, a silhouette and
## redaction bars. A resource is named only on the planets it was found on
## (is_resource_found_on): anything else on a planet is just "unidentified
## signals", and a resource's page lists only the planets it was found on.

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

const TABS := ["PLANETS", "RESOURCES"]
const TAB_PLANETS := 0
const TAB_RESOURCES := 1

var _system: Node = null
var _bodies: Array[Node2D] = []
var _selected: int = 0
var _hovered: int = -1
var _hover_close: bool = false
var _hover_help: bool = false
var _help: HelpPopup

var _viewport_container: SubViewportContainer
var _viewport: SubViewport
var _world_root: Node3D
var _camera: Camera3D
var _preview: Node3D = null
var _globe: Node3D = null
var _view_size: float = VIEW_DEFAULT
var _dragging: bool = false
var _idle_time: float = 0.0

var _tab: int = TAB_PLANETS
var _hovered_tab: int = -1
## Resource types in the order the tab lists them.
var _resources: Array = ResourceDeposits.TYPES.keys()
## The planet row selected when the tab was left, to come back to.
var _planet_selected: int = 0
## View size that frames the selected resource's model.
var _resource_view: float = 3.0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	_build_viewport()
	_help = HelpPopup.new(PackedStringArray([
		"Drag the planet: turn it",
		"Mouse wheel over the planet: zoom",
		"Up and Down arrows: previous and next entry",
		"Tab, Left or Right: planets / resources",
		"J or Esc: close the log",
	]))
	add_child(_help)
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
	_select(posmod(_selected + offset, _row_count()))


## Swaps between the planets and the resources.
func switch_tab() -> void:
	_set_tab(TAB_RESOURCES if _tab == TAB_PLANETS else TAB_PLANETS)


func _set_tab(tab: int) -> void:
	if tab == _tab:
		return
	if _tab == TAB_PLANETS:
		_planet_selected = _selected
	_tab = tab
	_select(_planet_selected if tab == TAB_PLANETS else 0)


func _row_count() -> int:
	return _bodies.size() if _tab == TAB_PLANETS else _resources.size()


func hide_panel() -> void:
	visible = false
	_help.close()
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
	_selected = clampi(index, 0, _row_count() - 1)
	_clear_preview()
	if _tab == TAB_RESOURCES:
		_select_resource()
		return

	var body: Node2D = _bodies[_selected]
	if _known_body(body):
		_preview = body.call("make_preview")
	else:
		# Uncharted: only its dark shape against the stars.
		_preview = Node3D.new()
		var ball := MeshInstance3D.new()
		var sphere := SphereMesh.new()
		sphere.radius = 1.0
		sphere.height = 2.0
		ball.mesh = sphere
		ball.material_override = _silhouette_material()
		_preview.add_child(ball)
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


## The resource's model, stood at the preview spot and seen a little from
## above and the side, as it would stand on a planet.
func _select_resource() -> void:
	var model: MeshInstance3D = ResourceDeposits.make_showcase(_resources[_selected])
	if not _known_resource(_resources[_selected]):
		model.material_override = _silhouette_material()
	# Turned about the middle of its bounds, not its foot, so a cluster that
	# sits off-centre does not swing out of view.
	var bounds: AABB = model.mesh.get_aabb()
	var pivot := Node3D.new()
	model.position = -bounds.get_center()
	pivot.add_child(model)
	_preview = Node3D.new()
	_preview.add_child(pivot)
	_world_root.add_child(_preview)
	_preview.position = _preview_origin()
	_globe = pivot
	_resource_view = maxf(bounds.size.y, maxf(bounds.size.x, bounds.size.z)) * 1.5
	_view_size = _resource_view
	_camera.size = _view_size
	_aim_camera()
	_idle_time = 0.0
	queue_redraw()


## Points the camera at the preview: straight down on a planet, like the
## game's own camera; slightly above and to the side of a resource.
func _aim_camera() -> void:
	var origin: Vector3 = _preview.position
	if _tab == TAB_RESOURCES:
		_camera.look_at_from_position(origin + Vector3(0.0, 1.6, 4.0) * 10.0, origin, Vector3.UP)
	else:
		_camera.look_at_from_position(origin + Vector3(0.0, 50.0, 0.0), origin, Vector3(0.0, 0.0, -1.0))


## Flat near-black, for things the player has not learned yet.
static func _silhouette_material() -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color(0.02, 0.022, 0.03)
	return material


func _known_body(body: Node2D) -> bool:
	return _system.call("is_charted", body)


func _known_resource(type_name: StringName) -> bool:
	return _system.call("is_resource_known", type_name)


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
		# A resource turns on its upright, and quicker - it is small.
		var axis := Vector3.UP if _tab == TAB_RESOURCES else Vector3(0.0, 0.0, 1.0)
		var speed: float = IDLE_SPIN * (3.0 if _tab == TAB_RESOURCES else 1.0)
		_turn(axis, speed * delta * smoothstep(0.0, 1.5, _idle_time))

	# Keep lighting right even if the sun moved while the catalog was open.
	if _preview != null:
		var origin: Vector3 = _preview_origin()
		if not origin.is_equal_approx(_preview.position):
			_preview.position = origin
			_aim_camera()


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


func _tab_rect(index: int) -> Rect2:
	var panel: Rect2 = _panel_rect()
	return Rect2(panel.position + Vector2(262.0 + index * 116.0, 16.0), Vector2(108.0, 26.0))


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


## Rows shrink to fit when the list is longer than the panel is tall.
func _row_height() -> float:
	return minf(ROW_HEIGHT, _list_rect().size.y / float(maxi(_row_count(), 1)))


func _row_at(point: Vector2) -> int:
	var list: Rect2 = _list_rect()
	if not list.has_point(point):
		return -1
	var index: int = int((point.y - list.position.y) / _row_height())
	return index if index < _row_count() else -1


func _tab_at(point: Vector2) -> int:
	for i in range(TABS.size()):
		if _tab_rect(i).has_point(point):
			return i
	return -1


# ---- input ----------------------------------------------------------------

func _gui_input(event: InputEvent) -> void:
	var view: Rect2 = _view_rect()

	if event is InputEventMouseMotion:
		var motion := event as InputEventMouseMotion
		if _dragging and _globe != null:
			# Drag sideways turns the globe about the screen's vertical, drag
			# up and down about its horizontal. A resource only turns on its
			# own upright, so it stays standing.
			if _tab == TAB_RESOURCES:
				_turn(Vector3.UP, motion.relative.x * DRAG_TURN)
			else:
				_turn(Vector3(0.0, 0.0, -1.0), motion.relative.x * DRAG_TURN)
				_turn(Vector3(1.0, 0.0, 0.0), motion.relative.y * DRAG_TURN)
		var hovered: int = _row_at(motion.position)
		var hover_close: bool = _close_rect().has_point(motion.position)
		var hovered_tab: int = _tab_at(motion.position)
		var hover_help: bool = HelpPopup.button_rect(_close_rect()).has_point(motion.position)
		if (
			hovered != _hovered or hover_close != _hover_close or hovered_tab != _hovered_tab
			or hover_help != _hover_help
		):
			_hovered = hovered
			_hover_close = hover_close
			_hovered_tab = hovered_tab
			_hover_help = hover_help
			queue_redraw()

	elif event is InputEventMouseButton:
		var button := event as InputEventMouseButton
		if button.button_index == MOUSE_BUTTON_LEFT:
			if button.pressed:
				var close: Rect2 = _close_rect()
				if HelpPopup.button_rect(close).has_point(button.position):
					_help.toggle_at(Vector2(close.end.x, close.end.y + 10.0))
					queue_redraw()
					accept_event()
					return
				_help.close()
				queue_redraw()
				if _close_rect().has_point(button.position) or not _panel_rect().has_point(button.position):
					hide_panel()
				elif _tab_at(button.position) >= 0:
					_set_tab(_tab_at(button.position))
				elif _row_at(button.position) >= 0:
					_select(_row_at(button.position))
				elif view.has_point(button.position):
					_dragging = true
			else:
				_dragging = false
				_idle_time = 0.0
		elif button.pressed and view.has_point(button.position):
			var base: float = _resource_view if _tab == TAB_RESOURCES \
				else (VIEW_STAR if _bodies[_selected].get("is_star") else VIEW_DEFAULT)
			if button.button_index == MOUSE_BUTTON_WHEEL_UP:
				_view_size = maxf(_view_size * 0.88, VIEW_CLOSEST * (_resource_view if _tab == TAB_RESOURCES else 1.0))
			elif button.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				_view_size = minf(_view_size / 0.88, base * 1.6)
			_camera.size = _view_size

	accept_event()


# ---- numbers ----------------------------------------------------------------

func _lore(body: Node2D) -> Dictionary:
	if body.get("is_wormhole"):
		var lore: Dictionary = PlanetLore.WORMHOLE.duplicate()
		lore["class"] = "%s %s" % [body.get("wormhole_size"), lore["class"]]
		return lore
	if body.get("is_black_hole"):
		return PlanetLore.BLACK_HOLE
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
	var variant: String = PlanetLore.variant_label(body.get("terrain_kind"), params) if not params.is_empty() else ""
	if variant != "":
		rows.insert(0, ["Variant", variant])
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
	for i in range(TABS.size()):
		var tab: Rect2 = _tab_rect(i)
		if i == _tab:
			draw_rect(tab, HudPanelStyle.COLOR_CYAN_GLOW)
			draw_rect(Rect2(tab.position + Vector2(0.0, tab.size.y - 2.0), Vector2(tab.size.x, 2.0)), HudPanelStyle.COLOR_CYAN)
		elif i == _hovered_tab:
			draw_rect(tab, Color(1.0, 1.0, 1.0, 0.04))
		draw_string(
			font, tab.position + Vector2(0.0, 18.0), TABS[i], HORIZONTAL_ALIGNMENT_CENTER, tab.size.x, 12,
			HudPanelStyle.COLOR_TEXT_PRIMARY if i == _tab else HudPanelStyle.COLOR_TEXT_MUTED
		)
	draw_string(
		font, panel.position + Vector2(262.0 + TABS.size() * 116.0 + 12.0, 34.0), "VESPERIS SYSTEM",
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

	_draw_list(font)
	_draw_view_frame(font)
	_draw_text(font)


func _draw_list(font: Font) -> void:
	if _tab == TAB_RESOURCES:
		_draw_resource_list(font)
		return
	var list: Rect2 = _list_rect()
	for i in range(_bodies.size()):
		var body: Node2D = _bodies[i]
		var row := Rect2(list.position + Vector2(0.0, i * _row_height()), Vector2(list.size.x, _row_height() - 4.0))
		if i == _selected:
			draw_rect(row, HudPanelStyle.COLOR_CYAN_GLOW)
			draw_rect(Rect2(row.position, Vector2(3.0, row.size.y)), HudPanelStyle.COLOR_CYAN)
		elif i == _hovered:
			draw_rect(row, Color(1.0, 1.0, 1.0, 0.04))

		if not _known_body(body):
			draw_rect(row, Color(0.0, 0.0, 0.0, 0.35))
			draw_circle(row.position + Vector2(20.0, row.size.y * 0.5), 7.0, Color(0.1, 0.1, 0.12))
			_draw_redacted(row.position.x + 38.0, row.position.y + 19.0, String(body.get("body_name")).length() * 10.0, 14)
			draw_string(
				font, row.position + Vector2(38.0, row.size.y - 7.0), "Uncharted", HORIZONTAL_ALIGNMENT_LEFT,
				row.size.x - 42.0, 10, HudPanelStyle.COLOR_TEXT_FAINT
			)
			continue
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
			font, row.position + Vector2(38.0, row.size.y - 7.0), lore.get("class", ""), HORIZONTAL_ALIGNMENT_LEFT,
			row.size.x - 42.0, 10, HudPanelStyle.COLOR_TEXT_MUTED
		)


func _draw_view_frame(_font: Font) -> void:
	var view: Rect2 = _view_rect()
	draw_rect(view, Color(HudPanelStyle.COLOR_BORDER_DEFAULT, 0.4), false, 1.0)


func _draw_text(font: Font) -> void:
	if _tab == TAB_RESOURCES:
		_draw_resource_text(font)
		return
	var text: Rect2 = _text_rect()
	var body: Node2D = _bodies[_selected]
	if not _known_body(body):
		_draw_uncharted_text(font, body)
		return
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

	# What this world has, as far as the player has found it; the rest is
	# only a count of signals.
	var tally: Dictionary = {}
	var signals: int = 0
	for deposit: Dictionary in body.get("resource_deposits"):
		if _system.call("is_resource_found_on", body, deposit["type"]):
			tally[deposit["type"]] = tally.get(deposit["type"], 0) + 1
		else:
			signals += 1
	if not tally.is_empty() or signals > 0:
		y += 14.0
		draw_string(font, Vector2(x, y), "RESOURCES", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, HudPanelStyle.COLOR_AMBER)
		y += 18.0
		for type_name: StringName in tally:
			var type: Dictionary = ResourceDeposits.TYPES[type_name]
			var scenery: bool = not type.get("collectible", true)
			draw_circle(Vector2(x + 4.0, y - 4.0), 3.5, type["color"])
			draw_string(
				font, Vector2(x + 14.0, y), "%s  ×%d%s" % [type["name"], tally[type_name], "  (scenery)" if scenery else ""],
				HORIZONTAL_ALIGNMENT_LEFT, text.size.x - 14.0, 11,
				HudPanelStyle.COLOR_TEXT_MUTED if scenery else HudPanelStyle.COLOR_TEXT_SECONDARY
			)
			y += 17.0
		if signals > 0:
			draw_circle(Vector2(x + 4.0, y - 4.0), 3.5, Color(0.1, 0.1, 0.12))
			draw_string(
				font, Vector2(x + 14.0, y), "Unidentified signals  ×%d" % signals,
				HORIZONTAL_ALIGNMENT_LEFT, text.size.x - 14.0, 11, HudPanelStyle.COLOR_TEXT_MUTED
			)
			y += 17.0

	var facts: Array = lore.get("facts", [])
	if not facts.is_empty():
		y += 14.0
		draw_string(font, Vector2(x, y), "DID YOU KNOW", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, HudPanelStyle.COLOR_EMERALD)
		y += 18.0
		for fact: String in facts:
			draw_string(font, Vector2(x, y), "›", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, HudPanelStyle.COLOR_EMERALD)
			y = _draw_paragraph(font, fact, x + 14.0, y, text.size.x - 14.0, 11, HudPanelStyle.COLOR_TEXT_SECONDARY)
			y += 6.0


func _draw_resource_list(font: Font) -> void:
	var list: Rect2 = _list_rect()
	for i in range(_resources.size()):
		var type: Dictionary = ResourceDeposits.TYPES[_resources[i]]
		var row := Rect2(list.position + Vector2(0.0, i * _row_height()), Vector2(list.size.x, _row_height() - 4.0))
		if i == _selected:
			draw_rect(row, HudPanelStyle.COLOR_CYAN_GLOW)
			draw_rect(Rect2(row.position, Vector2(3.0, row.size.y)), HudPanelStyle.COLOR_CYAN)
		elif i == _hovered:
			draw_rect(row, Color(1.0, 1.0, 1.0, 0.04))
		if not _known_resource(_resources[i]):
			if i != _selected:
				draw_rect(row, Color(0.0, 0.0, 0.0, 0.35))
			draw_circle(row.position + Vector2(20.0, row.size.y * 0.5), 7.0, Color(0.1, 0.1, 0.12))
			_draw_redacted(row.position.x + 38.0, row.position.y + 19.0, String(type["name"]).length() * 10.0, 14)
			draw_string(
				font, row.position + Vector2(38.0, row.size.y - 7.0), "Not yet found", HORIZONTAL_ALIGNMENT_LEFT,
				row.size.x - 42.0, 10, HudPanelStyle.COLOR_TEXT_FAINT
			)
			continue
		draw_circle(row.position + Vector2(20.0, row.size.y * 0.5), 7.0, type["color"])
		draw_string(
			font, row.position + Vector2(38.0, 19.0), String(type["name"]).to_upper(), HORIZONTAL_ALIGNMENT_LEFT,
			row.size.x - 42.0, 14,
			HudPanelStyle.COLOR_TEXT_PRIMARY if i == _selected else HudPanelStyle.COLOR_TEXT_SECONDARY
		)
		draw_string(
			font, row.position + Vector2(38.0, row.size.y - 7.0), "Collectible" if type.get("collectible", true) else "Scenery",
			HORIZONTAL_ALIGNMENT_LEFT, row.size.x - 42.0, 10, HudPanelStyle.COLOR_TEXT_MUTED
		)


## A resource: what it is, and the planets the player has found it on - how
## many each has now, and where on that kind of planet it turns up, on which
## variants and how many.
func _draw_resource_text(font: Font) -> void:
	var text: Rect2 = _text_rect()
	var type_name: StringName = _resources[_selected]
	var type: Dictionary = ResourceDeposits.TYPES[type_name]
	var x: float = text.position.x
	var y: float = text.position.y + 18.0
	if _known_resource(type_name):
		draw_string(font, Vector2(x, y), String(type["name"]).to_upper(), HORIZONTAL_ALIGNMENT_LEFT, text.size.x, 22, HudPanelStyle.COLOR_CYAN)
		y += 22.0
		var kind_line: String = "Resource - can be collected" if type.get("collectible", true) else "Scenery - cannot be collected"
		draw_string(font, Vector2(x, y), kind_line, HORIZONTAL_ALIGNMENT_LEFT, text.size.x, 12, HudPanelStyle.COLOR_AMBER)
	else:
		_draw_redacted(x, y, String(type["name"]).length() * 15.0, 22)
		y += 22.0
		draw_string(
			font, Vector2(x, y), "Not yet found - gather one to learn about it",
			HORIZONTAL_ALIGNMENT_LEFT, text.size.x, 12, HudPanelStyle.COLOR_TEXT_MUTED
		)
	y += 22.0

	# Every planet in the system that holds some right now: in full where the
	# player has found it, redacted everywhere else - so the log says how many
	# places it is on, but not which, until each is found.
	var found: Array = _system.call("bodies_where_found", type_name)
	var holders: Array[Node2D] = []
	for body: Node2D in _bodies:
		if _deposit_count(body, type_name) > 0 and not found.has(body):
			holders.append(body)
	draw_string(
		font, Vector2(x, y), "OCCURS ON  %d %s" % [found.size() + holders.size(), "planet" if found.size() + holders.size() == 1 else "planets"],
		HORIZONTAL_ALIGNMENT_LEFT, -1, 11, HudPanelStyle.COLOR_EMERALD
	)
	y += 18.0
	for body: Node2D in found:
		var kind: int = body.get("terrain_kind")
		var heading: String = "%s  -  %s  ×%d" % [
			body.get("body_name"), PlanetLore.KINDS.get(kind, {}).get("class", "Unknown world"), _deposit_count(body, type_name),
		]
		draw_string(font, Vector2(x, y), heading, HORIZONTAL_ALIGNMENT_LEFT, text.size.x, 12, HudPanelStyle.COLOR_TEXT_PRIMARY)
		y += 16.0
		for spawn: Array in ResourceDeposits.spawns_of(type_name):
			if spawn[0] != kind:
				continue
			var notes: Dictionary = ResourceDeposits.spawn_notes(kind, spawn[1])
			y = _draw_paragraph(
				font, "%s. %s. %s." % [notes["where"], notes["variants"], notes["count"]], x + 10.0, y,
				text.size.x - 10.0, 11, HudPanelStyle.COLOR_TEXT_SECONDARY
			)
		y += 8.0
	for body: Node2D in holders:
		# Not found there yet: a planet, a count and a note, all blacked out.
		_draw_redacted(x, y, text.size.x * (0.45 + 0.25 * fposmod(String(body.get("body_name")).hash() * 0.618, 1.0)), 12)
		y += 16.0
		_draw_redacted(x + 10.0, y, (text.size.x - 10.0) * 0.85, 11)
		y += 22.0


func _deposit_count(body: Node2D, type_name: StringName) -> int:
	var count: int = 0
	for deposit: Dictionary in body.get("resource_deposits"):
		if deposit["type"] == type_name:
			count += 1
	return count


## A planet the ship has not charted: the headings are there, the data is not.
func _draw_uncharted_text(font: Font, body: Node2D) -> void:
	var text: Rect2 = _text_rect()
	var x: float = text.position.x
	var y: float = text.position.y + 18.0
	draw_string(font, Vector2(x, y), "UNCHARTED BODY", HORIZONTAL_ALIGNMENT_LEFT, text.size.x, 22, HudPanelStyle.COLOR_TEXT_MUTED)
	y += 22.0
	draw_string(
		font, Vector2(x, y), "No survey data - fly close to chart it", HORIZONTAL_ALIGNMENT_LEFT,
		text.size.x, 12, HudPanelStyle.COLOR_AMBER
	)
	y += 22.0
	for row: Array in _stats(body):
		draw_string(font, Vector2(x, y), row[0], HORIZONTAL_ALIGNMENT_LEFT, text.size.x * 0.45, 11, HudPanelStyle.COLOR_TEXT_FAINT)
		_draw_redacted(x + text.size.x * 0.45, y, text.size.x * (0.2 + 0.25 * fposmod(String(row[0]).hash() * 0.618, 1.0)), 11)
		y += 18.0
	y += 14.0
	_draw_redacted_block(x, y, text.size.x, 5)


## A black redaction bar over where a line of text would sit (baseline `y`).
func _draw_redacted(x: float, y: float, width: float, font_size: int) -> void:
	var bar := Rect2(x, y - font_size * 0.85, width, font_size * 1.05)
	draw_rect(bar, Color(0.0, 0.0, 0.0, 0.92))
	draw_rect(bar, Color(HudPanelStyle.COLOR_TEXT_FAINT, 0.35), false, 1.0)


## `lines` redaction bars in a ragged paragraph.
func _draw_redacted_block(x: float, y: float, width: float, lines: int) -> void:
	for i in range(lines):
		var share: float = 0.6 if i == lines - 1 else 0.88 + 0.12 * fposmod(float(i) * 0.618, 1.0)
		_draw_redacted(x, y, width * share, 12)
		y += 18.0


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

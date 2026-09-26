extends Control
## Bottom-right: a live close-up of the ship - a real second camera on the
## game world, not a redrawing. A SubViewport shares the main view's 2D and
## 3D worlds, so it shows exactly what is there: the starfield background,
## the planets, the ship as built, enemies, shots and beams. Its zoom is its
## own (mouse wheel over the panel), whatever the main view does. The ship is
## always shown for real: zoomed out, the main view draws it as a marker on
## MARKER_VISIBILITY_LAYER, which this view culls, and _ship_layer draws the
## built ship over the middle instead. Clicking it points the main camera
## back at the ship.
## solar_system.gd calls setup() once and set_state() every frame.

signal clicked

## Screen pixels per world unit: the zoom range and where it starts.
const ZOOM_MIN := 0.05
const ZOOM_MAX := 20.0
const ZOOM_START := 3.0
const ZOOM_STEP := 1.2
const SHIP_TEXTURE := preload("res://textures/ship_blueprint.png")
const MAIN_OUTER_COLOR := Color(1.0, 0.45, 0.1)
const MAIN_CORE_COLOR := Color(1.0, 0.85, 0.5)
const PAD := 8.0
const LABEL_HEIGHT := 18.0

var throttle := 0.0
var _game: Node = null
var _zoom: float = ZOOM_START
var _container: SubViewportContainer
var _viewport: SubViewport
var _camera: Camera2D
var _camera_3d: Camera3D
## Draws the real ship over the view's middle while the world has it as a
## marker (its own canvas layer, so the main view never sees it).
var _ship_layer: CanvasLayer
var _ship_overlay: Control


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	_container = SubViewportContainer.new()
	_container.stretch = true
	_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_container)
	_viewport = SubViewport.new()
	_viewport.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE
	_viewport.handle_input_locally = false
	_viewport.gui_disable_input = true
	_container.add_child(_viewport)
	_camera = Camera2D.new()
	_camera.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_viewport.add_child(_camera)
	_camera_3d = Camera3D.new()
	_camera_3d.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_viewport.add_child(_camera_3d)
	_ship_layer = CanvasLayer.new()
	_viewport.add_child(_ship_layer)
	_ship_overlay = Control.new()
	_ship_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_ship_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ship_overlay.draw.connect(_draw_ship_overlay)
	_ship_layer.add_child(_ship_overlay)
	resized.connect(_layout)
	_layout()


## `game` is solar_system.gd: its viewport's worlds are shared, and its
## background is copied in so the view shows the same sky.
func setup(game: Node) -> void:
	_game = game
	var main_viewport: Viewport = game.get_viewport()
	_viewport.world_2d = main_viewport.world_2d
	_viewport.world_3d = main_viewport.world_3d
	var main_camera_3d: Camera3D = game.get("camera_3d")
	_camera_3d.projection = main_camera_3d.projection
	_camera_3d.near = main_camera_3d.near
	_camera_3d.far = main_camera_3d.far
	_camera_3d.environment = main_camera_3d.environment
	_camera_3d.current = true
	_camera.make_current()
	_viewport.canvas_cull_mask = 0xFFFFFFFF & ~int(game.get("MARKER_VISIBILITY_LAYER"))
	var background: Node = game.get_node_or_null("Background")
	if background != null:
		_viewport.add_child(background.duplicate())


func set_state(p_throttle: float) -> void:
	throttle = p_throttle


## Kept for solar_system.gd: the live view shows the ship itself.
func set_built_texture(_texture: Texture2D) -> void:
	pass


func _layout() -> void:
	if _container == null:
		return
	_container.position = Vector2(PAD, PAD)
	_container.size = size - Vector2(PAD * 2.0, PAD * 2.0 + LABEL_HEIGHT)


func _process(_delta: float) -> void:
	if _game == null or not is_visible_in_tree():
		return
	var ship: Node2D = _game.get("ship")
	var main_camera: Camera2D = _game.get("camera")
	if ship == null or main_camera == null:
		return
	# On the ship as it is drawn this frame (interpolated), like the main camera.
	var centre: Vector2 = _game.call("_drawn_position", ship)
	var zoom: float = _zoom
	_camera.position = centre
	_camera.zoom = Vector2(zoom, zoom)
	# The 3D planets: the main 3D camera's pose, over this view's centre.
	var main_camera_3d: Camera3D = _game.get("camera_3d")
	var transform_3d: Transform3D = main_camera_3d.global_transform
	transform_3d.origin = Vector3(centre.x, transform_3d.origin.y, centre.y)
	_camera_3d.global_transform = transform_3d
	_camera_3d.size = float(_viewport.size.y) / zoom
	_ship_overlay.visible = not bool(ship.get("true_scale"))
	_ship_overlay.queue_redraw()
	queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		match event.button_index:
			MOUSE_BUTTON_WHEEL_UP:
				_zoom = minf(_zoom * ZOOM_STEP, ZOOM_MAX)
			MOUSE_BUTTON_WHEEL_DOWN:
				_zoom = maxf(_zoom / ZOOM_STEP, ZOOM_MIN)
			MOUSE_BUTTON_LEFT:
				clicked.emit()
		accept_event()


func _draw() -> void:
	HudPanelStyle.draw_chamfered(self, size, HudPanelStyle.COLOR_BORDER_DEFAULT, 16.0, 0.85, 0.55)
	var font: Font = HudPanelStyle.get_font()
	var y: float = size.y - PAD - 4.0
	draw_string(font, Vector2(PAD + 2.0, y), "LOCAL VIEW", HORIZONTAL_ALIGNMENT_LEFT, -1, 9, HudPanelStyle.COLOR_TEXT_MUTED)
	if _camera != null and _camera.zoom.x > 0.0:
		draw_string(
			font, Vector2(PAD, y), "%d SU" % roundi(_container.size.x / _camera.zoom.x), HORIZONTAL_ALIGNMENT_RIGHT,
			size.x - PAD * 2.0 - 2.0, 9, HudPanelStyle.COLOR_TEXT_MUTED
		)


## The ship at true scale in the middle of the view: the built picture with
## its turrets and flames, or the stock blueprint.
func _draw_ship_overlay() -> void:
	var ship: Node2D = _game.get("ship") if _game != null else null
	if ship == null:
		return
	var o: Control = _ship_overlay
	var centre: Vector2 = o.size * 0.5
	var k: float = _zoom
	var turn: float = ship.rotation
	var visual: Dictionary = ship.get("built_visual")
	if visual.is_empty():
		var tex_size: Vector2 = SHIP_TEXTURE.get_size()
		var length: float = 22.0 * k
		var drawn := Vector2(length * tex_size.x / tex_size.y, length)
		o.draw_set_transform(centre, turn + PI * 0.5, Vector2.ONE)
		o.draw_texture_rect(SHIP_TEXTURE, Rect2(-drawn * 0.5, drawn), false)
		o.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		return
	o.draw_set_transform(centre, turn, Vector2(k, k))
	o.draw_texture_rect(visual["texture"], visual["rect"], false)
	var aim: Dictionary = ship.get("turret_aim")
	for turret: Dictionary in visual.get("turrets", []):
		var size_local: Vector2 = turret["size"]
		var offset: float = float(aim.get(int(turret["id"]), 0.0))
		o.draw_set_transform(centre + (turret["center"] as Vector2).rotated(turn) * k, turn + offset, Vector2(k, k))
		o.draw_texture_rect(turret["texture"], Rect2(-size_local * 0.5, size_local), false)
	o.draw_set_transform(centre, turn, Vector2(k, k))
	if throttle > 0.02:
		var flicker: float = 0.85 + 0.15 * sin(Time.get_ticks_msec() / 1000.0 * 24.0)
		for point: Vector2 in visual.get("engines", []):
			var length: float = 7.0 * throttle * flicker
			o.draw_colored_polygon(
				PackedVector2Array([point + Vector2(0.0, -1.1), point + Vector2(0.0, 1.1), point + Vector2(-length, 0.0)]),
				Color(MAIN_OUTER_COLOR, 0.75)
			)
			o.draw_colored_polygon(
				PackedVector2Array([point + Vector2(0.0, -0.5), point + Vector2(0.0, 0.5), point + Vector2(-length * 0.55, 0.0)]),
				MAIN_CORE_COLOR
			)
	o.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

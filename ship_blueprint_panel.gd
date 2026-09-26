extends Control
## Bottom-right: a live close-up of the ship - a real second camera on the
## game world, not a redrawing. A SubViewport shares the main view's 2D and
## 3D worlds, so it shows exactly what is there: the starfield background,
## the planets, the ship as built, enemies, shots and beams. Its zoom is the
## main camera's times `_magnify` (mouse wheel over the panel), so anything
## sized for the screen (the far-zoom ship and enemy markers) keeps its look,
## only bigger. Clicking it points the main camera back at the ship.
## solar_system.gd calls setup() once and set_state() every frame.

signal clicked

## How much closer than the main view the panel looks, and its limits.
const MAGNIFY_MIN := 1.0
const MAGNIFY_MAX := 12.0
const MAGNIFY_START := 2.0
const MAGNIFY_STEP := 1.25
const PAD := 8.0
const LABEL_HEIGHT := 18.0

var throttle := 0.0
var _game: Node = null
var _magnify: float = MAGNIFY_START
var _container: SubViewportContainer
var _viewport: SubViewport
var _camera: Camera2D
var _camera_3d: Camera3D


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
	var zoom: float = main_camera.zoom.x * _magnify
	_camera.position = centre
	_camera.zoom = Vector2(zoom, zoom)
	# The 3D planets: the main 3D camera's pose, over this view's centre.
	var main_camera_3d: Camera3D = _game.get("camera_3d")
	var transform_3d: Transform3D = main_camera_3d.global_transform
	transform_3d.origin = Vector3(centre.x, transform_3d.origin.y, centre.y)
	_camera_3d.global_transform = transform_3d
	_camera_3d.size = float(_viewport.size.y) / zoom
	queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		match event.button_index:
			MOUSE_BUTTON_WHEEL_UP:
				_magnify = minf(_magnify * MAGNIFY_STEP, MAGNIFY_MAX)
			MOUSE_BUTTON_WHEEL_DOWN:
				_magnify = maxf(_magnify / MAGNIFY_STEP, MAGNIFY_MIN)
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

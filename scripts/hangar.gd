extends Node2D

const CELL := 1.0
const ZOOM := 36.0

var graph := ModuleGraph.new()
var selected_id: String = "frame"
var rotation_steps: int = 0
var status_text: String = ""
var _cam: Camera2D
var _hud: Control
var _font: Font
var _palette_rects: Array[Dictionary] = []
var _button_rects: Array[Dictionary] = []


func _ready() -> void:
	RenderingServer.set_default_clear_color(Color("#0b1018"))
	_font = ThemeDB.fallback_font
	_cam = Camera2D.new()
	_cam.enabled = true
	_cam.zoom = Vector2(ZOOM, ZOOM)
	_cam.ignore_rotation = true
	_cam.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_cam.process_callback = Camera2D.CAMERA2D_PROCESS_IDLE
	add_child(_cam)
	_cam.make_current()
	var data := ShipBlueprint.load_current()
	if data.is_empty() or not graph.load_blueprint(data):
		graph = ShipBlueprint.starter_graph()
	_hud = Control.new()
	_hud.set_anchors_preset(Control.PRESET_FULL_RECT)
	_hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud.draw.connect(_draw_hud)
	var layer := CanvasLayer.new()
	layer.layer = 20
	add_child(layer)
	layer.add_child(_hud)
	queue_redraw()


func _process(_delta: float) -> void:
	if _hud:
		_hud.queue_redraw()
	queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		if _handle_hud_click(_hud.get_local_mouse_position() if _hud else event.position):
			get_viewport().set_input_as_handled()
			return
		var screen := get_viewport().get_mouse_position()
		var view := get_viewport().get_visible_rect().size
		if screen.x < 230.0 or (screen.x > view.x - 230.0 and screen.y > view.y - 170.0):
			get_viewport().set_input_as_handled()
			return
		var cell := _mouse_cell()
		if event.button_index == MOUSE_BUTTON_LEFT:
			_try_place(cell)
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			graph.remove_at(cell)
			status_text = ""
		get_viewport().set_input_as_handled()
	if event is InputEventKey and event.pressed and not event.echo:
		match event.physical_keycode:
			KEY_R:
				rotation_steps = posmod(rotation_steps + 1, 4)
			KEY_ESCAPE:
				_launch()
			KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6, KEY_7:
				var ids := ModuleCatalog.palette_ids()
				var index: int = int(event.physical_keycode) - int(KEY_1)
				if index >= 0 and index < ids.size():
					selected_id = ids[index]


func _try_place(cell: Vector2i) -> void:
	var def := ModuleCatalog.get_def(selected_id)
	if def == null:
		return
	var module := ShipModule.new(def, cell, rotation_steps)
	if graph.add_module(module):
		status_text = ""
		return
	status_text = "Nie można tu postawić — kolizja albo brak styku."


func _launch() -> void:
	var stats := graph.stats()
	if not graph.is_structure_connected():
		status_text = "Konstrukcja musi być spójna."
		return
	if stats.cockpit_count != 1:
		status_text = "Potrzeba dokładnie jednego kokpitu."
		return
	if stats.engine_count < 1:
		status_text = "Potrzeba przynajmniej jednego silnika."
		return
	_save_blueprint()
	get_tree().change_scene_to_file("res://scenes/main.tscn")


func _save_blueprint() -> void:
	ShipBlueprint.save_current(graph.to_blueprint())
	status_text = "Zapisano blueprint."


func _mouse_cell() -> Vector2i:
	var world := get_global_mouse_position()
	return Vector2i(floori(world.x), floori(world.y))


func _draw() -> void:
	for x in range(-18, 19):
		draw_line(Vector2(x, -12), Vector2(x, 12), Color(0.18, 0.24, 0.3, 0.45), 0.03)
	for y in range(-12, 13):
		draw_line(Vector2(-18, y), Vector2(18, y), Color(0.18, 0.24, 0.3, 0.45), 0.03)
	var stats := graph.stats()
	graph.draw_on(self, stats.com, 0.0, 1.0, 0.0, true)
	var com := stats.com
	draw_line(com + Vector2(-0.45, 0), com + Vector2(0.45, 0), Color(0.95, 0.85, 0.2), 0.08)
	draw_line(com + Vector2(0, -0.45), com + Vector2(0, 0.45), Color(0.95, 0.85, 0.2), 0.08)
	var def := ModuleCatalog.get_def(selected_id)
	if def:
		var ghost := ShipModule.new(def, _mouse_cell(), rotation_steps)
		var ok := graph.can_place(def, ghost.grid_pos, ghost.rotation_steps)
		var color := def.fill
		color.a = 0.35 if ok else 0.2
		var poly := ghost.world_polygon(stats.com)
		if poly.size() >= 3:
			draw_set_transform(stats.com, 0.0, Vector2.ONE)
			draw_colored_polygon(poly, color)
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _handle_hud_click(pos: Vector2) -> bool:
	for item in _palette_rects:
		var rect: Rect2 = item["rect"]
		if rect.has_point(pos):
			selected_id = String(item["id"])
			return true
	for item in _button_rects:
		var rect: Rect2 = item["rect"]
		if rect.has_point(pos):
			match String(item["id"]):
				"rotate":
					rotation_steps = posmod(rotation_steps + 1, 4)
				"save":
					_save_blueprint()
				"launch":
					_launch()
			return true
	return false


func _draw_hud() -> void:
	var vp := _hud.get_viewport_rect().size
	_palette_rects.clear()
	_button_rects.clear()
	_hud.draw_rect(Rect2(0, 0, 220, vp.y), Color(0.04, 0.07, 0.12, 0.92), true)
	_hud.draw_string(_font, Vector2(18, 36), "HANGAR", HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color(0.9, 0.96, 1.0))
	var ids := ModuleCatalog.palette_ids()
	for i in ids.size():
		var def := ModuleCatalog.get_def(ids[i])
		var rect := Rect2(16, 56 + i * 48, 188, 40)
		_palette_rects.append({"id": ids[i], "rect": rect})
		var bg := Color(0.12, 0.22, 0.3, 0.95) if ids[i] == selected_id else Color(0.08, 0.12, 0.18, 0.95)
		_hud.draw_rect(rect, bg, true)
		if def:
			_hud.draw_rect(Rect2(rect.position.x + 8, rect.position.y + 10, 18, 18), def.fill, true)
			_hud.draw_string(_font, rect.position + Vector2(34, 26), def.display_name, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.9, 0.95, 1.0))
	var stats := graph.stats()
	var info := "paliwo %.0f   HP %.0f   silniki %d" % [stats.fuel, stats.hull, stats.engine_count]
	_hud.draw_string(_font, Vector2(240, 32), info, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.75, 0.88, 1.0, 0.85))
	_hud.draw_string(_font, Vector2(240, vp.y - 28), "LPM stawianie   PPM usuwanie   R obrót   1-7 paleta", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.55, 0.7, 0.82, 0.75))
	if status_text != "":
		var status_color := Color(0.55, 0.92, 0.7) if status_text.begins_with("Zapisano") else Color(1.0, 0.55, 0.4)
		_hud.draw_string(_font, Vector2(240, 56), status_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, status_color)
	var rotate_rect := Rect2(vp.x - 220, vp.y - 158, 196, 40)
	var save_rect := Rect2(vp.x - 220, vp.y - 108, 196, 40)
	var launch_rect := Rect2(vp.x - 220, vp.y - 58, 196, 40)
	_button_rects.append({"id": "rotate", "rect": rotate_rect})
	_button_rects.append({"id": "save", "rect": save_rect})
	_button_rects.append({"id": "launch", "rect": launch_rect})
	_hud.draw_rect(rotate_rect, Color(0.08, 0.16, 0.24, 0.95), true)
	_hud.draw_string(_font, rotate_rect.position + Vector2(16, 26), "Obróć  (R)", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(0.9, 0.96, 1.0))
	_hud.draw_rect(save_rect, Color(0.08, 0.18, 0.28, 0.95), true)
	_hud.draw_string(_font, save_rect.position + Vector2(16, 26), "Zapisz blueprint", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(0.9, 0.96, 1.0))
	_hud.draw_rect(launch_rect, Color(0.12, 0.32, 0.28, 0.95), true)
	_hud.draw_string(_font, launch_rect.position + Vector2(16, 26), "Wyleć", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(0.9, 0.96, 1.0))

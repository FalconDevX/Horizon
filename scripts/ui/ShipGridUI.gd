class_name ShipGridUI
extends Control
## Drop target for inventory modules. Highlights valid cells green / invalid red
## while dragging / holding (drawn above module sprites).

signal placement_succeeded(module: PlacedModule)
signal placement_failed(module_data: ModuleData, origin: Vector2i)
signal module_removed(module: PlacedModule)
signal hold_changed(module: ModuleData, rotation: int)

@export var ship_hull: ShipHull
@export var cell_size: Vector2 = Vector2(48, 48)
@export var base_cell_size: float = 32.0
@export var zoom_min: float = 0.4
@export var zoom_max: float = 3.0
@export var zoom_step: float = 1.12
@export var valid_tint := Color(0.2, 0.9, 0.35, 0.55)
@export var invalid_tint := Color(0.95, 0.2, 0.2, 0.55)
@export var empty_tint := Color(0.1, 0.12, 0.16, 0.85)
@export var deck_tint := Color(0.22, 0.3, 0.4, 0.85)
@export var connector_tint := Color(0.85, 0.7, 0.15, 0.8)
@export var occupied_tint := Color(0.35, 0.55, 0.85, 0.45)
@export var grid_line := Color(0.45, 0.55, 0.7, 0.35)
@export var mount_tint := Color(0.35, 0.28, 0.22, 0.35) ## subtle hint for weapon-adjacent cells

var _hover_origin: Vector2i = Vector2i(-999, -999)
var _hover_module: ModuleData = null
var _hover_rotation: int = 0
var _hover_valid: bool = false

var _held_module: ModuleData = null
var _held_rotation: int = 0
## Cargo moving with a picked-up hull: Array of {data, rotation, local_origin}
var _held_cargo: Array = []
var _held_pick_rotation: int = 0

var _module_sprites: Dictionary = {}
var _texture_cache: Dictionary = {}
var _preview: Control ## draws green/red above sprites
var _scroll_parent: PannableScrollContainer
var _zoom: float = 1.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_process_unhandled_input(true)
	_ensure_preview()
	_scroll_parent = _find_scroll_parent()
	if base_cell_size <= 0.0:
		base_cell_size = cell_size.x
	_zoom = cell_size.x / base_cell_size
	if ship_hull == null:
		push_warning("ShipGridUI: assign a ShipHull reference.")
		return

	ship_hull.cell_size = cell_size
	ship_hull.module_attached.connect(_on_module_attached)
	ship_hull.module_detached.connect(_on_module_detached)
	ship_hull.stats_changed.connect(_on_stats_changed)

	_sync_control_size()
	queue_redraw()
	_preview.queue_redraw()


func _find_scroll_parent() -> PannableScrollContainer:
	var n: Node = get_parent()
	while n != null:
		if n is PannableScrollContainer:
			return n as PannableScrollContainer
		n = n.get_parent()
	return null


func _ensure_preview() -> void:
	if _preview != null and is_instance_valid(_preview):
		return
	_preview = Control.new()
	_preview.name = "PlacementPreview"
	_preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_preview.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_preview.draw.connect(_draw_preview)
	add_child(_preview)


func _sync_control_size() -> void:
	if ship_hull == null:
		return
	var g := ship_hull.get_grid_size()
	custom_minimum_size = Vector2(g) * cell_size
	size = custom_minimum_size
	if _preview != null:
		_preview.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		_preview.size = size
	var host := get_parent() as BuildAreaHost
	if host != null:
		host.refresh()


func bind_hull(hull: ShipHull) -> void:
	if ship_hull != null:
		if ship_hull.module_attached.is_connected(_on_module_attached):
			ship_hull.module_attached.disconnect(_on_module_attached)
		if ship_hull.module_detached.is_connected(_on_module_detached):
			ship_hull.module_detached.disconnect(_on_module_detached)
		if ship_hull.stats_changed.is_connected(_on_stats_changed):
			ship_hull.stats_changed.disconnect(_on_stats_changed)

	ship_hull = hull
	clear_hold()
	if ship_hull == null:
		return

	ship_hull.cell_size = cell_size
	ship_hull.module_attached.connect(_on_module_attached)
	ship_hull.module_detached.connect(_on_module_detached)
	ship_hull.stats_changed.connect(_on_stats_changed)
	_rebuild_all_sprites()
	_sync_control_size()
	queue_redraw()


## steps > 0 zooms in, < 0 zooms out. Keeps the point under the cursor stable.
func adjust_zoom(steps: int) -> void:
	if steps == 0:
		return
	var old_cell := cell_size.x
	var factor := zoom_step if steps > 0 else (1.0 / zoom_step)
	for _i in absi(steps):
		_zoom *= factor
	_zoom = clampf(_zoom, zoom_min, zoom_max)

	var mouse_in_scroll := Vector2.ZERO
	var content_under := Vector2.ZERO
	if _scroll_parent != null:
		mouse_in_scroll = _scroll_parent.get_local_mouse_position()
		content_under = Vector2(_scroll_parent.scroll_horizontal, _scroll_parent.scroll_vertical) + mouse_in_scroll

	var new_cell := base_cell_size * _zoom
	cell_size = Vector2(new_cell, new_cell)
	if ship_hull != null:
		ship_hull.cell_size = cell_size

	_texture_cache.clear()
	_sync_control_size()
	_rebuild_all_sprites()
	queue_redraw()
	if _preview != null:
		_preview.queue_redraw()

	if _scroll_parent != null and old_cell > 0.0:
		var ratio := new_cell / old_cell
		var new_under := content_under * ratio
		_scroll_parent.scroll_horizontal = int(new_under.x - mouse_in_scroll.x)
		_scroll_parent.scroll_vertical = int(new_under.y - mouse_in_scroll.y)


func get_zoom() -> float:
	return _zoom
	_preview.queue_redraw()


func hold_module(module: ModuleData, rotation: int = 0, cargo: Array = [], pick_rotation: int = -1) -> void:
	_held_module = module
	_held_rotation = posmod(rotation, 4)
	_held_cargo = cargo.duplicate(true)
	_held_pick_rotation = _held_rotation if pick_rotation < 0 else posmod(pick_rotation, 4)
	_hover_module = module
	_hover_rotation = _held_rotation
	hold_changed.emit(_held_module, _held_rotation)
	_preview.queue_redraw()


func clear_hold() -> void:
	_held_module = null
	_held_rotation = 0
	_held_cargo.clear()
	_held_pick_rotation = 0
	_clear_hover()
	hold_changed.emit(null, 0)


func has_held_module() -> bool:
	return _held_module != null


func rotate_held(steps: int = 1) -> void:
	if _held_module != null:
		_held_rotation = posmod(_held_rotation + steps, 4)
		_hover_rotation = _held_rotation
		hold_changed.emit(_held_module, _held_rotation)
		_refresh_hover_validity()
		_preview.queue_redraw()
	elif _hover_module != null:
		_hover_rotation = posmod(_hover_rotation + steps, 4)
		_refresh_hover_validity()
		_preview.queue_redraw()


func _can_drop_data(at_position: Vector2, data: Variant) -> bool:
	if typeof(data) != TYPE_DICTIONARY:
		return false
	if data.get("type", "") != "ship_module":
		return false
	var module: ModuleData = data.get("module") as ModuleData
	if module == null or ship_hull == null:
		return false

	_hover_module = module
	if _held_module == module:
		_hover_rotation = _held_rotation
	else:
		_hover_rotation = int(data.get("rotation", 0))
	_hover_origin = _centered_origin(at_position, module, _hover_rotation)
	_hover_valid = ship_hull.can_place(module, _hover_origin, _hover_rotation)
	_preview.queue_redraw()
	return _hover_valid


func _drop_data(at_position: Vector2, data: Variant) -> void:
	var module: ModuleData = data.get("module") as ModuleData
	if module == null or ship_hull == null:
		_clear_hover()
		return

	var rotation := _held_rotation if _held_module == module else int(data.get("rotation", 0))
	var origin := _centered_origin(at_position, module, rotation)
	var placed := ship_hull.attach_module(module, origin, rotation)
	if placed != null:
		placement_succeeded.emit(placed)
		clear_hold()
	else:
		placement_failed.emit(module, origin)
		_clear_hover()


func _notification(what: int) -> void:
	if what == NOTIFICATION_DRAG_END:
		_clear_hover()
		_preview.queue_redraw()


func _gui_input(event: InputEvent) -> void:
	# Middle-mouse pan (works even when cursor is over the grid).
	if event is InputEventMouseButton:
		var mb0 := event as InputEventMouseButton
		if mb0.button_index == MOUSE_BUTTON_MIDDLE and _scroll_parent != null:
			if mb0.pressed:
				_scroll_parent.begin_pan(mb0.global_position)
			else:
				_scroll_parent.end_pan()
			accept_event()
			return
	if event is InputEventMouseMotion and _scroll_parent != null and _scroll_parent.is_panning():
		_scroll_parent.pan_to((event as InputEventMouseMotion).global_position)
		accept_event()
		return

	if ship_hull == null:
		return

	if event is InputEventMouseMotion:
		var motion := event as InputEventMouseMotion
		if _held_module != null:
			_hover_module = _held_module
			_hover_rotation = _held_rotation
			_hover_origin = _centered_origin(motion.position, _held_module, _held_rotation)
			_refresh_hover_validity()
			_preview.queue_redraw()
		return

	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if not mb.pressed:
			return

		if mb.button_index == MOUSE_BUTTON_WHEEL_UP or mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			var dir := -1 if mb.button_index == MOUSE_BUTTON_WHEEL_UP else 1
			# Ctrl always zooms. Otherwise: holding a module rotates it, empty hand zooms.
			# Panning is middle-mouse-drag only - the wheel never scrolls the view.
			if mb.ctrl_pressed or _held_module == null:
				adjust_zoom(-dir) # wheel up → zoom in
			else:
				rotate_held(dir)
			accept_event()
			return

		var cell := ship_hull.world_to_cell(mb.position)

		if mb.button_index == MOUSE_BUTTON_RIGHT:
			if _held_module != null:
				clear_hold()
				accept_event()
				return
			var existing := ship_hull.get_module_at(cell)
			if existing != null:
				var removed := ship_hull.detach_module(existing.instance_id)
				if removed != null:
					module_removed.emit(removed)
			accept_event()
			return

		if mb.button_index == MOUSE_BUTTON_LEFT:
			_handle_left_click(cell)
			accept_event()


func _unhandled_input(event: InputEvent) -> void:
	if not is_visible_in_tree():
		return
	if event is InputEventKey and event.pressed and not event.echo:
		var key := event as InputEventKey
		if key.keycode == KEY_R:
			rotate_held(1)
			get_viewport().set_input_as_handled()
		elif key.keycode == KEY_ESCAPE:
			clear_hold()
			get_viewport().set_input_as_handled()


func _handle_left_click(cell: Vector2i) -> void:
	var existing := ship_hull.get_module_at(cell)

	if existing != null and _held_module == null:
		if existing.data != null and existing.data.category == ModuleData.Category.HULL:
			var pack := ship_hull.detach_hull_with_cargo(existing.instance_id)
			if pack.is_empty():
				return
			var cargo: Array = []
			for item in pack["cargo"]:
				cargo.append({
					"data": item["data"],
					"rotation": item["rotation"],
					"local_origin": item["local_origin"],
				})
			hold_module(pack["data"], pack["rotation"], cargo, pack["rotation"])
			_hover_origin = cell
			_refresh_hover_validity()
			_preview.queue_redraw()
			return

		var data := existing.data
		var rot := existing.rotation
		ship_hull.detach_module(existing.instance_id)
		hold_module(data, rot)
		_hover_origin = cell
		_refresh_hover_validity()
		_preview.queue_redraw()
		return

	if _held_module != null:
		var origin := _hover_origin
		if _held_module.category == ModuleData.Category.HULL and not _held_cargo.is_empty():
			if ship_hull.can_place_hull_with_cargo(
				_held_module, origin, _held_rotation, _held_cargo, _held_pick_rotation
			):
				var placed := ship_hull.attach_hull_with_cargo(
					_held_module, origin, _held_rotation, _held_cargo, _held_pick_rotation
				)
				if placed != null:
					placement_succeeded.emit(placed)
					clear_hold()
			else:
				placement_failed.emit(_held_module, origin)
			return

		if ship_hull.can_place(_held_module, origin, _held_rotation):
			var placed2 := ship_hull.attach_module(_held_module, origin, _held_rotation)
			if placed2 != null:
				placement_succeeded.emit(placed2)
				clear_hold()
			else:
				placement_failed.emit(_held_module, origin)
		return


func _refresh_hover_validity() -> void:
	if _hover_module == null or ship_hull == null:
		_hover_valid = false
		return
	if (
		_hover_module.category == ModuleData.Category.HULL
		and _held_module == _hover_module
		and not _held_cargo.is_empty()
	):
		_hover_valid = ship_hull.can_place_hull_with_cargo(
			_hover_module, _hover_origin, _hover_rotation, _held_cargo, _held_pick_rotation
		)
	else:
		_hover_valid = ship_hull.can_place(_hover_module, _hover_origin, _hover_rotation)


func _draw() -> void:
	if ship_hull == null:
		return

	var grid := ship_hull.get_grid_size()
	for y in grid.y:
		for x in grid.x:
			var cell := Vector2i(x, y)
			var rect := Rect2(Vector2(cell) * cell_size, cell_size)
			var floor := ship_hull.get_floor_type(cell)
			var fill := empty_tint
			match floor:
				HullData.FloorType.DECK:
					fill = deck_tint
				HullData.FloorType.CONNECTOR:
					fill = connector_tint
				_:
					fill = empty_tint
					if ship_hull.is_weapon_mount_cell(cell):
						fill = mount_tint
			if ship_hull.get_equipment_at(cell) != null:
				fill = occupied_tint
			draw_rect(rect, fill, true)
			draw_rect(rect, grid_line, false, 1.0)


func _draw_preview() -> void:
	if _hover_module == null or ship_hull == null:
		return
	var shape := _hover_module.get_shape(_hover_rotation)
	for offset: Vector2i in shape:
		var cell := _hover_origin + offset
		var rect := Rect2(Vector2(cell) * cell_size, cell_size)
		var blocked := (
			not ship_hull.is_cell_in_bounds(cell)
			or not ship_hull.is_floor_compatible(_hover_module, cell)
		)
		# When moving hull with cargo, floor_compatible ignores future hull — use overall validity.
		var tint := valid_tint if (_hover_valid and not blocked) else invalid_tint
		if _hover_module.category == ModuleData.Category.HULL and not _held_cargo.is_empty():
			tint = valid_tint if _hover_valid else invalid_tint
		_preview.draw_rect(rect, tint, true)
		_preview.draw_rect(rect, Color(tint.r, tint.g, tint.b, 0.95), false, 2.0)

	# Also preview cargo ghosts when moving a hull.
	if _hover_module.category == ModuleData.Category.HULL and not _held_cargo.is_empty():
		if _hover_module.hull_data == null:
			return
		var drot := posmod(_hover_rotation - _held_pick_rotation, 4)
		for item in _held_cargo:
			var c_data: ModuleData = item["data"]
			var c_rot := posmod(int(item["rotation"]) + drot, 4)
			var local: Vector2i = item["local_origin"]
			var world_origin: Vector2i = (
				_hover_origin
				+ ShipHull.local_to_world_delta(local, _hover_rotation, _hover_module.hull_data)
			)
			for off: Vector2i in c_data.get_shape(c_rot):
				var cell := world_origin + off
				var rect := Rect2(Vector2(cell) * cell_size, cell_size)
				var tint := valid_tint if _hover_valid else invalid_tint
				tint.a = 0.4
				_preview.draw_rect(rect, tint, true)


func _on_module_attached(module: PlacedModule) -> void:
	_spawn_sprite(module)
	queue_redraw()
	_preview.queue_redraw()


func _on_module_detached(module: PlacedModule) -> void:
	_free_sprite(module.instance_id)
	queue_redraw()
	_preview.queue_redraw()


func _on_stats_changed(_new_stats: Dictionary) -> void:
	queue_redraw()
	_preview.queue_redraw()


func _spawn_sprite(module: PlacedModule) -> void:
	_free_sprite(module.instance_id)
	if module.data == null:
		return

	var tex := _texture_for(module.data, module.rotation)
	if tex == null:
		return

	var sprite := TextureRect.new()
	sprite.texture = tex
	sprite.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	sprite.stretch_mode = TextureRect.STRETCH_SCALE
	sprite.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sprite.show_behind_parent = true

	var bounds := module.get_bounding_size()
	sprite.position = Vector2(module.origin) * cell_size
	sprite.size = Vector2(bounds) * cell_size
	add_child(sprite)
	# Keep preview on top.
	if _preview != null:
		move_child(_preview, get_child_count() - 1)
	_module_sprites[module.instance_id] = sprite


func _texture_for(data: ModuleData, rotation: int) -> Texture2D:
	var key := "%s:%d" % [str(data.id), rotation]
	if _texture_cache.has(key):
		return _texture_cache[key]

	var tex: Texture2D
	if data.category == ModuleData.Category.HULL and data.hull_data != null:
		tex = ModuleCatalog.make_hull_texture(data.hull_data, rotation, int(cell_size.x))
	elif rotation == 0 and data.texture != null:
		tex = data.texture
	else:
		tex = ModuleCatalog.make_shape_texture(
			data.grid_shape,
			data.category,
			rotation,
			int(cell_size.x)
		)
		if tex == null and data.texture != null:
			tex = data.texture

	_texture_cache[key] = tex
	return tex


func _free_sprite(instance_id: int) -> void:
	if not _module_sprites.has(instance_id):
		return
	var node: Node = _module_sprites[instance_id]
	_module_sprites.erase(instance_id)
	if is_instance_valid(node):
		node.queue_free()


func _rebuild_all_sprites() -> void:
	for id in _module_sprites.keys():
		_free_sprite(id)
	if ship_hull == null:
		return
	for module: PlacedModule in ship_hull.get_all_modules():
		_spawn_sprite(module)


func _position_to_origin(at_position: Vector2) -> Vector2i:
	return Vector2i(
		floori(at_position.x / cell_size.x),
		floori(at_position.y / cell_size.y)
	)


## Cell under the cursor, offset so the module's footprint is centered on the
## cursor instead of anchored at its top-left cell.
func _centered_origin(at_position: Vector2, module: ModuleData, rotation: int) -> Vector2i:
	var cell := _position_to_origin(at_position)
	if module == null:
		return cell
	var bounds := module.get_bounding_size(rotation)
	return cell - Vector2i(bounds.x / 2, bounds.y / 2)


func _clear_hover() -> void:
	if _held_module != null:
		_hover_module = _held_module
		_hover_rotation = _held_rotation
	else:
		_hover_module = null
		_hover_rotation = 0
		_hover_origin = Vector2i(-999, -999)
		_hover_valid = false
	if _preview != null:
		_preview.queue_redraw()

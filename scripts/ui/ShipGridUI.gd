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
## Fill alpha of the green/red footprint under a module's blueprint art.
const PLAN_TINT_ALPHA := 0.18
@export var empty_tint := Color(0.25, 0.4, 0.7, 0.16)
@export var deck_tint := Color(0.3, 0.5, 0.85, 0.22)
@export var connector_tint := Color(0.4, 0.65, 0.95, 0.26)
@export var occupied_tint := Color(0.35, 0.55, 0.85, 0.2)
@export var grid_line := Color(0.45, 0.55, 0.7, 0.35)
@export var mount_tint := Color(0.3, 0.5, 0.85, 0.16) ## subtle hint for weapon truss cells
@export var weapon_fov_fill := Color(0.75, 0.78, 0.82, 0.16)
@export var weapon_fov_outline := Color(0.82, 0.85, 0.9, 0.7)
## A turret's whole reach, fainter than the cone it fires in.
@export var turret_arc_fill := Color(0.75, 0.78, 0.82, 0.07)
@export var turret_arc_outline := Color(0.82, 0.85, 0.9, 0.3)
## How fast a hovered turret sweeps its arc in the preview (radians of phase per second).
const TURRET_SWEEP_SPEED := 1.3
@export var radar_fov_fill := Color(0.25, 0.75, 0.85, 0.16)
@export var radar_fov_outline := Color(0.45, 0.9, 1.0, 0.7)

var _hover_origin: Vector2i = Vector2i(-999, -999)
var _hover_module: ModuleData = null
var _hover_rotation: int = 0
var _hover_valid: bool = false
## Placed FOV module under the cursor when the hand is empty.
var _inspect_module: PlacedModule = null

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
var _view_rotation_steps: int = 0 ## Cosmetic only — build data & placement logic stay unrotated.


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_process_unhandled_input(true)
	_ensure_preview()
	_scroll_parent = _find_scroll_parent()
	# Line thickness depends on the window's stretch scale.
	get_viewport().size_changed.connect(queue_redraw)
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
	_apply_view_rotation()
	if _preview != null:
		_preview.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		_preview.size = size
	var host := get_parent() as BuildAreaHost
	if host != null:
		host.refresh()


## Cosmetic 90°-per-step counter-clockwise spin of the whole view (grid, sprites,
## preview all inherit this node's transform) — like turning a camera, not the
## ship. Build data and placement logic never see it — Godot delivers _gui_input
## positions already in local, unrotated space, so mount/edge rules stay
## left-to-right as always. Whatever was at the screen center stays there.
func rotate_view(steps: int = 1) -> void:
	if ship_hull == null:
		return
	var anchor := _local_point_at_view_center()
	_view_rotation_steps = posmod(_view_rotation_steps + steps, 4)
	_apply_view_rotation()
	var host := get_parent() as BuildAreaHost
	if host != null:
		host.refresh()
	_keep_local_point_centered(anchor)


func _apply_view_rotation() -> void:
	# Spin around the grid's own center so the host can keep it centered.
	pivot_offset = size * 0.5
	rotation = -_view_rotation_steps * (PI / 2.0)


## On-screen footprint of the grid — width/height swap on quarter turns.
## Middle of the built ship in this grid's own (unrotated) pixels, or
## Vector2.INF with nothing built - where Center View aims.
func ship_center_local() -> Vector2:
	if ship_hull == null:
		return Vector2.INF
	var bounds: Rect2i = ship_hull.get_occupied_bounds()
	if bounds.size == Vector2i.ZERO:
		return Vector2.INF
	return (Vector2(bounds.position) + Vector2(bounds.size) * 0.5) * cell_size


func get_view_size() -> Vector2:
	var s := custom_minimum_size if custom_minimum_size != Vector2.ZERO else size
	return Vector2(s.y, s.x) if _view_rotation_steps % 2 == 1 else s


func _local_point_at_view_center() -> Vector2:
	if _scroll_parent == null:
		return size * 0.5
	var center := _scroll_parent.get_global_rect().get_center()
	return get_global_transform().affine_inverse() * center


func _keep_local_point_centered(local_point: Vector2) -> void:
	if _scroll_parent == null:
		return
	# Wait one frame so the ScrollContainer picks up the host's new size.
	await get_tree().process_frame
	var center := _scroll_parent.get_global_rect().get_center()
	var delta := get_global_transform() * local_point - center
	_scroll_parent.scroll_horizontal += roundi(delta.x)
	_scroll_parent.scroll_vertical += roundi(delta.y)


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


func hold_module(module: ModuleData, rotation: int = 0, cargo: Array = [], pick_rotation: int = -1) -> void:
	_held_module = module
	_held_rotation = posmod(rotation, 4) if module == null or module.is_rotatable() else 0
	_held_cargo = cargo.duplicate(true)
	_held_pick_rotation = _held_rotation if pick_rotation < 0 else posmod(pick_rotation, 4)
	_hover_module = module
	_hover_rotation = _held_rotation
	# Seed the ghost under the cursor immediately (don't wait for the next motion).
	_hover_origin = _centered_origin(get_local_mouse_position(), module, _held_rotation)
	_refresh_hover_validity()
	_update_hull_dim_for_hold()
	hold_changed.emit(_held_module, _held_rotation)
	queue_redraw()
	_preview.queue_redraw()


func clear_hold() -> void:
	_held_module = null
	_held_rotation = 0
	_held_cargo.clear()
	_held_pick_rotation = 0
	_inspect_module = null
	_clear_hover()
	_update_hull_dim_for_hold()
	hold_changed.emit(null, 0)
	queue_redraw()
	if _preview != null:
		_preview.queue_redraw()


func has_held_module() -> bool:
	return _held_module != null


func rotate_held(steps: int = 1) -> void:
	if _held_module != null and not _held_module.is_rotatable():
		return
	if _held_module != null:
		_held_rotation = posmod(_held_rotation + steps, 4)
		_hover_rotation = _held_rotation
		hold_changed.emit(_held_module, _held_rotation)
		_refresh_hover_validity()
		_preview.queue_redraw()
	elif _hover_module != null and _hover_module.is_rotatable():
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
	elif module.is_rotatable():
		_hover_rotation = int(data.get("rotation", 0))
	else:
		_hover_rotation = 0
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
	if not module.is_rotatable():
		rotation = 0
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
			_inspect_module = null
			_hover_module = _held_module
			_hover_rotation = _held_rotation
			_hover_origin = _centered_origin(motion.position, _held_module, _held_rotation)
			_refresh_hover_validity()
			_preview.queue_redraw()
		else:
			_update_inspect_at(motion.position)
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
		# Place at the click, not a stale hover from before the cursor entered the grid.
		var origin := _centered_origin(
			Vector2(cell) * cell_size + cell_size * 0.5,
			_held_module,
			_held_rotation
		)
		_hover_origin = origin
		_refresh_hover_validity()
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
			_preview.queue_redraw()
			return

		if ship_hull.can_place(_held_module, origin, _held_rotation):
			var placed2 := ship_hull.attach_module(_held_module, origin, _held_rotation)
			if placed2 != null:
				placement_succeeded.emit(placed2)
				clear_hold()
			else:
				placement_failed.emit(_held_module, origin)
		else:
			placement_failed.emit(_held_module, origin)
		_preview.queue_redraw()
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


## Snaps a cell to integer pixel bounds so adjacent cells always share an edge —
## plain `Vector2(cell) * cell_size` leaves sub-pixel gaps at fractional zoom levels.
func _cell_rect(cell: Vector2i) -> Rect2:
	var x0 := roundi(cell.x * cell_size.x)
	var y0 := roundi(cell.y * cell_size.y)
	var x1 := roundi((cell.x + 1) * cell_size.x)
	var y1 := roundi((cell.y + 1) * cell_size.y)
	return Rect2(x0, y0, x1 - x0, y1 - y0)


func _draw() -> void:
	if ship_hull == null:
		return

	var grid := ship_hull.get_grid_size()
	# The whole field in one rect, then only the cells that differ from it
	# (hulls, connectors, truss, equipment) - asking every cell of the big grid
	# what it is made each redraw (zoom, placing a module) hitch.
	draw_rect(Rect2(Vector2.ZERO, _cell_rect(grid - Vector2i.ONE).end), empty_tint, true)
	var truss: Dictionary = ship_hull.get_weapon_mount_cells()
	var cells: Dictionary = truss.duplicate()
	for used: Vector2i in ship_hull.get_used_cells():
		cells[used] = true
	for cell: Vector2i in cells.keys():
		var fill := empty_tint
		match ship_hull.get_floor_type(cell):
			HullData.FloorType.DECK:
				# Stronger wash while placing interior modules so the hull interior reads as a drop target.
				fill = (
					Color(0.25, 0.85, 0.55, 0.32)
					if _held_module != null and _held_module.is_deck_equipment()
					else deck_tint
				)
			HullData.FloorType.CONNECTOR:
				fill = connector_tint
			_:
				if truss.has(cell):
					fill = mount_tint
		if ship_hull.get_equipment_at(cell) != null:
			fill = occupied_tint
		if fill != empty_tint:
			draw_rect(_cell_rect(cell), fill, true)
	_draw_grid_lines(grid)


## Grid lines as filled strips starting on each cell edge, at least one physical
## pixel thick. A width-1 outline is centered on the edge, and once the canvas
## stretch makes it thinner than a pixel it misses every pixel center at some
## zoom levels and drops out.
func _draw_grid_lines(grid: Vector2i) -> void:
	var screen_scale := (get_viewport().get_final_transform() * get_global_transform_with_canvas()).get_scale().abs()
	var tx := maxf(1.0, 1.0 / maxf(screen_scale.x, 0.001))
	var ty := maxf(1.0, 1.0 / maxf(screen_scale.y, 0.001))
	var w := float(roundi(grid.x * cell_size.x))
	var h := float(roundi(grid.y * cell_size.y))
	for x in grid.x + 1:
		var px := minf(float(roundi(x * cell_size.x)), w - tx)
		draw_rect(Rect2(px, 0.0, tx, h), grid_line, true)
	for y in grid.y + 1:
		var py := minf(float(roundi(y * cell_size.y)), h - ty)
		draw_rect(Rect2(0.0, py, w, ty), grid_line, true)


func _draw_preview() -> void:
	_draw_fov_preview()

	if _hover_module == null or ship_hull == null:
		return
	var shape := _hover_module.get_shape(_hover_rotation)
	for offset: Vector2i in shape:
		var cell := _hover_origin + offset
		var rect := _cell_rect(cell)
		var blocked := (
			not ship_hull.is_cell_in_bounds(cell)
			or not ship_hull.is_floor_compatible(_hover_module, cell)
		)
		# When moving hull with cargo, floor_compatible ignores future hull — use overall validity.
		var tint := valid_tint if (_hover_valid and not blocked) else invalid_tint
		if _hover_module.category == ModuleData.Category.HULL and not _held_cargo.is_empty():
			tint = valid_tint if _hover_valid else invalid_tint
		# With blueprint art on top, a light wash keeps the sketch readable; the
		# outline still says green/red.
		var fill := tint
		if _hover_module.plan_texture != null:
			fill.a = PLAN_TINT_ALPHA
		_preview.draw_rect(rect, fill, true)
		_preview.draw_rect(rect, Color(tint.r, tint.g, tint.b, 0.95), false, 2.0)

	# Blueprint art over the footprint while the module is held or dragged.
	if _hover_module.plan_texture != null:
		var bounds := _hover_module.get_bounding_size(_hover_rotation)
		var top_left := _cell_rect(_hover_origin).position
		var bottom_right := _cell_rect(_hover_origin + bounds - Vector2i.ONE).end
		_preview.draw_texture_rect(
			_plan_texture_for(_hover_module, _hover_rotation),
			Rect2(top_left, bottom_right - top_left),
			false
		)

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
				var rect := _cell_rect(cell)
				var tint := valid_tint if _hover_valid else invalid_tint
				tint.a = 0.4
				_preview.draw_rect(rect, tint, true)


func _draw_fov_preview() -> void:
	var data: ModuleData = null
	var origin := Vector2i.ZERO
	var rotation := 0
	var ignore_cells: Dictionary = {}
	if _hover_module != null and _hover_module.has_fov():
		data = _hover_module
		origin = _hover_origin
		rotation = _hover_rotation
		for off: Vector2i in data.get_shape(rotation):
			ignore_cells[origin + off] = true
	elif _inspect_module != null and _inspect_module.data != null and _inspect_module.data.has_fov():
		data = _inspect_module.data
		origin = _inspect_module.origin
		rotation = _inspect_module.rotation
		for cell: Vector2i in _inspect_module.get_occupied_cells():
			ignore_cells[cell] = true
	else:
		return

	var muzzle_cell := FovUtil.module_muzzle_cell(origin, data, rotation)
	var origin_px := muzzle_cell * cell_size
	var facing := FovUtil.local_facing(rotation)
	if data.is_turret():
		# The whole arc it can turn through, from the turret's middle, and
		# the cone it fires in turned to where the sweep has it now.
		var pivot_px := FovUtil.module_center_cell(origin, data, rotation) * cell_size
		var reach := FovUtil.builder_preview_length(data.fov_range, cell_size.x)
		var arc_blocked: Dictionary = ship_hull.get_structure_blocker_cells() if ship_hull != null else {}
		FovUtil.draw_cone(
			_preview, pivot_px, facing, data.turret_arc_deg, reach, turret_arc_fill, turret_arc_outline, 1.0,
			arc_blocked, ignore_cells, cell_size.x
		)
		facing = facing.rotated(_turret_sweep(data))
		origin_px = pivot_px
	var length := FovUtil.builder_preview_length(data.fov_range, cell_size.x)
	if data.is_radar():
		# Radars reach far past the yard: just a ring round the mount.
		length = minf(length, cell_size.x * 8.0)
	var fill := weapon_fov_fill if data.is_weapon() else radar_fov_fill
	var outline := weapon_fov_outline if data.is_weapon() else radar_fov_outline
	var blocked: Dictionary = {}
	if ship_hull != null:
		blocked = ship_hull.get_structure_blocker_cells()
	FovUtil.draw_cone(
		_preview,
		origin_px,
		facing,
		data.fov_angle_deg,
		length,
		fill,
		outline,
		2.0,
		blocked,
		ignore_cells,
		cell_size.x
	)


## Turn of a turret in the preview: a slow sweep across its arc while it is
## held or hovered, so the player sees how far it reaches.
func _turret_sweep(data: ModuleData) -> float:
	var half: float = deg_to_rad(data.turret_arc_deg) * 0.5
	return sin(float(Time.get_ticks_msec()) * 0.001 * TURRET_SWEEP_SPEED) * half


func _process(_delta: float) -> void:
	# A hovered turret turns its sprite with the sweep; the rest sit still.
	var turning: PlacedModule = null
	if _inspect_module != null and _inspect_module.data != null and _inspect_module.data.is_turret():
		turning = _inspect_module
	for id: int in _module_sprites.keys():
		var sprite: Control = _module_sprites[id]
		if not is_instance_valid(sprite):
			continue
		if turning != null and id == turning.instance_id:
			sprite.pivot_offset = sprite.size * 0.5
			sprite.rotation = _turret_sweep(turning.data)
		elif sprite.rotation != 0.0:
			sprite.rotation = 0.0
	var held_turret: bool = has_held_module() and _held_module != null and _held_module.is_turret()
	if turning != null or held_turret:
		_preview.queue_redraw()


func _update_inspect_at(local_pos: Vector2) -> void:
	if ship_hull == null:
		_inspect_module = null
		_preview.queue_redraw()
		return
	var cell := ship_hull.world_to_cell(local_pos)
	var module := ship_hull.get_module_at(cell)
	var next: PlacedModule = null
	if module != null and module.data != null and module.data.has_fov():
		next = module
	if next == _inspect_module:
		return
	_inspect_module = next
	_preview.queue_redraw()


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
	if module.data.category == ModuleData.Category.ENGINE:
		# Engine art is square; the M footprint (2x1) is not - fit, don't squash.
		sprite.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	sprite.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sprite.show_behind_parent = true
	# Interior gear must sit above the opaque hull interior art.
	sprite.z_index = 0 if module.data.is_structure() else 2

	var bounds := module.get_bounding_size()
	sprite.position = Vector2(module.origin) * cell_size
	sprite.size = Vector2(bounds) * cell_size
	add_child(sprite)
	# Keep preview on top.
	if _preview != null:
		move_child(_preview, get_child_count() - 1)
	_module_sprites[module.instance_id] = sprite
	_update_hull_dim_for_hold()


## Dim hull art while holding an interior module so deck cells stay readable.
func _update_hull_dim_for_hold() -> void:
	var dim := _held_module != null and _held_module.is_deck_equipment()
	if ship_hull == null:
		return
	for m: PlacedModule in ship_hull.get_all_modules():
		if not _module_sprites.has(m.instance_id) or m.data == null:
			continue
		var sprite: CanvasItem = _module_sprites[m.instance_id] as CanvasItem
		if sprite == null:
			continue
		if m.data.category == ModuleData.Category.HULL:
			sprite.modulate = Color(1, 1, 1, 0.45) if dim else Color.WHITE
		else:
			sprite.modulate = Color.WHITE


func _texture_for(data: ModuleData, rotation: int) -> Texture2D:
	var key := "%s:%d" % [str(data.id), rotation]
	if _texture_cache.has(key):
		return _texture_cache[key]

	var tex: Texture2D
	if data.category == ModuleData.Category.HULL and data.hull_data != null:
		tex = ModuleCatalog.make_hull_texture(data.hull_data, rotation, int(cell_size.x), true)
	elif rotation == 0 and data.texture != null:
		tex = data.texture
	elif data.texture != null and (
		data.category == ModuleData.Category.ENGINE or not data.texture.resource_path.is_empty()
	):
		# Drawn art (engines, and anything loaded from textures/modules) is a
		# picture, not a generated tile - turn the picture.
		tex = _rotated_texture(data.texture, rotation)
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


func _plan_texture_for(data: ModuleData, rotation: int) -> Texture2D:
	var key := "plan:%s:%d" % [str(data.id), rotation]
	if not _texture_cache.has(key):
		_texture_cache[key] = (
			data.plan_texture if posmod(rotation, 4) == 0
			else _rotated_texture(data.plan_texture, rotation)
		)
	return _texture_cache[key]


## `rotation` quarter turns clockwise on screen, matching ModuleData.rotate_shape.
static func _rotated_texture(source: Texture2D, rotation: int) -> Texture2D:
	var img: Image = source.get_image()
	if img == null:
		return source
	img = img.duplicate()
	if img.is_compressed():
		img.decompress()
	for _i in posmod(rotation, 4):
		img.rotate_90(CLOCKWISE)
	return ImageTexture.create_from_image(img)


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
		_inspect_module = null
	if _preview != null:
		_preview.queue_redraw()

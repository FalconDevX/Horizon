class_name ShipHull
extends Node2D
## Shipyard build grid with two layers:
##   structure  — HULL pieces + CONNECTOR (łącznik)
##   equipment  — engines/utilities on DECK; weapons on empty cells adjacent to DECK
##
## Rules:
##   - Hull pieces may not touch each other edge-to-edge (must use łącznik).
##   - Weapons mount next to hull floor (not on the floor).
##   - Moving a hull keeps its attached modules (cargo).

signal stats_changed(new_stats: Dictionary)
signal module_attached(module: PlacedModule)
signal module_detached(module: PlacedModule)
signal module_destroyed(module: PlacedModule)

@export var build_grid_size: Vector2i = Vector2i(40, 28)
@export var cell_size: Vector2 = Vector2(48, 48)
@export var show_debug_grid: bool = false

var _structure: Dictionary = {} ## Vector2i → PlacedModule
var _equipment: Dictionary = {} ## Vector2i → PlacedModule
var _modules: Dictionary = {} ## instance_id → PlacedModule
var _next_instance_id: int = 1
var _cached_stats: ShipStats = ShipStats.new()

const _DIRS: Array[Vector2i] = [
	Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)
]


func _ready() -> void:
	_recalculate_stats()


func _draw() -> void:
	if not show_debug_grid:
		return
	for y in build_grid_size.y:
		for x in build_grid_size.x:
			var rect := Rect2(Vector2(x, y) * cell_size, cell_size)
			draw_rect(rect, Color(0.2, 0.25, 0.3, 0.2), false, 1.0)


func get_grid_size() -> Vector2i:
	return build_grid_size


func get_stats() -> ShipStats:
	return _cached_stats.duplicate_stats()


func get_stats_dictionary() -> Dictionary:
	return _cached_stats.to_dictionary()


func get_all_modules() -> Array[PlacedModule]:
	var list: Array[PlacedModule] = []
	for module: PlacedModule in _modules.values():
		list.append(module)
	return list


func get_module_at(cell: Vector2i) -> PlacedModule:
	if _equipment.has(cell):
		return _equipment[cell] as PlacedModule
	return _structure.get(cell) as PlacedModule


func get_structure_at(cell: Vector2i) -> PlacedModule:
	return _structure.get(cell) as PlacedModule


func get_equipment_at(cell: Vector2i) -> PlacedModule:
	return _equipment.get(cell) as PlacedModule


func is_cell_in_bounds(cell: Vector2i) -> bool:
	return (
		cell.x >= 0 and cell.y >= 0
		and cell.x < build_grid_size.x and cell.y < build_grid_size.y
	)


func get_floor_type(cell: Vector2i) -> HullData.FloorType:
	var structure := get_structure_at(cell)
	if structure == null or structure.data == null:
		return HullData.FloorType.EMPTY
	if structure.data.category == ModuleData.Category.CONNECTOR:
		return HullData.FloorType.CONNECTOR
	if structure.data.category == ModuleData.Category.HULL:
		return HullData.FloorType.DECK
	return HullData.FloorType.EMPTY


func is_deck_cell(cell: Vector2i) -> bool:
	return get_floor_type(cell) == HullData.FloorType.DECK


## Empty cell orthogonally adjacent to at least one hull deck cell.
func is_weapon_mount_cell(cell: Vector2i, ignore_instance_id: int = -1) -> bool:
	if not is_cell_in_bounds(cell):
		return false
	var s := get_structure_at(cell)
	if s != null and s.instance_id != ignore_instance_id:
		return false
	for d: Vector2i in _DIRS:
		var n := cell + d
		var neighbor := get_structure_at(n)
		if neighbor == null or neighbor.data == null:
			continue
		if neighbor.instance_id == ignore_instance_id:
			continue
		if neighbor.data.category == ModuleData.Category.HULL:
			return true
	return false


func is_floor_compatible(data: ModuleData, cell: Vector2i) -> bool:
	if data == null:
		return false
	match data.category:
		ModuleData.Category.HULL, ModuleData.Category.CONNECTOR:
			return get_structure_at(cell) == null and get_equipment_at(cell) == null
		ModuleData.Category.WEAPON:
			return (
				get_structure_at(cell) == null
				and get_equipment_at(cell) == null
				and is_weapon_mount_cell(cell)
			)
		ModuleData.Category.ENGINE, ModuleData.Category.UTILITY, ModuleData.Category.FUEL_TANK:
			return get_floor_type(cell) == HullData.FloorType.DECK and get_equipment_at(cell) == null
		_:
			return false


func can_place(
	data: ModuleData,
	origin: Vector2i,
	rotation: int = 0,
	ignore_instance_id: int = -1
) -> bool:
	if data == null or data.grid_shape.is_empty():
		return false

	var cells := data.get_occupied_cells(origin, rotation)

	if data.is_equipment():
		var equip_count := _count_equipment_cells(ignore_instance_id)
		var cap := _total_hull_capacity(ignore_instance_id)
		if equip_count + cells.size() > cap:
			return false

	for cell: Vector2i in cells:
		if not is_cell_in_bounds(cell):
			return false
		if not _cell_free_for(data, cell, ignore_instance_id):
			return false

	if data.category == ModuleData.Category.HULL:
		if _hull_would_touch_other_hull(cells, ignore_instance_id):
			return false

	return true


## Like can_place, but also validates cargo that moves with a hull.
func can_place_hull_with_cargo(
	hull_module: ModuleData,
	origin: Vector2i,
	rotation: int,
	cargo: Array,
	pick_rotation: int
) -> bool:
	if not can_place(hull_module, origin, rotation):
		return false
	if hull_module.hull_data == null:
		return false

	var hull_cells: Dictionary = {}
	for c: Vector2i in hull_module.get_occupied_cells(origin, rotation):
		hull_cells[c] = true

	var drot := posmod(rotation - pick_rotation, 4)
	for item in cargo:
		var c_data: ModuleData = item["data"]
		var c_rot := posmod(int(item["rotation"]) + drot, 4)
		var local: Vector2i = item["local_origin"]
		var world_origin := origin + local_to_world_delta(local, rotation, hull_module.hull_data)
		var cells := c_data.get_occupied_cells(world_origin, c_rot)
		for cell: Vector2i in cells:
			if not is_cell_in_bounds(cell):
				return false
			if get_structure_at(cell) != null and not hull_cells.has(cell):
				return false
			if get_equipment_at(cell) != null:
				return false
			match c_data.category:
				ModuleData.Category.ENGINE, ModuleData.Category.UTILITY, ModuleData.Category.FUEL_TANK:
					if not hull_cells.has(cell):
						return false
				ModuleData.Category.WEAPON:
					if hull_cells.has(cell):
						return false
					var touches := false
					for d: Vector2i in _DIRS:
						if hull_cells.has(cell + d):
							touches = true
							break
					if not touches:
						return false
				_:
					return false
	return true


func attach_module(data: ModuleData, origin: Vector2i, rotation: int = 0) -> PlacedModule:
	if not can_place(data, origin, rotation):
		return null

	var placed := PlacedModule.new(data, origin, _next_instance_id, rotation)
	_next_instance_id += 1
	_modules[placed.instance_id] = placed

	for cell: Vector2i in placed.get_occupied_cells():
		if data.is_structure():
			_structure[cell] = placed
		else:
			_equipment[cell] = placed

	_recalculate_stats()
	module_attached.emit(placed)
	return placed


## Detach hull and return cargo descriptors (modules stay removed until reattached).
func detach_hull_with_cargo(instance_id: int) -> Dictionary:
	if not _modules.has(instance_id):
		return {}
	var hull: PlacedModule = _modules[instance_id]
	if hull.data == null or hull.data.category != ModuleData.Category.HULL:
		return {}

	var cargo: Array = _collect_cargo_for_hull(hull)
	for item in cargo:
		var eq: PlacedModule = item["module"]
		_remove_from_maps(eq)
		_modules.erase(eq.instance_id)
		module_detached.emit(eq)

	_remove_from_maps(hull)
	_modules.erase(instance_id)
	_recalculate_stats()
	module_detached.emit(hull)

	return {
		"data": hull.data,
		"rotation": hull.rotation,
		"origin": hull.origin,
		"cargo": cargo,
	}


func attach_hull_with_cargo(
	hull_data: ModuleData,
	origin: Vector2i,
	rotation: int,
	cargo: Array,
	pick_rotation: int
) -> PlacedModule:
	if not can_place_hull_with_cargo(hull_data, origin, rotation, cargo, pick_rotation):
		return null

	var hull := attach_module(hull_data, origin, rotation)
	if hull == null:
		return null

	var drot := posmod(rotation - pick_rotation, 4)
	for item in cargo:
		var c_data: ModuleData = item["data"]
		var c_rot := posmod(int(item["rotation"]) + drot, 4)
		var local: Vector2i = item["local_origin"]
		var world_origin := origin + local_to_world_delta(local, rotation, hull_data.hull_data)
		attach_module(c_data, world_origin, c_rot)

	return hull


func detach_module(instance_id: int) -> PlacedModule:
	if not _modules.has(instance_id):
		return null
	var placed: PlacedModule = _modules[instance_id]

	# Hard-delete hull (e.g. RMB) also removes its cargo permanently.
	if placed.data != null and placed.data.category == ModuleData.Category.HULL:
		var cargo := _collect_cargo_for_hull(placed)
		for item in cargo:
			var eq: PlacedModule = item["module"]
			_remove_from_maps(eq)
			_modules.erase(eq.instance_id)
			module_detached.emit(eq)

	_remove_from_maps(placed)
	_modules.erase(instance_id)
	_recalculate_stats()
	module_detached.emit(placed)
	return placed


func detach_at(cell: Vector2i) -> PlacedModule:
	var placed := get_module_at(cell)
	if placed == null:
		return null
	return detach_module(placed.instance_id)


func damage_module(instance_id: int, amount: float) -> void:
	if not _modules.has(instance_id):
		return
	var placed: PlacedModule = _modules[instance_id]
	placed.apply_damage(amount)
	if placed.is_destroyed():
		var destroyed := placed
		detach_module(instance_id)
		module_destroyed.emit(destroyed)


func clear_modules() -> void:
	_structure.clear()
	_equipment.clear()
	_modules.clear()
	_recalculate_stats()


func world_to_cell(local_pos: Vector2) -> Vector2i:
	return Vector2i(floori(local_pos.x / cell_size.x), floori(local_pos.y / cell_size.y))


func cell_to_local(cell: Vector2i) -> Vector2:
	return Vector2(cell) * cell_size


func cell_to_local_center(cell: Vector2i) -> Vector2:
	return cell_to_local(cell) + cell_size * 0.5


func are_hulls_connected() -> bool:
	var hulls: Array[PlacedModule] = []
	for m: PlacedModule in _modules.values():
		if m.data != null and m.data.category == ModuleData.Category.HULL:
			hulls.append(m)
	if hulls.size() <= 1:
		return true
	var start_cells := hulls[0].get_occupied_cells()
	if start_cells.is_empty():
		return true
	var visited: Dictionary = {}
	var queue: Array[Vector2i] = [start_cells[0]]
	visited[start_cells[0]] = true
	while not queue.is_empty():
		var c: Vector2i = queue.pop_front()
		for d: Vector2i in _DIRS:
			var n := c + d
			if visited.has(n):
				continue
			if get_structure_at(n) == null:
				continue
			visited[n] = true
			queue.append(n)
	for h: PlacedModule in hulls:
		for cell: Vector2i in h.get_occupied_cells():
			if not visited.has(cell):
				return false
	return true


func world_to_hull_local(hull: PlacedModule, world_cell: Vector2i) -> Vector2i:
	var hd: HullData = hull.data.hull_data
	var rel := world_cell - hull.origin
	return world_delta_to_local(rel, hull.rotation, hd)


static func world_delta_to_local(rel: Vector2i, rotation: int, hull: HullData) -> Vector2i:
	var W := hull.grid_size.x
	var H := hull.grid_size.y
	match posmod(rotation, 4):
		0:
			return rel
		1:
			return Vector2i(rel.y, H - 1 - rel.x)
		2:
			return Vector2i(W - 1 - rel.x, H - 1 - rel.y)
		3:
			return Vector2i(W - 1 - rel.y, rel.x)
		_:
			return rel


static func local_to_world_delta(local: Vector2i, rotation: int, hull: HullData) -> Vector2i:
	var W := hull.grid_size.x
	var H := hull.grid_size.y
	match posmod(rotation, 4):
		0:
			return local
		1:
			return Vector2i(H - 1 - local.y, local.x)
		2:
			return Vector2i(W - 1 - local.x, H - 1 - local.y)
		3:
			return Vector2i(local.y, W - 1 - local.x)
		_:
			return local


func _collect_cargo_for_hull(hull: PlacedModule) -> Array:
	var cargo: Array = []
	var seen: Dictionary = {}
	var hull_cells: Dictionary = {}
	for c: Vector2i in hull.get_occupied_cells():
		hull_cells[c] = true

	for m: PlacedModule in _modules.values():
		if m.data == null or not m.data.is_equipment():
			continue
		if seen.has(m.instance_id):
			continue
		var belongs := false
		for cell: Vector2i in m.get_occupied_cells():
			if hull_cells.has(cell):
				belongs = true
				break
			# Weapons mounted against this hull.
			if m.data.category == ModuleData.Category.WEAPON:
				for d: Vector2i in _DIRS:
					if hull_cells.has(cell + d):
						belongs = true
						break
			if belongs:
				break
		if not belongs:
			continue
		seen[m.instance_id] = true
		cargo.append({
			"module": m,
			"data": m.data,
			"rotation": m.rotation,
			"local_origin": world_to_hull_local(hull, m.origin),
		})
	return cargo


func _cell_free_for(data: ModuleData, cell: Vector2i, ignore_instance_id: int) -> bool:
	if data.is_structure():
		var s := get_structure_at(cell)
		if s != null and s.instance_id != ignore_instance_id:
			return false
		var e := get_equipment_at(cell)
		if e != null and e.instance_id != ignore_instance_id:
			return false
		return true

	var eq := get_equipment_at(cell)
	if eq != null and eq.instance_id != ignore_instance_id:
		return false
	if get_structure_at(cell) != null:
		var s2 := get_structure_at(cell)
		if s2.instance_id != ignore_instance_id and data.category == ModuleData.Category.WEAPON:
			return false
	match data.category:
		ModuleData.Category.WEAPON:
			return is_weapon_mount_cell(cell, ignore_instance_id)
		ModuleData.Category.ENGINE, ModuleData.Category.UTILITY, ModuleData.Category.FUEL_TANK:
			return get_floor_type(cell) == HullData.FloorType.DECK
		_:
			return false


func _hull_would_touch_other_hull(cells: Array[Vector2i], ignore_instance_id: int) -> bool:
	var proposed: Dictionary = {}
	for c: Vector2i in cells:
		proposed[c] = true
	for c: Vector2i in cells:
		for d: Vector2i in _DIRS:
			var n := c + d
			if proposed.has(n):
				continue
			var s := get_structure_at(n)
			if s == null or s.data == null:
				continue
			if s.instance_id == ignore_instance_id:
				continue
			if s.data.category == ModuleData.Category.HULL:
				return true
	return false


func _remove_from_maps(placed: PlacedModule) -> void:
	for cell: Vector2i in placed.get_occupied_cells():
		if _structure.get(cell) == placed:
			_structure.erase(cell)
		if _equipment.get(cell) == placed:
			_equipment.erase(cell)


func _count_equipment_cells(ignore_instance_id: int = -1) -> int:
	var count := 0
	for m: PlacedModule in _modules.values():
		if m.data == null or not m.data.is_equipment():
			continue
		if m.instance_id == ignore_instance_id:
			continue
		count += m.data.get_cell_count()
	return count


func _total_hull_capacity(ignore_instance_id: int = -1) -> int:
	var cap := 0
	for m: PlacedModule in _modules.values():
		if m.data == null or m.data.category != ModuleData.Category.HULL:
			continue
		if m.instance_id == ignore_instance_id:
			continue
		if m.data.hull_data != null:
			cap += m.data.hull_data.capacity
	return cap


func _recalculate_stats() -> void:
	var stats := ShipStats.new()
	for module: PlacedModule in _modules.values():
		var d: ModuleData = module.data
		if d == null:
			continue
		stats.module_count += 1
		if d.category == ModuleData.Category.HULL and d.hull_data != null:
			stats.mass += d.hull_data.base_mass
			stats.durability += d.hull_data.base_durability
			stats.capacity += d.hull_data.capacity
		else:
			stats.mass += d.mass
			stats.health += module.current_health
		if d.is_equipment():
			stats.occupied_cells += d.get_cell_count()
		stats.energy_consumption += d.energy_consumption
		stats.thrust += d.thrust
		stats.fuel_consumption += d.fuel_consumption
		stats.fuel_capacity += d.fuel_capacity
		stats.damage += d.damage
		stats.energy_generation += d.energy_generation
		stats.energy_capacity += d.capacity
		stats.repair_rate += d.repair_rate
		if d.category == ModuleData.Category.ENGINE and d.max_heat > stats.max_heat:
			stats.max_heat = d.max_heat
	stats.health += stats.durability
	stats.hulls_linked = are_hulls_connected()
	_cached_stats = stats
	stats_changed.emit(stats.to_dictionary())

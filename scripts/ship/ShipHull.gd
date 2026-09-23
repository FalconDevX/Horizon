class_name ShipHull
extends Node2D
## Shipyard build grid with two layers:
##   structure  - HULL pieces + CONNECTOR
##   equipment  - engines/utilities on DECK / mounts; weapons on the outer truss ring
##
## Rules:
##   - Hull pieces may not touch each other edge-to-edge (must use a connector).
##   - Left edge is ENGINE_MOUNT; main engines only there (+ optional truss overhang), not on deck.
##   - Corrective / RCS engines and weapons only on truss cells adjacent to normal DECK (not ENGINE_MOUNT).
##   - Ship-wide: ≥1 RCS on each outer side except the main-engine side.
##   - Truss itself: empty cells within WEAPON_MOUNT_DEPTH of a hull (also used for main-engine overhang).
##   - Moving a hull keeps its attached modules (cargo).

signal stats_changed(new_stats: Dictionary)
signal module_attached(module: PlacedModule)
signal module_detached(module: PlacedModule)
signal module_destroyed(module: PlacedModule)

@export var build_grid_size: Vector2i = Vector2i(40, 40)
@export var cell_size: Vector2 = Vector2(48, 48)
@export var show_debug_grid: bool = false

var _structure: Dictionary = {} ## Vector2i → PlacedModule
var _equipment: Dictionary = {} ## Vector2i → PlacedModule
var _modules: Dictionary = {} ## instance_id → PlacedModule
var _next_instance_id: int = 1
var _cached_stats: ShipStats = ShipStats.new()

## How many empty cells outward from a hull edge weapons may occupy (truss depth).
const WEAPON_MOUNT_DEPTH := 2

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


## Runtime FOV payloads for the orbital ship (weapons + radars).
## Each entry: id, kind, angle_deg, range, local_facing, local_origin, damage, title
func get_fov_devices() -> Array[Dictionary]:
	var devices: Array[Dictionary] = []
	var centroid := _structure_centroid_cells()
	var hull_rects := get_hull_blocker_rects_local(centroid)
	for module: PlacedModule in _modules.values():
		if module.data == null or not module.data.has_fov():
			continue
		if not (module.data.is_weapon() or module.data.is_radar()):
			continue
		var muzzle: Vector2 = FovUtil.module_muzzle_cell(module.origin, module.data, module.rotation)
		var offset_cells := muzzle - centroid
		var kind := "radar" if module.data.is_radar() else "weapon"
		var ignore_rects: Array = []
		for cell: Vector2i in module.get_occupied_cells():
			var c := Vector2(cell) + Vector2(0.5, 0.5) - centroid
			var local := c * FovUtil.WORLD_UNITS_PER_CELL
			var half := FovUtil.WORLD_UNITS_PER_CELL * 0.5
			ignore_rects.append(Rect2(local - Vector2(half, half), Vector2(half, half) * 2.0))
		devices.append({
			"id": module.data.id,
			"title": module.data.title,
			"kind": kind,
			"instance_id": module.instance_id,
			"angle_deg": module.data.fov_angle_deg,
			"range": module.data.fov_range,
			"local_facing": FovUtil.local_facing(module.rotation),
			"local_origin": offset_cells * FovUtil.WORLD_UNITS_PER_CELL,
			"damage": module.data.damage,
			"reload_time": module.data.reload_time,
			"hull_rects": hull_rects,
			"ignore_rects": ignore_rects,
		})
	return devices


## Hull + connector cells as local-space AABBs around the build centroid (ship-local units).
func get_hull_blocker_rects_local(centroid: Vector2 = Vector2.INF) -> Array:
	if centroid.x == INF:
		centroid = _structure_centroid_cells()
	var rects: Array = []
	var half := FovUtil.WORLD_UNITS_PER_CELL * 0.5
	for cell: Vector2i in _structure.keys():
		var c := Vector2(cell) + Vector2(0.5, 0.5) - centroid
		var local := c * FovUtil.WORLD_UNITS_PER_CELL
		rects.append(Rect2(local - Vector2(half, half), Vector2(half, half) * 2.0))
	return rects


## Structure cells for shipyard LOS (hull + connector).
func get_structure_blocker_cells() -> Dictionary:
	var cells: Dictionary = {}
	for cell: Vector2i in _structure.keys():
		cells[cell] = true
	return cells


func _structure_centroid_cells() -> Vector2:
	var sum := Vector2.ZERO
	var count := 0
	for cell: Vector2i in _structure.keys():
		sum += Vector2(cell) + Vector2(0.5, 0.5)
		count += 1
	if count == 0:
		return Vector2(build_grid_size) * 0.5
	return sum / float(count)


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
		if structure.data.hull_data == null:
			return HullData.FloorType.DECK
		var local := world_to_hull_local(structure, cell)
		return structure.data.hull_data.get_local_floor(local)
	return HullData.FloorType.EMPTY


func is_deck_cell(cell: Vector2i) -> bool:
	return HullData.is_deck_floor(get_floor_type(cell))


func is_engine_mount_cell(cell: Vector2i) -> bool:
	return get_floor_type(cell) == HullData.FloorType.ENGINE_MOUNT


## Empty cell on the weapon truss: within WEAPON_MOUNT_DEPTH (Manhattan) of a hull cell.
func is_weapon_mount_cell(cell: Vector2i, ignore_instance_id: int = -1) -> bool:
	if not is_cell_in_bounds(cell):
		return false
	var s := get_structure_at(cell)
	if s != null and s.instance_id != ignore_instance_id:
		return false
	return _nearest_hull_manhattan(cell, ignore_instance_id) <= WEAPON_MOUNT_DEPTH


## Manhattan distance to nearest hull cell in [1, INF]; INF if none within depth search.
func _nearest_hull_manhattan(cell: Vector2i, ignore_instance_id: int = -1) -> int:
	var best := 999999
	for dy in range(-WEAPON_MOUNT_DEPTH, WEAPON_MOUNT_DEPTH + 1):
		for dx in range(-WEAPON_MOUNT_DEPTH, WEAPON_MOUNT_DEPTH + 1):
			var dist := absi(dx) + absi(dy)
			if dist < 1 or dist > WEAPON_MOUNT_DEPTH:
				continue
			var n := cell + Vector2i(dx, dy)
			var neighbor := get_structure_at(n)
			if neighbor == null or neighbor.data == null:
				continue
			if neighbor.instance_id == ignore_instance_id:
				continue
			if neighbor.data.category == ModuleData.Category.HULL:
				best = mini(best, dist)
	return best


## True if `cell` is within WEAPON_MOUNT_DEPTH of any cell in `hull_cells`.
static func _cell_in_weapon_truss(cell: Vector2i, hull_cells: Dictionary) -> bool:
	for dy in range(-WEAPON_MOUNT_DEPTH, WEAPON_MOUNT_DEPTH + 1):
		for dx in range(-WEAPON_MOUNT_DEPTH, WEAPON_MOUNT_DEPTH + 1):
			var dist := absi(dx) + absi(dy)
			if dist < 1 or dist > WEAPON_MOUNT_DEPTH:
				continue
			if hull_cells.has(cell + Vector2i(dx, dy)):
				return true
	return false


## Empty truss cell orthogonally adjacent to at least one normal DECK (not ENGINE_MOUNT).
## Used by corrective engines and weapons.
func is_deck_adjacent_truss_cell(cell: Vector2i, ignore_instance_id: int = -1) -> bool:
	if not is_weapon_mount_cell(cell, ignore_instance_id):
		return false
	for d: Vector2i in _DIRS:
		if get_floor_type(cell + d) == HullData.FloorType.DECK:
			return true
	return false


## Deck-adjacent truss of a hull being relocated (floor not yet written).
static func _cell_is_deck_adjacent_truss_on_hull(
	cell: Vector2i,
	hull_cells: Dictionary,
	hull_origin: Vector2i,
	hull_rotation: int,
	hull: HullData
) -> bool:
	if hull_cells.has(cell):
		return false
	if not _cell_in_weapon_truss(cell, hull_cells):
		return false
	for d: Vector2i in _DIRS:
		var n := cell + d
		if not hull_cells.has(n):
			continue
		var local := world_delta_to_local(n - hull_origin, hull_rotation, hull)
		if hull.get_local_floor(local) == HullData.FloorType.DECK:
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
				and is_deck_adjacent_truss_cell(cell)
			)
		_:
			if data.is_main_engine():
				# Orange mount only, or empty truss (≥1 ENGINE_MOUNT checked in can_place).
				if get_floor_type(cell) == HullData.FloorType.ENGINE_MOUNT:
					return get_equipment_at(cell) == null
				return (
					get_structure_at(cell) == null
					and get_equipment_at(cell) == null
					and is_weapon_mount_cell(cell)
				)
			if data.is_rcs_engine():
				return (
					get_structure_at(cell) == null
					and get_equipment_at(cell) == null
					and is_deck_adjacent_truss_cell(cell)
				)
			if data.is_deck_equipment():
				return _equipment_floor_ok(data, cell) and get_equipment_at(cell) == null
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

	if data.is_main_engine():
		if not _cells_touch_floor(cells, HullData.FloorType.ENGINE_MOUNT):
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
				ModuleData.Category.WEAPON:
					if not _cell_is_deck_adjacent_truss_on_hull(
						cell, hull_cells, origin, rotation, hull_module.hull_data
					):
						return false
				_:
					if c_data.is_main_engine():
						# Orange mount cells, or overhanging onto the truss — not regular deck.
						if hull_cells.has(cell):
							var local_floor := world_delta_to_local(
								cell - origin, rotation, hull_module.hull_data
							)
							if (
								hull_module.hull_data.get_local_floor(local_floor)
								!= HullData.FloorType.ENGINE_MOUNT
							):
								return false
						elif not _cell_in_weapon_truss(cell, hull_cells):
							return false
					elif c_data.is_rcs_engine():
						if not _cell_is_deck_adjacent_truss_on_hull(
							cell, hull_cells, origin, rotation, hull_module.hull_data
						):
							return false
					elif c_data.is_deck_equipment():
						if not hull_cells.has(cell):
							return false
						var local_floor := world_delta_to_local(cell - origin, rotation, hull_module.hull_data)
						if not _equipment_floor_type_ok(
							c_data, hull_module.hull_data.get_local_floor(local_floor)
						):
							return false
					else:
						return false
		if c_data.category == ModuleData.Category.ENGINE:
			var cargo_cells := c_data.get_occupied_cells(world_origin, c_rot)
			if c_data.is_main_engine():
				if not _cells_touch_floor_on_hull(
					cargo_cells, origin, rotation, hull_module.hull_data, HullData.FloorType.ENGINE_MOUNT
				):
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


## Bounding box (in cells) of every placed module; zero-size Rect2i if nothing is built.
func get_occupied_bounds() -> Rect2i:
	var min_c := Vector2i(999999, 999999)
	var max_c := Vector2i(-999999, -999999)
	var has_cells := false
	for module: PlacedModule in _modules.values():
		if module.data == null:
			continue
		for cell: Vector2i in module.get_occupied_cells():
			has_cells = true
			min_c = Vector2i(mini(min_c.x, cell.x), mini(min_c.y, cell.y))
			max_c = Vector2i(maxi(max_c.x, cell.x), maxi(max_c.y, cell.y))
	if not has_cells:
		return Rect2i()
	return Rect2i(min_c, max_c - min_c + Vector2i.ONE)


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


## Ship-level (not per-hull): ≥1 corrective engine on each outer side
## except the side that carries the main engines / ENGINE_MOUNT.
## Sides: 0=top(min_y), 1=right(max_x), 2=bottom(max_y), 3=left(min_x).
func are_ship_rcs_sides_covered() -> bool:
	var hull_cells := _collect_hull_cells()
	if hull_cells.is_empty():
		return true
	var bbox := _cells_bbox(hull_cells)
	var main_side := _ship_main_engine_side(hull_cells, bbox)
	var covered: Array[bool] = [false, false, false, false]
	for m: PlacedModule in _modules.values():
		if m.data == null or not m.data.is_rcs_engine():
			continue
		var side := _rcs_module_ship_side(m, hull_cells, bbox, main_side)
		if side >= 0 and side < covered.size():
			covered[side] = true
	for s in 4:
		if s == main_side:
			continue
		if not covered[s]:
			return false
	return true


func _collect_hull_cells() -> Dictionary:
	var hull_cells: Dictionary = {}
	for cell: Vector2i in _structure.keys():
		var s := get_structure_at(cell)
		if s == null or s.data == null:
			continue
		if s.data.category == ModuleData.Category.HULL:
			hull_cells[cell] = true
	return hull_cells


static func _cells_bbox(cells: Dictionary) -> Rect2i:
	var first := true
	var min_c := Vector2i.ZERO
	var max_c := Vector2i.ZERO
	for cell: Vector2i in cells.keys():
		if first:
			min_c = cell
			max_c = cell
			first = false
		else:
			min_c = Vector2i(mini(min_c.x, cell.x), mini(min_c.y, cell.y))
			max_c = Vector2i(maxi(max_c.x, cell.x), maxi(max_c.y, cell.y))
	return Rect2i(min_c, max_c - min_c + Vector2i.ONE)


## Dominant ship side that holds ENGINE_MOUNT tiles on the hull AABB perimeter.
func _ship_main_engine_side(hull_cells: Dictionary, bbox: Rect2i) -> int:
	var counts: Array[int] = [0, 0, 0, 0] # N, E, S, W
	var min_c := bbox.position
	var max_c := bbox.position + bbox.size - Vector2i.ONE
	for cell: Vector2i in hull_cells.keys():
		if get_floor_type(cell) != HullData.FloorType.ENGINE_MOUNT:
			continue
		if cell.y == min_c.y:
			counts[0] += 1
		if cell.x == max_c.x:
			counts[1] += 1
		if cell.y == max_c.y:
			counts[2] += 1
		if cell.x == min_c.x:
			counts[3] += 1
	# Prefer a side that also has a placed main engine.
	var engine_boost: Array[int] = [0, 0, 0, 0]
	for m: PlacedModule in _modules.values():
		if m.data == null or not m.data.is_main_engine():
			continue
		for cell: Vector2i in m.get_occupied_cells():
			if get_floor_type(cell) != HullData.FloorType.ENGINE_MOUNT:
				continue
			if cell.y == min_c.y:
				engine_boost[0] += 2
			if cell.x == max_c.x:
				engine_boost[1] += 2
			if cell.y == max_c.y:
				engine_boost[2] += 2
			if cell.x == min_c.x:
				engine_boost[3] += 2
	var best := 3 # default west (authoring left / aft)
	var best_score := -1
	for s in 4:
		var score: int = counts[s] + engine_boost[s]
		if score > best_score:
			best_score = score
			best = s
	return best


## One RCS module covers one non-main ship side (corner prefers a required side).
func _rcs_module_ship_side(
	module: PlacedModule,
	hull_cells: Dictionary,
	bbox: Rect2i,
	main_side: int
) -> int:
	var min_c := bbox.position
	var max_c := bbox.position + bbox.size - Vector2i.ONE
	for cell: Vector2i in module.get_occupied_cells():
		var hits: Array[int] = []
		for d: Vector2i in _DIRS:
			var n := cell + d
			if not hull_cells.has(n):
				continue
			if n.y == min_c.y:
				hits.append(0)
			if n.x == max_c.x:
				hits.append(1)
			if n.y == max_c.y:
				hits.append(2)
			if n.x == min_c.x:
				hits.append(3)
		for s in hits:
			if s != main_side:
				return s
	return -1


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
			# Weapons / RCS on deck-adjacent truss of this hull.
			if m.data.category == ModuleData.Category.WEAPON or m.data.is_rcs_engine():
				for d: Vector2i in _DIRS:
					var n := cell + d
					if not hull_cells.has(n):
						continue
					if get_floor_type(n) == HullData.FloorType.DECK:
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
	# RCS, like weapons, never sits on a structure cell.
	if get_structure_at(cell) != null:
		var s2 := get_structure_at(cell)
		if s2.instance_id != ignore_instance_id:
			if data.category == ModuleData.Category.WEAPON or data.is_rcs_engine():
				return false
	match data.category:
		ModuleData.Category.WEAPON:
			return is_deck_adjacent_truss_cell(cell, ignore_instance_id)
		_:
			if data.is_main_engine():
				return _main_engine_cell_ok(cell, ignore_instance_id)
			if data.is_rcs_engine():
				return is_deck_adjacent_truss_cell(cell, ignore_instance_id)
			if data.is_deck_equipment():
				return _equipment_floor_ok(data, cell)
			return false


func _equipment_floor_ok(data: ModuleData, cell: Vector2i) -> bool:
	return _equipment_floor_type_ok(data, get_floor_type(cell))


## Main engines: orange ENGINE_MOUNT only, or empty truss (can_place requires ≥1 ENGINE_MOUNT).
func _main_engine_cell_ok(cell: Vector2i, ignore_instance_id: int = -1) -> bool:
	if get_floor_type(cell) == HullData.FloorType.ENGINE_MOUNT:
		return true
	return is_weapon_mount_cell(cell, ignore_instance_id)


func _equipment_floor_type_ok(_data: ModuleData, floor: HullData.FloorType) -> bool:
	# General deck gear on DECK / ENGINE_MOUNT.
	# Main / RCS engines use their own truss / mount checks.
	return HullData.is_deck_floor(floor)


func _cells_touch_floor(cells: Array[Vector2i], floor: HullData.FloorType) -> bool:
	for cell: Vector2i in cells:
		if get_floor_type(cell) == floor:
			return true
	return false


## Same rule while a hull+cargo ghost is being relocated (floor not yet written).
func _cells_touch_floor_on_hull(
	cells: Array[Vector2i],
	hull_origin: Vector2i,
	hull_rotation: int,
	hull: HullData,
	floor: HullData.FloorType
) -> bool:
	if hull == null:
		return false
	for cell: Vector2i in cells:
		var local := world_delta_to_local(cell - hull_origin, hull_rotation, hull)
		if hull.get_local_floor(local) == floor:
			return true
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
		if d.is_rcs_engine():
			stats.correction_thrust += d.thrust
		else:
			stats.thrust += d.thrust
		stats.fuel_consumption += d.fuel_consumption
		stats.fuel_capacity += d.fuel_capacity
		stats.damage += d.damage
		stats.energy_generation += d.energy_generation
		stats.energy_capacity += d.capacity
		stats.shield_strength += d.shield_strength
		stats.repair_rate += d.repair_rate
		if d.is_main_engine() and d.max_heat > stats.max_heat:
			stats.max_heat = d.max_heat
	stats.health += stats.durability
	stats.hulls_linked = are_hulls_connected()
	stats.rcs_sides_ok = are_ship_rcs_sides_covered()
	_cached_stats = stats
	stats_changed.emit(stats.to_dictionary())

class_name ShipHull
extends Node2D
## Shipyard build grid with two layers:
##   structure  - HULL pieces + CONNECTOR
##   equipment  - engines/utilities on DECK / mounts; weapons on the outer truss ring
##
## Rules:
##   - Hull pieces and the cockpit may not touch each other edge-to-edge (must use a connector).
##   - Main engines stand in open space on a hull's left (aft) side: grid -x, whatever
##     way the hull is turned. At least one engine cell must touch the hull's left face.
##   - Corrective / RCS engines only on truss cells adjacent to DECK.
##   - Weapons: every cell on the truss ring (or a truss beam), and at least one
##     anchored - next to DECK or on a beam - so a long gun can stick out. A gun
##     may not face the ship: no hull or cockpit straight ahead of its muzzle.
##   - Ship-wide: ≥1 RCS on each outer side except the left (main-engine) side.
##   - Truss itself: empty cells within WEAPON_MOUNT_DEPTH of a hull or truss beam.
##   - TRUSS beams go on the truss ring (so they can chain outward); weapons may stand on them.
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
const WEAPON_MOUNT_DEPTH := 3
## Main engines go on this side of a hull - the build grid's left, never turned
## with the hull (the shipyard view can still be rotated around it).
const AFT := Vector2i(-1, 0)
## Ship side the main engines push from (see are_ship_rcs_sides_covered).
const AFT_SIDE := 3

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
			"scan_time": module.data.scan_time,
			"energy": module.data.energy_consumption,
			"turret_arc": module.data.turret_arc_deg,
			# Where the turret turns about: the module's middle.
			"center": (FovUtil.module_center_cell(module.origin, module.data, module.rotation) - centroid)
				* FovUtil.WORLD_UNITS_PER_CELL,
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
		if _is_open_frame(cell):
			continue
		var c := Vector2(cell) + Vector2(0.5, 0.5) - centroid
		var local := c * FovUtil.WORLD_UNITS_PER_CELL
		rects.append(Rect2(local - Vector2(half, half), Vector2(half, half) * 2.0))
	return rects


## Structure cells for shipyard LOS (hull + connector).
func get_structure_blocker_cells() -> Dictionary:
	var cells: Dictionary = {}
	for cell: Vector2i in _structure.keys():
		if not _is_open_frame(cell):
			cells[cell] = true
	return cells


## Truss beams are an open lattice: they never block a gun's or radar's view.
func _is_open_frame(cell: Vector2i) -> bool:
	var s := get_structure_at(cell)
	return s != null and s.data != null and s.data.category == ModuleData.Category.TRUSS


## Middle of the ship's structure, in cells - the origin of its ship-local
## space (weapon mounts, the picture in space).
func structure_centroid() -> Vector2:
	return _structure_centroid_cells()


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


## Every cell that is not empty space, for drawing: structure (hulls,
## connectors) plus equipment.
func get_used_cells() -> Array:
	var cells: Dictionary = _structure.duplicate()
	cells.merge(_equipment)
	return cells.keys()


## All weapon-truss cells at once (same rule as is_weapon_mount_cell), built by
## spreading out from the hull cells - far cheaper than asking cell by cell
## over the whole build grid.
func get_weapon_mount_cells() -> Dictionary:
	var result: Dictionary = {}
	for hull_cell: Vector2i in _collect_frame_cells().keys():
		for dy in range(-WEAPON_MOUNT_DEPTH, WEAPON_MOUNT_DEPTH + 1):
			for dx in range(-WEAPON_MOUNT_DEPTH, WEAPON_MOUNT_DEPTH + 1):
				var dist := absi(dx) + absi(dy)
				if dist < 1 or dist > WEAPON_MOUNT_DEPTH:
					continue
				var n := hull_cell + Vector2i(dx, dy)
				if is_cell_in_bounds(n) and get_structure_at(n) == null:
					result[n] = true
	return result


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
			if neighbor.data.is_frame():
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


func is_truss_beam_cell(cell: Vector2i, ignore_instance_id: int = -1) -> bool:
	var s := get_structure_at(cell)
	return (
		s != null and s.data != null and s.instance_id != ignore_instance_id
		and s.data.category == ModuleData.Category.TRUSS
	)


## Empty truss cell orthogonally adjacent to at least one DECK cell.
## Used by corrective engines and weapons.
func is_deck_adjacent_truss_cell(cell: Vector2i, ignore_instance_id: int = -1) -> bool:
	if not is_weapon_mount_cell(cell, ignore_instance_id):
		return false
	for d: Vector2i in _DIRS:
		if get_floor_type(cell + d) == HullData.FloorType.DECK:
			return true
	return false


## How far ahead of a gun its line of fire is checked for the ship's own hull.
const WEAPON_CLEAR_AHEAD := 12


## True if a gun turned this way would fire into the ship: a hull or cockpit
## cell straight ahead of any of its cells, in the direction it faces.
func _weapon_faces_ship(cells: Array[Vector2i], rotation: int, ignore_instance_id: int = -1) -> bool:
	var facing: Vector2 = FovUtil.local_facing(rotation)
	var step := Vector2i(roundi(facing.x), roundi(facing.y))
	var own: Dictionary = {}
	for cell: Vector2i in cells:
		own[cell] = true
	for cell: Vector2i in cells:
		for k in range(1, WEAPON_CLEAR_AHEAD + 1):
			var ahead: Vector2i = cell + step * k
			if own.has(ahead):
				continue
			var s := get_structure_at(ahead)
			if s != null and s.data != null and s.instance_id != ignore_instance_id and s.data.is_hull_like():
				return true
	return false


## A weapon cell that holds the gun to the ship: on a truss beam, or an empty
## truss cell right next to DECK.
func _weapon_anchor(cell: Vector2i, ignore_instance_id: int = -1) -> bool:
	return is_truss_beam_cell(cell, ignore_instance_id) or is_deck_adjacent_truss_cell(cell, ignore_instance_id)


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
		ModuleData.Category.HULL, ModuleData.Category.CONNECTOR, ModuleData.Category.COCKPIT:
			return get_structure_at(cell) == null and get_equipment_at(cell) == null
		ModuleData.Category.TRUSS:
			return (
				get_structure_at(cell) == null
				and get_equipment_at(cell) == null
				and is_weapon_mount_cell(cell)
			)
		ModuleData.Category.WEAPON:
			if get_equipment_at(cell) != null:
				return false
			if is_truss_beam_cell(cell):
				return true
			return is_weapon_mount_cell(cell)
		_:
			if data.is_main_engine():
				# Open space; touching a hull's left face is checked in can_place.
				return get_structure_at(cell) == null and get_equipment_at(cell) == null
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
	if not data.is_rotatable() and posmod(rotation, 4) != 0:
		return false

	var cells := data.get_occupied_cells(origin, rotation)

	if data.uses_deck_slot():
		var equip_count := _count_equipment_cells(ignore_instance_id)
		var cap := _total_hull_capacity(ignore_instance_id)
		if equip_count + cells.size() > cap:
			return false

	for cell: Vector2i in cells:
		if not is_cell_in_bounds(cell):
			return false
		if not _cell_free_for(data, cell, ignore_instance_id):
			return false

	if data.is_hull_like():
		if _hull_would_touch_other_hull(cells, ignore_instance_id):
			return false

	# A connector joins things: it must touch a hull, the cockpit or another
	# connector, never float on its own.
	if data.category == ModuleData.Category.CONNECTOR:
		if not _touches_solid_structure(cells, ignore_instance_id):
			return false

	if data.category == ModuleData.Category.TRUSS:
		for cell: Vector2i in cells:
			if not is_weapon_mount_cell(cell, ignore_instance_id):
				return false

	if data.category == ModuleData.Category.WEAPON:
		if not cells.any(func(cell: Vector2i) -> bool: return _weapon_anchor(cell, ignore_instance_id)):
			return false
		if _weapon_faces_ship(cells, rotation, ignore_instance_id):
			return false

	if data.is_main_engine():
		if not _cells_behind_hull(cells, ignore_instance_id):
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
		# Main engines stay facing aft even when their hull turns.
		var c_rot := posmod(int(item["rotation"]) + drot, 4) if c_data.is_rotatable() else 0
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
					# On the moved hull's ring; anchoring is checked for the whole gun below.
					if hull_cells.has(cell) or not _cell_in_weapon_truss(cell, hull_cells):
						return false
				_:
					if c_data.is_main_engine():
						# Open space only - never on the hull itself.
						if hull_cells.has(cell):
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
		if c_data.is_main_engine():
			if not _cells_left_of(c_data.get_occupied_cells(world_origin, c_rot), hull_cells):
				return false
		if c_data.category == ModuleData.Category.WEAPON:
			if not cells.any(func(cell: Vector2i) -> bool:
				return _cell_is_deck_adjacent_truss_on_hull(cell, hull_cells, origin, rotation, hull_module.hull_data)
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
		# Main engines stay facing aft even when their hull turns.
		var c_rot := posmod(int(item["rotation"]) + drot, 4) if c_data.is_rotatable() else 0
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
	return unconnected_hull_like().is_empty()


## Hulls and cockpits not joined (through connectors and other structure) to
## the first hull - what keeps a ship from leaving the yard.
func unconnected_hull_like() -> Array[PlacedModule]:
	var hulls: Array[PlacedModule] = []
	for m: PlacedModule in _modules.values():
		if m.data != null and m.data.is_hull_like():
			hulls.append(m)
	var loose: Array[PlacedModule] = []
	if hulls.size() <= 1:
		return loose
	# Grow from a real hull when there is one, so a lone cockpit is the loose part.
	hulls.sort_custom(func(a: PlacedModule, b: PlacedModule) -> bool:
		return a.data.category == ModuleData.Category.HULL and b.data.category != ModuleData.Category.HULL
	)
	var start_cells := hulls[0].get_occupied_cells()
	if start_cells.is_empty():
		return loose
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
		if not visited.has(h.get_occupied_cells()[0]):
			loose.append(h)
	return loose


## Ship-level (not per-hull): ≥1 corrective engine on each outer side
## except the left one, where the main engines are (AFT_SIDE).
## Sides: 0=top(min_y), 1=right(max_x), 2=bottom(max_y), 3=left(min_x).
func are_ship_rcs_sides_covered() -> bool:
	var hull_cells := _collect_hull_cells()
	if hull_cells.is_empty():
		return true
	var bbox := _cells_bbox(hull_cells)
	var main_side := AFT_SIDE
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


## Hull and truss cells - what the weapon-mount ring grows from.
func _collect_frame_cells() -> Dictionary:
	var cells: Dictionary = {}
	for cell: Vector2i in _structure.keys():
		var s := get_structure_at(cell)
		if s != null and s.data != null and s.data.is_frame():
			cells[cell] = true
	return cells


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
			# Main engines hanging off this hull's left face.
			if m.data.is_main_engine() and hull_cells.has(cell - AFT):
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
	# Weapons stand on truss beams; otherwise, like RCS, never on structure.
	if data.category == ModuleData.Category.WEAPON and is_truss_beam_cell(cell, ignore_instance_id):
		return true
	if get_structure_at(cell) != null:
		var s2 := get_structure_at(cell)
		if s2.instance_id != ignore_instance_id:
			if data.category == ModuleData.Category.WEAPON or data.is_rcs_engine():
				return false
	match data.category:
		ModuleData.Category.WEAPON:
			return is_weapon_mount_cell(cell, ignore_instance_id)
		_:
			if data.is_main_engine():
				# Open space only; must not overlap any hull or truss.
				var s3 := get_structure_at(cell)
				return s3 == null or s3.instance_id == ignore_instance_id
			if data.is_rcs_engine():
				return is_deck_adjacent_truss_cell(cell, ignore_instance_id)
			if data.is_deck_equipment():
				return _equipment_floor_ok(data, cell)
			return false


func _equipment_floor_ok(data: ModuleData, cell: Vector2i) -> bool:
	return _equipment_floor_type_ok(data, get_floor_type(cell))


func _equipment_floor_type_ok(_data: ModuleData, floor: HullData.FloorType) -> bool:
	# General deck gear on DECK.
	# Main / RCS engines use their own open-space / truss checks.
	return HullData.is_deck_floor(floor)


## Main engine footprint touches a hull's left face: some cell has a hull
## cell straight to its right (the AFT rule).
func _cells_behind_hull(cells: Array[Vector2i], ignore_instance_id: int = -1) -> bool:
	for cell: Vector2i in cells:
		var s := get_structure_at(cell - AFT)
		if (
			s != null and s.data != null and s.instance_id != ignore_instance_id
			and s.data.category == ModuleData.Category.HULL
		):
			return true
	return false


## Same rule while a hull+cargo ghost is being relocated (hull not yet written).
static func _cells_left_of(cells: Array[Vector2i], hull_cells: Dictionary) -> bool:
	for cell: Vector2i in cells:
		if hull_cells.has(cell - AFT):
			return true
	return false


func _touches_solid_structure(cells: Array[Vector2i], ignore_instance_id: int) -> bool:
	var own: Dictionary = {}
	for c: Vector2i in cells:
		own[c] = true
	for c: Vector2i in cells:
		for d: Vector2i in _DIRS:
			var n := c + d
			if own.has(n):
				continue
			var s := get_structure_at(n)
			if s == null or s.data == null or s.instance_id == ignore_instance_id:
				continue
			if s.data.is_hull_like() or s.data.category == ModuleData.Category.CONNECTOR:
				return true
	return false


## Modules that no longer hold to the ship - each checked against the rules
## as if placed now, among the rest (a gun whose truss was taken away, an
## engine off the hull, a connector left touching nothing) - plus connectors
## not joined to the hulls. Leaving the yard needs this empty.
func unattached_modules() -> Array[PlacedModule]:
	var loose: Array[PlacedModule] = []
	for m: PlacedModule in _modules.values():
		if m.data == null or m.data.is_hull_like():
			continue
		if not can_place(m.data, m.origin, m.rotation, m.instance_id):
			loose.append(m)
	# Connectors must also lead back to the hulls, not just touch each other.
	var reached: Dictionary = _structure_reached_from_first_hull()
	if not reached.is_empty():
		for m: PlacedModule in _modules.values():
			if m.data != null and m.data.category == ModuleData.Category.CONNECTOR and not loose.has(m):
				if not reached.has(m.get_occupied_cells()[0]):
					loose.append(m)
	return loose


## Every structure cell reachable, edge to edge, from the first hull.
func _structure_reached_from_first_hull() -> Dictionary:
	var start: PlacedModule = null
	for m: PlacedModule in _modules.values():
		if m.data != null and m.data.category == ModuleData.Category.HULL:
			start = m
			break
	var visited: Dictionary = {}
	if start == null:
		return visited
	var first: Vector2i = start.get_occupied_cells()[0]
	var queue: Array[Vector2i] = [first]
	visited[first] = true
	while not queue.is_empty():
		var c: Vector2i = queue.pop_front()
		for d: Vector2i in _DIRS:
			var n := c + d
			if visited.has(n) or get_structure_at(n) == null:
				continue
			visited[n] = true
			queue.append(n)
	return visited


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
			if s.data.is_hull_like():
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
		if m.data == null or not m.data.uses_deck_slot():
			continue
		if m.instance_id == ignore_instance_id:
			continue
		count += m.data.get_cell_count()
	return count


func _total_hull_capacity(ignore_instance_id: int = -1) -> int:
	var cap := 0
	for m: PlacedModule in _modules.values():
		if m.data == null or m.instance_id == ignore_instance_id:
			continue
		if m.data.category != ModuleData.Category.HULL:
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
		if d.uses_deck_slot():
			stats.occupied_cells += d.get_cell_count()
		stats.energy_consumption += d.energy_consumption
		match d.category:
			ModuleData.Category.ENGINE:
				stats.energy_engines += d.energy_consumption
			ModuleData.Category.SHIELD:
				stats.energy_shields += d.energy_consumption
			ModuleData.Category.WEAPON:
				stats.energy_weapons += d.energy_consumption
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

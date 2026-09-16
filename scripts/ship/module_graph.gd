class_name ModuleGraph
extends RefCounted

var modules: Array[ShipModule] = []
var _stats := ShipStats.new()
var _dirty: bool = true


func clear() -> void:
	modules.clear()
	_dirty = true


func add_module(module: ShipModule) -> bool:
	if module == null or module.def == null:
		return false
	if not can_place(module.def, module.grid_pos, module.rotation_steps, module):
		return false
	modules.append(module)
	_dirty = true
	return true


func remove_at(cell: Vector2i) -> bool:
	var target := module_at(cell)
	if target == null:
		return false
	modules.erase(target)
	_dirty = true
	return true


func module_at(cell: Vector2i) -> ShipModule:
	for module in modules:
		if module.occupied_cells().has(cell):
			return module
	return null


func occupied_cells() -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for module in modules:
		for cell in module.occupied_cells():
			cells.append(cell)
	return cells


func can_place(def: ModuleDef, pos: Vector2i, rot: int, ignore: ShipModule = null) -> bool:
	if def == null:
		return false
	var proposed: Array[Vector2i] = []
	for offset in def.occupied:
		proposed.append(pos + ModuleDef.rotate_cell(offset, rot))
	for cell in proposed:
		var occupant := module_at(cell)
		if occupant != null and occupant != ignore:
			return false
	if modules.is_empty() or (modules.size() == 1 and modules[0] == ignore):
		return true
	for cell in proposed:
		for neighbor in _neighbors(cell):
			var occupant := module_at(neighbor)
			if occupant != null and occupant != ignore:
				return true
	return false


func is_structure_connected() -> bool:
	return connected_components().size() <= 1


func connected_components() -> Array:
	var remaining: Array[ShipModule] = modules.duplicate()
	var groups: Array = []
	while not remaining.is_empty():
		var seed: ShipModule = remaining.pop_back()
		var group: Array[ShipModule] = [seed]
		var queue: Array[ShipModule] = [seed]
		while not queue.is_empty():
			var current: ShipModule = queue.pop_back()
			for other in remaining.duplicate():
				if _modules_adjacent(current, other):
					remaining.erase(other)
					group.append(other)
					queue.append(other)
		groups.append(group)
	return groups


func stats() -> ShipStats:
	if _dirty:
		_recompute()
	return _stats


func consume_fuel(amount: float) -> float:
	if amount <= 0.0:
		return 0.0
	var total := 0.0
	for module in modules:
		total += module.fuel
	if total <= 0.0001:
		return 0.0
	var taken := minf(amount, total)
	var ratio := taken / total
	for module in modules:
		module.fuel *= (1.0 - ratio)
	_dirty = true
	return taken


func refill_fuel() -> void:
	for module in modules:
		if module.def:
			module.fuel = module.def.fuel_capacity
	_dirty = true


func restore_hull() -> void:
	for module in modules:
		if module.def:
			module.hp = module.def.hp_max
	_dirty = true


func apply_hull_damage(amount: float) -> void:
	if modules.is_empty() or amount <= 0.0:
		return
	var share := amount / float(modules.size())
	for module in modules:
		module.hp = maxf(0.0, module.hp - share)
	_dirty = true


func fuel_total() -> float:
	return stats().fuel


func fuel_max() -> float:
	return stats().fuel_max


func set_fuel_total(value: float) -> void:
	var cap := fuel_max()
	if cap <= 0.0:
		return
	var fraction := clampf(value / cap, 0.0, 1.0)
	for module in modules:
		if module.def:
			module.fuel = module.def.fuel_capacity * fraction
	_dirty = true


func to_blueprint() -> Dictionary:
	var entries: Array = []
	for module in modules:
		if module.def == null:
			continue
		entries.append({
			"type": module.def.id,
			"x": module.grid_pos.x,
			"y": module.grid_pos.y,
			"rotation": module.rotation_steps,
		})
	return {"modules": entries}


func load_blueprint(data: Dictionary) -> bool:
	clear()
	var entries: Array = data.get("modules", [])
	for entry in entries:
		var def := ModuleCatalog.get_def(String(entry.get("type", "")))
		if def == null:
			clear()
			return false
		var module := ShipModule.new(
			def,
			Vector2i(int(entry.get("x", 0)), int(entry.get("y", 0))),
			int(entry.get("rotation", 0))
		)
		modules.append(module)
	_dirty = true
	return not modules.is_empty()


func draw_on(canvas: CanvasItem, origin: Vector2, angle: float, draw_scale: float, throttle: float = 0.0, fuel_available: bool = true) -> void:
	var current := stats()
	canvas.draw_set_transform(origin, angle, Vector2(draw_scale, draw_scale))
	for module in modules:
		if module.def and module.def.role == "engine" and throttle > 0.04 and fuel_available:
			var nozzle := ModuleDef.rotate_point(Vector2(-1.05, 0.0), module.rotation_steps)
			var flame_tip := ModuleDef.rotate_point(Vector2(-1.05 - (0.55 + throttle * 0.85), 0.0), module.rotation_steps)
			var side := ModuleDef.rotate_point(Vector2(0.0, 0.22), module.rotation_steps)
			var center := module.center_meters() - current.com
			canvas.draw_colored_polygon(PackedVector2Array([
				center + nozzle + side,
				center + nozzle - side,
				center + flame_tip,
			]), Color(0.3, 0.72, 1.0, 0.8))
		var poly := module.world_polygon(current.com)
		if poly.size() >= 3:
			canvas.draw_colored_polygon(poly, module.def.fill if module.def else Color.WHITE)
	canvas.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func mark_dirty() -> void:
	_dirty = true


func _recompute() -> void:
	_dirty = false
	var result := ShipStats.new()
	var mass_sum := 0.0
	var com_acc := Vector2.ZERO
	for module in modules:
		var wet := module.wet_mass()
		mass_sum += wet
		com_acc += module.center_meters() * wet
		result.fuel += module.fuel
		if module.def:
			result.fuel_max += module.def.fuel_capacity
			result.rcs_thrust += module.def.rcs_thrust
			result.hull += module.hp
			result.hull_max += module.def.hp_max
			if module.def.role == "cockpit":
				result.cockpit_count += 1
			if module.def.role == "engine":
				result.engine_count += 1
	if mass_sum <= 0.0001:
		mass_sum = 1.0
	result.mass = mass_sum
	result.com = com_acc / mass_sum
	var inertia := 0.0
	var radius := 1.0
	var force := Vector2.ZERO
	var torque := 0.0
	for module in modules:
		var relative := module.center_meters() - result.com
		inertia += module.wet_mass() * relative.length_squared()
		radius = maxf(radius, relative.length() + 0.7)
		var thrust_vec := module.thrust_vector()
		if thrust_vec.length_squared() > 0.0:
			force += thrust_vec
			torque += relative.cross(thrust_vec)
	result.inertia = maxf(inertia, 0.4)
	result.radius = radius
	result.thrust_force = force
	result.thrust = force.length()
	result.thrust_torque = torque
	result.component_count = connected_components().size()
	_stats = result


func _modules_adjacent(a: ShipModule, b: ShipModule) -> bool:
	for cell in a.occupied_cells():
		for neighbor in _neighbors(cell):
			if b.occupied_cells().has(neighbor):
				return true
	return false


func _neighbors(cell: Vector2i) -> Array[Vector2i]:
	return [
		cell + Vector2i.RIGHT,
		cell + Vector2i.LEFT,
		cell + Vector2i.UP,
		cell + Vector2i.DOWN,
	]

class_name ShipModule
extends RefCounted

var def: ModuleDef
var grid_pos: Vector2i = Vector2i.ZERO
var rotation_steps: int = 0
var fuel: float = 0.0
var hp: float = 100.0


func _init(p_def: ModuleDef = null, p_pos: Vector2i = Vector2i.ZERO, p_rot: int = 0) -> void:
	def = p_def
	grid_pos = p_pos
	rotation_steps = posmod(p_rot, 4)
	if def:
		hp = def.hp_max
		fuel = def.fuel_capacity


func occupied_cells() -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	if def == null:
		return cells
	for offset in def.occupied:
		cells.append(grid_pos + ModuleDef.rotate_cell(offset, rotation_steps))
	return cells


func center_meters() -> Vector2:
	var acc := Vector2.ZERO
	var cells := occupied_cells()
	if cells.is_empty():
		return Vector2(grid_pos) + Vector2(0.5, 0.5)
	for cell in cells:
		acc += Vector2(cell) + Vector2(0.5, 0.5)
	return acc / float(cells.size())


func dry_mass() -> float:
	return def.mass if def else 0.0


func wet_mass() -> float:
	var density := def.fuel_mass_per_unit if def else 0.04
	return dry_mass() + fuel * density


func thrust_vector() -> Vector2:
	if def == null or def.thrust <= 0.0:
		return Vector2.ZERO
	return ModuleDef.rotate_point(Vector2.RIGHT, rotation_steps) * def.thrust


func world_polygon(com: Vector2) -> PackedVector2Array:
	var result := PackedVector2Array()
	if def == null or def.polygon.is_empty():
		var center := center_meters() - com
		result.append(center + Vector2(-0.4, -0.4))
		result.append(center + Vector2(0.4, -0.4))
		result.append(center + Vector2(0.4, 0.4))
		result.append(center + Vector2(-0.4, 0.4))
		return result
	var centroid := def.occupancy_centroid()
	for point in def.polygon:
		var local := ModuleDef.rotate_point(point, rotation_steps)
		var origin := Vector2(grid_pos) + ModuleDef.rotate_point(centroid, rotation_steps)
		result.append(origin + local - com)
	return result

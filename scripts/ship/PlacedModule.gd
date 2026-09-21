class_name PlacedModule
extends RefCounted
## Runtime instance of a ModuleData attached to a specific grid origin.

var data: ModuleData
var origin: Vector2i = Vector2i.ZERO
## 0–3: quarters clockwise from the ModuleData authoring orientation.
var rotation: int = 0
var instance_id: int = 0
var current_health: float = 0.0


func _init(
	p_data: ModuleData = null,
	p_origin: Vector2i = Vector2i.ZERO,
	p_id: int = 0,
	p_rotation: int = 0
) -> void:
	data = p_data
	origin = p_origin
	instance_id = p_id
	rotation = posmod(p_rotation, 4)
	if data != null:
		current_health = data.health


func get_occupied_cells() -> Array[Vector2i]:
	if data == null:
		return []
	return data.get_occupied_cells(origin, rotation)


func get_bounding_size() -> Vector2i:
	if data == null:
		return Vector2i.ZERO
	return data.get_bounding_size(rotation)


func is_destroyed() -> bool:
	return current_health <= 0.0


func apply_damage(amount: float) -> void:
	current_health = maxf(0.0, current_health - amount)

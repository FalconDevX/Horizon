class_name ModuleDef
extends Resource

@export var id: String = ""
@export var display_name: String = ""
@export var category: String = "hull"
@export var role: String = "frame"
@export var occupied: Array[Vector2i] = []
@export var mass: float = 1.0
@export var fuel_capacity: float = 0.0
@export var fuel_mass_per_unit: float = 0.04
@export var thrust: float = 0.0
@export var rcs_thrust: float = 0.0
@export var hp_max: float = 100.0
@export var fill: Color = Color("#c5d0de")
@export var polygon: PackedVector2Array = PackedVector2Array()


static func rotate_cell(cell: Vector2i, steps: int) -> Vector2i:
	var turns := posmod(steps, 4)
	match turns:
		1:
			return Vector2i(-cell.y, cell.x)
		2:
			return Vector2i(-cell.x, -cell.y)
		3:
			return Vector2i(cell.y, -cell.x)
		_:
			return cell


static func rotate_point(point: Vector2, steps: int) -> Vector2:
	var turns := posmod(steps, 4)
	match turns:
		1:
			return Vector2(-point.y, point.x)
		2:
			return -point
		3:
			return Vector2(point.y, -point.x)
		_:
			return point


func occupancy_centroid() -> Vector2:
	if occupied.is_empty():
		return Vector2(0.5, 0.5)
	var acc := Vector2.ZERO
	for cell in occupied:
		acc += Vector2(cell) + Vector2(0.5, 0.5)
	return acc / float(occupied.size())

class_name ModuleData
extends Resource
## Blueprint for a placeable ship module.

enum Category {
	HULL,
	ENGINE,
	WEAPON,
	UTILITY,
	FUEL_TANK,
	BATTERY,
	SHIELD,
	CONNECTOR, ## 1×1 łącznik — bridges separate hull pieces
}

@export var title: String = "Module"
@export var category: Category = Category.UTILITY
@export var grid_shape: Array[Vector2i] = [Vector2i.ZERO]
@export var texture: Texture2D
@export var id: StringName = &""

## For Category.HULL — defines local size, mass, capacity, truss ring.
@export var hull_data: HullData

@export_group("Shared")
@export var mass: float = 1.0
@export var health: float = 10.0
@export var energy_consumption: float = 0.0

@export_group("Engine")
@export var thrust: float = 0.0
@export var fuel_consumption: float = 0.0
@export var max_heat: float = 100.0

@export_group("Weapon")
@export var damage: float = 0.0
@export var reload_time: float = 1.0
@export var accuracy: float = 1.0

@export_group("Utility")
@export var capacity: float = 0.0
@export var fuel_capacity: float = 0.0
@export var energy_generation: float = 0.0
@export var repair_rate: float = 0.0

@export_group("Shield")
@export var shield_strength: float = 0.0

@export_group("Extras")
@export var custom_stats: Dictionary = {}


func is_structure() -> bool:
	return category == Category.HULL or category == Category.CONNECTOR


func is_equipment() -> bool:
	return (
		category == Category.ENGINE
		or category == Category.WEAPON
		or category == Category.UTILITY
		or category == Category.FUEL_TANK
		or category == Category.BATTERY
		or category == Category.SHIELD
	)


## Engines, utilities, tanks, batteries and shields mount on hull deck cells.
func is_deck_equipment() -> bool:
	return (
		category == Category.ENGINE
		or category == Category.UTILITY
		or category == Category.FUEL_TANK
		or category == Category.BATTERY
		or category == Category.SHIELD
	)


func get_cell_count() -> int:
	return grid_shape.size()


func get_bounding_size(rotation: int = 0) -> Vector2i:
	return bounding_size_of(get_shape(rotation))


func get_shape(rotation: int = 0) -> Array[Vector2i]:
	return rotate_shape(grid_shape, rotation)


func get_occupied_cells(origin: Vector2i, rotation: int = 0) -> Array[Vector2i]:
	var shape := get_shape(rotation)
	var result: Array[Vector2i] = []
	result.resize(shape.size())
	for i in shape.size():
		result[i] = origin + shape[i]
	return result


static func rotate_shape(shape: Array[Vector2i], quarters: int) -> Array[Vector2i]:
	var q := posmod(quarters, 4)
	if shape.is_empty():
		return []
	var rotated: Array[Vector2i] = []
	rotated.resize(shape.size())
	for i in shape.size():
		var c: Vector2i = shape[i]
		match q:
			0:
				rotated[i] = c
			1:
				rotated[i] = Vector2i(-c.y, c.x)
			2:
				rotated[i] = Vector2i(-c.x, -c.y)
			3:
				rotated[i] = Vector2i(c.y, -c.x)
	return normalize_shape(rotated)


static func normalize_shape(shape: Array[Vector2i]) -> Array[Vector2i]:
	if shape.is_empty():
		return []
	var min_x := shape[0].x
	var min_y := shape[0].y
	for c: Vector2i in shape:
		min_x = mini(min_x, c.x)
		min_y = mini(min_y, c.y)
	var result: Array[Vector2i] = []
	result.resize(shape.size())
	for i in shape.size():
		result[i] = shape[i] - Vector2i(min_x, min_y)
	return result


static func bounding_size_of(shape: Array[Vector2i]) -> Vector2i:
	if shape.is_empty():
		return Vector2i.ZERO
	var max_x := 0
	var max_y := 0
	for c: Vector2i in shape:
		max_x = maxi(max_x, c.x)
		max_y = maxi(max_y, c.y)
	return Vector2i(max_x + 1, max_y + 1)


func get_stat(key: StringName, default: Variant = 0.0) -> Variant:
	if custom_stats.has(key):
		return custom_stats[key]
	match String(key):
		"mass":
			return mass
		"health":
			return health
		"energy_consumption":
			return energy_consumption
		"thrust":
			return thrust
		"fuel_consumption":
			return fuel_consumption
		"max_heat":
			return max_heat
		"damage":
			return damage
		"reload_time":
			return reload_time
		"accuracy":
			return accuracy
		"capacity":
			return capacity
		"fuel_capacity":
			return fuel_capacity
		"energy_generation":
			return energy_generation
		"repair_rate":
			return repair_rate
		"shield_strength":
			return shield_strength
		_:
			return default


func category_name() -> String:
	match category:
		Category.HULL:
			return "Hull"
		Category.ENGINE:
			return "Engine"
		Category.WEAPON:
			return "Weapon"
		Category.UTILITY:
			return "Utility"
		Category.FUEL_TANK:
			return "Fuel Tank"
		Category.BATTERY:
			return "Battery"
		Category.SHIELD:
			return "Shield"
		Category.CONNECTOR:
			return "Connector"
		_:
			return "Unknown"

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
	CONNECTOR, ## 1x1 connector - bridges separate hull pieces
	RADAR,
	TRUSS, ## mounting frame: guns sit on it, and it reaches further out
	COCKPIT, ## the bridge: stands in open space like a hull, linked to one by a connector
}

@export var title: String = "Module"
@export var category: Category = Category.UTILITY
@export var grid_shape: Array[Vector2i] = [Vector2i.ZERO]
@export var texture: Texture2D
## Optional blueprint-style art shown while the module is being dragged or
## held over the grid; `texture` takes over once it is placed.
@export var plan_texture: Texture2D
@export var id: StringName = &""

## For Category.HULL — defines local size, mass (weapon truss is ShipHull.WEAPON_MOUNT_DEPTH).
@export var hull_data: HullData

@export_group("Shared")
@export var mass: float = 1.0
@export var health: float = 10.0
@export var energy_consumption: float = 0.0

@export_group("Engine")
@export var thrust: float = 0.0
@export var fuel_consumption: float = 0.0
@export var max_heat: float = 100.0
## When true, this engine is RCS-only (truss next to deck).
@export var is_corrective_engine: bool = false
## Engine family this size belongs to (e.g. "Chemical") and its star ratings
## [thrust, fuel, energy, mass] - the shipyard groups engines into rows by it.
@export var family: String = ""
@export var family_stars: Array[int] = []

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

@export_group("Field of View")
## Full cone angle in real degrees (same in builder preview and on the map).
@export var fov_angle_deg: float = 0.0
## Detection / engagement range in world SU. Builder preview scales this down.
@export var fov_range: float = 0.0

@export_group("Extras")
@export var custom_stats: Dictionary = {}


func is_structure() -> bool:
	return (
		category == Category.HULL
		or category == Category.CONNECTOR
		or category == Category.TRUSS
		or category == Category.COCKPIT
	)


## Hulls and truss beams: what the weapon-mount ring is measured from
## (ShipHull.WEAPON_MOUNT_DEPTH).
## Hulls and the cockpit: the big pieces that stand apart and are joined by
## connectors (ShipHull keeps them from touching edge to edge).
func is_hull_like() -> bool:
	return category == Category.HULL or category == Category.COCKPIT


func is_frame() -> bool:
	return category == Category.HULL or category == Category.TRUSS


func is_equipment() -> bool:
	return (
		category == Category.ENGINE
		or category == Category.WEAPON
		or category == Category.UTILITY
		or category == Category.FUEL_TANK
		or category == Category.BATTERY
		or category == Category.SHIELD
		or category == Category.RADAR
	)


## Modules that build inside a hull (on its deck cells).
## Excludes structure (Hull / Cockpit / Truss / Connector), engines and weapons —
## those have their own placement rules (open space, truss ring, etc.).
func is_deck_equipment() -> bool:
	return (
		not is_structure()
		and category != Category.ENGINE
		and category != Category.WEAPON
	)


func has_fov() -> bool:
	return fov_angle_deg > 0.0 and fov_range > 0.0


func is_radar() -> bool:
	return category == Category.RADAR


func is_weapon() -> bool:
	return category == Category.WEAPON


func is_main_engine() -> bool:
	return category == Category.ENGINE and not is_corrective_engine


## Main engines never turn: their nozzle always points to the grid's left
## (the aft, ShipHull.AFT). Rotating the shipyard view turns them with it.
func is_rotatable() -> bool:
	return not is_main_engine()


func is_rcs_engine() -> bool:
	return category == Category.ENGINE and is_corrective_engine


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
		"fov_angle_deg":
			return fov_angle_deg
		"fov_range":
			return fov_range
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
		Category.RADAR:
			return "Radar"
		Category.TRUSS:
			return "Truss"
		Category.COCKPIT:
			return "Cockpit"
		_:
			return "Unknown"

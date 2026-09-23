class_name HullData
extends Resource
## Blueprint for a placeable hull piece (local footprint + stats).

enum HullType {
	LIGHT,
	STANDARD,
	HEAVY,
}

enum FloorType {
	EMPTY, ## Shipyard void
	DECK, ## Hull floor (utilities / tanks / RCS / etc.)
	ENGINE_MOUNT, ## Left-edge tiles — main engines must touch at least one
	CONNECTOR, ## Connector cell
}

@export var title: String = "Standard"
@export var hull_type: HullType = HullType.STANDARD
@export var grid_size: Vector2i = Vector2i(5, 5)
@export var base_durability: float = 100.0
@export var base_mass: float = 50.0
@export var capacity: int = 20
@export var description: String = ""
@export var custom_texture: Texture2D = null ## Fixed art asset drawn instead of the procedural grid texture.
@export var interior_texture: Texture2D = null ## Overrides custom_texture on the build grid once the hull is placed (inventory icon still uses custom_texture).


func get_local_floor(local_cell: Vector2i) -> FloorType:
	if local_cell.x < 0 or local_cell.y < 0:
		return FloorType.EMPTY
	if local_cell.x >= grid_size.x or local_cell.y >= grid_size.y:
		return FloorType.EMPTY
	# Left column — main engine hardpoints.
	if local_cell.x == 0:
		return FloorType.ENGINE_MOUNT
	return FloorType.DECK


## Deck cells that may hold general equipment.
static func is_deck_floor(floor: FloorType) -> bool:
	return floor == FloorType.DECK or floor == FloorType.ENGINE_MOUNT


func make_rect_shape() -> Array[Vector2i]:
	var shape: Array[Vector2i] = []
	for y in grid_size.y:
		for x in grid_size.x:
			shape.append(Vector2i(x, y))
	return shape


static func make_light() -> HullData:
	var h := HullData.new()
	h.title = "Light"
	h.hull_type = HullType.LIGHT
	h.grid_size = Vector2i(5, 5)
	h.base_durability = 80.0
	h.base_mass = 30.0
	h.capacity = 12
	h.description = "Light hull, 5x5 - left edge main mounts, rest is deck."
	h.custom_texture = load("res://textures/hulls/hull_core.png")
	h.interior_texture = load("res://textures/hulls/hull_light_interior.png")
	return h


static func make_standard() -> HullData:
	var h := HullData.new()
	h.title = "Standard"
	h.hull_type = HullType.STANDARD
	h.grid_size = Vector2i(7, 6)
	h.base_durability = 120.0
	h.base_mass = 55.0
	h.capacity = 24
	h.description = "Standard hull, 7x6 - left edge main mounts, rest is deck."
	h.custom_texture = load("res://textures/hulls/hull_standard.png")
	h.interior_texture = load("res://textures/hulls/hull_standard_interior.png")
	return h


static func make_heavy() -> HullData:
	var h := HullData.new()
	h.title = "Heavy"
	h.hull_type = HullType.HEAVY
	h.grid_size = Vector2i(14, 7)
	h.base_durability = 200.0
	h.base_mass = 90.0
	h.capacity = 40
	h.description = "Heavy hull, 14x7 - left edge main mounts, rest is deck."
	h.custom_texture = load("res://textures/hulls/hull_heavy.png")
	h.interior_texture = load("res://textures/hulls/hull_heavy_interior.png")
	return h

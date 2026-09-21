class_name HullData
extends Resource
## Blueprint for a placeable hull piece (local footprint + stats).

enum HullType {
	LEKKI,
	STANDARDOWY,
	CIEZKI,
}

enum FloorType {
	EMPTY, ## Shipyard void
	DECK, ## Hull floor (engines / utilities)
	CONNECTOR, ## Łącznik cell
}

@export var title: String = "Standardowy"
@export var hull_type: HullType = HullType.STANDARDOWY
@export var grid_size: Vector2i = Vector2i(5, 5)
@export var base_durability: float = 100.0
@export var base_mass: float = 50.0
@export var capacity: int = 20
@export var description: String = ""


func get_local_floor(local_cell: Vector2i) -> FloorType:
	if local_cell.x < 0 or local_cell.y < 0:
		return FloorType.EMPTY
	if local_cell.x >= grid_size.x or local_cell.y >= grid_size.y:
		return FloorType.EMPTY
	return FloorType.DECK


func make_rect_shape() -> Array[Vector2i]:
	var shape: Array[Vector2i] = []
	for y in grid_size.y:
		for x in grid_size.x:
			shape.append(Vector2i(x, y))
	return shape


static func make_lekki() -> HullData:
	var h := HullData.new()
	h.title = "Lekki"
	h.hull_type = HullType.LEKKI
	h.grid_size = Vector2i(5, 5)
	h.base_durability = 80.0
	h.base_mass = 30.0
	h.capacity = 12
	h.description = "Lekki kadłub 5×5 — łączy się przez łączniki."
	return h


static func make_standardowy() -> HullData:
	var h := HullData.new()
	h.title = "Standardowy"
	h.hull_type = HullType.STANDARDOWY
	h.grid_size = Vector2i(7, 6)
	h.base_durability = 120.0
	h.base_mass = 55.0
	h.capacity = 24
	h.description = "Standardowy kadłub 7×6 — łączy się przez łączniki."
	return h


static func make_ciezki() -> HullData:
	var h := HullData.new()
	h.title = "Ciężki"
	h.hull_type = HullType.CIEZKI
	h.grid_size = Vector2i(9, 7)
	h.base_durability = 200.0
	h.base_mass = 90.0
	h.capacity = 40
	h.description = "Ciężki kadłub 9×7 — łączy się przez łączniki."
	return h

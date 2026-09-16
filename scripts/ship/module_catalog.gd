class_name ModuleCatalog
extends RefCounted

static var _defs: Dictionary = {}


static func all_defs() -> Array[ModuleDef]:
	_ensure()
	var result: Array[ModuleDef] = []
	for def in _defs.values():
		result.append(def)
	return result


static func get_def(id: String) -> ModuleDef:
	_ensure()
	return _defs.get(id, null)


static func palette_ids() -> PackedStringArray:
	return PackedStringArray([
		"cockpit_mk1",
		"frame",
		"fuel_tank_s",
		"engine_chemical_s",
		"engine_chemical_l",
		"rcs",
		"cargo_s",
	])


static func _ensure() -> void:
	if not _defs.is_empty():
		return
	_defs["cockpit_mk1"] = _make(
		"cockpit_mk1",
		"Kokpit",
		"cockpit",
		[Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1)],
		2.4,
		0.0,
		0.0,
		0.0,
		120.0,
		Color("#e8eef6"),
		PackedVector2Array([
			Vector2(1.15, 0.0), Vector2(0.35, 0.7), Vector2(-0.85, 0.55),
			Vector2(-0.85, -0.55), Vector2(0.35, -0.7),
		])
	)
	_defs["frame"] = _make(
		"frame",
		"Szkielet",
		"frame",
		[Vector2i(0, 0)],
		0.6,
		0.0,
		0.0,
		0.0,
		80.0,
		Color("#8a97a8"),
		PackedVector2Array([
			Vector2(-0.42, -0.42), Vector2(0.42, -0.42), Vector2(0.42, 0.42), Vector2(-0.42, 0.42),
		])
	)
	_defs["fuel_tank_s"] = _make(
		"fuel_tank_s",
		"Zbiornik",
		"tank",
		[Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1)],
		1.6,
		2000.0,
		0.0,
		0.0,
		90.0,
		Color("#3aa0d8"),
		PackedVector2Array([
			Vector2(-0.85, -0.7), Vector2(0.85, -0.7), Vector2(0.85, 0.7), Vector2(-0.85, 0.7),
		])
	)
	_defs["engine_chemical_s"] = _make(
		"engine_chemical_s",
		"Silnik S",
		"engine",
		[Vector2i(0, 0), Vector2i(1, 0)],
		3.1,
		0.0,
		220.0,
		0.0,
		110.0,
		Color("#d45a5a"),
		PackedVector2Array([
			Vector2(-0.15, -0.55), Vector2(0.95, -0.38), Vector2(0.95, 0.38),
			Vector2(-0.15, 0.55), Vector2(-1.05, 0.28), Vector2(-1.05, -0.28),
		])
	)
	_defs["engine_chemical_l"] = _make(
		"engine_chemical_l",
		"Silnik L",
		"engine",
		[Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0), Vector2i(0, 1), Vector2i(1, 1), Vector2i(2, 1)],
		6.8,
		0.0,
		520.0,
		0.0,
		160.0,
		Color("#c44a4a"),
		PackedVector2Array([
			Vector2(-1.2, -0.85), Vector2(1.35, -0.7), Vector2(1.35, 0.7),
			Vector2(-1.2, 0.85), Vector2(-1.7, 0.4), Vector2(-1.7, -0.4),
		])
	)
	_defs["rcs"] = _make(
		"rcs",
		"RCS",
		"rcs",
		[Vector2i(0, 0)],
		0.35,
		80.0,
		0.0,
		14.0,
		40.0,
		Color("#9aa8b8"),
		PackedVector2Array([
			Vector2(-0.28, -0.28), Vector2(0.28, -0.28), Vector2(0.28, 0.28), Vector2(-0.28, 0.28),
		])
	)
	_defs["cargo_s"] = _make(
		"cargo_s",
		"Ładownia",
		"cargo",
		[Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1)],
		4.8,
		0.0,
		0.0,
		0.0,
		100.0,
		Color("#c5a45a"),
		PackedVector2Array([
			Vector2(-0.9, -0.9), Vector2(0.9, -0.9), Vector2(0.9, 0.9), Vector2(-0.9, 0.9),
		])
	)


static func _make(
	id: String,
	name: String,
	role: String,
	cells: Array,
	mass: float,
	fuel_capacity: float,
	thrust: float,
	rcs_thrust: float,
	hp: float,
	fill: Color,
	polygon: PackedVector2Array
) -> ModuleDef:
	var def := ModuleDef.new()
	def.id = id
	def.display_name = name
	def.role = role
	var occupied: Array[Vector2i] = []
	for cell in cells:
		occupied.append(cell)
	def.occupied = occupied
	def.mass = mass
	def.fuel_capacity = fuel_capacity
	def.thrust = thrust
	def.rcs_thrust = rcs_thrust
	def.hp_max = hp
	def.fill = fill
	def.polygon = polygon
	return def

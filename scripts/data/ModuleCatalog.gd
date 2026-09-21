class_name ModuleCatalog
extends RefCounted
## Factory for buildable modules: hulls, connector, engines, weapons, utilities.

const CELL_PX := 48


static func all_buildable_modules() -> Array[ModuleData]:
	var list: Array[ModuleData] = []
	list.append_array(hull_modules())
	list.append(connector())
	list.append_array(engines())
	list.append_array(weapons())
	list.append_array(utilities())
	return list


static func hull_modules() -> Array[ModuleData]:
	return [
		_hull_module(HullData.make_lekki(), &"hull_lekki"),
		_hull_module(HullData.make_standardowy(), &"hull_standardowy"),
		_hull_module(HullData.make_ciezki(), &"hull_ciezki"),
	]


static func connector() -> ModuleData:
	var m := _base("Łącznik", &"connector", ModuleData.Category.CONNECTOR, 2.0, 20.0, 0.0, _shape_1x1())
	m.texture = make_shape_texture(m.grid_shape, ModuleData.Category.CONNECTOR)
	return m


static func engines() -> Array[ModuleData]:
	return [
		_engine("Chemiczny", &"engine_chemical", 40.0, 8.0, 2.0, 6.0, 120.0, _shape_1x1()),
		_engine("Nuklearny termiczny", &"engine_nuclear", 70.0, 5.0, 6.0, 12.0, 180.0, _shape_2x1()),
		_engine("Jonowy", &"engine_ion", 25.0, 1.5, 10.0, 4.0, 90.0, _shape_1x1()),
		_engine("Plazmowy", &"engine_plasma", 95.0, 12.0, 14.0, 14.0, 220.0, _shape_2x2()),
		_engine("Fuzyjny", &"engine_fusion", 140.0, 4.0, 18.0, 20.0, 260.0, _shape_l()),
	]


static func weapons() -> Array[ModuleData]:
	return [
		_weapon("Działo Gaussa", &"weapon_gauss", 35.0, 1.2, 0.85, 8.0, 5.0, _shape_2x1()),
		_weapon("Railgun", &"weapon_railgun", 55.0, 2.0, 0.9, 12.0, 8.0, _shape_2x1()),
		_weapon("Laser DEW", &"weapon_laser", 22.0, 0.4, 0.95, 6.0, 12.0, _shape_1x1()),
		_weapon("Działo cząsteczkowe", &"weapon_particle", 80.0, 3.5, 0.98, 10.0, 15.0, _shape_3x1()),
	]


static func utilities() -> Array[ModuleData]:
	var repair := _base("Moduł Naprawczy", &"util_repair", ModuleData.Category.UTILITY, 5.0, 15.0, 2.0, _shape_1x1())
	repair.repair_rate = 4.0

	var generator := _base("Generator", &"util_generator", ModuleData.Category.UTILITY, 8.0, 20.0, 0.0, _shape_2x1())
	generator.energy_generation = 25.0

	var battery := _base("Baterie", &"util_battery", ModuleData.Category.UTILITY, 4.0, 12.0, 0.0, _shape_1x1())
	battery.capacity = 60.0

	return [repair, generator, battery]


static func hulls() -> Array[HullData]:
	return [
		HullData.make_lekki(),
		HullData.make_standardowy(),
		HullData.make_ciezki(),
	]


static func make_shape_texture(
	shape: Array[Vector2i],
	category: ModuleData.Category,
	rotation: int = 0,
	cell_px: int = CELL_PX
) -> Texture2D:
	var rotated := ModuleData.rotate_shape(shape, rotation)
	var bounds := ModuleData.bounding_size_of(rotated)
	if bounds.x <= 0 or bounds.y <= 0:
		return null

	var img := Image.create(bounds.x * cell_px, bounds.y * cell_px, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))

	var fill := _category_color(category)
	var hi := fill.lightened(0.25)
	var lo := fill.darkened(0.25)

	for c: Vector2i in rotated:
		var ox := c.x * cell_px
		var oy := c.y * cell_px
		for py in cell_px:
			for px in cell_px:
				var edge := px < 2 or py < 2 or px >= cell_px - 2 or py >= cell_px - 2
				var color := hi if (px < 3 or py < 3) else (lo if edge else fill)
				if px > 4 and py > 4 and px < cell_px - 5 and py < cell_px - 5:
					color = fill.lerp(Color.WHITE, 0.08)
				img.set_pixel(ox + px, oy + py, color)
		_draw_cell_glyph(img, ox, oy, cell_px, category)

	return ImageTexture.create_from_image(img)


static func make_hull_texture(hull: HullData, rotation: int = 0, cell_px: int = CELL_PX) -> Texture2D:
	var shape := ModuleData.rotate_shape(hull.make_rect_shape(), rotation)
	var bounds := ModuleData.bounding_size_of(shape)
	var img := Image.create(bounds.x * cell_px, bounds.y * cell_px, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))

	var deck := Color(0.32, 0.4, 0.52)
	for c: Vector2i in shape:
		var ox := c.x * cell_px
		var oy := c.y * cell_px
		for py in cell_px:
			for px in cell_px:
				var color := deck
				if px < 2 or py < 2 or px >= cell_px - 2 or py >= cell_px - 2:
					color = deck.darkened(0.25)
				elif px > 3 and py > 3 and px < cell_px - 4 and py < cell_px - 4:
					color = deck.lightened(0.06)
				img.set_pixel(ox + px, oy + py, color)
	return ImageTexture.create_from_image(img)


static func _hull_module(hull: HullData, id: StringName) -> ModuleData:
	var m := ModuleData.new()
	m.title = "Kadłub %s" % hull.title
	m.id = id
	m.category = ModuleData.Category.HULL
	m.hull_data = hull
	m.mass = hull.base_mass
	m.health = hull.base_durability
	m.grid_shape = hull.make_rect_shape()
	# Compact inventory icon (large footprints stay readable).
	m.texture = make_hull_texture(hull, 0, 10)
	return m


static func _engine(
	title: String,
	id: StringName,
	thrust: float,
	fuel: float,
	energy: float,
	mass: float,
	max_heat: float,
	shape: Array[Vector2i]
) -> ModuleData:
	var m := _base(title, id, ModuleData.Category.ENGINE, mass, 25.0, energy, shape)
	m.thrust = thrust
	m.fuel_consumption = fuel
	m.max_heat = max_heat
	return m


static func _weapon(
	title: String,
	id: StringName,
	damage: float,
	reload: float,
	accuracy: float,
	mass: float,
	energy: float,
	shape: Array[Vector2i]
) -> ModuleData:
	var m := _base(title, id, ModuleData.Category.WEAPON, mass, 18.0, energy, shape)
	m.damage = damage
	m.reload_time = reload
	m.accuracy = accuracy
	return m


static func _base(
	title: String,
	id: StringName,
	category: ModuleData.Category,
	mass: float,
	health: float,
	energy: float,
	shape: Array[Vector2i]
) -> ModuleData:
	var m := ModuleData.new()
	m.title = title
	m.id = id
	m.category = category
	m.mass = mass
	m.health = health
	m.energy_consumption = energy
	m.grid_shape = shape
	m.texture = make_shape_texture(shape, category)
	return m


static func _shape_1x1() -> Array[Vector2i]:
	return [Vector2i(0, 0)]


static func _shape_2x1() -> Array[Vector2i]:
	return [Vector2i(0, 0), Vector2i(1, 0)]


static func _shape_2x2() -> Array[Vector2i]:
	return [
		Vector2i(0, 0), Vector2i(1, 0),
		Vector2i(0, 1), Vector2i(1, 1),
	]


static func _shape_3x1() -> Array[Vector2i]:
	return [Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0)]


static func _shape_l() -> Array[Vector2i]:
	return [
		Vector2i(0, 0),
		Vector2i(0, 1),
		Vector2i(0, 2),
		Vector2i(1, 2),
	]


static func _category_color(category: ModuleData.Category) -> Color:
	match category:
		ModuleData.Category.ENGINE:
			return Color(0.95, 0.45, 0.15)
		ModuleData.Category.WEAPON:
			return Color(0.85, 0.2, 0.25)
		ModuleData.Category.UTILITY:
			return Color(0.25, 0.7, 0.55)
		ModuleData.Category.HULL:
			return Color(0.45, 0.55, 0.75)
		ModuleData.Category.CONNECTOR:
			return Color(0.9, 0.75, 0.2)
		_:
			return Color(0.4, 0.45, 0.5)


static func _draw_cell_glyph(
	img: Image,
	ox: int,
	oy: int,
	cell_px: int,
	category: ModuleData.Category
) -> void:
	var cx := ox + cell_px / 2
	var cy := oy + cell_px / 2
	var mark := Color(1, 1, 1, 0.55)
	match category:
		ModuleData.Category.ENGINE:
			for i in range(-6, 7):
				img.set_pixel(cx + i, cy, mark)
				img.set_pixel(cx, cy + i, mark)
		ModuleData.Category.WEAPON:
			for i in range(-8, 9):
				img.set_pixel(cx + i, cy, mark)
			for i in range(0, 7):
				img.set_pixel(cx + 4, cy - i, mark)
		ModuleData.Category.UTILITY:
			for i in range(-5, 6):
				for j in range(-5, 6):
					if absi(i) == 5 or absi(j) == 5:
						img.set_pixel(cx + i, cy + j, mark)
		ModuleData.Category.CONNECTOR:
			for i in range(-8, 9):
				img.set_pixel(cx + i, cy, mark)
				img.set_pixel(cx, cy + i, mark)
		_:
			pass

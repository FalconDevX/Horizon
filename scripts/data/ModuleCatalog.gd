class_name ModuleCatalog
extends RefCounted
## Factory for buildable modules: hulls, connector, engines, weapons, utilities.

const CELL_PX := 48


static func all_buildable_modules() -> Array[ModuleData]:
	var list: Array[ModuleData] = []
	list.append_array(hull_modules())
	list.append_array(connectors())
	list.append_array(trusses())
	list.append(cockpit())
	list.append_array(engines())
	list.append_array(weapons())
	list.append_array(radars())
	list.append_array(shields())
	list.append_array(utilities())
	list.append_array(fuel_tanks())
	list.append_array(batteries())
	return list


static func hull_modules() -> Array[ModuleData]:
	return [
		_hull_module(HullData.make_light(), &"hull_light"),
		_hull_module(HullData.make_standard(), &"hull_standard"),
		_hull_module(HullData.make_heavy(), &"hull_heavy"),
	]


## The four connector pieces from the board. They behave the same (a 1x1
## bridge between hulls); the shape is the look.
static func connectors() -> Array[ModuleData]:
	var list: Array[ModuleData] = []
	for piece: Array in [
		["Connector: Straight", &"connector_straight"],
		["Connector: Elbow", &"connector_elbow"],
		["Connector: T", &"connector_t"],
		["Connector: Cross", &"connector_cross"],
	]:
		var m := _base(piece[0], piece[1], ModuleData.Category.CONNECTOR, 2.0, 20.0, 0.0, _shape_1x1())
		_use_art(m, String(piece[1]))
		list.append(m)
	return list


## Truss beams (1-3 cells long): a frame for guns. Built on the weapon-mount
## ring or off another beam, and guns can stand on them.
static func trusses() -> Array[ModuleData]:
	var list: Array[ModuleData] = []
	for n in [1, 2, 3]:
		var m := _base("Truss %d" % n, StringName("truss_%d" % n), ModuleData.Category.TRUSS, 0.8 * n, 8.0 * n, 0.0, _shape_line(n))
		_use_art(m, "truss_%d" % n)
		list.append(m)
	return list


static func cockpit() -> ModuleData:
	# Stands in open space like a hull and joins one through a connector.
	var m := _base("Cockpit", &"cockpit", ModuleData.Category.COCKPIT, 6.0, 30.0, 1.0, _shape_rect(3, 2))
	_use_art(m, "cockpit")
	return m


static func _with_art(m: ModuleData) -> ModuleData:
	_use_art(m, String(m.id))
	return m


## Sprite for a module from textures/modules/<name>.png, if there is one.
static func _use_art(m: ModuleData, name: String) -> void:
	var path := "res://textures/modules/%s.png" % name
	if ResourceLoader.exists(path):
		m.texture = load(path)


## Star rating (1-5) -> in-game values for a size-S (1x1) engine:
##   thrust: 8 / 16 / 24 / 32 / 40
##   fuel:   1 / 2.5 / 4.5 / 7 / 10   (higher = more consumption)
##   energy: 1.5 / 4 / 8 / 13 / 18
##   mass:   3 / 6 / 10 / 15 / 22
const _STAR_THRUST: Array[float] = [8.0, 16.0, 24.0, 32.0, 40.0]
const _STAR_FUEL: Array[float] = [1.0, 2.5, 4.5, 7.0, 10.0]
const _STAR_ENERGY: Array[float] = [1.5, 4.0, 8.0, 13.0, 18.0]
const _STAR_MASS: Array[float] = [3.0, 6.0, 10.0, 15.0, 22.0]

## Engine sizes S / M / L: footprints 1x1 / 2x1 / 2x2 (as on the Drive sketches,
## "Horizon/silniki 2d"; art index 1/2/3 in the file names). Bigger engines
## get a little more thrust per unit of fuel and mass.
const _ENGINE_SIZES := [
	{"suffix": "S", "id": "s", "art": 1, "size": Vector2i(1, 1), "thrust": 1.0, "fuel": 1.0, "energy": 1.0, "mass": 1.0, "heat": 1.0},
	{"suffix": "M", "id": "m", "art": 2, "size": Vector2i(2, 1), "thrust": 2.5, "fuel": 2.3, "energy": 2.3, "mass": 2.2, "heat": 1.8},
	{"suffix": "L", "id": "l", "art": 3, "size": Vector2i(2, 2), "thrust": 4.5, "fuel": 4.0, "energy": 4.0, "mass": 3.8, "heat": 2.6},
]


## Five engine types in three sizes each. Stars: thrust, fuel, energy, mass.
## Sprites: textures/modules/engine_<type>_<1|2|3>.png, nozzle pointing left
## (the aft side: main engines stand left of a hull).
static func engines() -> Array[ModuleData]:
	var list: Array[ModuleData] = []
	list.append_array(_engine_family("Chemical", "chemical", 5, 5, 1, 2, 120.0))
	list.append_array(_engine_family("Nuclear Thermal", "nuclear", 4, 3, 2, 4, 180.0))
	list.append_array(_engine_family("Ion", "ion", 1, 1, 3, 1, 90.0))
	list.append_array(_engine_family("Plasma", "plasma", 3, 2, 4, 3, 200.0))
	list.append_array(_engine_family("Fusion", "fusion", 5, 1, 5, 5, 260.0))
	return list


static func _engine_family(
	title: String,
	key: String,
	thrust_stars: int,
	fuel_stars: int,
	energy_stars: int,
	mass_stars: int,
	base_heat: float
) -> Array[ModuleData]:
	var list: Array[ModuleData] = []
	for size: Dictionary in _ENGINE_SIZES:
		var art: int = size["art"]
		var footprint: Vector2i = size["size"]
		var shape: Array[Vector2i] = []
		for y in footprint.y:
			for x in footprint.x:
				shape.append(Vector2i(x, y))
		var m := _engine(
			"%s %s" % [title, size["suffix"]],
			StringName("engine_%s_%s" % [key, size["id"]]),
			_STAR_THRUST[thrust_stars - 1] * float(size["thrust"]),
			_STAR_FUEL[fuel_stars - 1] * float(size["fuel"]),
			_STAR_ENERGY[energy_stars - 1] * float(size["energy"]),
			_STAR_MASS[mass_stars - 1] * float(size["mass"]),
			base_heat * float(size["heat"]),
			shape
		)
		var sprite := "res://textures/modules/engine_%s_%d.png" % [key, art]
		if ResourceLoader.exists(sprite):
			m.texture = load(sprite)
		var plan := "res://textures/modules/engine_%s_%d_plan.png" % [key, art]
		if ResourceLoader.exists(plan):
			m.plan_texture = load(plan)
		m.family = title
		m.family_stars = [thrust_stars, fuel_stars, energy_stars, mass_stars]
		list.append(m)
	return list


static func weapons() -> Array[ModuleData]:
	return [
		# angle / range tuned per role; range is world SU (builder scales preview).
		_with_art(_weapon("Gauss Cannon", &"weapon_gauss", 35.0, 1.2, 0.85, 8.0, 5.0, 40.0, 1800.0, _shape_2x1())),
		_with_art(_weapon("Railgun", &"weapon_railgun", 55.0, 2.0, 0.9, 12.0, 8.0, 22.0, 3400.0, _shape_2x1())),
		_with_art(_weapon("Laser DEW", &"weapon_laser", 22.0, 0.4, 0.95, 6.0, 12.0, 12.0, 2800.0, _shape_1x1())),
		_with_art(_weapon("Particle Cannon", &"weapon_particle", 80.0, 3.5, 0.98, 10.0, 15.0, 55.0, 1500.0, _shape_3x1())),
		# Long yellow beam (ship.gd SNIPER_ID): the longest reach by far, in a
		# narrow cone, slow to reload.
		_with_art(_weapon("Sniper Laser", &"weapon_sniper", 70.0, 4.0, 0.99, 14.0, 20.0, 6.0, 12000.0, _shape_line(4))),
		# From the board's star ratings (DMG / reload / accuracy): see _stars_weapon.
		_stars_weapon("Revolver Cannon", &"weapon_revolver", 4, 4, 4, 9.0, 4.0, 30.0, 2000.0, _shape_2x1()),
		_stars_weapon("Coilgun: Shotgun", &"weapon_coilgun", 5, 4, 1, 10.0, 10.0, 50.0, 1200.0, _shape_2x1()),
		_stars_weapon("Rocket Launcher", &"weapon_rockets", 5, 1, 5, 12.0, 2.0, 25.0, 3000.0, _shape_2x1()),
		_stars_weapon("Drone Bay", &"weapon_drones", 2, 3, 3, 6.0, 8.0, 90.0, 2500.0, _shape_1x1()),
	]


## Deck-mounted sensors. Wider / longer FOV than weapons; no damage.
static func radars() -> Array[ModuleData]:
	return [
		_radar("Proximity Radar", &"radar_proximity", 4.0, 12.0, 2.0, 90.0, 2200.0, _shape_1x1()),
		_radar("Survey Radar", &"radar_survey", 7.0, 18.0, 4.0, 60.0, 4800.0, _shape_2x1()),
		_radar("Deep Space Array", &"radar_deep", 14.0, 28.0, 8.0, 35.0, 9000.0, _shape_2x2()),
	]


static func utilities() -> Array[ModuleData]:
	var repair := _base("Repair Module", &"util_repair", ModuleData.Category.UTILITY, 5.0, 15.0, 2.0, _shape_1x1())
	repair.repair_rate = 4.0
	_use_art(repair, "util_repair")

	var generator := _base("Generator", &"util_generator", ModuleData.Category.UTILITY, 8.0, 20.0, 0.0, _shape_2x2())
	generator.energy_generation = 25.0
	_use_art(generator, "util_generator")

	var solar := _base("Solar Panels", &"util_solar", ModuleData.Category.UTILITY, 3.0, 8.0, 0.0, _shape_2x1())
	solar.energy_generation = 10.0
	_use_art(solar, "util_solar")

	var fabricator := _base("Fabricator", &"util_fabricator", ModuleData.Category.UTILITY, 14.0, 30.0, 12.0, _shape_2x2())
	_use_art(fabricator, "util_fabricator")

	return [repair, generator, solar, fabricator]


## Three sizes × two variants (standard / armored), same layout as fuel tanks.
## Armored: +mass, +HP, slightly less energy capacity.
static func batteries() -> Array[ModuleData]:
	return [
		_battery("Battery S", &"battery_s", false, 3.0, 10.0, 40.0, _shape_1x1()),
		_battery("Battery S (Armored)", &"battery_s_armored", true, 5.5, 24.0, 32.0, _shape_1x1()),
		_battery("Battery M", &"battery_m", false, 6.0, 16.0, 100.0, _shape_2x1()),
		_battery("Battery M (Armored)", &"battery_m_armored", true, 11.0, 40.0, 85.0, _shape_2x1()),
		_battery("Battery L", &"battery_l", false, 12.0, 28.0, 220.0, _shape_2x2()),
		_battery("Battery L (Armored)", &"battery_l_armored", true, 22.0, 65.0, 185.0, _shape_2x2()),
	]


static func _battery(
	title: String,
	id: StringName,
	armored: bool,
	mass: float,
	health: float,
	energy_cap: float,
	shape: Array[Vector2i]
) -> ModuleData:
	var m := _base(title, id, ModuleData.Category.BATTERY, mass, health, 0.0, shape)
	m.capacity = energy_cap
	m.texture = make_battery_texture(shape, armored)
	return m


## Three shield types — light / balanced / heavy.
static func shields() -> Array[ModuleData]:
	return [
		_shield("Deflector Shield", &"shield_deflector", 8.0, 18.0, 4.0, 60.0, _shape_1x1()),
		_shield("Barrier Shield", &"shield_barrier", 14.0, 28.0, 8.0, 120.0, _shape_2x1()),
		_shield("Aegis Shield", &"shield_aegis", 24.0, 45.0, 14.0, 220.0, _shape_2x2()),
	]


static func _shield(
	title: String,
	id: StringName,
	mass: float,
	health: float,
	energy: float,
	strength: float,
	shape: Array[Vector2i]
) -> ModuleData:
	var m := _base(title, id, ModuleData.Category.SHIELD, mass, health, energy, shape)
	m.shield_strength = strength
	m.texture = make_shape_texture(shape, ModuleData.Category.SHIELD)
	_use_art(m, String(id))
	return m


## Three sizes × two variants (standard / armored).
## Armored: +mass, +HP, slightly less fuel capacity.
static func fuel_tanks() -> Array[ModuleData]:
	return [
		_fuel_tank("Fuel Tank S", &"fuel_s", false, 4.0, 12.0, 40.0, _shape_1x1()),
		_fuel_tank("Fuel Tank S (Armored)", &"fuel_s_armored", true, 7.0, 28.0, 32.0, _shape_1x1()),
		_fuel_tank("Fuel Tank M", &"fuel_m", false, 8.0, 20.0, 100.0, _shape_2x1()),
		_fuel_tank("Fuel Tank M (Armored)", &"fuel_m_armored", true, 14.0, 48.0, 85.0, _shape_2x1()),
		_fuel_tank("Fuel Tank L", &"fuel_l", false, 16.0, 35.0, 220.0, _shape_2x2()),
		_fuel_tank("Fuel Tank L (Armored)", &"fuel_l_armored", true, 28.0, 80.0, 185.0, _shape_2x2()),
	]


static func _fuel_tank(
	title: String,
	id: StringName,
	armored: bool,
	mass: float,
	health: float,
	fuel: float,
	shape: Array[Vector2i]
) -> ModuleData:
	var m := _base(title, id, ModuleData.Category.FUEL_TANK, mass, health, 0.0, shape)
	m.fuel_capacity = fuel
	m.texture = make_fuel_tank_texture(shape, armored)
	# Drawn art (textures/modules/fuel_*.png) replaces the placeholder.
	_use_art(m, String(id))
	return m


static func make_fuel_tank_texture(
	shape: Array[Vector2i],
	armored: bool,
	rotation: int = 0,
	cell_px: int = CELL_PX
) -> Texture2D:
	var rotated := ModuleData.rotate_shape(shape, rotation)
	var bounds := ModuleData.bounding_size_of(rotated)
	if bounds.x <= 0 or bounds.y <= 0:
		return null

	var img := Image.create(bounds.x * cell_px, bounds.y * cell_px, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))

	var fill := Color(0.22, 0.55, 0.72) if not armored else Color(0.38, 0.42, 0.48)
	var hi := fill.lightened(0.22)
	var lo := fill.darkened(0.28)
	var accent := Color(0.85, 0.7, 0.25, 0.7) if not armored else Color(0.65, 0.55, 0.3, 0.75)

	for c: Vector2i in rotated:
		var ox := c.x * cell_px
		var oy := c.y * cell_px
		for py in cell_px:
			for px in cell_px:
				var edge := px < 2 or py < 2 or px >= cell_px - 2 or py >= cell_px - 2
				var color := hi if (px < 3 or py < 3) else (lo if edge else fill)
				if px > 4 and py > 4 and px < cell_px - 5 and py < cell_px - 5:
					color = fill.lerp(Color.WHITE, 0.06)
				img.set_pixel(ox + px, oy + py, color)
		_draw_fuel_tank_glyph(img, ox, oy, cell_px, accent, armored)

	return ImageTexture.create_from_image(img)


static func _draw_fuel_tank_glyph(
	img: Image,
	ox: int,
	oy: int,
	cell_px: int,
	accent: Color,
	armored: bool
) -> void:
	var cx := ox + cell_px / 2
	var cy := oy + cell_px / 2
	# Vertical tank body outline.
	for y in range(-8, 9):
		img.set_pixel(cx - 5, cy + y, accent)
		img.set_pixel(cx + 5, cy + y, accent)
	for x in range(-5, 6):
		img.set_pixel(cx + x, cy - 8, accent)
		img.set_pixel(cx + x, cy + 8, accent)
	# Fuel level bar.
	for y in range(0, 7):
		for x in range(-3, 4):
			img.set_pixel(cx + x, cy + y, Color(accent, 0.45))
	if armored:
		# Extra armor braces.
		for x in range(-5, 6):
			img.set_pixel(cx + x, cy - 3, accent)
			img.set_pixel(cx + x, cy + 3, accent)


static func make_battery_texture(
	shape: Array[Vector2i],
	armored: bool,
	rotation: int = 0,
	cell_px: int = CELL_PX
) -> Texture2D:
	var rotated := ModuleData.rotate_shape(shape, rotation)
	var bounds := ModuleData.bounding_size_of(rotated)
	if bounds.x <= 0 or bounds.y <= 0:
		return null

	var img := Image.create(bounds.x * cell_px, bounds.y * cell_px, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))

	var fill := Color(0.2, 0.72, 0.45) if not armored else Color(0.35, 0.48, 0.42)
	var hi := fill.lightened(0.22)
	var lo := fill.darkened(0.28)
	var accent := Color(0.7, 0.95, 0.4, 0.75) if not armored else Color(0.55, 0.7, 0.4, 0.8)

	for c: Vector2i in rotated:
		var ox := c.x * cell_px
		var oy := c.y * cell_px
		for py in cell_px:
			for px in cell_px:
				var edge := px < 2 or py < 2 or px >= cell_px - 2 or py >= cell_px - 2
				var color := hi if (px < 3 or py < 3) else (lo if edge else fill)
				if px > 4 and py > 4 and px < cell_px - 5 and py < cell_px - 5:
					color = fill.lerp(Color.WHITE, 0.06)
				img.set_pixel(ox + px, oy + py, color)
		_draw_battery_glyph(img, ox, oy, cell_px, accent, armored)

	return ImageTexture.create_from_image(img)


static func _draw_battery_glyph(
	img: Image,
	ox: int,
	oy: int,
	cell_px: int,
	accent: Color,
	armored: bool
) -> void:
	var cx := ox + cell_px / 2
	var cy := oy + cell_px / 2
	# Battery body.
	for y in range(-7, 8):
		img.set_pixel(cx - 6, cy + y, accent)
		img.set_pixel(cx + 6, cy + y, accent)
	for x in range(-6, 7):
		img.set_pixel(cx + x, cy - 7, accent)
		img.set_pixel(cx + x, cy + 7, accent)
	# Terminal nub.
	for x in range(-2, 3):
		img.set_pixel(cx + x, cy - 9, accent)
		img.set_pixel(cx + x, cy - 8, accent)
	# Charge bars.
	for bar in range(3):
		var by: int = cy + 3 - bar * 4
		for x in range(-4, 5):
			img.set_pixel(cx + x, by, Color(accent, 0.55))
			img.set_pixel(cx + x, by + 1, Color(accent, 0.55))
	if armored:
		for x in range(-6, 7):
			img.set_pixel(cx + x, cy, accent)


static func hulls() -> Array[HullData]:
	return [
		HullData.make_light(),
		HullData.make_standard(),
		HullData.make_heavy(),
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


static func make_hull_texture(hull: HullData, rotation: int = 0, cell_px: int = CELL_PX, for_grid: bool = false) -> Texture2D:
	if for_grid and hull.interior_texture != null:
		return hull.interior_texture
	if hull.custom_texture != null:
		return hull.custom_texture

	var local_shape := hull.make_rect_shape()
	var placed: Array[Vector2i] = []
	placed.resize(local_shape.size())
	for i in local_shape.size():
		placed[i] = ShipHull.local_to_world_delta(local_shape[i], rotation, hull)
	var bounds := ModuleData.bounding_size_of(placed)
	var img := Image.create(bounds.x * cell_px, bounds.y * cell_px, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))

	var base := Color(0.32, 0.4, 0.52)
	for i in local_shape.size():
		var c: Vector2i = placed[i]
		var ox := c.x * cell_px
		var oy := c.y * cell_px
		for py in cell_px:
			for px in cell_px:
				var color := base
				if px < 2 or py < 2 or px >= cell_px - 2 or py >= cell_px - 2:
					color = base.darkened(0.25)
				elif px > 3 and py > 3 and px < cell_px - 4 and py < cell_px - 4:
					color = base.lightened(0.06)
				img.set_pixel(ox + px, oy + py, color)
	return ImageTexture.create_from_image(img)


static func _hull_module(hull: HullData, id: StringName) -> ModuleData:
	var m := ModuleData.new()
	m.title = "%s Hull" % hull.title
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
	m.is_corrective_engine = false
	return m


static func _weapon(
	title: String,
	id: StringName,
	damage: float,
	reload: float,
	accuracy: float,
	mass: float,
	energy: float,
	fov_angle_deg: float,
	fov_range: float,
	shape: Array[Vector2i]
) -> ModuleData:
	var m := _base(title, id, ModuleData.Category.WEAPON, mass, 18.0, energy, shape)
	m.damage = damage
	m.reload_time = reload
	m.accuracy = accuracy
	m.fov_angle_deg = fov_angle_deg
	m.fov_range = fov_range
	return m


## Weapon from the board's 1-5 star ratings. Damage and accuracy rise with
## stars; reload stars mean a faster weapon, so fewer seconds between shots.
static func _stars_weapon(
	title: String,
	id: StringName,
	damage_stars: int,
	reload_stars: int,
	accuracy_stars: int,
	mass: float,
	energy: float,
	fov_angle_deg: float,
	fov_range: float,
	shape: Array[Vector2i]
) -> ModuleData:
	const DAMAGE: Array[float] = [10.0, 22.0, 35.0, 55.0, 80.0]
	const RELOAD: Array[float] = [4.0, 3.0, 2.0, 1.2, 0.4]
	const ACCURACY: Array[float] = [0.6, 0.72, 0.82, 0.9, 0.97]
	var m := _weapon(
		title, id,
		DAMAGE[damage_stars - 1], RELOAD[reload_stars - 1], ACCURACY[accuracy_stars - 1],
		mass, energy, fov_angle_deg, fov_range, shape
	)
	_use_art(m, String(id))
	return m


static func _radar(
	title: String,
	id: StringName,
	mass: float,
	health: float,
	energy: float,
	fov_angle_deg: float,
	fov_range: float,
	shape: Array[Vector2i]
) -> ModuleData:
	var m := _base(title, id, ModuleData.Category.RADAR, mass, health, energy, shape)
	m.fov_angle_deg = fov_angle_deg
	m.fov_range = fov_range
	_use_art(m, String(id))
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


## A straight run of `n` cells.
static func _shape_line(n: int) -> Array[Vector2i]:
	var shape: Array[Vector2i] = []
	for x in n:
		shape.append(Vector2i(x, 0))
	return shape


static func _shape_1x1() -> Array[Vector2i]:
	return [Vector2i(0, 0)]


static func _shape_2x1() -> Array[Vector2i]:
	return [Vector2i(0, 0), Vector2i(1, 0)]


static func _shape_rect(width: int, height: int) -> Array[Vector2i]:
	var shape: Array[Vector2i] = []
	for y in height:
		for x in width:
			shape.append(Vector2i(x, y))
	return shape


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
		ModuleData.Category.FUEL_TANK:
			return Color(0.22, 0.55, 0.72)
		ModuleData.Category.BATTERY:
			return Color(0.2, 0.72, 0.45)
		ModuleData.Category.SHIELD:
			return Color(0.45, 0.55, 0.95)
		ModuleData.Category.RADAR:
			return Color(0.35, 0.75, 0.85)
		ModuleData.Category.HULL:
			return Color(0.45, 0.55, 0.75)
		ModuleData.Category.CONNECTOR:
			return Color(0.9, 0.75, 0.2)
		ModuleData.Category.TRUSS:
			return Color(0.62, 0.62, 0.6)
		ModuleData.Category.COCKPIT:
			return Color(0.85, 0.88, 0.92)
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
			# Barrel along +X (rot 0), tip on the right edge.
			for i in range(-8, 9):
				img.set_pixel(cx + i, cy, mark)
			for i in range(0, 7):
				img.set_pixel(cx + 4 + i, cy - 1, mark)
				img.set_pixel(cx + 4 + i, cy, mark)
				img.set_pixel(cx + 4 + i, cy + 1, mark)
		ModuleData.Category.UTILITY:
			for i in range(-5, 6):
				for j in range(-5, 6):
					if absi(i) == 5 or absi(j) == 5:
						img.set_pixel(cx + i, cy + j, mark)
		ModuleData.Category.FUEL_TANK:
			for y in range(-8, 9):
				img.set_pixel(cx - 5, cy + y, mark)
				img.set_pixel(cx + 5, cy + y, mark)
			for x in range(-5, 6):
				img.set_pixel(cx + x, cy - 8, mark)
				img.set_pixel(cx + x, cy + 8, mark)
		ModuleData.Category.BATTERY:
			for y in range(-6, 7):
				img.set_pixel(cx - 5, cy + y, mark)
				img.set_pixel(cx + 5, cy + y, mark)
			for x in range(-5, 6):
				img.set_pixel(cx + x, cy - 6, mark)
				img.set_pixel(cx + x, cy + 6, mark)
			for x in range(-2, 3):
				img.set_pixel(cx + x, cy - 8, mark)
		ModuleData.Category.SHIELD:
			for i in range(-7, 8):
				var y_off: int = int(sqrt(float(49 - i * i)))
				img.set_pixel(cx + i, cy - y_off, mark)
				img.set_pixel(cx + i, cy + y_off, mark)
		ModuleData.Category.RADAR:
			# Concentric arcs facing up (rot 0).
			for i in range(-6, 7):
				var y1: int = cy - int(sqrt(float(max(0, 36 - i * i))))
				img.set_pixel(cx + i, y1, mark)
			for i in range(-4, 5):
				var y2: int = cy - 2 - int(sqrt(float(max(0, 16 - i * i))))
				img.set_pixel(cx + i, y2, mark)
			img.set_pixel(cx, cy + 2, mark)
			img.set_pixel(cx, cy + 3, mark)
		ModuleData.Category.CONNECTOR:
			for i in range(-8, 9):
				img.set_pixel(cx + i, cy, mark)
				img.set_pixel(cx, cy + i, mark)
		_:
			pass

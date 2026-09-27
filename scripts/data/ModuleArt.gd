class_name ModuleArt
extends RefCounted
## Plain generated pictures for modules - every module but the engines, which
## keep their drawn art. Each is one body over the module's cells, in its
## category's colour, with one simple mark for what it is (a barrel, a dish,
## a panel grid...), drawn nose to the right (+x) at rotation 0 like the ship.
## Shapes are signed distances, so edges come out smooth at any size.

const OUTLINE := Color(0.06, 0.08, 0.11)
const MARK := Color(0.93, 0.95, 0.98)


## The picture for a module, turned `rotation` quarter turns clockwise.
static func make(
	id: StringName,
	category: ModuleData.Category,
	shape: Array[Vector2i],
	rotation: int = 0,
	cell_px: int = ModuleCatalog.CELL_PX
) -> Texture2D:
	var bounds := ModuleData.bounding_size_of(shape)
	if bounds.x <= 0 or bounds.y <= 0:
		return null
	var cells: Dictionary = {}
	for c: Vector2i in shape:
		cells[c] = true
	var size := Vector2(bounds) * cell_px
	var img := Image.create(int(size.x), int(size.y), false, Image.FORMAT_RGBA8)
	var name := String(id)
	var base: Color = color_of(name, category)
	var inset: float = maxf(2.0, cell_px * 0.07)
	var radius: float = cell_px * 0.16
	for py in int(size.y):
		for px in int(size.x):
			var p := Vector2(px + 0.5, py + 0.5)
			var body: float = _body_distance(p, cells, cell_px, inset, radius, size)
			if body > 1.0:
				img.set_pixel(px, py, Color(0, 0, 0, 0))
				continue
			# Outline, then the body lit a little from the top left.
			var shade: float = 1.0 + 0.12 * (1.0 - (p.x + p.y) / (size.x + size.y) * 2.0)
			var colour: Color = Color(base.r * shade, base.g * shade, base.b * shade)
			colour = colour.lerp(OUTLINE, _cover(-body - maxf(1.5, cell_px * 0.045)))
			var mark: Color = _mark(name, category, p, size, cell_px, colour)
			img.set_pixel(px, py, Color(mark, _cover(body)))
	for _i in posmod(rotation, 4):
		img.rotate_90(CLOCKWISE)
	return ImageTexture.create_from_image(img)


## Category colour, with a few modules picked out on their own.
static func color_of(name: String, category: ModuleData.Category) -> Color:
	var colour: Color
	match category:
		ModuleData.Category.WEAPON:
			colour = Color(0.78, 0.24, 0.26)
		ModuleData.Category.RADAR:
			colour = Color(0.22, 0.62, 0.72)
		ModuleData.Category.SHIELD:
			colour = Color(0.4, 0.46, 0.9)
		ModuleData.Category.FUEL_TANK:
			colour = Color(0.9, 0.62, 0.18)
		ModuleData.Category.BATTERY:
			colour = Color(0.26, 0.7, 0.4)
		ModuleData.Category.UTILITY:
			colour = Color(0.2, 0.64, 0.56)
		ModuleData.Category.CONNECTOR:
			colour = Color(0.86, 0.72, 0.22)
		ModuleData.Category.TRUSS:
			colour = Color(0.5, 0.52, 0.55)
		ModuleData.Category.COCKPIT:
			colour = Color(0.78, 0.82, 0.88)
		_:
			colour = Color(0.45, 0.5, 0.58)
	match name:
		"util_solar":
			colour = Color(0.16, 0.3, 0.62)
		"util_generator":
			colour = Color(0.2, 0.48, 0.78)
		"util_fabricator":
			colour = Color(0.72, 0.55, 0.22)
		"util_repair":
			colour = Color(0.3, 0.68, 0.36)
	if name.ends_with("_armored"):
		colour = colour.darkened(0.3)
	return colour


## What sits on the body: `under` is the body colour at `p`.
static func _mark(
	name: String,
	category: ModuleData.Category,
	p: Vector2,
	size: Vector2,
	cell_px: int,
	under: Color
) -> Color:
	var c := size * 0.5
	var s: float = minf(size.x, size.y)
	var line: float = maxf(1.5, cell_px * 0.06)
	var d: float = INF
	var dark := false
	match category:
		ModuleData.Category.WEAPON:
			# Turret ring on the back cell, barrel out to the nose.
			var pivot := Vector2(cell_px * 0.5, c.y)
			var ring: float = absf(p.distance_to(pivot) - s * 0.26) - line * 0.6
			var barrel: float = _box(p - Vector2((pivot.x + size.x - cell_px * 0.12) * 0.5, c.y),
				Vector2((size.x - cell_px * 0.12 - pivot.x) * 0.5, s * 0.08))
			d = minf(ring, barrel)
			if name == "weapon_rockets" or name == "weapon_drones":
				# Launch tubes instead of a barrel.
				d = INF
				for i in 3:
					var tube := Vector2(size.x * (0.3 + 0.2 * i), c.y)
					d = minf(d, p.distance_to(tube) - s * 0.12)
				dark = true
		ModuleData.Category.RADAR:
			# A dish: an arc opening to the nose, and its feed.
			var r: float = s * 0.3
			var arc: float = absf(p.distance_to(c - Vector2(r * 0.4, 0.0)) - r) - line * 0.6
			var front: float = (c.x - r * 0.4) - p.x
			d = maxf(arc, front)
			d = minf(d, p.distance_to(c + Vector2(r * 0.25, 0.0)) - line * 1.2)
		ModuleData.Category.SHIELD:
			d = absf(_hexagon(p - c, s * 0.3)) - line * 0.7
		ModuleData.Category.FUEL_TANK:
			# A capsule along the long side.
			var half := size * 0.5 - Vector2.ONE * cell_px * 0.24
			var r: float = minf(half.x, half.y)
			d = absf(_box(p - c, half - Vector2.ONE * r) - r) - line * 0.6
		ModuleData.Category.BATTERY:
			# Charge bars across the long side, a terminal on the nose.
			var long_x: bool = size.x >= size.y
			var count: int = maxi(2, int((size.x if long_x else size.y) / cell_px) * 2)
			d = INF
			for i in count:
				var t: float = (i + 0.5) / count
				var at := Vector2(size.x * t, c.y) if long_x else Vector2(c.x, size.y * t)
				var half := Vector2(cell_px * 0.1, s * 0.22) if long_x else Vector2(s * 0.22, cell_px * 0.1)
				d = minf(d, _box(p - at, half))
		ModuleData.Category.CONNECTOR:
			var long_x: bool = size.x >= size.y
			var half := Vector2(size.x * 0.4, line) if long_x else Vector2(line, size.y * 0.4)
			d = _box(p - c, half)
		ModuleData.Category.TRUSS:
			# Cross bracing in every cell.
			var local := Vector2(fposmod(p.x, cell_px), fposmod(p.y, cell_px)) - Vector2.ONE * cell_px * 0.5
			d = minf(absf(local.x - local.y), absf(local.x + local.y)) * 0.7071 - line * 0.5
			dark = true
		ModuleData.Category.COCKPIT:
			# Canopy: a wedge pointing at the nose.
			var tip := Vector2(size.x - cell_px * 0.3, c.y)
			var back: float = cell_px * 0.5
			var h: float = size.y * 0.28
			var k: float = (p.x - back) / maxf(tip.x - back, 1.0)
			d = maxf(maxf(back - p.x, p.x - tip.x), absf(p.y - c.y) - h * (1.0 - k))
			dark = true
		ModuleData.Category.UTILITY:
			match name:
				"util_solar":
					# Panel grid lines.
					var step: float = cell_px * 0.25
					var gx: float = absf(fposmod(p.x, step) - step * 0.5)
					var gy: float = absf(fposmod(p.y, step) - step * 0.5)
					d = step * 0.5 - maxf(gx, gy) - line * 0.3
				"util_generator":
					d = minf(p.distance_to(c) - s * 0.18, absf(p.distance_to(c) - s * 0.3) - line * 0.5)
				"util_repair":
					d = minf(_box(p - c, Vector2(s * 0.28, s * 0.08)), _box(p - c, Vector2(s * 0.08, s * 0.28)))
				"util_fabricator":
					d = absf(_box(p - c, Vector2.ONE * s * 0.22)) - line * 0.6
					d = minf(d, p.distance_to(c) - s * 0.08)
				_:
					d = absf(p.distance_to(c) - s * 0.25) - line * 0.6
	var ink: Color = OUTLINE if dark else MARK
	return under.lerp(Color(ink, 1.0), _cover(d) * (0.85 if dark else 0.9))


## Distance to the module's rounded body (negative inside). A full rectangle
## is one rounded box; any other shape is its cells joined, each inset only
## where it has no neighbour.
static func _body_distance(p: Vector2, cells: Dictionary, cell_px: int, inset: float, radius: float, size: Vector2) -> float:
	if cells.size() * cell_px * cell_px == int(size.x * size.y):
		var half := size * 0.5 - Vector2.ONE * inset
		return _box(p - size * 0.5, half - Vector2.ONE * radius) - radius
	var best: float = INF
	var home := Vector2i(floori(p.x / cell_px), floori(p.y / cell_px))
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			var cell := home + Vector2i(dx, dy)
			if not cells.has(cell):
				continue
			var lo := Vector2(cell) * cell_px
			var hi := lo + Vector2.ONE * cell_px
			if not cells.has(cell + Vector2i.LEFT):
				lo.x += inset
			if not cells.has(cell + Vector2i.UP):
				lo.y += inset
			if not cells.has(cell + Vector2i.RIGHT):
				hi.x -= inset
			if not cells.has(cell + Vector2i.DOWN):
				hi.y -= inset
			var half := (hi - lo) * 0.5
			best = minf(best, _box(p - (lo + half), half))
	return best


static func _box(p: Vector2, half: Vector2) -> float:
	var q := Vector2(absf(p.x), absf(p.y)) - half
	return Vector2(maxf(q.x, 0.0), maxf(q.y, 0.0)).length() + minf(maxf(q.x, q.y), 0.0)


static func _hexagon(p: Vector2, r: float) -> float:
	var q := Vector2(absf(p.x), absf(p.y))
	return maxf(q.x * 0.866 + q.y * 0.5, q.y) - r


## 0..1 coverage of a pixel by a shape at signed distance `d` (inside < 0).
static func _cover(d: float) -> float:
	return clampf(0.5 - d, 0.0, 1.0)

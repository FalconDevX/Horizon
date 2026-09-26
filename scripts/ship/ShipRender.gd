class_name ShipRender
extends RefCounted
## Flattens the ship built in the yard (ShipHull) into one picture, for the
## ship in space (ship.gd) and the HUD preview (ship_blueprint_panel.gd).
## Every module's art is laid on its cells, turned as it was placed -
## structure first, equipment over it - with the nose to the right (+x), the
## way the ship faces at rotation 0.

## Pixels per build cell in the composed picture.
const CELL_PX := 32


## {texture, rect, engines, turrets, modules} for `hull`, or {} with nothing
## built. `modules` lists every module's footprint for the damage schematic:
## {id, title, rect (ship-local units), max_hp, structure, texture (its art
## as placed, nose right; null without art)}.
## Turret guns are left out of the picture and listed in `turrets` -
## {id, texture, center, size} in ship-local units - so ship.gd can turn them. `rect` is
## where the picture goes in ship-local units, centred on the structure the
## same way the weapon and radar mounts are (FovUtil.WORLD_UNITS_PER_CELL per
## cell), so their cones leave the right spots; `engines` are the main
## engines' aft points in the same space, where the flames go.
static func compose(hull: ShipHull) -> Dictionary:
	var modules: Array[PlacedModule] = hull.get_all_modules()
	if modules.is_empty():
		return {}
	var lo := Vector2i(1 << 30, 1 << 30)
	var hi := Vector2i(-(1 << 30), -(1 << 30))
	for m: PlacedModule in modules:
		for cell: Vector2i in m.get_occupied_cells():
			lo = Vector2i(mini(lo.x, cell.x), mini(lo.y, cell.y))
			hi = Vector2i(maxi(hi.x, cell.x), maxi(hi.y, cell.y))
	var size_cells: Vector2i = hi - lo + Vector2i.ONE
	var image := Image.create(size_cells.x * CELL_PX, size_cells.y * CELL_PX, false, Image.FORMAT_RGBA8)
	image.fill(Color(0.0, 0.0, 0.0, 0.0))

	var ordered: Array[PlacedModule] = []
	ordered.append_array(modules.filter(func(m: PlacedModule) -> bool: return m.data.is_structure()))
	ordered.append_array(modules.filter(func(m: PlacedModule) -> bool: return not m.data.is_structure()))
	var centroid: Vector2 = hull.structure_centroid()
	var unit: float = FovUtil.WORLD_UNITS_PER_CELL
	var engines: Array[Vector2] = []
	var turrets: Array[Dictionary] = []
	var footprints: Array[Dictionary] = []
	for m: PlacedModule in ordered:
		var corner: Vector2i = _top_left(m)
		var bounds: Vector2i = m.get_bounding_size()
		var art: Image = _module_image(m)
		var art_texture: ImageTexture = null
		if art != null:
			art.resize(bounds.x * CELL_PX, bounds.y * CELL_PX, Image.INTERPOLATE_BILINEAR)
			art_texture = ImageTexture.create_from_image(art)
		footprints.append({
			"id": m.instance_id,
			"title": m.data.title,
			"rect": Rect2((Vector2(corner) - centroid) * unit, Vector2(bounds) * unit),
			"max_hp": maxf(m.data.health, 1.0),
			"structure": m.data.is_structure(),
			"texture": art_texture,
		})
		if m.data.is_main_engine():
			# Aft = the grid's left: the middle of the engine's left edge.
			engines.append((Vector2(corner.x, corner.y + bounds.y * 0.5) - centroid) * unit)
		if art == null:
			continue
		if m.data.is_turret():
			turrets.append({
				"id": m.instance_id,
				"texture": art_texture,
				"center": (Vector2(corner) + Vector2(bounds) * 0.5 - centroid) * unit,
				"size": Vector2(bounds) * unit,
			})
			continue
		image.blend_rect(art, Rect2i(Vector2i.ZERO, art.get_size()), (corner - lo) * CELL_PX)

	var texture := ImageTexture.create_from_image(image)
	return {
		"texture": texture,
		"rect": Rect2((Vector2(lo) - centroid) * unit, Vector2(size_cells) * unit),
		"engines": engines,
		"turrets": turrets,
		"modules": footprints,
	}


static func _top_left(m: PlacedModule) -> Vector2i:
	var corner := Vector2i(1 << 30, 1 << 30)
	for cell: Vector2i in m.get_occupied_cells():
		corner = Vector2i(mini(corner.x, cell.x), mini(corner.y, cell.y))
	return corner


## The module's picture as placed: hulls their outside art, everything else
## its catalog texture, turned clockwise a quarter per rotation step (as the
## yard turns shapes and art).
static func _module_image(m: PlacedModule) -> Image:
	var texture: Texture2D = m.data.texture
	if m.data.category == ModuleData.Category.HULL and m.data.hull_data != null:
		texture = m.data.hull_data.custom_texture if m.data.hull_data.custom_texture != null else m.data.hull_data.interior_texture
	if texture == null:
		return null
	var image: Image = texture.get_image()
	if image == null:
		return null
	image = image.duplicate()
	if image.is_compressed():
		image.decompress()
	image.convert(Image.FORMAT_RGBA8)
	for _i in posmod(m.rotation, 4):
		image.rotate_90(CLOCKWISE)
	return image

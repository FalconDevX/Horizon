class_name FovUtil
extends RefCounted
## Shared FOV math + drawing for shipyard preview and in-world cones.
## Angle is always real degrees. Range is stored in world SU; builder scales it.
## Rot 0 faces +X (right edge of the module = muzzle / LOS exit).
## Rays that leave free space and then hit hull cells are blocked.

## World SU mapped to one shipyard cell when previewing cones.
const BUILDER_SU_PER_CELL := 250.0
## Grid cell → ship-local offset on the orbital map (keeps mounts near the hull icon).
const WORLD_UNITS_PER_CELL := 1.8
const CONE_SEGMENTS := 28
const LOS_STEP_FRAC := 0.2 ## fraction of a cell per ray-march step


## Authoring face for rot 0 = +X (right). Quarters are clockwise on screen
## (y down), the same way ModuleData.rotate_shape and the grid's rotated art
## turn - so the cone leaves the barrel end.
static func local_facing(rotation: int) -> Vector2:
	return Vector2.RIGHT.rotated(float(posmod(rotation, 4)) * PI * 0.5)


static func builder_preview_length(fov_range_su: float, cell_size: float) -> float:
	if fov_range_su <= 0.0 or cell_size <= 0.0:
		return 0.0
	return (fov_range_su / BUILDER_SU_PER_CELL) * cell_size


static func module_center_cell(origin: Vector2i, data: ModuleData, rotation: int) -> Vector2:
	if data == null:
		return Vector2(origin) + Vector2(0.5, 0.5)
	var bounds := data.get_bounding_size(rotation)
	return Vector2(origin) + Vector2(bounds) * 0.5


## LOS exits from the facing edge of the footprint (right side at rot 0).
static func module_muzzle_cell(origin: Vector2i, data: ModuleData, rotation: int) -> Vector2:
	var center := module_center_cell(origin, data, rotation)
	var facing := local_facing(rotation)
	var bounds := Vector2i.ONE if data == null else data.get_bounding_size(rotation)
	return center + Vector2(facing.x * float(bounds.x) * 0.5, facing.y * float(bounds.y) * 0.5)


static func is_point_in_cone(
	origin: Vector2,
	facing: Vector2,
	half_angle_rad: float,
	range_su: float,
	point: Vector2
) -> bool:
	if range_su <= 0.0 or facing.length_squared() < 0.0001:
		return false
	var to_point := point - origin
	var dist := to_point.length()
	if dist > range_su or dist < 0.0001:
		return false
	return absf(facing.angle_to(to_point)) <= half_angle_rad


## True if the segment clears hull after leaving free space (or if start is already free).
## `hull_rects` are axis-aligned blockers in the same space as `from` / `to`.
static func has_clear_los(
	from: Vector2,
	to: Vector2,
	hull_rects: Array,
	ignore_rects: Array = []
) -> bool:
	var delta := to - from
	var dist := delta.length()
	if dist < 0.0001:
		return true
	var dir := delta / dist
	var step := maxf(WORLD_UNITS_PER_CELL * LOS_STEP_FRAC, dist * 0.02)
	var seen_free := not _point_in_any_rect(from, hull_rects) or _point_in_any_rect(from, ignore_rects)
	var traveled := 0.0
	while traveled < dist:
		traveled = minf(traveled + step, dist)
		var p := from + dir * traveled
		if _point_in_any_rect(p, ignore_rects):
			continue
		var in_hull := _point_in_any_rect(p, hull_rects)
		if in_hull:
			if seen_free:
				return false
		else:
			seen_free = true
	return true


static func _point_in_any_rect(point: Vector2, rects: Array) -> bool:
	for item in rects:
		if item is Rect2 and (item as Rect2).has_point(point):
			return true
	return false


## Ray length until hull blocks LOS (after clearing interior / own cells).
static func cast_los_length(
	origin: Vector2,
	dir: Vector2,
	max_length: float,
	cell_size: float,
	blocked_cells: Dictionary,
	ignore_cells: Dictionary = {}
) -> float:
	if max_length <= 0.0 or dir.length_squared() < 0.0001 or cell_size <= 0.0:
		return 0.0
	var d := dir.normalized()
	var step := cell_size * LOS_STEP_FRAC
	var origin_cell := _pos_to_cell(origin, cell_size)
	var start_blocked := blocked_cells.has(origin_cell) and not ignore_cells.has(origin_cell)
	var seen_free := not start_blocked
	var traveled := 0.0
	while traveled < max_length:
		traveled += step
		var p := origin + d * minf(traveled, max_length)
		var cell := _pos_to_cell(p, cell_size)
		if ignore_cells.has(cell):
			continue
		if blocked_cells.has(cell):
			if seen_free:
				return maxf(traveled - step, 0.0)
		else:
			seen_free = true
	return max_length


static func _pos_to_cell(pos: Vector2, cell_size: float) -> Vector2i:
	return Vector2i(floori(pos.x / cell_size), floori(pos.y / cell_size))


## Ray length until a hull rect blocks LOS (after clearing interior).
static func cast_los_length_rects(
	origin: Vector2,
	dir: Vector2,
	max_length: float,
	hull_rects: Array,
	ignore_rects: Array = []
) -> float:
	if max_length <= 0.0 or dir.length_squared() < 0.0001:
		return 0.0
	var d := dir.normalized()
	var step := maxf(WORLD_UNITS_PER_CELL * LOS_STEP_FRAC, max_length * 0.01)
	var seen_free := (
		not _point_in_any_rect(origin, hull_rects)
		or _point_in_any_rect(origin, ignore_rects)
	)
	var traveled := 0.0
	while traveled < max_length:
		traveled += step
		var p := origin + d * minf(traveled, max_length)
		if _point_in_any_rect(p, ignore_rects):
			continue
		var in_hull := _point_in_any_rect(p, hull_rects)
		if in_hull:
			if seen_free:
				return maxf(traveled - step, 0.0)
		else:
			seen_free = true
	return max_length


static func cone_polygon(
	origin: Vector2,
	facing: Vector2,
	angle_deg: float,
	length: float,
	segments: int = CONE_SEGMENTS
) -> PackedVector2Array:
	return cone_polygon_los(origin, facing, angle_deg, length, {}, {}, 1.0, segments)


## Builds a fan clipped by hull cells. `cell_size` in the same units as origin/length.
static func cone_polygon_los(
	origin: Vector2,
	facing: Vector2,
	angle_deg: float,
	length: float,
	blocked_cells: Dictionary,
	ignore_cells: Dictionary = {},
	cell_size: float = 1.0,
	segments: int = CONE_SEGMENTS
) -> PackedVector2Array:
	var points := PackedVector2Array()
	if length <= 0.0 or angle_deg <= 0.0 or facing.length_squared() < 0.0001:
		return points
	var dir := facing.normalized()
	var half := deg_to_rad(angle_deg) * 0.5
	var base_angle := dir.angle()
	points.append(origin)
	var steps := maxi(segments, 4)
	for i in range(steps + 1):
		var t := float(i) / float(steps)
		var a := base_angle - half + (half * 2.0) * t
		var ray := Vector2.from_angle(a)
		var ray_len := length
		if not blocked_cells.is_empty():
			ray_len = cast_los_length(origin, ray, length, cell_size, blocked_cells, ignore_cells)
		points.append(origin + ray * ray_len)
	return points


static func cone_polygon_los_rects(
	origin: Vector2,
	facing: Vector2,
	angle_deg: float,
	length: float,
	hull_rects: Array,
	ignore_rects: Array = [],
	segments: int = CONE_SEGMENTS
) -> PackedVector2Array:
	var points := PackedVector2Array()
	if length <= 0.0 or angle_deg <= 0.0 or facing.length_squared() < 0.0001:
		return points
	var dir := facing.normalized()
	var half := deg_to_rad(angle_deg) * 0.5
	var base_angle := dir.angle()
	points.append(origin)
	var steps := maxi(segments, 4)
	for i in range(steps + 1):
		var t := float(i) / float(steps)
		var a := base_angle - half + (half * 2.0) * t
		var ray := Vector2.from_angle(a)
		var ray_len := length
		if not hull_rects.is_empty():
			ray_len = cast_los_length_rects(origin, ray, length, hull_rects, ignore_rects)
		points.append(origin + ray * ray_len)
	return points


static func draw_cone(
	ci: CanvasItem,
	origin: Vector2,
	facing: Vector2,
	angle_deg: float,
	length: float,
	fill: Color,
	outline: Color,
	outline_width: float = 1.5,
	blocked_cells: Dictionary = {},
	ignore_cells: Dictionary = {},
	cell_size: float = 1.0
) -> void:
	var poly := cone_polygon_los(
		origin, facing, angle_deg, length, blocked_cells, ignore_cells, cell_size
	)
	_stroke_cone(ci, poly, fill, outline, outline_width)


static func draw_cone_rects(
	ci: CanvasItem,
	origin: Vector2,
	facing: Vector2,
	angle_deg: float,
	length: float,
	fill: Color,
	outline: Color,
	outline_width: float,
	hull_rects: Array,
	ignore_rects: Array = []
) -> void:
	var poly := cone_polygon_los_rects(
		origin, facing, angle_deg, length, hull_rects, ignore_rects
	)
	_stroke_cone(ci, poly, fill, outline, outline_width)


static func _stroke_cone(
	ci: CanvasItem,
	poly: PackedVector2Array,
	fill: Color,
	outline: Color,
	outline_width: float
) -> void:
	if poly.size() < 3:
		return
	var apex: Vector2 = poly[0]
	ci.draw_colored_polygon(poly, fill)
	ci.draw_polyline(poly, outline, outline_width, true)
	ci.draw_line(poly[poly.size() - 1], apex, outline, outline_width, true)
	ci.draw_line(apex, poly[1], outline, outline_width, true)

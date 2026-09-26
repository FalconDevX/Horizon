class_name EnemyMarkers
extends RefCounted
## How each enemy type looks on the HUD: a red shape and a short code
## ("MS" for a mothership), for the far-zoom map and the contacts panel.

## Red HUD marker per craft type: [abbreviation, shape]. Drawn by
## draw_marker() on the far-zoom map and in the contacts panel. Keys are
## Enemy.type_id ("fighter" = a mothership's deployed craft).
const MARKERS := {
	"basic": ["BS", "chevron"],
	"tank": ["TK", "square"],
	"sniper": ["SN", "diamond"],
	"kamikaze": ["KZ", "dart"],
	"cruiser": ["CR", "hexagon"],
	"mothership": ["MS", "carrier"],
	"minelayer": ["ML", "mine"],
	"black_hole": ["BH", "ring"],
	"fighter": ["FT", "small"],
}
const MARKER_COLOR := Color(1.0, 0.22, 0.18)
## Same names as EnemyCatalog's roster (kept here so Enemy.gd can use this
## without loading the catalog, which preloads the enemy scenes).
const TITLES := {
	"basic": "Basic", "tank": "Tank", "sniper": "Sniper", "kamikaze": "Kamikaze",
	"cruiser": "Cruiser", "mothership": "Mothership", "minelayer": "Minelayer",
	"black_hole": "Black hole", "fighter": "Fighter",
}


static func abbreviation(type_id: String) -> String:
	return String(MARKERS.get(type_id, ["??", "chevron"])[0])


static func title_for(type_id: String) -> String:
	return String(TITLES.get(type_id, "Unknown"))


## The type's marker, `size` px across round `center`; `heading` turns the
## pointed shapes (chevron, dart, small) the way the craft flies.
static func draw_marker(
	canvas: CanvasItem, center: Vector2, size: float, type_id: String, color: Color = MARKER_COLOR, heading: float = 0.0
) -> void:
	var shape: String = String(MARKERS.get(type_id, ["??", "chevron"])[1])
	var r: float = size * 0.5
	var line: float = maxf(size * 0.12, 1.0)
	match shape:
		"chevron":
			canvas.draw_colored_polygon(_turned([Vector2(r, 0), Vector2(-r * 0.7, -r * 0.6), Vector2(-r * 0.7, r * 0.6)], center, heading), color)
		"small":
			canvas.draw_colored_polygon(_turned([Vector2(r * 0.7, 0), Vector2(-r * 0.5, -r * 0.4), Vector2(-r * 0.5, r * 0.4)], center, heading), color)
		"dart":
			canvas.draw_colored_polygon(_turned([Vector2(r, 0), Vector2(-r * 0.8, -r * 0.45), Vector2(-r * 0.35, 0), Vector2(-r * 0.8, r * 0.45)], center, heading), color)
		"square":
			canvas.draw_rect(Rect2(center - Vector2(r, r) * 0.75, Vector2(r, r) * 1.5), color)
		"diamond":
			canvas.draw_colored_polygon(_turned([Vector2(r, 0), Vector2(0, -r * 0.7), Vector2(-r, 0), Vector2(0, r * 0.7)], center, 0.0), color)
		"hexagon":
			canvas.draw_colored_polygon(_ngon(center, r * 0.9, 6, 0.0), color)
		"carrier":
			# A big pentagon with a hollow middle - the fighters' hangar.
			canvas.draw_colored_polygon(_ngon(center, r, 5, -PI * 0.5), color)
			canvas.draw_colored_polygon(_ngon(center, r * 0.45, 5, -PI * 0.5), Color(0.05, 0.02, 0.02, 0.9))
		"mine":
			canvas.draw_arc(center, r * 0.75, 0.0, TAU, 20, color, line, true)
			for i in 4:
				var d := Vector2.RIGHT.rotated(PI * 0.25 + i * PI * 0.5)
				canvas.draw_line(center + d * r * 0.3, center + d * r, color, line, true)
		"ring":
			canvas.draw_arc(center, r * 0.8, 0.0, TAU, 24, color, line * 1.4, true)
			canvas.draw_circle(center, r * 0.3, color)
		_:
			canvas.draw_circle(center, r * 0.6, color)


static func _turned(points: Array, center: Vector2, angle: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p: Vector2 in points:
		out.append(center + p.rotated(angle))
	return out


static func _ngon(center: Vector2, r: float, sides: int, start: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in sides:
		out.append(center + Vector2.RIGHT.rotated(start + TAU * i / sides) * r)
	return out

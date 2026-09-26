class_name EnemyCatalog
extends RefCounted
## Roster for the sandbox (E) enemy menu, and which craft guard planets.
## Each type also has a flat HUD/map glyph (shape + colour) so contacts stay
## readable at a glance.

## Ids that orbit ordinary worlds (no T3 deposits).
const BASIC_IDS: Array[String] = ["basic", "tank", "sniper", "kamikaze"]
## Ids that orbit worlds with at least one T3 deposit.
const ELITE_IDS: Array[String] = ["cruiser", "mothership", "minelayer", "black_hole"]

## Flat marker look per id: colour + glyph name (see draw_glyph).
const MARKERS := {
	"basic": {"color": Color(1.0, 0.32, 0.22), "glyph": "triangle"},
	"tank": {"color": Color(1.0, 0.72, 0.12), "glyph": "square"},
	"sniper": {"color": Color(0.95, 0.9, 0.2), "glyph": "diamond"},
	"kamikaze": {"color": Color(1.0, 0.2, 0.45), "glyph": "cross"},
	"fast": {"color": Color(0.15, 0.85, 1.0), "glyph": "dart"},
	"cruiser": {"color": Color(1.0, 0.45, 0.2), "glyph": "hex"},
	"mothership": {"color": Color(0.72, 0.35, 1.0), "glyph": "bar"},
	"minelayer": {"color": Color(0.25, 0.9, 0.45), "glyph": "ring"},
	"black_hole": {"color": Color(0.55, 0.4, 1.0), "glyph": "hole"},
}


static func all_enemies() -> Array[Dictionary]:
	return [
		{
			"id": "basic",
			"title": "Basic",
			"texture": preload("res://textures/enemies/enemy_basic.png"),
			"scene": preload("res://scenes/enemies/Enemy.tscn"),
		},
		{
			"id": "tank",
			"title": "Tank",
			"texture": preload("res://textures/enemies/enemy_tank.png"),
			"scene": preload("res://scenes/enemies/EnemyTank.tscn"),
		},
		{
			"id": "sniper",
			"title": "Sniper",
			"texture": preload("res://textures/enemies/enemy_sniper.png"),
			"scene": preload("res://scenes/enemies/EnemySniper.tscn"),
		},
		{
			"id": "kamikaze",
			"title": "Kamikaze",
			"texture": preload("res://textures/enemies/enemy_kamikaze.png"),
			"scene": preload("res://scenes/enemies/EnemyKamikaze.tscn"),
		},
		{
			"id": "fast",
			"title": "Fast",
			"texture": preload("res://textures/enemies/enemy_fast.png"),
			"scene": preload("res://scenes/enemies/EnemyFast.tscn"),
		},
		{
			"id": "cruiser",
			"title": "Cruiser",
			"texture": preload("res://textures/enemies/enemy_cruiser.png"),
			"scene": preload("res://scenes/enemies/EnemyCruiser.tscn"),
		},
		{
			"id": "mothership",
			"title": "Mothership",
			"texture": preload("res://textures/enemies/enemy_mothership.png"),
			"scene": preload("res://scenes/enemies/EnemyMothership.tscn"),
		},
		{
			"id": "minelayer",
			"title": "Minelayer",
			"texture": preload("res://textures/enemies/enemy_minelayer.png"),
			"scene": preload("res://scenes/enemies/EnemyMinelayer.tscn"),
		},
		{
			"id": "black_hole",
			"title": "Black hole",
			"texture": preload("res://textures/enemies/enemy_black_hole.png"),
			"scene": preload("res://scenes/enemies/EnemyBlackHole.tscn"),
		},
	]


static func entry_for(enemy_id: String) -> Dictionary:
	for candidate: Dictionary in all_enemies():
		if str(candidate.get("id", "")) == enemy_id:
			return candidate
	return {}


static func scene_for(enemy_id: String) -> PackedScene:
	return entry_for(enemy_id).get("scene") as PackedScene


static func marker_of(enemy_id: String) -> Dictionary:
	return MARKERS.get(enemy_id, MARKERS["basic"]) as Dictionary


static func marker_color(enemy_id: String) -> Color:
	return marker_of(enemy_id).get("color", Color(1.0, 0.3, 0.25)) as Color


## Apply catalog title / kind id (and texture, if the scene left it blank).
static func configure(enemy: Enemy, enemy_id: String) -> void:
	var entry: Dictionary = entry_for(enemy_id)
	if entry.is_empty() or enemy == null:
		return
	enemy.kind_id = enemy_id
	enemy.title = str(entry.get("title", enemy.title))
	var tex: Texture2D = entry.get("texture") as Texture2D
	if tex != null and enemy.ship_texture == null:
		enemy.ship_texture = tex


## Flat HUD / map glyph. `nose_right` true = sharp end along +X (ship local);
## false = upright for panels (+Y up).
static func draw_glyph(
	ci: CanvasItem,
	center: Vector2,
	radius: float,
	enemy_id: String,
	nose_right: bool = false
) -> void:
	var marker: Dictionary = marker_of(enemy_id)
	var color: Color = marker.get("color", Color(1.0, 0.3, 0.25)) as Color
	var glyph: String = str(marker.get("glyph", "triangle"))
	var rot: float = -PI * 0.5 if nose_right else 0.0
	match glyph:
		"square":
			_draw_poly(ci, center, radius, color, rot, [
				Vector2(-0.7, -0.7), Vector2(0.7, -0.7), Vector2(0.7, 0.7), Vector2(-0.7, 0.7),
			])
		"diamond":
			_draw_poly(ci, center, radius, color, rot, [
				Vector2(0.0, -1.0), Vector2(0.7, 0.0), Vector2(0.0, 1.0), Vector2(-0.7, 0.0),
			])
		"cross":
			_draw_cross(ci, center, radius, color, rot)
		"dart":
			_draw_poly(ci, center, radius, color, rot, [
				Vector2(0.0, -1.05), Vector2(0.45, 0.85), Vector2(0.0, 0.45), Vector2(-0.45, 0.85),
			])
		"hex":
			_draw_poly(ci, center, radius, color, rot, [
				Vector2(0.0, -1.0), Vector2(0.86, -0.5), Vector2(0.86, 0.5),
				Vector2(0.0, 1.0), Vector2(-0.86, 0.5), Vector2(-0.86, -0.5),
			])
		"bar":
			_draw_poly(ci, center, radius, color, rot, [
				Vector2(-1.0, -0.45), Vector2(1.0, -0.45), Vector2(1.0, 0.45), Vector2(-1.0, 0.45),
			])
		"ring":
			ci.draw_circle(center, radius * 0.85, color)
			ci.draw_circle(center, radius * 0.45, Color(0.05, 0.07, 0.1, 1.0))
			ci.draw_circle(center + Vector2(0.0, -radius * 0.05).rotated(rot), radius * 0.18, color)
		"hole":
			ci.draw_arc(center, radius * 0.9, 0.0, TAU, 28, color, maxf(radius * 0.28, 2.0), true)
			ci.draw_circle(center, radius * 0.28, Color(0.08, 0.04, 0.14, 1.0))
			ci.draw_circle(center, radius * 0.12, color)
		_:
			# triangle
			_draw_poly(ci, center, radius, color, rot, [
				Vector2(0.0, -1.0), Vector2(0.85, 0.8), Vector2(-0.85, 0.8),
			])


static func _draw_poly(
	ci: CanvasItem,
	center: Vector2,
	radius: float,
	color: Color,
	rot: float,
	units: Array
) -> void:
	var points := PackedVector2Array()
	for u: Vector2 in units:
		points.append(center + u.rotated(rot) * radius)
	ci.draw_colored_polygon(points, color)


static func _draw_cross(
	ci: CanvasItem,
	center: Vector2,
	radius: float,
	color: Color,
	rot: float
) -> void:
	var t: float = radius * 0.28
	var arm: float = radius * 0.95
	var bars: Array = [
		[Vector2(-t, -arm), Vector2(t, -arm), Vector2(t, arm), Vector2(-t, arm)],
		[Vector2(-arm, -t), Vector2(arm, -t), Vector2(arm, t), Vector2(-arm, t)],
	]
	for bar: Array in bars:
		var points := PackedVector2Array()
		for u: Vector2 in bar:
			points.append(center + (u as Vector2).rotated(rot))
		ci.draw_colored_polygon(points, color)

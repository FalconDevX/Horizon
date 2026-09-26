class_name EnemyCatalog
extends RefCounted
## Roster for the sandbox (E) enemy menu, planet guards, and the planetary
## catalog's ENEMIES tab. Each type has art, a flat HUD/map glyph, and lore.

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

## Cached combat numbers read once from each enemy scene.
static var _combat_cache: Dictionary = {}


static func all_enemies() -> Array[Dictionary]:
	return [
		{
			"id": "basic",
			"title": "Basic",
			"role": "Patrol craft",
			"roster": "basic",
			"texture": preload("res://textures/enemies/enemy_basic.png"),
			"scene": preload("res://scenes/enemies/Enemy.tscn"),
			"description": "The workhorse of planetary defence. Light, cheap, and common on worlds without rare deposits. It flies a circular rail until a ship comes close, then breaks orbit to chase and fire twin forward lasers.",
			"facts": [
				"Most basic-roster planets field two to four of these at once.",
				"Its silhouette is the catalog's red triangle on long-range contacts.",
			],
		},
		{
			"id": "tank",
			"title": "Tank",
			"role": "Heavy gunship",
			"roster": "basic",
			"texture": preload("res://textures/enemies/enemy_tank.png"),
			"scene": preload("res://scenes/enemies/EnemyTank.tscn"),
			"description": "A slow, broad-hulled gunship built to absorb fire and return it with a heavy forward cannon. Turns poorly, but each bolt hits harder and travels farther than a Basic's twin guns.",
			"facts": [
				"Amber square on the contacts panel - hard to miss in a mixed patrol.",
				"Favours holding a firing lane rather than jinking past you.",
			],
		},
		{
			"id": "sniper",
			"title": "Sniper",
			"role": "Long-range beam",
			"roster": "basic",
			"texture": preload("res://textures/enemies/enemy_sniper.png"),
			"scene": preload("res://scenes/enemies/EnemySniper.tscn"),
			"description": "A spindly beam platform. It barely moves, but when it fires the shot is instant across extreme range - a yellow diamond on the radar means you are already in its corridor.",
			"facts": [
				"Reload is long; closing the gap between shots is safer than trading at distance.",
				"The beam ignores travel time - there is no dodge window once it lights.",
			],
		},
		{
			"id": "kamikaze",
			"title": "Kamikaze",
			"role": "Ram drone",
			"roster": "basic",
			"texture": preload("res://textures/enemies/enemy_kamikaze.png"),
			"scene": preload("res://scenes/enemies/EnemyKamikaze.tscn"),
			"description": "An unarmed dart that exists to collide. It detonates on hull contact or the first hit it takes, trading its own frame for a burst of contact damage.",
			"facts": [
				"Magenta cross on contacts. Shoot early - a near miss still closes fast.",
				"Spawned on the same basic roster as patrol craft and tanks.",
			],
		},
		{
			"id": "fast",
			"title": "Fast",
			"role": "Interceptor",
			"roster": "fighter",
			"texture": preload("res://textures/enemies/enemy_fast.png"),
			"scene": preload("res://scenes/enemies/EnemyFast.tscn"),
			"description": "A mothership-launched interceptor: light, agile, and armed with very high-velocity bolts. It does not orbit with planet guards on its own - carriers deploy it once the patrol is alerted.",
			"facts": [
				"Cyan dart glyph. Bolts arrive almost as soon as the muzzle flashes.",
				"Launched every ten to fifteen seconds while a Mothership is fighting.",
			],
		},
		{
			"id": "cruiser",
			"title": "Cruiser",
			"role": "Capital escort",
			"roster": "elite",
			"texture": preload("res://textures/enemies/enemy_cruiser.png"),
			"scene": preload("res://scenes/enemies/EnemyCruiser.tscn"),
			"description": "A multi-battery escort found on worlds rich in tier-3 deposits. Twin forward guns and broadside mounts make it dangerous from several angles at once.",
			"facts": [
				"Orange hexagon on the map. Elite roster only.",
				"Fires more often than a Tank and from more muzzles.",
			],
		},
		{
			"id": "mothership",
			"title": "Mothership",
			"role": "Carrier",
			"roster": "elite",
			"texture": preload("res://textures/enemies/enemy_mothership.png"),
			"scene": preload("res://scenes/enemies/EnemyMothership.tscn"),
			"description": "A lumbering carrier that holds orbit until approached, then breaks to chase while launching Fast interceptors. It has no forward guns of its own - the threat is the swarm it feeds.",
			"facts": [
				"Purple bar glyph. Kill it to stop the fighter trickle.",
				"Only wakes and deploys when you enter the planet's alert range.",
			],
		},
		{
			"id": "minelayer",
			"title": "Minelayer",
			"role": "Area denial",
			"roster": "elite",
			"texture": preload("res://textures/enemies/enemy_minelayer.png"),
			"scene": preload("res://scenes/enemies/EnemyMinelayer.tscn"),
			"description": "Drops lingering damage fields instead of shooting. Each mine is a glowing hazard zone that burns anything that drifts through it for several seconds.",
			"facts": [
				"Green ring on contacts. Watch where it has already been.",
				"Mines outlive a short dogfight - leave the area or punch through.",
			],
		},
		{
			"id": "black_hole",
			"title": "Black hole",
			"role": "Anomaly weapon",
			"roster": "elite",
			"texture": preload("res://textures/enemies/enemy_black_hole.png"),
			"scene": preload("res://scenes/enemies/EnemyBlackHole.tscn"),
			"description": "A hostile craft that opens a short-lived gravity well. While armed it pulls ships, bolts and mines inward, then detonates in a wide blast when the fuse runs out.",
			"facts": [
				"Violet hollow ring. Stay outside the pull if you can.",
				"The fuse only counts down while the well is active and near you.",
			],
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


## Human label for which planet-guard pool this type belongs to.
static func roster_label(enemy_id: String) -> String:
	match str(entry_for(enemy_id).get("roster", "")):
		"elite":
			return "Elite patrol - T3 deposit worlds"
		"fighter":
			return "Carrier fighter - launched in combat"
		_:
			return "Basic patrol - ordinary worlds"


## Live combat numbers from the type's scene (cached).
static func combat_stats(enemy_id: String) -> Dictionary:
	if _combat_cache.has(enemy_id):
		return _combat_cache[enemy_id]
	var scene: PackedScene = scene_for(enemy_id)
	var stats: Dictionary = {
		"hull": 60.0,
		"speed": 160.0,
		"turn": 2.6,
		"armament": "None",
		"damage": 0.0,
		"range": 0.0,
	}
	if scene == null:
		_combat_cache[enemy_id] = stats
		return stats
	var enemy := scene.instantiate() as Enemy
	if enemy == null:
		_combat_cache[enemy_id] = stats
		return stats
	stats["hull"] = enemy.max_health
	stats["speed"] = enemy.move_speed
	stats["turn"] = enemy.turn_speed
	if enemy.explodes_on_hit:
		stats["armament"] = "Ram / detonation"
		stats["damage"] = enemy.contact_damage
	elif enemy.deploy_fighters:
		stats["armament"] = "Fast fighter bay"
		stats["range"] = enemy.deploy_cooldown
	elif enemy.lay_mines:
		stats["armament"] = "Damage mines"
		stats["damage"] = enemy.mine_dps
		stats["range"] = enemy.mine_radius
	elif enemy.black_hole_mode:
		stats["armament"] = "Gravity well + blast"
		stats["damage"] = enemy.black_hole_blast_damage
		stats["range"] = enemy.black_hole_radius
	elif enemy.beam_mode:
		stats["armament"] = "Sniper beam"
		stats["damage"] = enemy.laser_damage
		stats["range"] = enemy.laser_range
	elif enemy.can_fire:
		stats["armament"] = "Laser bolts"
		stats["damage"] = enemy.laser_damage
		stats["range"] = enemy.laser_range
	enemy.free()
	_combat_cache[enemy_id] = stats
	return stats


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

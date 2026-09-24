class_name ResourceDeposits
extends RefCounted

## Resource deposits on terrain planets: objects of their own standing on the
## ground (children of the planet's sphere, so they turn with it), not part of
## the heightmap - the player will pick them up.
##
## Two tables drive it all:
## - TYPES: what each resource is and how it looks (shape from
##   deposit_meshes.gd, colour, shine, glow, size).
## - SPAWNS: which resources each planet kind gets, how many, and where - on
##   land or liquid, in which height band, how steep, on which landmark - and
##   whether they move (DepositMotion; see deposit_motion.gd to add a walk).
## Placement runs on the baked heightmap (PlanetTerrain.height_at), so it
## agrees with the picture. Everything is rolled from the planet's generation
## seed: a world always gets the same deposits, a reroll (N) new ones.

const SHADER := preload("res://resource_deposit.gdshader")

## What each resource is. `size` is the cluster's footprint in planet radii;
## the rest are resource_deposit.gdshader's uniforms.
const TYPES := {
	&"silver_ore": {
		"name": "Silver ore", "mesh": &"crystals", "size": Vector2(0.03, 0.045),
		"color": Color(0.78, 0.8, 0.85), "shine": 0.9, "glow": 0.06,
	},
	&"gold_ore": {
		"name": "Gold ore", "mesh": &"tiles", "size": Vector2(0.05, 0.07),
		"color": Color(1.0, 0.76, 0.28), "shine": 0.9, "glow": 0.06,
	},
	&"scrap": {
		"name": "Scrap", "mesh": &"scrap", "size": Vector2(0.06, 0.08),
		"color": Color.WHITE, "shine": 0.25, "glow": 0.04,
	},
	&"beanstalk": {
		"name": "Beanstalk", "mesh": &"beanstalk", "size": Vector2(0.045, 0.065),
		"color": Color.WHITE, "shine": 0.2, "glow": 0.05, "wiggle": 0.035,
	},
	&"gold_pillar": {
		"name": "Gold pillar", "mesh": &"pillars", "size": Vector2(0.06, 0.09),
		"color": Color(1.0, 0.82, 0.3), "shine": 0.85, "glow": 0.15,
	},
	&"egg": {
		"name": "Egg", "mesh": &"egg", "size": Vector2(0.08, 0.11),
		"color": Color(0.97, 0.96, 0.93), "shine": 0.35, "glow": 0.08,
		"spots": 1.0, "spot_color_a": Color(0.3, 0.55, 1.0), "spot_color_b": Color(1.0, 0.5, 0.75),
	},
	&"sky_stone": {
		"name": "Sky stone", "mesh": &"pebbles", "size": Vector2(0.022, 0.032),
		"color": Color(0.55, 0.88, 1.0), "shine": 1.0, "glow": 0.12,
	},
	&"bone": {
		"name": "Bone", "mesh": &"bones", "size": Vector2(0.06, 0.08),
		"color": Color(0.94, 0.91, 0.82), "shine": 0.3, "glow": 0.05,
	},
	&"toxic_ore": {
		"name": "Toxic ore", "mesh": &"slabs", "size": Vector2(0.05, 0.07),
		"color": Color(0.12, 0.45, 0.14), "shine": 0.5, "glow": 1.1,
	},
}

## What each planet kind spawns: a list of entries, each
##   type    - a key of TYPES
##   count   - how many, rolled per world (fewer if the ground runs out)
##   on      - "land" (default), "liquid" (out on the sea, lava or acid) or
##             "any"
##   land    - height band on land, in the terrain's colour-gradient units
##             (0 = shore or lowest ground, 1 = highest); default all of it
##   lowest  - only the lowest this share of the planet's land (0.1 = its
##             lowest tenth): valley floors, whatever the roll's heights
##   slope   - steepest ground allowed (rise over run; default MAX_SLOPE)
##   feature - a landmark it must stand on: &"swirl_ridge" (a Swirl's raised
##             arm)
##   motion  - &"still" (default) or &"drift" (see MOTIONS)
## Kinds missing here get no deposits.
const SPAWNS := {
	PlanetTerrain.Kind.TERRAN: [
		{"type": &"gold_ore", "count": Vector2i(5, 9)},
		{"type": &"silver_ore", "count": Vector2i(5, 9)},
	],
	PlanetTerrain.Kind.DESERT: [
		{"type": &"gold_ore", "count": Vector2i(14, 20)},
		{"type": &"scrap", "count": Vector2i(2, 4)},
	],
	PlanetTerrain.Kind.BARREN: [
		{"type": &"gold_ore", "count": Vector2i(2, 4)},
		{"type": &"silver_ore", "count": Vector2i(2, 4)},
		{"type": &"scrap", "count": Vector2i(1, 3)},
	],
	PlanetTerrain.Kind.TOXIC: [
		{"type": &"toxic_ore", "count": Vector2i(6, 10)},
	],
	PlanetTerrain.Kind.SLIME: [
		{"type": &"beanstalk", "count": Vector2i(8, 14), "on": "any", "slope": 0.5},
		{"type": &"toxic_ore", "count": Vector2i(5, 8)},
	],
	PlanetTerrain.Kind.OCCULT: [
		{"type": &"gold_ore", "count": Vector2i(8, 14)},
		{"type": &"bone", "count": Vector2i(5, 9)},
	],
	PlanetTerrain.Kind.BLOOM: [
		# The brown valley floors only - the flower fields stay bare.
		{"type": &"beanstalk", "count": Vector2i(8, 14), "lowest": 0.1, "slope": 0.7},
	],
	PlanetTerrain.Kind.OASIS: [
		{"type": &"silver_ore", "count": Vector2i(14, 20)},
		{"type": &"scrap", "count": Vector2i(5, 8)},
	],
	PlanetTerrain.Kind.LOTUS: [
		{"type": &"gold_pillar", "count": Vector2i(5, 9), "on": "liquid"},
	],
	PlanetTerrain.Kind.SWIRL: [
		{"type": &"sky_stone", "count": Vector2i(8, 14), "feature": &"swirl_ridge"},
		{"type": &"silver_ore", "count": Vector2i(6, 10)},
	],
	PlanetTerrain.Kind.RINGS: [
		{"type": &"gold_ore", "count": Vector2i(6, 10)},
	],
	PlanetTerrain.Kind.FRACTAL: [
		# On the massifs: the plains stay below ~0.25.
		{"type": &"egg", "count": Vector2i(1, 3), "land": Vector2(0.45, 1.0), "slope": 0.45},
		{"type": &"silver_ore", "count": Vector2i(8, 14), "land": Vector2(0.0, 0.25)},
	],
}

## Room kept round each deposit, in its own sizes.
const SPACING := 1.6
## Tries per spawn entry; narrow rules (a thin band of valleys) need many.
const ATTEMPTS := 3000
## Height (0..1) a spot must clear the liquid by, or keep under it by. The
## shader's fine detail shifts the shoreline a little either way.
const SHORE_MARGIN := 0.02
## Steepest ground a deposit stands on, by default: rise over run on the
## displaced surface.
const MAX_SLOPE := 0.35
const SLOPE_STEP := 0.012

const MOTIONS := {
	&"still": preload("res://deposit_motion.gd"),
	&"drift": preload("res://deposit_drift.gd"),
}


## The terrain deposits stand and walk on: its rolled look, baked heightmap
## and pole, with the questions deposits ask of them.
class Ground:
	var params: Dictionary
	var data: Dictionary
	var pole: Vector3
	## Land heights sampled over the whole planet, sorted, for `lowest`.
	var _land_sample := PackedFloat32Array()

	func _init(terrain_params: Dictionary, terrain_data: Dictionary, spin_axis: Vector3) -> void:
		params = terrain_params
		data = terrain_data
		pole = spin_axis.normalized()

	## The land height (colour-gradient units) below which `share` of the
	## planet's land lies.
	func land_below(share: float) -> float:
		if _land_sample.is_empty():
			var rng := RandomNumberGenerator.new()
			rng.seed = 1
			for i in range(4096):
				var h: float = PlanetTerrain.height_at(data, ResourceDeposits._random_direction(rng))
				if data["sea_level"] < 0.0 or h >= data["sea_level"]:
					_land_sample.append(ResourceDeposits._land_height(data, h))
			_land_sample.sort()
		if _land_sample.is_empty():
			return 0.0
		return _land_sample[clampi(int(share * _land_sample.size()), 0, _land_sample.size() - 1)]

	## Whether `dir` suits a deposit spawned by `rule` (an entry of SPAWNS).
	func allows(rule: Dictionary, dir: Vector3) -> bool:
		return ResourceDeposits._allows(self, rule, dir)

	## The ground's height above the unit sphere at `dir`, in radii (0 on
	## liquid, which lies at the unit sphere).
	func lift(dir: Vector3) -> float:
		return params["relief"] * ResourceDeposits._ground(data, PlanetTerrain.height_at(data, dir))


## Where the deposits go, as dictionaries: `type` (a key of TYPES),
## `direction` (planet space, unit; kept current as it moves), `lift`, `size`
## (radii), `seed` (for its shape) and `motion`. Empty for kinds with nothing
## in SPAWNS, or before the bake has landed.
static func place(kind: PlanetTerrain.Kind, ground: Ground, body_seed: int) -> Array:
	var deposits: Array = []
	if ground.data.is_empty() or not SPAWNS.has(kind):
		return deposits

	var rng := RandomNumberGenerator.new()
	rng.seed = body_seed ^ 0x5EEDDE9051
	for rule: Dictionary in SPAWNS[kind]:
		var type: Dictionary = TYPES[rule["type"]]
		var count: int = rng.randi_range(rule["count"].x, rule["count"].y)
		var placed: int = 0
		for _attempt in range(ATTEMPTS):
			if placed >= count:
				break
			var dir := _random_direction(rng)
			var size: float = rng.randf_range(type["size"].x, type["size"].y)
			if not _is_clear(deposits, dir, size) or not ground.allows(rule, dir):
				continue
			var motion: DepositMotion = _motion_for(rule).new()
			motion.setup(dir, rule, rng.randi())
			deposits.append({
				"type": rule["type"],
				"direction": dir,
				"lift": ground.lift(dir),
				"size": size,
				"seed": rng.randi(),
				"motion": motion,
			})
			placed += 1
	return deposits


## Moves every deposit that animates on by `delta` of game time and puts its
## node where it now is. `time` is game time since the deposits were placed.
static func advance(deposits: Array, ground: Ground, delta: float, time: float) -> void:
	for deposit: Dictionary in deposits:
		var motion: DepositMotion = deposit["motion"]
		if not motion.animates():
			continue
		motion.update(ground, delta, time)
		deposit["direction"] = motion.direction
		deposit["lift"] = ground.lift(motion.direction)
		var node: Node3D = deposit.get("node")
		if node != null:
			node.transform = transform_of(deposit, time)


## Where a deposit's node sits, in the unit-sphere space of the planet's
## sphere node: standing on the ground at its direction, facing its heading,
## scaled to its size, with its motion's pose on top.
static func transform_of(deposit: Dictionary, time: float) -> Transform3D:
	var motion: DepositMotion = deposit["motion"]
	var up: Vector3 = motion.direction
	var back: Vector3 = -motion.heading
	var frame := Transform3D(
		Basis(up.cross(back), up, back).scaled(Vector3.ONE * deposit["size"]),
		up * (1.0 + deposit["lift"])
	)
	return frame * motion.pose(time)


## The deposit as a node, its look from TYPES.
static func make_node(deposit: Dictionary) -> MeshInstance3D:
	var type: Dictionary = TYPES[deposit["type"]]
	var material := ShaderMaterial.new()
	material.shader = SHADER
	material.set_shader_parameter("base_color", type["color"])
	material.set_shader_parameter("shine", type.get("shine", 0.3))
	material.set_shader_parameter("glow", type.get("glow", 0.15))
	material.set_shader_parameter("wiggle", type.get("wiggle", 0.0))
	material.set_shader_parameter("phase", float(deposit["seed"] % 1000) * 0.37)
	material.set_shader_parameter("spots", type.get("spots", 0.0))
	material.set_shader_parameter("spot_color_a", type.get("spot_color_a", Color.WHITE))
	material.set_shader_parameter("spot_color_b", type.get("spot_color_b", Color.WHITE))

	var node := MeshInstance3D.new()
	node.mesh = DepositMeshes.build(type["mesh"], deposit["seed"])
	node.material_override = material
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	node.transform = transform_of(deposit, 0.0)
	return node


static func _motion_for(rule: Dictionary) -> GDScript:
	return MOTIONS[rule.get("motion", &"still")]


static func _is_clear(deposits: Array, dir: Vector3, size: float) -> bool:
	for deposit: Dictionary in deposits:
		if dir.angle_to(deposit["direction"]) < (size + deposit["size"]) * SPACING:
			return false
	return true


static func _allows(ground: Ground, rule: Dictionary, dir: Vector3) -> bool:
	var data: Dictionary = ground.data
	var h: float = PlanetTerrain.height_at(data, dir)
	var sea: float = data["sea_level"]
	var on: String = rule.get("on", "land")

	if sea >= 0.0 and h < sea:
		# Out on the liquid, clear of the shore.
		return on != "land" and h < sea - SHORE_MARGIN
	if on == "liquid" or (sea >= 0.0 and h < sea + SHORE_MARGIN):
		return false

	var band: Vector2 = rule.get("land", Vector2(0.0, 1.0))
	var land: float = _land_height(data, h)
	if land < band.x or land > band.y:
		return false
	if rule.has("lowest") and land > ground.land_below(rule["lowest"]):
		return false

	# Rise over run across the spot, both ways, on the surface as displaced.
	var helper := Vector3.UP if absf(dir.y) < 0.9 else Vector3.RIGHT
	var t: Vector3 = helper.cross(dir).normalized()
	var b: Vector3 = dir.cross(t)
	var ground_here: float = _ground(data, h)
	var max_slope: float = rule.get("slope", MAX_SLOPE)
	for side: Vector3 in [t, -t, b, -b]:
		var h_near: float = PlanetTerrain.height_at(data, (dir + side * SLOPE_STEP).normalized())
		if sea >= 0.0 and h_near < sea + SHORE_MARGIN:
			return false
		var rise: float = absf(_ground(data, h_near) - ground_here) * ground.params["relief"]
		if rise / SLOPE_STEP > max_slope:
			return false

	match rule.get("feature", &""):
		&"swirl_ridge":
			return _on_swirl_ridge(ground, dir)
	return true


## Height above the liquid (or above zero on a dry world), as the terrain
## shader's ground() displaces the mesh.
static func _ground(data: Dictionary, h: float) -> float:
	var sea: float = data["sea_level"]
	return maxf(h - sea, 0.0) if sea >= 0.0 else h


## Height on land in the units the colour gradient uses: 0 at the shore (or
## the lowest ground on a dry world), 1 at the top.
static func _land_height(data: Dictionary, h: float) -> float:
	var sea: float = data["sea_level"]
	return clampf((h - sea) / maxf(1.0 - sea, 1e-3) if sea >= 0.0 else h, 0.0, 1.0)


## On the raised (orange) arm of a Swirl's spiral, well up its crest. Mirrors
## swirl_parts() and sigil_frame() in the shaders.
static func _on_swirl_ridge(ground: Ground, dir: Vector3) -> bool:
	for sigil: Dictionary in ground.params.get("sigils", []):
		var centre: Vector3 = sigil["direction"]
		var size: float = sigil["size"]
		var style: Vector4 = sigil["style"]
		var arc: float = dir.angle_to(centre)
		if arc > size:
			continue
		var up: Vector3 = ground.pole if absf(ground.pole.dot(centre)) < 0.95 else Vector3.RIGHT
		var east: Vector3 = up.cross(centre).normalized()
		var north: Vector3 = centre.cross(east)
		var flat := Vector2(dir.dot(east), dir.dot(north))
		var q: Vector2 = (flat * (arc / flat.length()) if flat.length() > 1e-6 else flat) / size
		q = Vector2(cos(style.x) * q.x - sin(style.x) * q.y, sin(style.x) * q.x + cos(style.x) * q.y)
		var r: float = q.length()
		if r > 0.85:
			continue
		var theta: float = atan2(q.y, q.x) * style.w
		var u: float = r * style.y + style.z * theta / TAU
		var f: float = u - floor(u)
		if posmod(int(floor(u)), 2) == 0 and sin(f * PI) > 0.4:
			return true
	return false


static func _random_direction(rng: RandomNumberGenerator) -> Vector3:
	var z: float = rng.randf_range(-1.0, 1.0)
	var angle: float = rng.randf_range(0.0, TAU)
	var ring: float = sqrt(1.0 - z * z)
	return Vector3(ring * cos(angle), ring * sin(angle), z)

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

## Looks made from a model instead of built by DepositMeshes: the mesh (in
## cluster units, standing on +Y) and its colour texture. A type using one
## recolours the texture with `tint` (hue turn, saturation and value
## multipliers), which a spawn may override - one flower, many worlds.
const MODELS := {
	&"moonbloom": {"mesh": "res://models/moonbloom.obj", "texture": "res://models/moonbloom_albedo.png"},
}
## No recolour: the texture as painted.
const TINT_NONE := Vector3(0.0, 1.0, 1.0)
## Loaded MODELS entries: name -> {mesh, texture}.
static var _model_cache: Dictionary = {}

## What each resource is. `size` is the cluster's footprint in planet radii;
## `collectible` false marks scenery the player cannot pick up (default true);
## `tier` is 1/2/3 from the Miro raw-material map (T3 worlds get elite guards);
## `color_param` takes the colour from a terrain param instead (a slime's own
## green); the rest are resource_deposit.gdshader's uniforms.
const TYPES := {
	&"silver_ore": {
		"name": "Silver ore", "mesh": &"crystals", "size": Vector2(0.03, 0.045),
		"color": Color(0.78, 0.8, 0.85), "shine": 0.9, "glow": 0.06,
		"tier": 1,
	},
	&"gold_ore": {
		"name": "Gold ore", "mesh": &"tiles", "size": Vector2(0.05, 0.07),
		"color": Color(1.0, 0.76, 0.28), "shine": 0.9, "glow": 0.06,
		"tier": 1,
	},
	&"scrap": {
		"name": "Scrap", "mesh": &"scrap", "size": Vector2(0.06, 0.08),
		"color": Color.WHITE, "shine": 0.25, "glow": 0.04,
		"tier": 1,
	},
	# The three plants are one model (MODELS moonbloom), told apart by how
	# its texture is recoloured: as painted alive (teal leaves, crimson
	# flowers), drained and washed ice-blue frozen, drained and browned dried.
	&"beanstalk": {
		"name": "Moonbloom", "mesh": &"moonbloom", "size": Vector2(0.045, 0.065),
		"color": Color.WHITE, "shine": 0.2, "glow": 0.05, "wiggle": 0.035,
		"tint": TINT_NONE,
		"tier": 2,
	},
	&"frozen_beanstalk": {
		"name": "Frozen moonbloom", "mesh": &"moonbloom", "size": Vector2(0.045, 0.065),
		"color": Color(0.72, 0.87, 1.0), "shine": 0.6, "glow": 0.08, "wiggle": 0.012,
		"tint": Vector3(0.0, 0.25, 1.45),
		"tier": 2,
	},
	&"dried_beanstalk": {
		"name": "Dried moonbloom", "mesh": &"moonbloom", "size": Vector2(0.04, 0.06),
		"color": Color(0.9, 0.66, 0.42), "shine": 0.1, "glow": 0.02, "wiggle": 0.02, "collectible": false,
		"tint": Vector3(0.0, 0.3, 0.9),
	},
	&"gold_pillar": {
		"name": "Gold pillar", "mesh": &"pillars", "size": Vector2(0.06, 0.09),
		"color": Color(1.0, 0.82, 0.3), "shine": 0.85, "glow": 0.15,
		"tier": 3,
	},
	&"egg": {
		"name": "Egg", "mesh": &"egg", "size": Vector2(0.08, 0.11),
		"color": Color(0.97, 0.96, 0.93), "shine": 0.35, "glow": 0.08,
		"spots": 1.0, "spot_color_a": Color(0.12, 0.38, 1.0), "spot_color_b": Color(1.0, 0.3, 0.62),
		"tier": 5,
	},
	&"sky_stone": {
		"name": "Sky stone", "mesh": &"pebbles", "size": Vector2(0.022, 0.032),
		"color": Color(0.55, 0.88, 1.0), "shine": 1.0, "glow": 0.12,
		"tier": 2,
	},
	&"bone": {
		"name": "Bone", "mesh": &"bones", "size": Vector2(0.06, 0.08),
		"color": Color(0.94, 0.91, 0.82), "shine": 0.3, "glow": 0.05,
		"tier": 2,
	},
	&"toxic_ore": {
		"name": "Toxic ore", "mesh": &"slabs", "size": Vector2(0.05, 0.07),
		"color": Color(0.12, 0.45, 0.14), "shine": 0.5, "glow": 1.1,
		"tier": 3,
	},
	&"pink_crystal": {
		"name": "Pink crystal", "mesh": &"crystals", "size": Vector2(0.035, 0.05),
		"color": Color(1.0, 0.58, 0.8), "shine": 0.85, "glow": 0.18,
		"tier": 1,
	},
	&"ice_crystal": {
		"name": "Ice crystal", "mesh": &"spikes", "size": Vector2(0.04, 0.06),
		"color": Color(0.72, 0.9, 1.0), "shine": 0.95, "glow": 0.12,
		"tier": 1,
	},
	&"slime_jelly": {
		"name": "Slime jelly", "mesh": &"jelly", "size": Vector2(0.03, 0.045),
		"color": Color(0.5, 1.0, 0.5), "color_param": "shallow", "shine": 0.9, "glow": 0.35,
		"tier": 4,
	},
	&"tumbleweed": {
		"name": "Tumbleweed", "mesh": &"tumbleweed", "size": Vector2(0.035, 0.05),
		"color": Color(0.64, 0.5, 0.32), "shine": 0.1, "glow": 0.02, "collectible": false,
	},
	&"ice_wurm": {
		"name": "Ice wurm", "mesh": &"geyser", "size": Vector2(0.03, 0.045),
		"color": Color.WHITE, "shine": 0.3, "glow": 0.3, "wiggle": 0.04,
		"tier": 3,
	},
	&"hel": {
		"name": "Hel", "mesh": &"bubbles", "size": Vector2(0.05, 0.07),
		"color": Color(0.95, 0.72, 1.0), "shine": 0.6, "glow": 0.7, "wiggle": 0.03,
		"tier": 3,
	},
	&"silver_spheres": {
		"name": "Silver spheres", "mesh": &"sphere_arch", "size": Vector2(0.045, 0.065),
		"color": Color(0.86, 0.88, 0.93), "shine": 0.95, "glow": 0.08,
		"tier": 4,
	},
}

## What each planet kind spawns: a list of entries, each
##   type    - a key of TYPES, or &"random": each one any collectible type
##             except those in `except_types`
##   count   - how many, rolled per world (fewer if the ground runs out)
##   chance  - chance the entry spawns at all on a world (default 1)
##   only    - variants it spawns on: a name matches the roll's `variant`,
##             or a param of that name that is true ("blind"); default all
##   except  - variants it does not spawn on, the same way
##   color   - its colour here instead of the type's; `glow` likewise
##   on      - "land" (default), "liquid" (out on the sea, lava or acid) or
##             "any"
##   land    - height band on land, in the terrain's colour-gradient units
##             (0 = shore or lowest ground, 1 = highest); default all of it
##   lowest  - only the lowest this share of the planet's land (0.1 = its
##             lowest tenth): valley floors, whatever the roll's heights
##   above   - only above the lowest this share: off the valley floors
##   slope   - steepest ground allowed (rise over run; default MAX_SLOPE)
##   feature - a landmark it must stand on: &"swirl_ridge" (a Swirl's raised
##             arm), &"ring_centre" (a Rings ring set's middle),
##             &"quake_hole" (the middle of a Quake scar's hole)
##   cluster - all within this many radians of the first one (a field)
##   motion  - &"still" (default), &"drift", &"roll" or &"hop" (see MOTIONS)
##   per_feature - instead of `count` per world, this many round every
##             placed feature (the world's sigils: Ice hollows), in a group
##   note    - how it differs on the variants this entry is for, for the
##             journal ("near-black here")
## Kinds missing here get no deposits.
const SPAWNS := {
	PlanetTerrain.Kind.TERRAN: [
		{"type": &"gold_ore", "count": Vector2i(5, 9)},
		{"type": &"silver_ore", "count": Vector2i(5, 9)},
		{"type": &"sky_stone", "count": Vector2i(0, 2), "only": ["temperate"]},
		{"type": &"pink_crystal", "count": Vector2i(0, 2), "only": ["autumn"],
			"note": "A few stray crystals among the autumn woods"},
		{"type": &"ice_crystal", "count": Vector2i(0, 2), "only": ["snowy"], "feature": &"snow_hump", "slope": 2.0},
	],
	PlanetTerrain.Kind.DESERT: [
		{"type": &"gold_ore", "count": Vector2i(8, 15)},
		{"type": &"scrap", "count": Vector2i(2, 4)},
		{"type": &"bone", "count": Vector2i(1, 1), "chance": 0.25},
		{"type": &"tumbleweed", "count": Vector2i(4, 7), "only": ["open"], "motion": &"roll"},
		{"type": &"tumbleweed", "count": Vector2i(3, 5), "only": ["sandstorm"], "motion": &"roll",
			"note": "Blown along by the storm"},
		{"type": &"gold_pillar", "count": Vector2i(1, 3), "only": ["sandstorm"],
			"note": "Uncovered where the storm scours the sand away"},
		{"type": &"sky_stone", "count": Vector2i(5, 6), "only": ["lava"],
			"note": "Blown out of the lava canyons on the hot winds"},
	],
	PlanetTerrain.Kind.VOLCANIC: [
		{"type": &"scrap", "count": Vector2i(8, 10)},
		{"type": &"pink_crystal", "count": Vector2i(7, 10), "only": ["lava"]},
		{"type": &"ice_crystal", "count": Vector2i(7, 10), "only": ["cryo"]},
		{"type": &"sky_stone", "count": Vector2i(3, 6), "only": ["cryo"]},
	],
	PlanetTerrain.Kind.BARREN: [
		{"type": &"gold_ore", "count": Vector2i(2, 4)},
		{"type": &"silver_ore", "count": Vector2i(2, 4)},
		{"type": &"scrap", "count": Vector2i(12, 20), "only": ["spiked"],
			"note": "Strewn round the jagged crater rims"},
		{"type": &"scrap", "count": Vector2i(10, 12), "except": ["spiked"]},
	],
	PlanetTerrain.Kind.TOXIC: [
		{"type": &"toxic_ore", "count": Vector2i(3, 5), "only": ["crystal"]},
		{"type": &"pink_crystal", "count": Vector2i(8, 10), "only": ["crystal"]},
		{"type": &"sky_stone", "count": Vector2i(3, 7), "only": ["crystal"]},
		{"type": &"toxic_ore", "count": Vector2i(4, 7), "except": ["crystal"]},
		{"type": &"bone", "count": Vector2i(5, 9), "except": ["crystal"]},
	],
	PlanetTerrain.Kind.GAS_GIANT: [
		{"type": &"hel", "count": Vector2i(15, 20), "on": "any", "slope": 2.0, "motion": &"drift",
			"note": "Bubbles of fuel gas drifting over the cloud tops"},
	],
	PlanetTerrain.Kind.ICE_GIANT: [
		{"type": &"hel", "count": Vector2i(15, 20), "on": "any", "slope": 2.0, "motion": &"drift",
			"note": "Bubbles of fuel gas drifting over the cloud tops"},
	],
	PlanetTerrain.Kind.SLIME: [
		{"type": &"beanstalk", "count": Vector2i(8, 14), "on": "any", "slope": 0.5, "except": ["petrified"],
			"tint": Vector3(0.75, 1.0, 1.0), "note": "Sickly green here, soaked in slime"},
		{"type": &"toxic_ore", "count": Vector2i(6, 12), "except": ["petrified"]},
		{"type": &"toxic_ore", "count": Vector2i(15, 20), "only": ["petrified"],
			"note": "Far more of it once the slime has dried off it"},
		{"type": &"slime_jelly", "count": Vector2i(4, 7), "on": "any", "except": ["petrified"], "motion": &"hop"},
	],
	PlanetTerrain.Kind.OCCULT: [
		{"type": &"silver_ore", "count": Vector2i(4, 9), "only": ["obsidian_yellow"],
			"note": "Silver, not gold, where the eyes are gold"},
		{"type": &"gold_ore", "count": Vector2i(4, 9), "except": ["obsidian_yellow"]},
		{"type": &"bone", "count": Vector2i(10, 15), "except": ["blind"]},
		# Blind worlds hide their bones: near-black, no glow.
		{"type": &"bone", "count": Vector2i(10, 15), "only": ["blind"], "color": Color(0.1, 0.085, 0.09), "glow": 0.0,
			"note": "Near-black and dull here - hard to tell from the dust"},
	],
	PlanetTerrain.Kind.GLOOM: [
		{"type": &"silver_spheres", "count": Vector2i(5, 7)},
	],
	PlanetTerrain.Kind.BLOOM: [
		# The valley floors only - the flower fields stay bare, bar some
		# silver on dried worlds.
		{"type": &"beanstalk", "count": Vector2i(15, 25), "lowest": 0.1, "slope": 0.7, "only": ["fields"]},
		{"type": &"frozen_beanstalk", "count": Vector2i(10, 18), "lowest": 0.1, "slope": 0.7, "only": ["winter"]},
		{"type": &"ice_crystal", "count": Vector2i(8, 16), "only": ["winter"], "feature": &"snow_hump", "slope": 2.0},
		{"type": &"scrap", "count": Vector2i(5, 15), "except": ["dried"]},
		{"type": &"dried_beanstalk", "count": Vector2i(50, 70), "lowest": 0.35, "slope": 0.9, "only": ["dried"],
			"note": "Everywhere in the low ground - the dead stalks choke it"},
		{"type": &"beanstalk", "count": Vector2i(0, 18), "lowest": 0.35, "slope": 0.9, "only": ["dried"],
			"note": "The last few still alive among the dead stalks"},
		{"type": &"silver_ore", "count": Vector2i(8, 12), "above": 0.3, "only": ["dried"],
			"note": "Laid bare where the flowers withered"},
	],
	PlanetTerrain.Kind.OASIS: [
		{"type": &"scrap", "count": Vector2i(14, 20)},
		{"type": &"silver_ore", "count": Vector2i(5, 8)},
		{"type": &"gold_pillar", "count": Vector2i(0, 3)},
		{"type": &"tumbleweed", "count": Vector2i(3, 6), "motion": &"roll"},
	],
	PlanetTerrain.Kind.LOTUS: [
		{"type": &"gold_pillar", "count": Vector2i(10, 13), "on": "liquid", "except": ["giant"]},
		{"type": &"gold_pillar", "count": Vector2i(6, 10), "on": "liquid", "only": ["giant"],
			"note": "Fewer, where the giant flowers crowd the sea"},
		{"type": &"toxic_ore", "count": Vector2i(2, 8), "slope": 0.9, "only": ["night"],
			"note": "Only while the flowers are closed for the night"},
	],
	PlanetTerrain.Kind.SWIRL: [
		{"type": &"sky_stone", "count": Vector2i(8, 14), "feature": &"swirl_ridge"},
		{"type": &"silver_ore", "count": Vector2i(6, 10)},
		{"type": &"scrap", "count": Vector2i(0, 2)},
		{"type": &"bone", "count": Vector2i(0, 2), "chance": 0.5},
	],
	PlanetTerrain.Kind.RINGS: [
		{"type": &"bone", "count": Vector2i(0, 4), "feature": &"ring_centre", "slope": 0.8},
		{"type": &"gold_ore", "count": Vector2i(13, 20), "only": ["sandy"],
			"note": "Twice as rich where the sand has spread"},
		{"type": &"gold_ore", "count": Vector2i(5, 9), "except": ["sandy"]},
		{"type": &"scrap", "count": Vector2i(3, 6)},
		{"type": &"sky_stone", "count": Vector2i(2, 5), "only": ["volcanic"], "feature": &"volcano", "slope": 2.0},
	],
	PlanetTerrain.Kind.FRACTAL: [
		# On the massifs: the plains stay below ~0.25.
		{"type": &"egg", "count": Vector2i(3, 6), "land": Vector2(0.45, 1.0), "slope": 0.45},
		{"type": &"silver_ore", "count": Vector2i(8, 14), "land": Vector2(0.0, 0.25)},
		{"type": &"scrap", "count": Vector2i(6, 15), "land": Vector2(0.0, 0.25)},
	],
	PlanetTerrain.Kind.MERIDIAN: [
		# Pink crystals along the shores; gold anywhere - silver on inverted
		# worlds.
		{"type": &"pink_crystal", "count": Vector2i(8, 13), "land": Vector2(0.0, 0.07), "slope": 0.6},
		{"type": &"gold_ore", "count": Vector2i(8, 13), "except": ["inverted"]},
		{"type": &"silver_ore", "count": Vector2i(8, 13), "only": ["inverted"],
			"note": "Silver instead of gold where the seas run white"},
	],
	PlanetTerrain.Kind.QUAKE: [
		# Scarce: each find in the middle of a hole, of any kind.
		{"type": &"random", "count": Vector2i(6, 10), "except_types": [&"egg", &"hel"], "feature": &"quake_hole", "slope": 2.0,
			"except": ["terraced"]},
		{"type": &"random", "count": Vector2i(10, 14), "except_types": [&"egg", &"hel"], "feature": &"quake_hole", "slope": 2.0,
			"only": ["terraced"]},
	],
	PlanetTerrain.Kind.FROZEN: [
		{"type": &"ice_crystal", "count": Vector2i(6, 10)},
		{"type": &"silver_ore", "count": Vector2i(4, 7)},
		{"type": &"ice_wurm", "count": Vector2i(2, 4), "slope": 0.6, "except": ["pink"]},
		{"type": &"ice_wurm", "count": Vector2i(2, 4), "slope": 0.6, "only": ["pink"], "color": Color(1.0, 0.55, 0.76),
			"note": "Pink as the methane ice they burrow in"},
	],
	PlanetTerrain.Kind.ICE: [
		{"type": &"ice_crystal", "count": Vector2i(6, 10)},
		{"type": &"scrap", "count": Vector2i(3, 5)},
		{"type": &"ice_wurm", "count": Vector2i(8, 13), "only": ["geysers"], "cluster": 0.45, "slope": 0.8,
			"note": "Crowded into one field, steaming like vents"},
		# Groups in every hollow (per_feature: how many round each sigil).
		{"type": &"ice_wurm", "per_feature": Vector2i(4, 5), "count": Vector2i(4, 5), "only": ["hollows"],
			"slope": 2.0, "color": Color(0.8, 0.56, 0.66), "note": "Grey-pink, knotted together in the hollows"},
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
	&"roll": preload("res://deposit_roll.gd"),
	&"hop": preload("res://deposit_hop.gd"),
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
## (radii), `seed` (for its shape), `color`, `glow`, `collectible` and
## `motion`. Empty for kinds with nothing in SPAWNS, or before the bake has
## landed.
static func place(kind: PlanetTerrain.Kind, ground: Ground, body_seed: int) -> Array:
	var deposits: Array = []
	if ground.data.is_empty() or not SPAWNS.has(kind):
		return deposits

	var rng := RandomNumberGenerator.new()
	rng.seed = body_seed ^ 0x5EEDDE9051
	for rule: Dictionary in SPAWNS[kind]:
		if not _applies(rule, ground.params) or rng.randf() > rule.get("chance", 1.0):
			continue
		if rule.has("per_feature"):
			_place_per_feature(deposits, rule, ground, rng)
			continue
		var count: int = rng.randi_range(rule["count"].x, rule["count"].y)
		var placed: int = 0
		var cluster_centre := Vector3.ZERO
		for _attempt in range(ATTEMPTS):
			if placed >= count:
				break
			var type_name: StringName = _pick_type(rule, rng)
			var type: Dictionary = TYPES[type_name]
			var dir := _random_direction(rng)
			if rule.get("feature", &"") == &"quake_hole":
				# Straight into the middle of the nearest hole.
				dir = _quake_hole_centre(ground.params, dir)
				if dir == Vector3.ZERO:
					continue
			elif rule.get("feature", &"") == &"snow_hump":
				# Somewhere on top of a hump - they are too small a share of
				# the world for random spots to find.
				var humps: Array = ground.params.get("sigils", [])
				if humps.is_empty():
					continue
				var hump: Dictionary = humps[rng.randi() % humps.size()]
				dir = _near(hump["direction"], hump["size"] * 0.4, rng)
			if cluster_centre != Vector3.ZERO and dir.angle_to(cluster_centre) > rule["cluster"]:
				continue
			var size: float = rng.randf_range(type["size"].x, type["size"].y)
			if not _is_clear(deposits, dir, size) or not ground.allows(rule, dir):
				continue
			if rule.has("cluster") and cluster_centre == Vector3.ZERO:
				cluster_centre = dir
			deposits.append(_deposit(rule, type_name, dir, size, ground, rng))
			placed += 1
	return deposits


## One deposit of `type_name` at `dir`, its motion and look from the entry.
static func _deposit(
	rule: Dictionary, type_name: StringName, dir: Vector3, size: float, ground: Ground, rng: RandomNumberGenerator
) -> Dictionary:
	var type: Dictionary = TYPES[type_name]
	var motion: DepositMotion = _motion_for(rule).new()
	motion.setup(dir, rule, rng.randi())
	var color: Color = rule.get("color", type["color"])
	if type.has("color_param") and not rule.has("color") and ground.params.get("liquid", false):
		# The planet's own colour, but well lighter, or it vanishes
		# against the very liquid it came from.
		var own: Color = ground.params[type["color_param"]]
		color = Color.from_hsv(own.h, clampf(own.s + 0.15, 0.0, 1.0), clampf(own.v + 0.4, 0.0, 1.0))
	return {
		"type": type_name,
		"direction": dir,
		"lift": ground.lift(dir),
		"size": size,
		"seed": rng.randi(),
		"color": color,
		"glow": rule.get("glow", type.get("glow", 0.15)),
		"tint": rule.get("tint", type.get("tint", TINT_NONE)),
		"collectible": type.get("collectible", true),
		"motion": motion,
	}


## A `per_feature` entry: a group round every placed feature (sigil) of the
## world - the middle half of it - `per_feature` strong each.
static func _place_per_feature(deposits: Array, rule: Dictionary, ground: Ground, rng: RandomNumberGenerator) -> void:
	for sigil: Dictionary in ground.params.get("sigils", []):
		var want: int = rng.randi_range(rule["per_feature"].x, rule["per_feature"].y)
		var placed: int = 0
		for _attempt in range(300):
			if placed >= want:
				break
			var type_name: StringName = _pick_type(rule, rng)
			var type: Dictionary = TYPES[type_name]
			var dir: Vector3 = _near(sigil["direction"], sigil["size"] * 0.55, rng)
			var size: float = rng.randf_range(type["size"].x, type["size"].y)
			if not _is_clear(deposits, dir, size) or not ground.allows(rule, dir):
				continue
			deposits.append(_deposit(rule, type_name, dir, size, ground, rng))
			placed += 1


## Every spawn entry that can place `type_name`, as [kind, rule] pairs - a
## &"random" entry counts for every type it may pick.
static func spawns_of(type_name: StringName) -> Array:
	var found: Array = []
	for kind in SPAWNS:
		for rule: Dictionary in SPAWNS[kind]:
			var random_pick: bool = rule["type"] == &"random" and TYPES[type_name].get("collectible", true) \
				and not rule.get("except_types", []).has(type_name)
			if rule["type"] == type_name or random_pick:
				found.append([kind, rule])
	return found


## A spawn entry in words, for the catalog: `where` it stands, on which
## `variants`, and how many (`count`).
static func spawn_notes(kind: int, rule: Dictionary) -> Dictionary:
	var where: PackedStringArray = []
	match rule.get("feature", &""):
		&"swirl_ridge":
			where.append("on the raised spiral ridges")
		&"ring_centre":
			where.append("at the centres of the ring sets")
		&"quake_hole":
			where.append("at the bottom of the quake holes")
		&"volcano":
			where.append("on the scorched ground round the volcanoes")
		&"snow_hump":
			where.append("on top of the snow humps")
	match rule.get("on", "land"):
		"liquid":
			where.append("out on the sea")
		"any":
			where.append("on land or out on the liquid")
	if rule.has("lowest"):
		where.append("in the valley floors")
	if rule.has("above"):
		where.append("on the higher ground, off the valley floors")
	if rule.has("land"):
		var band: Vector2 = rule["land"]
		if band.y <= 0.1:
			where.append("along the shores")
		elif band.x >= 0.4:
			where.append("on the high ground")
		elif band.y <= 0.3:
			where.append("on the low plains")
	if rule.has("cluster"):
		where.append("gathered in one field")
	if rule.has("per_feature"):
		where.append("in groups in the hollows")
	if where.is_empty():
		where.append("anywhere on land")
	match rule.get("motion", &"still"):
		&"roll":
			where.append("rolling with the wind")
		&"hop":
			where.append("hopping about")
		&"drift":
			where.append("drifting slowly")

	var variants := "Every variant"
	if rule.has("only"):
		variants = "Only " + ", ".join((rule["only"] as Array).map(
			func(name: String) -> String: return PlanetLore.variant_name(kind, name)
		))
	elif rule.has("except"):
		variants = "All but " + ", ".join((rule["except"] as Array).map(
			func(name: String) -> String: return PlanetLore.variant_name(kind, name)
		))

	var range_of: Vector2i = rule.get("per_feature", rule["count"])
	var low: int = range_of.x
	var high: int = range_of.y
	var count: String = ("%d" % low if low == high else "%d-%d" % [low, high]) + (
		" in each hollow" if rule.has("per_feature") else " per world"
	)
	if rule["type"] == &"random":
		count += ", as one of several finds"
	if rule.get("chance", 1.0) < 1.0:
		count += " (on %d%% of worlds)" % roundi(rule["chance"] * 100.0)
	var place: String = ", ".join(where)
	return {
		"where": place.left(1).to_upper() + place.substr(1), "variants": variants, "count": count,
		"note": rule.get("note", ""),
	}


## The spawn entries that apply to a world of `kind` as it rolled (its full
## terrain_params: variant and traits) - what it yields, whatever the counts
## came out as this time.
static func rules_for(kind: int, params: Dictionary) -> Array:
	return (SPAWNS.get(kind, []) as Array).filter(
		func(rule: Dictionary) -> bool: return _applies(rule, params)
	)


## What a world of `kind` rolled as `variant` (plus the trait `flag`, if
## given) yields: [{type, rule}] for every spawn entry that applies to it.
## With `flag`, only what the trait adds - entries that would not apply
## without it.
static func yields(kind: int, variant: String, flag: String = "") -> Array:
	var plain := {"variant": variant}
	var with_flag := {"variant": variant}
	if flag != "":
		with_flag[flag] = true
	var result: Array = []
	for rule: Dictionary in SPAWNS.get(kind, []):
		if flag != "" and (not _applies(rule, with_flag) or _applies(rule, plain)):
			continue
		if flag == "" and not _applies(rule, plain):
			continue
		result.append({"type": rule["type"], "rule": rule})
	return result


## Rarity tier of a deposit type: 1 common, 2 uncommon, 3 rare, 4 special,
## 5 wildcard. Scenery / unknown -> 0. PlanetGuards gives worlds with tier 3
## or above the elite guards.
static func tier_of(type_name: StringName) -> int:
	return int(TYPES.get(type_name, {}).get("tier", 0))


## True when any collectible deposit in `deposits` is at least `tier`.
static func has_tier(deposits: Array, tier: int) -> bool:
	for deposit: Dictionary in deposits:
		if not deposit.get("collectible", true):
			continue
		if tier_of(deposit.get("type", &"")) >= tier:
			return true
	return false


## Whether a spawn entry applies to this world's roll (its `only` / `except`).
static func _applies(rule: Dictionary, params: Dictionary) -> bool:
	var matches := func(name: String) -> bool:
		return params.get("variant", "") == name or params.get(name, false) == true
	if rule.has("only") and not (rule["only"] as Array).any(matches):
		return false
	if rule.has("except") and (rule["except"] as Array).any(matches):
		return false
	return true


## The type an entry spawns this time: its own, or for &"random" any
## collectible type but those it excludes.
static func _pick_type(rule: Dictionary, rng: RandomNumberGenerator) -> StringName:
	if rule["type"] != &"random":
		return rule["type"]
	var pool: Array = TYPES.keys().filter(
		func(name: StringName) -> bool:
			return TYPES[name].get("collectible", true) and not rule.get("except_types", []).has(name)
	)
	return pool[rng.randi_range(0, pool.size() - 1)]


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


## One of a type standing on its own at the origin, one cluster unit across -
## for the catalog to show.
static func make_showcase(type_name: StringName) -> MeshInstance3D:
	var type: Dictionary = TYPES[type_name]
	var node: MeshInstance3D = make_node({
		"type": type_name, "seed": 7, "size": 1.0, "lift": 0.0,
		"color": type["color"], "glow": type.get("glow", 0.15),
		"tint": type.get("tint", TINT_NONE),
		"motion": DepositMotion.new(),
	})
	node.transform = Transform3D.IDENTITY
	return node


## The deposit as a node, its look from TYPES.
static func make_node(deposit: Dictionary) -> MeshInstance3D:
	var type: Dictionary = TYPES[deposit["type"]]
	var material := ShaderMaterial.new()
	material.shader = SHADER
	material.set_shader_parameter("base_color", deposit.get("color", type["color"]))
	material.set_shader_parameter("shine", type.get("shine", 0.3))
	material.set_shader_parameter("glow", deposit.get("glow", type.get("glow", 0.15)))
	material.set_shader_parameter("wiggle", type.get("wiggle", 0.0))
	material.set_shader_parameter("phase", float(deposit["seed"] % 1000) * 0.37)
	material.set_shader_parameter("spots", type.get("spots", 0.0))
	material.set_shader_parameter("spot_color_a", type.get("spot_color_a", Color.WHITE))
	material.set_shader_parameter("spot_color_b", type.get("spot_color_b", Color.WHITE))

	var node := MeshInstance3D.new()
	if MODELS.has(type["mesh"]):
		# One shared mesh; each deposit gets its own touch of hue and
		# brightness on top of the type's (or spawn's) tint.
		var model: Dictionary = _model(type["mesh"])
		node.mesh = model["mesh"]
		var tint: Vector3 = deposit.get("tint", type.get("tint", TINT_NONE))
		var jitter := RandomNumberGenerator.new()
		jitter.seed = deposit["seed"]
		tint += Vector3(jitter.randf_range(-0.025, 0.025), 0.0, jitter.randf_range(-0.08, 0.08))
		material.set_shader_parameter("albedo_tex", model["texture"])
		material.set_shader_parameter("use_texture", true)
		material.set_shader_parameter("tex_adjust", tint)
	else:
		node.mesh = DepositMeshes.build(type["mesh"], deposit["seed"])
	node.material_override = material
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	node.transform = transform_of(deposit, 0.0)
	return node


static func _model(model_name: StringName) -> Dictionary:
	if not _model_cache.has(model_name):
		var entry: Dictionary = MODELS[model_name]
		_model_cache[model_name] = {"mesh": load(entry["mesh"]), "texture": load(entry["texture"])}
	return _model_cache[model_name]


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
	if rule.has("above") and land < ground.land_below(rule["above"]):
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
		&"ring_centre":
			return _in_ring_centre(ground, dir)
		&"quake_hole":
			var centre: Vector3 = _quake_hole_centre(ground.params, dir)
			return centre != Vector3.ZERO and dir.angle_to(centre) < 0.01
		&"snow_hump":
			# On top of a Terran snow hump.
			for sigil: Dictionary in ground.params.get("sigils", []):
				if dir.angle_to(sigil["direction"]) < sigil["size"] * 0.45:
					return true
			return false
		&"volcano":
			# On the scorched ring round a cone, off its steep flanks.
			var distance: float = _volcano_distance(ground.params, dir)
			return distance > 1.0 and distance < 1.45
	return true


## In the middle of a Rings ring set - its innermost quarter.
static func _in_ring_centre(ground: Ground, dir: Vector3) -> bool:
	for sigil: Dictionary in ground.params.get("sigils", []):
		if dir.angle_to(sigil["direction"]) < sigil["size"] * 0.25:
			return true
	return false


## The middle of the Quake scar nearest `dir` whose hole the surface really
## cuts (not one that only grazes it), or Vector3.ZERO. Mirrors quakes_at() in
## the planet shader and quake_holes() in the bake, hash and all.
static func _quake_hole_centre(params: Dictionary, dir: Vector3) -> Vector3:
	var scale: float = params["quake_scale"]
	var shift := Vector3.ONE * float(params["quake_shift"])
	var p: Vector3 = dir * scale + shift
	var cell := p.floor()
	var best := Vector3.ZERO
	var best_angle := INF
	for z in range(-1, 2):
		for y in range(-1, 2):
			for x in range(-1, 2):
				var o := Vector3(x, y, z)
				var h: Vector3 = _shader_hash(cell + o + Vector3(0.0, 0.0, 577.0))
				if h.x > params["quake_density"]:
					continue
				var point: Vector3 = cell + o + Vector3(0.5, 0.5, 0.5) + (_shader_hash(cell + o + Vector3(0.0, 57.0, 0.0)) - Vector3(0.5, 0.5, 0.5)) * 0.7
				var size: float = params["quake_size"] * lerpf(0.7, 1.2, h.y)
				var out: Vector3 = point - shift
				# How far the lattice point sits off the sphere: well off and
				# the hole is only a shallow graze.
				if absf(out.length() - scale) > size * 0.5:
					continue
				var angle: float = dir.angle_to(out)
				if angle < best_angle:
					best_angle = angle
					best = out.normalized()
	return best


## A random direction within `angle` radians of `centre`.
static func _near(centre: Vector3, angle: float, rng: RandomNumberGenerator) -> Vector3:
	var helper := Vector3.UP if absf(centre.y) < 0.9 else Vector3.RIGHT
	var t: Vector3 = helper.cross(centre).normalized()
	var b: Vector3 = centre.cross(t)
	var spin: float = rng.randf() * TAU
	var off: float = sqrt(rng.randf()) * angle
	return (centre + (t * cos(spin) + b * sin(spin)) * tan(off)).normalized()


## How far `dir` is from the nearest Rings volcano, in that cone's radii - the
## planet shader's volcano_at() (and the bake's volcano_cones) on the CPU.
static func _volcano_distance(params: Dictionary, dir: Vector3) -> float:
	if params.get("volcano", 0.0) <= 0.0:
		return INF
	var density: float = params["volcano_density"]
	var p: Vector3 = dir * float(params["volcano_scale"]) + Vector3.ONE * float(params["volcano_shift"])
	var cell := p.floor()
	var local: Vector3 = p - cell
	var best := INF
	for z in range(-1, 2):
		for y in range(-1, 2):
			for x in range(-1, 2):
				var o := Vector3(x, y, z)
				var roll: Vector3 = _shader_hash(cell + o + Vector3(0.0, 0.0, 6143.0))
				if roll.x > density:
					continue
				var r: Vector3 = o + Vector3(0.5, 0.5, 0.5) + (_shader_hash(cell + o + Vector3(0.0, 31.0, 0.0)) - Vector3(0.5, 0.5, 0.5)) * 0.8 - local
				var radius: float = lerpf(0.35, 0.6, roll.x / maxf(density, 1e-3))
				best = minf(best, r.length() / radius)
	return best


## hash3() of the planet shader (planet_noise.gdshaderinc): PCG3D on the
## cell's integer coordinates, in 32-bit unsigned maths.
static func _shader_hash(cell: Vector3) -> Vector3:
	const MASK := 0xFFFFFFFF
	var v := [int(cell.x) & MASK, int(cell.y) & MASK, int(cell.z) & MASK]
	for i in range(3):
		v[i] = (_mul32(v[i], 1664525) + 1013904223) & MASK
	for pass_index in range(2):
		v[0] = (v[0] + _mul32(v[1], v[2])) & MASK
		v[1] = (v[1] + _mul32(v[2], v[0])) & MASK
		v[2] = (v[2] + _mul32(v[0], v[1])) & MASK
		if pass_index == 0:
			for i in range(3):
				v[i] = v[i] ^ (v[i] >> 16)
	return Vector3(v[0], v[1], v[2]) / 4294967295.0


## a * b modulo 2^32, without overflowing a 64-bit int.
static func _mul32(a: int, b: int) -> int:
	return (a * (b & 0xFFFF) + (((a * (b >> 16)) & 0xFFFF) << 16)) & 0xFFFFFFFF


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

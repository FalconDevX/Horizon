class_name PlanetTerrain
extends RefCounted

## Heightmap terrain for planets. Each body bakes one heightmap from noise,
## stored as the six faces of a cube wrapped onto the sphere (a cube-sphere:
## no pole pinching, no seam), and planet_terrain.gdshader both displaces the
## mesh by it and colours it by height through a per-kind palette.
##
## The face layout below is private to this file and the shader - neither uses
## the GPU's own cubemap convention - so height_at() on the CPU reads exactly
## the texels the shader does. Edge texels sit ON the cube edge, so the two
## faces meeting there store the same direction and the terrain is continuous.

enum Kind {
	NONE, TERRAN, DESERT, VOLCANIC, ICE, BARREN, TOXIC, GAS_GIANT, ICE_GIANT,
	FROZEN, SLIME, OCCULT, GLOOM, BLOOM, OASIS,
	LOTUS, SWIRL, RINGS, QUAKE, FRACTAL, MERIDIAN,
}

## What the placed features (the sigil arrays) are, for the planet shader.
enum FeatureMode { EYES, SWIRLS, RINGS, BAKE_ONLY }

## Cube face frames: a face's texel (u, v) in -1..1 is the direction
## forward + u * right + v * up. Mirrored by face_uv() in the shader.
const FACE_FORWARD: Array[Vector3] = [
	Vector3(1, 0, 0), Vector3(-1, 0, 0),
	Vector3(0, 1, 0), Vector3(0, -1, 0),
	Vector3(0, 0, 1), Vector3(0, 0, -1),
]
const FACE_RIGHT: Array[Vector3] = [
	Vector3(0, 0, -1), Vector3(0, 0, 1),
	Vector3(1, 0, 0), Vector3(1, 0, 0),
	Vector3(1, 0, 0), Vector3(-1, 0, 0),
]
const FACE_UP: Array[Vector3] = [
	Vector3(0, 1, 0), Vector3(0, 1, 0),
	Vector3(0, 0, -1), Vector3(0, 0, 1),
	Vector3(0, 1, 0), Vector3(0, 1, 0),
]

const MIN_RESOLUTION := 32
const MAX_RESOLUTION := 1024

## Array size of the placed-feature (sigil) arrays in both shaders.
const MAX_SIGILS := 24

const BAKE_SHADER: RDShaderFile = preload("res://planet_terrain_bake.glsl")

## Weighted-histogram resolution used to place sea level at a coverage.
const HISTOGRAM_BINS := 1024

const PALETTE_SALT := 0x3C6EF372
const NOISE_SALT := 0x1B873593

## Finished bakes, keyed by everything that shapes them. Main-thread only:
## looked up before a bake is started, filled when one lands. Survives scene
## reloads, so going back to the menu and in again does not bake twice.
static var _cache: Dictionary = {}

## One GPU bake at a time: each opens its own local RenderingDevice.
static var _gpu_mutex := Mutex.new()


## Rolls a planet's numbers within ranges. `between()` is pulled toward the
## middle of its range as chaos drops, so chaos 0 is each kind's textbook look
## and 1 is the full spread; discrete choices (palette family, cryovolcano,
## terrace count) stay random at any chaos.
class Roller:
	var rng := RandomNumberGenerator.new()
	var chaos := 1.0

	func _init(seed_value: int, chaos_value: float) -> void:
		rng.seed = seed_value
		chaos = clampf(chaos_value, 0.0, 1.0)

	func between(lo: float, hi: float) -> float:
		return lerpf((lo + hi) * 0.5, rng.randf_range(lo, hi), chaos)

	func whole(lo: int, hi: int) -> int:
		return roundi(between(float(lo), float(hi)))

	func chance(probability: float) -> bool:
		return rng.randf() < probability

	## An index into `weights`, chosen in proportion to them.
	func pick(weights: Array) -> int:
		var total := 0.0
		for weight in weights:
			total += weight
		var roll: float = rng.randf() * total
		for i in range(weights.size()):
			roll -= weights[i]
			if roll < 0.0:
				return i
		return weights.size() - 1

	## A colour from hue, saturation and value ranges. Hue is in turns and may
	## run past 1 to wrap through red.
	func hsv(h: Vector2, s: Vector2, v: Vector2) -> Color:
		return Color.from_hsv(
			fposmod(between(h.x, h.y), 1.0),
			clampf(between(s.x, s.y), 0.0, 1.0),
			clampf(between(v.x, v.y), 0.0, 1.0)
		)

	## A colour at hue `h` (+- hue_spread), saturation scaled from `s`, and an
	## exact value - for ramps whose brightness is laid out on purpose.
	func tone(h: float, hue_spread: float, s: float, v: float) -> Color:
		return Color.from_hsv(
			fposmod(h + between(-hue_spread, hue_spread), 1.0),
			clampf(s * between(0.8, 1.2), 0.0, 1.0),
			clampf(v, 0.0, 1.0)
		)


static func is_gas(kind: Kind) -> bool:
	return kind == Kind.GAS_GIANT or kind == Kind.ICE_GIANT


## One planet's whole look and bake recipe, rolled from its seed by the kind's
## _roll_*() below. Colours are sRGB; `land` is a height gradient, one colour
## per entry of `stops` (0 = shoreline or lowest ground, 1 = highest peak).
## `dry` is laid over the lowlands where a moisture noise runs dry; `strata`
## bands rock on cliffs. `recipe` and `detail` go to the bake - what each
## `detail` slot does is spelled out per kind in raw_height() in
## planet_terrain_bake.glsl. `coverage_override` >= 0 pins the liquid share.
static func resolve(
	kind: Kind, terrain_seed: int, coverage_override: float = -1.0, chaos: float = 1.0
) -> Dictionary:
	var r := Roller.new(hash(terrain_seed ^ PALETTE_SALT), chaos)
	var params: Dictionary

	match kind:
		Kind.TERRAN:
			params = _roll_terran(r)
		Kind.TOXIC:
			params = _roll_toxic(r)
		Kind.DESERT:
			params = _roll_desert(r)
		Kind.VOLCANIC:
			params = _roll_volcanic(r)
		Kind.ICE:
			params = _roll_ice(r)
		Kind.BARREN:
			params = _roll_barren(r)
		Kind.GAS_GIANT, Kind.ICE_GIANT:
			params = _roll_giant(r, kind == Kind.ICE_GIANT)
		Kind.FROZEN:
			params = _roll_frozen(r)
		Kind.SLIME:
			params = _roll_slime(r)
		Kind.OCCULT:
			params = _roll_occult(r)
		Kind.GLOOM:
			params = _roll_gloom(r)
		Kind.BLOOM:
			params = _roll_bloom(r)
		Kind.OASIS:
			params = _roll_oasis(r)
		Kind.LOTUS:
			params = _roll_lotus(r)
		Kind.SWIRL:
			params = _roll_swirl(r)
		Kind.RINGS:
			params = _roll_rings(r)
		Kind.QUAKE:
			params = _roll_quake(r)
		Kind.FRACTAL:
			params = _roll_fractal(r)
		Kind.MERIDIAN:
			params = _roll_meridian(r)
		_:
			return {}

	if coverage_override >= 0.0:
		params["coverage"] = clampf(coverage_override, 0.0, 0.98)
		params["liquid"] = coverage_override > 0.0

	return params


## Everything a kind may leave out, plus the recipe every rocky kind shares:
## how hard the continents are domain-warped, where mountain belts start and
## end, and how sharp ridge crests are.
static func _base(r: Roller) -> Dictionary:
	return {
		"variant": "",
		"liquid": false, "coverage": 0.0,
		"shallow": Color.BLACK, "deep": Color.BLACK, "emission": 0.0, "gloss": 0.0, "crust": 0.0,
		"rock": Color(0.35, 0.33, 0.31), "slope_rock": 0.0, "strata": 0.0,
		"dry": Color.BLACK, "dry_amount": 0.0,
		"cap": Color.WHITE, "cap_latitude": 2.0,
		"atmo": Color.BLACK, "atmo_strength": 0.0, "haze": 0.0,
		# The cloud deck's height, as a share of `relief`: over the plains, not
		# the summits, unless the kind's high ground is everywhere.
		"clouds": 0.0, "cloud_color": Color.WHITE, "cloud_height": 0.45,
		"relief": 0.0, "bump": 0.0, "frequency": 1.5, "bands": 0,
		"recipe": [r.between(0.6, 1.3), r.between(-0.2, 0.0), r.between(0.15, 0.35), r.between(1.2, 1.7)],
		"detail": _detail([]),
		"storm": {"strength": 0.0, "width": 0.2, "latitude": -0.3, "bright": false},
		# Lighting character: night-side floor, light wrapped past the
		# terminator, terminator softness (1 = default), diffuse contrast.
		"ambient": 0.04, "light_wrap": 0.15, "terminator": 1.0, "shade_contrast": 1.0,
		# Drawn-on effects, all off unless a kind turns them on.
		"aurora": 0.0, "aurora_latitude": 0.75, "aurora_width": 0.1, "aurora_speed": 0.03,
		"aurora_colors": [Color(0.2, 1.0, 0.5), Color(0.2, 0.8, 1.0), Color(0.9, 0.3, 0.9)],
		"cracks": 0.0, "crack_color": Color(1.0, 0.75, 0.3), "crack_scale": 6.0,
		"crack_width": 0.03, "crack_coverage": 0.0,
		"sigils": [], "sigil_mode": FeatureMode.EYES,
		"sigil_color": Color(0.9, 0.05, 0.05), "sigil_color_b": Color.BLACK, "sigil_glow": 0.0,
		# >= 0 pins sea level (0..1 height) instead of placing it by coverage.
		"sea_fixed": -1.0,
		"quake": 0.0, "quake_color": Color(0.85, 0.87, 0.9), "quake_scale": 16.0,
		"quake_density": 0.4, "quake_size": 0.38, "quake_rings": 2.0, "quake_spokes": 6.0,
		"quake_shift": 7.0,
		"mist": 0.0, "mist_color": Color(0.8, 0.7, 1.0), "mist_height": 0.25,
		"buds": 0.0, "bud_color": Color(0.35, 0.6, 0.25), "bud_scale": 100.0, "bud_size": 0.25,
		"bud_spike": 0.12, "bud_density": 0.5, "bud_reach": 0.08, "bud_near_features": 0.0,
	}


## The bake's 16 kind-specific knobs, zero-padded.
static func _detail(values: Array) -> PackedFloat32Array:
	var detail := PackedFloat32Array(values)
	detail.resize(16)
	return detail


## Land stops: 0, then one roll per range, which must not overlap.
static func _stops(r: Roller, ranges: Array) -> Array:
	var stops: Array = [0.0]
	for range_value in ranges:
		stops.append(r.between(range_value.x, range_value.y))
	return stops


static func _roll_terran(r: Roller) -> Dictionary:
	var p: Dictionary = _base(r)
	p["liquid"] = true
	p["coverage"] = r.between(0.45, 0.8)
	p["gloss"] = r.between(0.7, 0.95)

	# Water is always blue-ish: the deep anywhere from teal-blue to navy, darker
	# or brighter; the shallows lean blue, blue-green, or a murky yellow-green
	# as if over sand.
	var deep: Color = r.hsv(Vector2(0.53, 0.66), Vector2(0.6, 0.95), Vector2(0.12, 0.38))
	var shallow_hue: float = deep.h
	var shallow_saturation: float = r.between(0.45, 0.85)
	match r.pick([0.5, 0.3, 0.2]):
		0:
			shallow_hue += r.between(-0.03, 0.03)
		1:
			shallow_hue += r.between(-0.11, -0.05)
		2:
			shallow_hue += r.between(-0.2, -0.13)
			shallow_saturation = r.between(0.3, 0.55)
	p["deep"] = deep
	p["shallow"] = Color.from_hsv(fposmod(shallow_hue, 1.0), shallow_saturation, r.between(0.45, 0.8))

	# Land keeps the idea - sand, grass, forest, highland, rock, snow - but each
	# is its own roll, so grass runs yellow-green to blue-green, light to dark.
	var grass: Color = r.hsv(Vector2(0.22, 0.36), Vector2(0.45, 0.75), Vector2(0.35, 0.6))
	var forest := Color.from_hsv(
		fposmod(grass.h + r.between(-0.02, 0.05), 1.0),
		clampf(grass.s + r.between(0.0, 0.15), 0.0, 1.0),
		r.between(0.18, 0.33)
	)
	var rock: Color = r.hsv(Vector2(0.04, 0.12), Vector2(0.03, 0.15), Vector2(0.42, 0.6))
	var snow: Color = r.hsv(Vector2(0.55, 0.62), Vector2(0.0, 0.08), Vector2(0.92, 1.0))
	p["land"] = [
		r.hsv(Vector2(0.09, 0.14), Vector2(0.25, 0.5), Vector2(0.65, 0.85)),
		grass,
		forest,
		r.hsv(Vector2(0.06, 0.14), Vector2(0.25, 0.5), Vector2(0.3, 0.48)),
		rock,
		snow,
	]
	p["stops"] = _stops(r, [
		Vector2(0.02, 0.06), Vector2(0.15, 0.35), Vector2(0.45, 0.62),
		Vector2(0.66, 0.8), Vector2(0.84, 0.94),
	])
	p["rock"] = Color.from_hsv(rock.h, rock.s, rock.v * r.between(0.65, 0.85))
	p["slope_rock"] = r.between(0.3, 0.7)
	p["strata"] = r.between(0.0, 0.25)
	p["dry"] = r.hsv(Vector2(0.08, 0.13), Vector2(0.3, 0.5), Vector2(0.5, 0.7))
	p["dry_amount"] = r.between(0.4, 0.95)
	p["cap"] = snow
	p["cap_latitude"] = r.between(0.68, 0.92)
	p["atmo"] = r.hsv(Vector2(0.55, 0.62), Vector2(0.45, 0.7), Vector2(0.9, 1.0))
	p["atmo_strength"] = r.between(0.6, 1.1)
	p["haze"] = r.between(0.0, 0.08)
	p["clouds"] = r.between(0.15, 0.6)
	p["cloud_color"] = r.hsv(Vector2(0.55, 0.65), Vector2(0.0, 0.08), Vector2(0.92, 1.0))
	p["relief"] = r.between(0.05, 0.1)
	p["bump"] = r.between(2.5, 4.5)
	p["frequency"] = r.between(1.0, 1.9)
	p["detail"] = _detail([
		r.between(-0.12, 0.0), r.between(0.2, 0.45), r.between(0.2, 0.5), r.between(0.55, 1.05),
		r.between(0.08, 0.18), r.between(0.15, 0.35), r.between(2.5, 3.5),
	])
	return p


static func _roll_toxic(r: Roller) -> Dictionary:
	var p: Dictionary = _base(r)
	p["liquid"] = true
	p["coverage"] = r.between(0.3, 0.6)
	p["gloss"] = r.between(0.35, 0.65)
	p["emission"] = r.between(0.0, 0.3)
	# A faint scum at most - a lava-style crust would read as polka dots.
	p["crust"] = r.between(0.0, 0.2)

	var acid: Color = r.hsv(Vector2(0.13, 0.3), Vector2(0.6, 0.9), Vector2(0.6, 0.85))
	p["shallow"] = acid
	p["deep"] = Color.from_hsv(
		fposmod(acid.h + r.between(0.0, 0.05), 1.0), r.between(0.7, 0.95), r.between(0.2, 0.4)
	)

	var hue: float = r.between(0.72, 0.88)
	var saturation: float = r.between(0.25, 0.5)
	var values: Array = [
		r.between(0.22, 0.32), r.between(0.32, 0.45), r.between(0.42, 0.55),
		r.between(0.3, 0.42), r.between(0.5, 0.65), r.between(0.72, 0.88),
	]
	var land: Array = []
	for value in values:
		land.append(r.tone(hue, 0.04, saturation, value))
	p["land"] = land
	p["stops"] = _stops(r, [
		Vector2(0.05, 0.12), Vector2(0.25, 0.4), Vector2(0.5, 0.62),
		Vector2(0.7, 0.82), Vector2(0.88, 0.96),
	])
	p["rock"] = r.hsv(Vector2(hue - 0.03, hue + 0.03), Vector2(0.2, 0.4), Vector2(0.15, 0.25))
	p["slope_rock"] = r.between(0.35, 0.65)
	p["strata"] = r.between(0.1, 0.5)
	p["dry"] = r.hsv(Vector2(0.14, 0.2), Vector2(0.35, 0.55), Vector2(0.35, 0.5))
	p["dry_amount"] = r.between(0.4, 0.8)
	p["atmo"] = r.hsv(Vector2(0.72, 0.82), Vector2(0.4, 0.6), Vector2(0.9, 1.0))
	p["atmo_strength"] = r.between(0.8, 1.2)
	p["haze"] = r.between(0.1, 0.3)
	p["clouds"] = r.between(0.2, 0.55)
	p["cloud_color"] = r.hsv(Vector2(0.72, 0.85), Vector2(0.15, 0.35), Vector2(0.75, 0.9))
	p["relief"] = r.between(0.05, 0.09)
	p["bump"] = r.between(3.0, 4.5)
	p["frequency"] = r.between(1.2, 1.9)
	# Same continents as Terran, but eroded at a finer scale of its own (5-9x
	# against Terran's ~3x) and pocked with sinkholes, so it is its own world.
	p["detail"] = _detail([
		r.between(-0.1, 0.0), r.between(0.15, 0.35), r.between(0.3, 0.6), r.between(0.3, 0.7),
		r.between(0.25, 0.55), r.between(5.0, 9.0), r.between(0.05, 0.25), r.between(0.03, 0.09),
		r.between(3.0, 5.5),
	])
	return p


static func _roll_desert(r: Roller) -> Dictionary:
	var p: Dictionary = _base(r)

	# Palette families, from classic sand to the odd rose or salt-white world.
	# Whatever the hue, brightness climbs with height (with one darker rock
	# band): a strong value ramp is what keeps mesas and ridges readable, where
	# a random colour per band would drown them.
	var families: Array = [
		[Vector2(0.09, 0.12), Vector2(0.35, 0.6)],    # sand
		[Vector2(0.055, 0.085), Vector2(0.55, 0.8)],  # orange
		[Vector2(0.005, 0.045), Vector2(0.5, 0.75)],  # rust
		[Vector2(0.12, 0.16), Vector2(0.3, 0.5)],     # ochre / khaki
		[Vector2(0.94, 0.99), Vector2(0.25, 0.45)],   # rose
		[Vector2(0.05, 0.12), Vector2(0.05, 0.18)],   # pale salt / bone
	]
	var family: Array = families[r.pick([0.3, 0.25, 0.15, 0.12, 0.1, 0.08])]
	var hue: float = r.between(family[0].x, family[0].y)
	var saturation: float = r.between(family[1].x, family[1].y)
	var values: Array = [
		r.between(0.3, 0.42), r.between(0.5, 0.62), r.between(0.66, 0.78),
		r.between(0.8, 0.92), r.between(0.52, 0.66), r.between(0.86, 0.96),
	]
	# Lowlands a touch redder, heights a touch yellower.
	var tilt: float = r.between(0.0, 0.012)
	var land: Array = []
	for i in range(values.size()):
		land.append(r.tone(hue + (float(i) - 2.5) * tilt, 0.012, saturation, values[i]))
	p["land"] = land
	p["stops"] = _stops(r, [
		Vector2(0.16, 0.28), Vector2(0.36, 0.48), Vector2(0.56, 0.68),
		Vector2(0.76, 0.88), Vector2(0.92, 0.99),
	])

	# Dunes over the lowlands in a neighbouring hue, so sand and rock read as
	# two materials.
	p["dry"] = Color.from_hsv(
		fposmod(hue + r.between(-0.05, 0.05), 1.0),
		clampf(saturation * r.between(0.7, 1.1), 0.0, 1.0),
		r.between(0.75, 0.92)
	)
	p["dry_amount"] = r.between(0.3, 0.75)
	p["rock"] = r.tone(hue, 0.02, saturation, r.between(0.22, 0.35))
	p["strata"] = r.between(0.5, 1.0)
	p["slope_rock"] = r.between(0.35, 0.7)
	if r.chance(0.5):
		p["cap"] = r.hsv(Vector2(hue, hue), Vector2(0.05, 0.12), Vector2(0.92, 0.98))
		p["cap_latitude"] = r.between(0.85, 0.95)
	p["atmo"] = r.hsv(Vector2(hue - 0.03, hue + 0.03), Vector2(0.35, 0.6), Vector2(0.9, 1.0))
	p["atmo_strength"] = r.between(0.3, 0.7)
	p["haze"] = r.between(0.02, 0.1)
	p["relief"] = r.between(0.06, 0.12)
	p["bump"] = r.between(2.5, 4.0)
	p["frequency"] = r.between(1.3, 2.3)
	# c: canyon scale, width, depth (0 = none), wander. A few worlds are cut
	# by deep valleys running with lava.
	var lava: bool = r.chance(0.25)
	if lava:
		p["variant"] = "lava"
		p["liquid"] = true
		p["coverage"] = r.between(0.05, 0.09)
		var glow: Color = r.hsv(Vector2(0.02, 0.1), Vector2(0.85, 1.0), Vector2(0.9, 1.0))
		p["shallow"] = glow
		p["deep"] = Color.from_hsv(fposmod(glow.h - r.between(0.015, 0.04), 1.0), r.between(0.9, 1.0), r.between(0.7, 0.85))
		p["emission"] = r.between(1.0, 1.8)
		p["crust"] = r.between(0.3, 0.7)
		p["gloss"] = r.between(0.05, 0.2)
	p["detail"] = _detail([
		r.between(0.6, 1.0), r.between(0.3, 0.9), r.between(0.0, 0.2), r.between(2.5, 5.0),
		float(r.whole(3, 12)), r.between(0.3, 0.85), r.between(0.3, 0.8), r.between(0.06, 0.2),
		r.between(1.2, 2.2), r.between(0.05, 0.09), r.between(0.9, 1.3) if lava else 0.0, r.between(0.6, 1.4),
	])
	return p


static func _roll_volcanic(r: Roller) -> Dictionary:
	var p: Dictionary = _base(r)
	p["liquid"] = true
	p["coverage"] = r.between(0.15, 0.45)
	p["crust"] = r.between(0.6, 1.0)

	var hue: float
	var saturation: float
	var values: Array

	# A third of volcanic worlds are cryovolcanic: brine erupts instead of rock
	# melt, glowing a deep light blue through frost.
	if r.chance(0.35):
		p["variant"] = "cryo"
		p["shallow"] = r.hsv(Vector2(0.5, 0.57), Vector2(0.3, 0.55), Vector2(0.9, 1.0))
		p["deep"] = r.hsv(Vector2(0.55, 0.62), Vector2(0.6, 0.85), Vector2(0.6, 0.85))
		p["emission"] = r.between(0.8, 1.5)
		p["gloss"] = r.between(0.3, 0.6)
		hue = r.between(0.53, 0.62)
		saturation = r.between(0.05, 0.2)
		values = [
			r.between(0.35, 0.45), r.between(0.5, 0.6), r.between(0.62, 0.72),
			r.between(0.72, 0.82), r.between(0.55, 0.65), r.between(0.88, 0.97),
		]
		p["rock"] = r.hsv(Vector2(0.55, 0.62), Vector2(0.1, 0.25), Vector2(0.2, 0.32))
		p["dry"] = r.hsv(Vector2(0.5, 0.6), Vector2(0.05, 0.15), Vector2(0.8, 0.9))
		p["cap"] = r.hsv(Vector2(0.55, 0.6), Vector2(0.02, 0.08), Vector2(0.95, 1.0))
		p["cap_latitude"] = r.between(0.6, 0.85)
		p["atmo"] = r.hsv(Vector2(0.5, 0.58), Vector2(0.3, 0.5), Vector2(0.9, 1.0))
		p["atmo_strength"] = r.between(0.3, 0.7)
		p["haze"] = r.between(0.02, 0.1)
		p["clouds"] = r.between(0.05, 0.3)
		p["cloud_color"] = r.hsv(Vector2(0.55, 0.6), Vector2(0.0, 0.08), Vector2(0.9, 1.0))
	else:
		p["variant"] = "lava"
		var lava: Color = r.hsv(Vector2(0.02, 0.13), Vector2(0.85, 1.0), Vector2(0.9, 1.0))
		p["shallow"] = lava
		p["deep"] = Color.from_hsv(
			fposmod(lava.h - r.between(0.015, 0.05), 1.0), r.between(0.9, 1.0), r.between(0.7, 0.9)
		)
		p["emission"] = r.between(0.9, 1.8)
		p["gloss"] = r.between(0.05, 0.2)
		hue = r.between(0.0, 0.1)
		saturation = r.between(0.05, 0.3)
		values = [
			r.between(0.07, 0.12), r.between(0.12, 0.18), r.between(0.18, 0.28),
			r.between(0.26, 0.36), r.between(0.16, 0.24), r.between(0.38, 0.5),
		]
		p["rock"] = r.tone(hue, 0.02, saturation, r.between(0.05, 0.09))
		p["dry"] = r.tone(hue, 0.03, saturation, r.between(0.22, 0.32))
		p["atmo"] = r.hsv(Vector2(0.02, 0.08), Vector2(0.6, 0.8), Vector2(0.9, 1.0))
		p["atmo_strength"] = r.between(0.4, 0.9)
		p["haze"] = r.between(0.02, 0.08)
		p["clouds"] = r.between(0.1, 0.35)
		p["cloud_color"] = r.hsv(Vector2(0.02, 0.08), Vector2(0.05, 0.2), Vector2(0.25, 0.4))

	var land: Array = []
	for value in values:
		land.append(r.tone(hue, 0.02, saturation, value))
	p["land"] = land
	p["stops"] = _stops(r, [
		Vector2(0.06, 0.14), Vector2(0.3, 0.4), Vector2(0.55, 0.65),
		Vector2(0.76, 0.84), Vector2(0.9, 0.97),
	])
	p["dry_amount"] = r.between(0.3, 0.6)
	p["strata"] = r.between(0.2, 0.6)
	p["slope_rock"] = r.between(0.4, 0.8)
	p["relief"] = r.between(0.07, 0.14)
	p["bump"] = r.between(2.5, 4.0)
	p["frequency"] = r.between(1.2, 2.1)
	p["detail"] = _detail([
		r.between(0.4, 0.8), r.between(0.3, 0.7), r.between(0.35, 0.8), r.between(0.05, 0.2),
		r.between(2.5, 5.5), r.between(0.45, 0.8), r.between(0.08, 0.18), r.between(0.2, 0.5),
	])
	return p


static func _roll_ice(r: Roller) -> Dictionary:
	var p: Dictionary = _base(r)
	p["liquid"] = true
	p["coverage"] = r.between(0.1, 0.4)
	p["gloss"] = r.between(0.75, 0.95)
	p["deep"] = r.hsv(Vector2(0.56, 0.65), Vector2(0.7, 0.95), Vector2(0.1, 0.25))
	p["shallow"] = r.hsv(Vector2(0.5, 0.6), Vector2(0.35, 0.6), Vector2(0.4, 0.65))

	# Ice in its own blue-white shades; everything that is not ice - gravel,
	# moraine, bare rock - in natural greys and browns.
	var ice: float = r.between(0.52, 0.6)
	p["land"] = [
		r.hsv(Vector2(ice, ice), Vector2(0.08, 0.2), Vector2(0.78, 0.88)),
		r.hsv(Vector2(ice, ice), Vector2(0.02, 0.1), Vector2(0.88, 0.96)),
		r.hsv(Vector2(0.06, 0.13), Vector2(0.08, 0.25), Vector2(0.38, 0.52)),
		r.hsv(Vector2(0.04, 0.12), Vector2(0.05, 0.18), Vector2(0.3, 0.45)),
		r.hsv(Vector2(ice, ice), Vector2(0.1, 0.25), Vector2(0.8, 0.9)),
		r.hsv(Vector2(ice, ice), Vector2(0.0, 0.05), Vector2(0.95, 1.0)),
	]
	# Bare ground from the lowlands up, ice returning only near the tops - and
	# caps kept to the high latitudes - or the natural colours never show.
	p["stops"] = _stops(r, [
		Vector2(0.06, 0.12), Vector2(0.22, 0.32), Vector2(0.42, 0.55),
		Vector2(0.66, 0.78), Vector2(0.86, 0.95),
	])
	p["rock"] = r.hsv(Vector2(0.04, 0.12), Vector2(0.05, 0.2), Vector2(0.28, 0.42))
	p["slope_rock"] = r.between(0.55, 0.9)
	p["dry"] = r.hsv(Vector2(0.07, 0.17), Vector2(0.1, 0.3), Vector2(0.35, 0.55))
	p["dry_amount"] = r.between(0.4, 0.85)
	p["strata"] = r.between(0.1, 0.4)
	p["cap"] = r.hsv(Vector2(ice, ice), Vector2(0.0, 0.05), Vector2(0.96, 1.0))
	p["cap_latitude"] = r.between(0.7, 0.9)
	p["atmo"] = r.hsv(Vector2(0.52, 0.6), Vector2(0.3, 0.5), Vector2(0.9, 1.0))
	p["atmo_strength"] = r.between(0.5, 0.9)
	p["haze"] = r.between(0.04, 0.12)
	p["clouds"] = r.between(0.1, 0.4)
	p["cloud_color"] = r.hsv(Vector2(0.55, 0.6), Vector2(0.0, 0.06), Vector2(0.9, 1.0))
	p["relief"] = r.between(0.04, 0.09)
	p["bump"] = r.between(3.0, 5.0)
	p["frequency"] = r.between(1.1, 2.0)
	p["detail"] = _detail([
		r.between(0.55, 0.85), r.between(0.2, 0.45), r.between(0.03, 0.1), r.between(2.0, 5.0),
		r.between(0.015, 0.045), r.between(0.05, 0.18), r.between(0.0, 0.7), r.between(-0.4, 0.2),
		r.between(0.5, 2.0),
	])
	_roll_aurora(r, p)
	return p


## Aurora curtains round the poles: green, teal and pink-violet, drifting.
## Most icy worlds get one; a few are left dark.
static func _roll_aurora(r: Roller, p: Dictionary) -> void:
	p["aurora"] = r.between(0.6, 1.2) if r.chance(0.85) else 0.0
	p["aurora_colors"] = [
		r.hsv(Vector2(0.3, 0.4), Vector2(0.7, 0.95), Vector2(0.9, 1.0)),
		r.hsv(Vector2(0.45, 0.55), Vector2(0.6, 0.9), Vector2(0.85, 1.0)),
		r.hsv(Vector2(0.78, 0.92), Vector2(0.5, 0.8), Vector2(0.85, 1.0)),
	]
	p["aurora_latitude"] = r.between(0.62, 0.82)
	p["aurora_width"] = r.between(0.05, 0.12)
	p["aurora_speed"] = r.between(0.02, 0.06)


static func _roll_barren(r: Roller) -> Dictionary:
	var p: Dictionary = _base(r)

	# Natural rock families: grey moon, brown, reddish, dark basalt, beige.
	var families: Array = [
		[Vector2(0.0, 1.0), Vector2(0.0, 0.06), 1.0],
		[Vector2(0.06, 0.1), Vector2(0.15, 0.3), 1.0],
		[Vector2(0.01, 0.05), Vector2(0.25, 0.4), 1.0],
		[Vector2(0.55, 0.65), Vector2(0.03, 0.1), 0.75],
		[Vector2(0.1, 0.14), Vector2(0.12, 0.25), 1.05],
	]
	var family: Array = families[r.pick([0.3, 0.25, 0.15, 0.15, 0.15])]
	var hue: float = r.between(family[0].x, family[0].y)
	var saturation: float = r.between(family[1].x, family[1].y)
	var brightness: float = family[2]
	var values: Array = [
		r.between(0.16, 0.24), r.between(0.26, 0.36), r.between(0.36, 0.46),
		r.between(0.46, 0.56), r.between(0.54, 0.64), r.between(0.64, 0.76),
	]
	var land: Array = []
	for value in values:
		land.append(r.tone(hue, 0.015, saturation, value * brightness))
	p["land"] = land
	p["stops"] = _stops(r, [
		Vector2(0.15, 0.25), Vector2(0.35, 0.45), Vector2(0.55, 0.65),
		Vector2(0.75, 0.85), Vector2(0.93, 1.0),
	])
	p["rock"] = r.tone(hue, 0.02, saturation, r.between(0.18, 0.28) * brightness)
	p["slope_rock"] = r.between(0.3, 0.6)
	p["strata"] = r.between(0.3, 0.8)
	p["dry"] = r.tone(hue, 0.03, saturation * 0.8, r.between(0.45, 0.6) * brightness)
	p["dry_amount"] = r.between(0.2, 0.6)
	p["relief"] = r.between(0.07, 0.13)
	p["bump"] = r.between(2.5, 4.0)
	p["frequency"] = r.between(1.3, 2.2)
	# Craters as before, plus dry riverbeds cut into the plains and smooth
	# basins (maria) that bury older craters. Some worlds roll no rivers.
	# Spiked worlds: crater rims thrown up into jagged teeth, turning from the
	# rock's brown to a metallic green or blue as they climb.
	var spikes := 0.0
	if r.chance(0.35):
		p["variant"] = "spiked"
		spikes = r.between(2.5, 4.0)
		var metal: Color = r.hsv(Vector2(0.38, 0.6), Vector2(0.45, 0.65), Vector2(0.55, 0.72))
		land[2] = (land[2] as Color).lerp(metal, 0.25)
		land[3] = (land[3] as Color).lerp(metal, 0.6)
		land[4] = (land[4] as Color).lerp(metal, 0.9)
		land[5] = metal.lightened(0.1)
		p["land"] = land
	p["detail"] = _detail([
		r.between(0.3, 0.6), r.between(0.1, 0.3), r.between(0.04, 0.12), r.between(0.1, 0.55),
		r.between(0.2, 0.5), r.between(0.08, 0.22), r.between(0.02, 0.08), r.between(0.25, 0.55),
		r.between(1.5, 3.5), r.between(0.03, 0.08), r.between(0.0, 0.3), r.between(0.0, 0.7),
		r.between(0.6, 2.0), r.between(0.1, 0.3), r.between(0.8, 1.25), spikes,
	])

	# Half the worlds are split by fine dark cracks.
	if r.chance(0.5):
		p["cracks"] = 1.0
		p["crack_color"] = r.tone(hue, 0.02, saturation, r.between(0.03, 0.07))
		p["crack_scale"] = r.between(4.0, 8.0)
		p["crack_width"] = r.between(0.006, 0.012)
		p["crack_coverage"] = r.between(-0.3, 0.2)
	# Some carry a thin red mist in the low ground, and wisps of red cloud.
	if r.chance(0.3):
		var red: Color = r.hsv(Vector2(0.98, 1.02), Vector2(0.55, 0.8), Vector2(0.55, 0.8))
		p["mist"] = r.between(0.3, 0.5)
		p["mist_color"] = red
		p["mist_height"] = r.between(0.2, 0.35)
		p["clouds"] = r.between(0.06, 0.16)
		p["cloud_color"] = red.lightened(0.2)
		p["atmo"] = red
		p["atmo_strength"] = r.between(0.2, 0.4)
	return p


## Any hue works on a giant, so the palette is a colour harmony around a random
## base - analogous, complementary, triadic or monochrome - with light and dark
## alternating down the gradient so the bands always read.
static func _roll_giant(r: Roller, icy: bool) -> Dictionary:
	var p: Dictionary = _base(r)
	var base: float = r.rng.randf()
	var scheme: int = r.pick([0.35, 0.25, 0.2, 0.2])
	var values: Array = [
		r.between(0.3, 0.45), r.between(0.6, 0.75), r.between(0.82, 0.95),
		r.between(0.5, 0.65), r.between(0.35, 0.5), r.between(0.88, 0.98),
	]
	var saturation := Vector2(0.25, 0.55) if icy else Vector2(0.35, 0.75)
	var land: Array = []
	for i in range(values.size()):
		var hue: float = base
		match scheme:
			0:
				hue += r.between(-0.08, 0.08)
			1:
				hue += (0.5 if i == 1 or i == 4 else 0.0) + r.between(-0.03, 0.03)
			2:
				hue += [0.0, 0.0, 0.33, 0.0, -0.33, 0.0][i] + r.between(-0.02, 0.02)
			3:
				hue += r.between(-0.015, 0.015)
		land.append(Color.from_hsv(
			fposmod(hue, 1.0), r.between(saturation.x, saturation.y), values[i]
		))
	p["land"] = land
	p["stops"] = _stops(r, [
		Vector2(0.15, 0.25), Vector2(0.35, 0.45), Vector2(0.55, 0.65),
		Vector2(0.75, 0.85), Vector2(0.95, 1.0),
	])
	p["atmo"] = r.hsv(Vector2(base, base), Vector2(0.3, 0.5), Vector2(0.95, 1.0))
	p["atmo_strength"] = r.between(0.5, 0.9)
	p["haze"] = r.between(0.08, 0.25) if icy else r.between(0.0, 0.06)
	p["frequency"] = r.between(1.0, 1.6)
	p["bands"] = r.whole(3, 9) if icy else r.whole(4, 14)
	# Turbulence, fine-streak weight, band sharpness (<1 flat bands with crisp
	# edges, >1 thin lines), band-width wobble; wobble scale, band offset.
	p["detail"] = _detail([
		r.between(0.8, 2.5) if icy else r.between(1.5, 4.5),
		r.between(0.05, 0.18) if icy else r.between(0.08, 0.3),
		r.between(0.4, 1.6), r.between(0.0, 0.25),
		r.between(1.5, 5.0), r.between(-0.15, 0.15),
	])
	p["storm"] = {
		"strength": r.between(0.5, 1.0) if r.chance(0.75) else 0.0,
		"width": r.between(0.1, 0.3),
		"latitude": r.between(-0.6, 0.6),
		"bright": r.chance(0.5),
	}
	return p


## An airless ice moon - ice over dark rock, cratered like Barren and cracked
## like Ice - with aurorae round the poles, as Ganymede has.
static func _roll_frozen(r: Roller) -> Dictionary:
	var p: Dictionary = _base(r)
	var ice: float = r.between(0.52, 0.6)
	p["land"] = [
		r.hsv(Vector2(0.05, 0.12), Vector2(0.05, 0.2), Vector2(0.18, 0.28)),
		r.hsv(Vector2(0.04, 0.12), Vector2(0.04, 0.15), Vector2(0.3, 0.4)),
		r.hsv(Vector2(ice, ice), Vector2(0.06, 0.15), Vector2(0.55, 0.68)),
		r.hsv(Vector2(ice, ice), Vector2(0.08, 0.2), Vector2(0.72, 0.82)),
		r.hsv(Vector2(ice, ice), Vector2(0.03, 0.1), Vector2(0.85, 0.93)),
		r.hsv(Vector2(ice, ice), Vector2(0.0, 0.05), Vector2(0.94, 1.0)),
	]
	p["stops"] = _stops(r, [
		Vector2(0.12, 0.22), Vector2(0.3, 0.4), Vector2(0.48, 0.58),
		Vector2(0.68, 0.8), Vector2(0.86, 0.95),
	])
	p["rock"] = r.hsv(Vector2(0.05, 0.12), Vector2(0.05, 0.2), Vector2(0.2, 0.3))
	p["slope_rock"] = r.between(0.3, 0.6)
	p["strata"] = r.between(0.1, 0.4)
	p["dry"] = r.hsv(Vector2(ice, ice), Vector2(0.02, 0.08), Vector2(0.8, 0.9))
	p["dry_amount"] = r.between(0.2, 0.5)
	p["cap"] = r.hsv(Vector2(ice, ice), Vector2(0.0, 0.05), Vector2(0.95, 1.0))
	p["cap_latitude"] = r.between(0.6, 0.85)
	# Too thin to be called an atmosphere; just enough glow for the aurora.
	p["atmo"] = r.hsv(Vector2(ice, ice), Vector2(0.3, 0.5), Vector2(0.9, 1.0))
	p["atmo_strength"] = r.between(0.1, 0.3)
	p["relief"] = r.between(0.05, 0.1)
	p["bump"] = r.between(3.0, 4.5)
	p["frequency"] = r.between(1.3, 2.1)
	p["detail"] = _detail([
		r.between(0.3, 0.6), r.between(0.1, 0.3), r.between(0.03, 0.1), r.between(0.15, 0.55),
		r.between(0.2, 0.45), r.between(0.08, 0.2), r.between(0.02, 0.07), r.between(0.25, 0.5),
		r.between(2.0, 4.5), r.between(0.015, 0.04), r.between(0.05, 0.15), r.between(-0.3, 0.3),
		r.between(0.5, 2.0), r.between(0.8, 1.2),
	])
	_roll_aurora(r, p)
	return p


## Mushy, scummed slime over low marsh, broken by single sharp dark peaks that
## take roughly a sixth of the land.
static func _roll_slime(r: Roller) -> Dictionary:
	var p: Dictionary = _base(r)
	p["liquid"] = true
	p["coverage"] = r.between(0.45, 0.7)

	# Green, yellow, teal, or blue - and the teal-to-blue shades between.
	var slime: float = [
		r.between(0.22, 0.33), r.between(0.14, 0.2), r.between(0.38, 0.5), r.between(0.5, 0.62),
	][r.pick([0.35, 0.2, 0.2, 0.25])]
	p["shallow"] = r.hsv(Vector2(slime, slime), Vector2(0.5, 0.8), Vector2(0.45, 0.65))
	p["deep"] = r.hsv(Vector2(slime - 0.02, slime + 0.03), Vector2(0.6, 0.9), Vector2(0.15, 0.3))
	# A trace of glow is what lets the shader lay scum over the slime.
	p["emission"] = r.between(0.03, 0.12)
	p["crust"] = r.between(0.3, 0.6)
	p["gloss"] = r.between(0.2, 0.45)

	# Marsh stays low and murky; the peaks run near-black.
	var peak_hue: float = r.between(0.6, 0.8)
	p["land"] = [
		r.hsv(Vector2(0.08, 0.14), Vector2(0.3, 0.5), Vector2(0.2, 0.3)),
		r.hsv(Vector2(slime - 0.03, slime + 0.03), Vector2(0.35, 0.6), Vector2(0.18, 0.28)),
		r.hsv(Vector2(0.2, 0.3), Vector2(0.2, 0.4), Vector2(0.12, 0.2)),
		r.hsv(Vector2(peak_hue, peak_hue), Vector2(0.05, 0.2), Vector2(0.1, 0.16)),
		r.hsv(Vector2(peak_hue, peak_hue), Vector2(0.05, 0.15), Vector2(0.07, 0.12)),
		r.hsv(Vector2(peak_hue, peak_hue), Vector2(0.03, 0.12), Vector2(0.16, 0.24)),
	]
	p["stops"] = _stops(r, [
		Vector2(0.03, 0.08), Vector2(0.12, 0.2), Vector2(0.3, 0.42),
		Vector2(0.55, 0.7), Vector2(0.85, 0.95),
	])
	p["rock"] = r.hsv(Vector2(peak_hue, peak_hue), Vector2(0.05, 0.15), Vector2(0.06, 0.1))
	p["slope_rock"] = r.between(0.6, 0.9)
	p["strata"] = r.between(0.0, 0.3)
	p["dry"] = r.hsv(Vector2(0.08, 0.13), Vector2(0.3, 0.5), Vector2(0.2, 0.3))
	p["dry_amount"] = r.between(0.3, 0.7)
	p["atmo"] = r.hsv(Vector2(slime, slime), Vector2(0.4, 0.6), Vector2(0.7, 0.9))
	p["atmo_strength"] = r.between(0.5, 0.9)
	p["haze"] = r.between(0.12, 0.3)
	p["clouds"] = r.between(0.1, 0.35)
	p["cloud_color"] = r.hsv(Vector2(slime, slime), Vector2(0.1, 0.25), Vector2(0.6, 0.8))
	p["relief"] = r.between(0.09, 0.15)
	p["bump"] = r.between(4.0, 6.0)
	p["frequency"] = r.between(1.2, 2.0)
	p["detail"] = _detail([
		# Sharpness above 1 makes each peak concave - a broad foot rising to a
		# needle tip; much higher and only the tip is left, too small to see.
		r.between(0.35, 0.6), r.between(0.05, 0.15), r.between(1.2, 2.0), r.between(3.0, 6.0),
		r.between(0.25, 0.45), r.between(1.3, 2.2), r.between(0.2, 0.5),
	])
	return p


## Black dust under a thin red sky, with glowing red eye sigils on the ground.
static func _roll_occult(r: Roller) -> Dictionary:
	var p: Dictionary = _base(r)
	# Black dust with red eyes, or glassy obsidian - a violet-black sheen, the
	# crests catching the light - with deep purple or deep yellow eyes.
	p["variant"] = ["dust", "obsidian_purple", "obsidian_yellow"][r.pick([0.4, 0.3, 0.3])]
	var obsidian: bool = p["variant"] != "dust"
	var hue: float = r.between(0.7, 0.76) if obsidian else r.between(0.95, 1.05)
	var saturation: float = r.between(0.12, 0.25) if obsidian else r.between(0.0, 0.08)
	var values: Array = [
		r.between(0.03, 0.06), r.between(0.06, 0.1), r.between(0.09, 0.14),
		r.between(0.13, 0.18), r.between(0.1, 0.15), r.between(0.18, 0.26),
	]
	if obsidian:
		values[5] = r.between(0.28, 0.36)
	var land: Array = []
	for value in values:
		land.append(r.tone(hue, 0.02, saturation, value))
	p["land"] = land
	p["stops"] = _stops(r, [
		Vector2(0.15, 0.25), Vector2(0.35, 0.45), Vector2(0.55, 0.65),
		Vector2(0.75, 0.85), Vector2(0.93, 1.0),
	])
	p["rock"] = r.tone(hue, 0.02, saturation, r.between(0.02, 0.05))
	p["slope_rock"] = r.between(0.3, 0.6)
	p["strata"] = r.between(0.0, 0.3)
	p["dry"] = r.tone(hue, 0.02, saturation * 0.6, r.between(0.14, 0.22))
	p["dry_amount"] = r.between(0.4, 0.8)
	var eye_hue := Vector2(0.98, 1.01)
	if p["variant"] == "obsidian_purple":
		eye_hue = Vector2(0.76, 0.8)
	elif p["variant"] == "obsidian_yellow":
		eye_hue = Vector2(0.12, 0.15)
	# Only a thin rim in the eyes' colour - any more haze and the black reads
	# tinted.
	p["atmo"] = r.hsv(eye_hue, Vector2(0.7, 0.9), Vector2(0.6, 0.9))
	p["atmo_strength"] = r.between(0.08, 0.2)
	p["haze"] = r.between(0.0, 0.04)
	p["relief"] = r.between(0.03, 0.07)
	p["bump"] = r.between(2.0, 3.5)
	p["frequency"] = r.between(1.4, 2.4)
	# c.x: tentacle ridge height.
	p["detail"] = _detail([
		r.between(0.3, 0.55), r.between(0.1, 0.3), r.between(0.05, 0.15), r.between(0.5, 0.85),
		r.between(0.1, 0.3), r.between(0.1, 0.3), r.between(4.0, 9.0), 0.0,
		r.between(1.0, 1.6),
	])

	# Eye-shaped craters, baked into the ground and stained red, with tentacle
	# ridges curling out of them - plus a nest or two of tentacles with no eye.
	# Only the iris and the drips glow, faintly, so they sit in the terrain
	# rather than on top of it.
	p["sigil_color"] = r.hsv(eye_hue, Vector2(0.85, 1.0), Vector2(0.6, 0.85))
	p["sigil_glow"] = r.between(0.35, 0.8)
	var sigils: Array = []
	var eyes: int = r.whole(3, 5)
	for i in range(eyes + r.whole(1, 2)):
		var size: float = r.between(0.2, 0.3) if i < eyes else r.between(0.15, 0.25)
		var reach: float = r.between(2.0, 3.0)
		var direction: Vector3 = _spaced_direction(r, sigils, size * reach * 1.4)
		if direction == Vector3.ZERO or sigils.size() >= MAX_SIGILS:
			break
		# style: rotation, pupil (0 round, 1 slit, 2 diamond; below 0 a tentacle
		# nest with no eye), drip count, crater depth.
		# extra: tentacle count, curl, reach (eye radii), width.
		sigils.append({
			"direction": direction,
			"size": size,
			"reach": reach,
			"style": Vector4(
				r.between(-0.4, 0.4),
				float(r.pick([0.5, 0.3, 0.2])) if i < eyes else -1.0,
				float(r.whole(3, 5)),
				r.between(0.5, 0.9)
			),
			"extra": Vector4(
				float(r.whole(4, 8)), r.between(-2.5, 2.5), reach, r.between(0.3, 0.5)
			),
		})
	p["sigils"] = sigils
	return p


## A random direction for a feature `spacing` radians across that stays clear
## of every feature placed so far (their tentacle tips may just touch), or
## ZERO if none turns up.
static func _spaced_direction(r: Roller, placed: Array, spacing: float) -> Vector3:
	for _attempt in range(60):
		var z: float = r.rng.randf_range(-1.0, 1.0)
		var phi: float = r.rng.randf_range(0.0, TAU)
		var ring: float = sqrt(1.0 - z * z)
		var direction := Vector3(ring * cos(phi), ring * sin(phi), z)
		var clear := true
		for sigil in placed:
			var apart: float = (spacing + sigil["size"] * sigil["reach"] * 1.4) * 0.5
			if direction.angle_to(sigil["direction"]) < apart:
				clear = false
				break
		if clear:
			return direction
	return Vector3.ZERO


## Placed features - Occult eyes, Swirl spirals, Rings, Fractal massifs - as
## the shaders' fixed-size uniform arrays, shared by the bake (which carves
## them) and the planet shader (which colours them; `sigil_mode` says which
## kind they are): count, then per feature xyz centre + angular radius, and the
## kind's own `style` and `extra` vectors, documented where each kind rolls
## them.
static func sigil_arrays(params: Dictionary) -> Dictionary:
	var centres := PackedVector4Array()
	var styles := PackedVector4Array()
	var extras := PackedVector4Array()
	for sigil in params["sigils"]:
		var direction: Vector3 = sigil["direction"]
		centres.append(Vector4(direction.x, direction.y, direction.z, sigil["size"]))
		styles.append(sigil["style"])
		extras.append(sigil["extra"])
	var count: int = mini(centres.size(), MAX_SIGILS)
	centres.resize(MAX_SIGILS)
	styles.resize(MAX_SIGILS)
	extras.resize(MAX_SIGILS)
	return {"count": count, "centres": centres, "styles": styles, "extras": extras}


## Scatters up to `count` features of angular radius `size` (+- 20%), each
## clear of the others by `reach` radii, calling `make.call(i)` for the
## feature's style and extra as [Vector4, Vector4].
static func _place_features(
	r: Roller, count: int, size: Vector2, reach: float, make: Callable
) -> Array:
	var features: Array = []
	for i in range(mini(count, MAX_SIGILS)):
		var radius: float = r.between(size.x, size.y)
		var direction: Vector3 = _spaced_direction(r, features, radius * reach * 1.4)
		if direction == Vector3.ZERO:
			break
		var shape: Array = make.call(i)
		features.append({
			"direction": direction, "size": radius, "reach": reach,
			"style": shape[0], "extra": shape[1],
		})
	return features


## Gloomy dark blue, split by glowing gold cracks, under hard theatrical light:
## no light wrapping round the terminator, no ambient, steep contrast.
static func _roll_gloom(r: Roller) -> Dictionary:
	var p: Dictionary = _base(r)
	if r.chance(0.4):
		p["liquid"] = true
		p["coverage"] = r.between(0.1, 0.3)
		p["shallow"] = r.hsv(Vector2(0.6, 0.68), Vector2(0.6, 0.9), Vector2(0.15, 0.25))
		p["deep"] = r.hsv(Vector2(0.62, 0.7), Vector2(0.7, 0.95), Vector2(0.03, 0.08))
		p["gloss"] = r.between(0.6, 0.9)

	var hue: float = r.between(0.58, 0.7)
	var saturation: float = r.between(0.35, 0.65)
	var values: Array = [
		r.between(0.05, 0.08), r.between(0.08, 0.12), r.between(0.11, 0.16),
		r.between(0.14, 0.2), r.between(0.1, 0.15), r.between(0.2, 0.28),
	]
	var land: Array = []
	for value in values:
		land.append(r.tone(hue, 0.03, saturation, value))
	p["land"] = land
	p["stops"] = _stops(r, [
		Vector2(0.1, 0.2), Vector2(0.3, 0.42), Vector2(0.52, 0.64),
		Vector2(0.72, 0.84), Vector2(0.9, 0.98),
	])
	p["rock"] = r.tone(hue, 0.02, saturation * 0.8, r.between(0.03, 0.06))
	p["slope_rock"] = r.between(0.4, 0.7)
	p["strata"] = r.between(0.1, 0.4)
	# Fine seams over part of the surface - wider or everywhere reads as a net.
	p["cracks"] = r.between(0.8, 1.6)
	# Anywhere from molten gold through orange to crimson.
	var crack_hue: float = fposmod(lerpf(0.13, -0.02, r.between(0.0, 1.0)), 1.0)
	p["crack_color"] = Color.from_hsv(crack_hue, r.between(0.65, 0.9), r.between(0.85, 1.0))
	p["crack_scale"] = r.between(4.0, 8.0)
	p["crack_width"] = r.between(0.008, 0.02)
	# Below 0 the seams reach over most of the planet; a little above, about
	# half. The gold on black is the whole look, so never much less.
	p["crack_coverage"] = r.between(-0.25, 0.1)
	p["ambient"] = 0.0
	p["light_wrap"] = 0.0
	p["terminator"] = r.between(0.1, 0.25)
	p["shade_contrast"] = r.between(1.5, 2.2)
	p["atmo"] = r.hsv(Vector2(0.6, 0.68), Vector2(0.5, 0.7), Vector2(0.4, 0.6))
	p["atmo_strength"] = r.between(0.2, 0.5)
	p["haze"] = r.between(0.05, 0.15)
	# Thin, still air: no cloud deck to hide the dark ground and its seams.
	p["relief"] = r.between(0.06, 0.11)
	p["bump"] = r.between(4.0, 6.0)
	p["frequency"] = r.between(1.3, 2.2)
	p["detail"] = _detail([r.between(0.5, 0.8), r.between(0.6, 1.2), r.between(0.1, 0.25)])
	return p


## Flower fields - navy blue or crimson - broken by deep brown valleys, with a
## light purple mist pooling in the lows and drifting.
static func _roll_bloom(r: Roller) -> Dictionary:
	var p: Dictionary = _base(r)
	# The fields are never one colour: two flower hues from anywhere between
	# navy, dark purple and crimson, alternating up the slopes so the rolling
	# ground breaks them into patches.
	var hue: float = fposmod(r.between(0.6, 1.0), 1.0)
	var other: float = fposmod(hue + r.between(0.08, 0.2) * (1.0 if hue < 0.8 else -1.0), 1.0)
	var saturation: float = r.between(0.6, 0.9)
	p["land"] = [
		r.hsv(Vector2(0.05, 0.08), Vector2(0.5, 0.7), Vector2(0.12, 0.18)),
		r.hsv(Vector2(0.06, 0.09), Vector2(0.45, 0.65), Vector2(0.2, 0.28)),
		r.tone(hue, 0.02, saturation, r.between(0.18, 0.28)),
		r.tone(other, 0.02, saturation, r.between(0.3, 0.42)),
		r.tone(hue, 0.02, saturation * 0.9, r.between(0.4, 0.52)),
		r.tone(other, 0.03, saturation * 0.75, r.between(0.5, 0.65)),
	]
	p["stops"] = _stops(r, [
		Vector2(0.05, 0.1), Vector2(0.16, 0.24), Vector2(0.35, 0.5),
		Vector2(0.6, 0.75), Vector2(0.85, 0.95),
	])
	p["rock"] = r.hsv(Vector2(0.05, 0.09), Vector2(0.4, 0.6), Vector2(0.15, 0.22))
	p["slope_rock"] = r.between(0.5, 0.8)
	# Grass among the flowers.
	p["dry"] = r.hsv(Vector2(0.25, 0.33), Vector2(0.4, 0.6), Vector2(0.25, 0.4))
	p["dry_amount"] = r.between(0.2, 0.5)
	# The purple is a veil, not a lid: thin mist in the valleys, a light rim
	# and few clouds - stacked any thicker, they bury the fields.
	p["mist"] = r.between(0.25, 0.45)
	p["mist_color"] = r.hsv(Vector2(0.75, 0.82), Vector2(0.2, 0.4), Vector2(0.85, 0.95))
	p["mist_height"] = r.between(0.2, 0.35)
	p["atmo"] = r.hsv(Vector2(0.75, 0.82), Vector2(0.3, 0.5), Vector2(0.9, 1.0))
	p["atmo_strength"] = r.between(0.25, 0.45)
	p["haze"] = r.between(0.0, 0.04)
	p["clouds"] = r.between(0.0, 0.12)
	p["cloud_color"] = r.hsv(Vector2(0.75, 0.82), Vector2(0.1, 0.25), Vector2(0.9, 1.0))
	p["relief"] = r.between(0.04, 0.08)
	p["bump"] = r.between(2.5, 4.0)
	p["frequency"] = r.between(1.5, 2.5)
	# Valleys sparse and narrow enough that the fields stay the main thing.
	p["detail"] = _detail([
		r.between(0.3, 0.5), r.between(0.1, 0.25), r.between(1.0, 2.0), r.between(0.04, 0.09),
		r.between(0.3, 0.6), r.between(0.6, 1.8),
	])
	return p


## Sand dunes with muddy, shining puddles in their hollows, and small spiky
## green buds - pufferfish, or a dab of a brush - thickest near the water.
static func _roll_oasis(r: Roller) -> Dictionary:
	var p: Dictionary = _base(r)
	# A small liquid share over a field of pits fills them as separate
	# puddles instead of one sea.
	# Coverage is kept to about the pits' own area; any more and the rest
	# floods the dune troughs into a maze of water.
	p["liquid"] = true
	p["coverage"] = r.between(0.03, 0.07)
	p["gloss"] = r.between(0.85, 0.97)
	var water: float = r.between(0.38, 0.55)
	p["shallow"] = r.hsv(Vector2(water, water), Vector2(0.3, 0.5), Vector2(0.45, 0.6))
	p["deep"] = r.hsv(Vector2(water - 0.03, water + 0.03), Vector2(0.35, 0.55), Vector2(0.28, 0.4))

	# Sand, darker and wetter at the waterline, palest on the dune crests -
	# pale yellow sand through to orange.
	var hue: float = r.between(0.045, 0.13)
	var saturation: float = lerpf(0.65, 0.3, inverse_lerp(0.045, 0.13, hue)) + r.between(-0.05, 0.1)
	var values: Array = [
		r.between(0.48, 0.58), r.between(0.62, 0.72), r.between(0.7, 0.8),
		r.between(0.78, 0.88), r.between(0.66, 0.76), r.between(0.85, 0.93),
	]
	var land: Array = []
	for value in values:
		land.append(r.tone(hue, 0.012, saturation, value))
	p["land"] = land
	p["stops"] = _stops(r, [
		Vector2(0.04, 0.1), Vector2(0.2, 0.32), Vector2(0.45, 0.58),
		Vector2(0.68, 0.8), Vector2(0.88, 0.97),
	])
	p["rock"] = r.tone(hue - 0.02, 0.02, saturation, r.between(0.4, 0.5))
	p["slope_rock"] = r.between(0.2, 0.45)
	p["strata"] = r.between(0.3, 0.7)
	p["dry"] = r.tone(hue, 0.02, saturation * 0.8, r.between(0.82, 0.92))
	p["dry_amount"] = r.between(0.2, 0.5)
	p["atmo"] = r.hsv(Vector2(hue - 0.01, hue + 0.01), Vector2(0.3, 0.5), Vector2(0.95, 1.0))
	p["atmo_strength"] = r.between(0.3, 0.6)
	p["haze"] = r.between(0.02, 0.08)
	p["clouds"] = r.between(0.0, 0.15)
	p["relief"] = r.between(0.03, 0.06)
	p["bump"] = r.between(2.5, 4.0)
	p["frequency"] = r.between(1.3, 2.2)
	# a: continent, dune and erosion weights, dune scale
	# b: share of cells holding a puddle, puddle depth, puddle scale
	# Puddles just deep enough to be the lowest ground; deeper and they read
	# as black holes.
	# c: river scale, width, depth (0 = none), wander. Half the worlds have
	# long muddy rivers winding between the puddles.
	var rivers: bool = r.chance(0.5)
	if rivers:
		p["coverage"] += r.between(0.04, 0.07)
	p["detail"] = _detail([
		r.between(0.25, 0.45), r.between(0.15, 0.35), r.between(0.05, 0.12), r.between(2.5, 5.0),
		r.between(0.2, 0.4), r.between(0.35, 0.6), r.between(4.0, 8.0), 0.0,
		r.between(1.2, 2.2), r.between(0.04, 0.07), r.between(0.45, 0.65) if rivers else 0.0, r.between(0.6, 1.4),
	])

	p["buds"] = 1.0
	p["bud_color"] = r.hsv(Vector2(0.22, 0.38), Vector2(0.55, 0.8), Vector2(0.55, 0.75))
	# Small, but around ten pixels across when the planet fills the view.
	p["bud_scale"] = r.between(12.0, 22.0)
	p["bud_size"] = r.between(0.22, 0.34)
	p["bud_spike"] = r.between(0.12, 0.25)
	p["bud_density"] = r.between(0.35, 0.7)
	p["bud_reach"] = r.between(0.04, 0.12)
	return p


## Open ocean whose only land is giant four-petal flowers lying on lily pads.
## The bake raises each flower far above a low ocean floor and the sea is
## pinned between the two, so the flowers are all the land there is. Colour
## runs with height: pad green at the waterline, then the petals from tip to
## centre in some order of white, pink and yellow.
static func _roll_lotus(r: Roller) -> Dictionary:
	var p: Dictionary = _base(r)
	p["liquid"] = true
	p["coverage"] = 0.9
	p["sea_fixed"] = r.between(0.22, 0.28)
	p["gloss"] = r.between(0.75, 0.95)
	var deep: Color = r.hsv(Vector2(0.5, 0.64), Vector2(0.6, 0.9), Vector2(0.15, 0.35))
	p["deep"] = deep
	p["shallow"] = Color.from_hsv(
		fposmod(deep.h - r.between(0.0, 0.06), 1.0), r.between(0.45, 0.7), r.between(0.45, 0.7)
	)

	var yellow: Color = r.hsv(Vector2(0.12, 0.16), Vector2(0.55, 0.85), Vector2(0.9, 1.0))
	var pink: Color = r.hsv(Vector2(0.9, 0.98), Vector2(0.35, 0.6), Vector2(0.9, 1.0))
	var white: Color = r.hsv(Vector2(0.0, 1.0), Vector2(0.0, 0.06), Vector2(0.95, 1.0))
	var orders: Array = [
		[white, pink, yellow], [pink, white, yellow], [white, yellow, pink],
		[pink, yellow, white], [yellow, pink, white],
	]
	var petals: Array = orders[r.pick([0.35, 0.25, 0.15, 0.15, 0.1])]
	var pad: Color = r.hsv(Vector2(0.25, 0.36), Vector2(0.45, 0.7), Vector2(0.3, 0.45))
	p["land"] = [
		pad, pad.lightened(0.15), petals[0], petals[0].lerp(petals[1], 0.5), petals[1], petals[2],
	]
	p["stops"] = [
		0.0, r.between(0.18, 0.22), r.between(0.28, 0.32), r.between(0.45, 0.55),
		r.between(0.65, 0.75), r.between(0.88, 0.96),
	]
	p["rock"] = pad.darkened(0.3)
	p["atmo"] = r.hsv(Vector2(0.55, 0.62), Vector2(0.3, 0.5), Vector2(0.9, 1.0))
	p["atmo_strength"] = r.between(0.4, 0.8)
	p["haze"] = r.between(0.0, 0.05)
	p["clouds"] = r.between(0.0, 0.15)
	p["relief"] = r.between(0.02, 0.04)
	p["bump"] = r.between(2.0, 3.5)
	p["frequency"] = r.between(1.0, 1.6)
	# a: ocean-floor roughness, flower scale (higher = more, smaller flowers),
	#    share of cells holding a flower, petal roundness (lower = pointier)
	p["detail"] = _detail([
		r.between(0.05, 0.15), r.between(1.4, 2.2), r.between(0.4, 0.65), r.between(0.4, 0.8),
	])
	return p


## Crimson ground under about ten big snail-shell swirls: two interleaved
## spiral arms, one a raised orange ridge, the other a pit of the same shape.
static func _roll_swirl(r: Roller) -> Dictionary:
	var p: Dictionary = _base(r)
	var hue: float = r.between(0.955, 0.99)
	var saturation: float = r.between(0.65, 0.85)
	var values: Array = [
		r.between(0.25, 0.32), r.between(0.32, 0.4), r.between(0.38, 0.46),
		r.between(0.44, 0.52), r.between(0.5, 0.58), r.between(0.58, 0.68),
	]
	var land: Array = []
	for value in values:
		land.append(r.tone(hue, 0.02, saturation, value))
	p["land"] = land
	p["stops"] = _stops(r, [
		Vector2(0.15, 0.25), Vector2(0.35, 0.45), Vector2(0.55, 0.65),
		Vector2(0.75, 0.85), Vector2(0.92, 0.99),
	])
	p["rock"] = r.tone(hue, 0.02, saturation, r.between(0.15, 0.22))
	p["slope_rock"] = r.between(0.2, 0.4)
	p["dry"] = r.tone(hue + 0.02, 0.02, saturation * 0.8, r.between(0.5, 0.6))
	p["dry_amount"] = r.between(0.2, 0.5)
	p["atmo"] = r.hsv(Vector2(0.95, 0.99), Vector2(0.45, 0.65), Vector2(0.85, 1.0))
	p["atmo_strength"] = r.between(0.3, 0.55)
	p["haze"] = r.between(0.02, 0.06)
	p["clouds"] = r.between(0.0, 0.12)
	# Over the spiral ridges, which stand at the top of the range - a deck at
	# the usual height has them poking up through it.
	p["cloud_height"] = 1.0
	p["relief"] = r.between(0.04, 0.07)
	p["bump"] = r.between(3.0, 4.5)
	p["frequency"] = r.between(1.2, 1.9)
	# a: continent, peak and erosion weights, swirl ridge weight
	p["detail"] = _detail([
		r.between(0.3, 0.5), r.between(0.1, 0.3), r.between(0.05, 0.15), r.between(0.9, 1.3),
	])

	p["sigil_mode"] = FeatureMode.SWIRLS
	p["sigil_color"] = r.hsv(Vector2(0.06, 0.1), Vector2(0.75, 0.95), Vector2(0.8, 0.95))
	# The floor of the pit: the ground's crimson, deeper.
	p["sigil_color_b"] = r.tone(hue, 0.01, saturation, r.between(0.1, 0.16))
	# style: rotation, turns from centre to rim, arms (kept even, so ridge and
	# pit alternate without a seam), handedness.
	# extra: ridge height, pit depth (against the ridge's height).
	p["sigils"] = _place_features(r, r.whole(8, 11), Vector2(0.38, 0.55), 1.25,
		func(_i: int) -> Array:
			return [
				Vector4(r.between(0.0, TAU), r.between(3.0, 5.0), 2.0, 1.0 if r.chance(0.5) else -1.0),
				Vector4(r.between(0.55, 0.85), r.between(0.5, 0.8), 0.0, 0.0),
			]
	)
	return p


## Happy greens of every shade, with here and there a set of onion-like
## concentric rings - dark red and near black, alternating - broken by gaps,
## ringed by patches of violet bushes. Some ring sets stand as islands in a
## ring of sea. Variants: traces of sand and sand hills, or a few volcanoes.
static func _roll_rings(r: Roller) -> Dictionary:
	var p: Dictionary = _base(r)
	p["variant"] = ["green", "sandy", "volcanic"][r.pick([0.5, 0.25, 0.25])]
	var land: Array = []
	var values: Array = [0.35, 0.45, 0.55, 0.62, 0.7, 0.8]
	for value in values:
		land.append(r.hsv(Vector2(0.2, 0.42), Vector2(0.45, 0.8), Vector2(value - 0.05, value + 0.05)))
	p["land"] = land
	p["stops"] = _stops(r, [
		Vector2(0.12, 0.22), Vector2(0.3, 0.42), Vector2(0.5, 0.62),
		Vector2(0.7, 0.82), Vector2(0.88, 0.97),
	])
	p["rock"] = r.hsv(Vector2(0.28, 0.38), Vector2(0.4, 0.6), Vector2(0.2, 0.3))
	p["slope_rock"] = r.between(0.2, 0.4)
	p["dry"] = r.hsv(Vector2(0.17, 0.24), Vector2(0.5, 0.75), Vector2(0.6, 0.75))
	p["dry_amount"] = r.between(0.3, 0.6)
	p["atmo"] = r.hsv(Vector2(0.35, 0.5), Vector2(0.3, 0.5), Vector2(0.9, 1.0))
	p["atmo_strength"] = r.between(0.4, 0.7)
	p["haze"] = r.between(0.0, 0.05)
	p["clouds"] = r.between(0.0, 0.15)
	p["relief"] = r.between(0.04, 0.08)
	p["bump"] = r.between(3.0, 4.5)
	p["frequency"] = r.between(1.3, 2.0)

	# b: sand-hill weight and scale, volcano weight and scale. c.x: share of
	# cells with a volcano.
	var sand_hills := Vector2.ZERO
	var volcanoes := Vector3.ZERO
	if p["variant"] == "sandy":
		# Sand drifts over the lowlands (the dry biome), piled into hills.
		p["dry"] = r.hsv(Vector2(0.1, 0.13), Vector2(0.3, 0.5), Vector2(0.75, 0.88))
		p["dry_amount"] = r.between(0.7, 0.95)
		sand_hills = Vector2(r.between(0.2, 0.4), r.between(4.0, 8.0))
	elif p["variant"] == "volcanic":
		# Dark basalt cones with calderas, standing out of the green.
		p["rock"] = r.hsv(Vector2(0.0, 0.08), Vector2(0.1, 0.25), Vector2(0.1, 0.16))
		p["slope_rock"] = r.between(0.6, 0.85)
		volcanoes = Vector3(r.between(1.4, 2.0), r.between(2.5, 4.0), r.between(0.12, 0.25))

	# a: continent, peak and erosion weights, ring ridge weight
	p["detail"] = _detail([
		r.between(0.3, 0.5), r.between(0.2, 0.4), r.between(0.08, 0.2), r.between(0.4, 0.8),
		sand_hills.x, sand_hills.y, volcanoes.x, volcanoes.y,
		volcanoes.z,
	])

	p["sigil_mode"] = FeatureMode.RINGS
	p["sigil_color"] = r.hsv(Vector2(0.98, 1.02), Vector2(0.7, 0.9), Vector2(0.5, 0.65))
	p["sigil_color_b"] = r.hsv(Vector2(0.98, 1.02), Vector2(0.3, 0.6), Vector2(0.04, 0.08))
	# style: rotation, ring count, ring width (share of each ring's spacing),
	# gaps per ring. extra: gap width (share of each segment), ridge height,
	# island (1 = raised in a ring of sea), island plateau height.
	# Spaced for their moats (see ISLAND_MOAT in the bake).
	p["sigils"] = _place_features(r, r.whole(3, 5), Vector2(0.28, 0.45), 1.9,
		func(_i: int) -> Array:
			return [
				Vector4(r.between(0.0, TAU), float(r.whole(3, 6)), r.between(0.4, 0.6), float(r.whole(2, 4))),
				Vector4(r.between(0.08, 0.2), r.between(0.3, 0.6), 1.0 if r.chance(0.4) else 0.0, r.between(0.3, 0.5)),
			]
	)

	# The islands' moats are the planet's lowest ground; a sea just big
	# enough to fill them, in ordinary ocean blues.
	# A moat's floor spans about 1.15 to 1.55 of its island's radii: on the
	# unit sphere that is about 0.27 * size^2 of the whole surface.
	var moat_share := 0.0
	for sigil: Dictionary in p["sigils"]:
		if (sigil["extra"] as Vector4).z > 0.5:
			moat_share += 0.27 * pow(sigil["size"], 2.0)
	if moat_share > 0.0:
		p["liquid"] = true
		p["coverage"] = moat_share * r.between(0.9, 1.05)
		p["deep"] = r.hsv(Vector2(0.58, 0.64), Vector2(0.7, 0.9), Vector2(0.2, 0.35))
		p["shallow"] = r.hsv(Vector2(0.48, 0.54), Vector2(0.5, 0.7), Vector2(0.55, 0.75))
		p["gloss"] = r.between(0.7, 0.9)

	# Violet bushes in patches round every ring set.
	p["buds"] = 1.0
	p["bud_near_features"] = 1.0
	p["bud_color"] = r.hsv(Vector2(0.74, 0.82), Vector2(0.5, 0.7), Vector2(0.7, 0.88))
	p["bud_scale"] = r.between(10.0, 14.0)
	p["bud_size"] = r.between(0.38, 0.46)
	p["bud_spike"] = r.between(0.15, 0.3)
	p["bud_density"] = r.between(0.85, 1.0)
	return p


## Brown blending into a steel-blue cast, scarred all over by small silver
## quake cracks - jagged rings with spokes running out - drawn by the shader.
static func _roll_quake(r: Roller) -> Dictionary:
	var p: Dictionary = _base(r)
	var brown: Color = r.hsv(Vector2(0.06, 0.1), Vector2(0.3, 0.5), Vector2(0.3, 0.4))
	# The cast: steel, or a metallic green or blue.
	var steel: Color = [
		r.hsv(Vector2(0.56, 0.62), Vector2(0.15, 0.35), Vector2(0.45, 0.6)),
		r.hsv(Vector2(0.38, 0.46), Vector2(0.35, 0.55), Vector2(0.45, 0.62)),
		r.hsv(Vector2(0.56, 0.62), Vector2(0.45, 0.65), Vector2(0.5, 0.66)),
	][r.pick([0.4, 0.3, 0.3])]
	var land: Array = []
	for i in range(6):
		var t: float = float(i) / 5.0
		var c: Color = brown.lerp(steel, clampf(t * r.between(0.8, 1.2), 0.0, 1.0))
		land.append(c.lightened(t * 0.15))
	p["land"] = land
	p["stops"] = _stops(r, [
		Vector2(0.12, 0.22), Vector2(0.32, 0.42), Vector2(0.52, 0.62),
		Vector2(0.72, 0.82), Vector2(0.9, 0.98),
	])
	p["rock"] = brown.darkened(0.3)
	p["slope_rock"] = r.between(0.3, 0.5)
	p["strata"] = r.between(0.2, 0.5)
	p["dry"] = brown.lerp(steel, 0.5)
	p["dry_amount"] = r.between(0.3, 0.6)
	p["atmo"] = Color.from_hsv(steel.h, r.between(0.2, 0.4), r.between(0.85, 1.0))
	p["atmo_strength"] = r.between(0.2, 0.5)
	p["haze"] = r.between(0.02, 0.08)
	p["relief"] = r.between(0.04, 0.08)
	p["bump"] = r.between(3.0, 4.5)
	p["frequency"] = r.between(1.3, 2.1)
	p["quake"] = 1.0
	p["quake_color"] = r.hsv(Vector2(0.55, 0.6), Vector2(0.02, 0.08), Vector2(0.8, 0.95))
	# Small scars, and many of them.
	p["quake_scale"] = r.between(7.0, 11.0)
	p["quake_density"] = r.between(0.35, 0.65)
	p["quake_size"] = r.between(0.35, 0.45)
	p["quake_rings"] = float(r.whole(1, 3))
	p["quake_spokes"] = float(r.whole(5, 9))
	p["quake_shift"] = r.between(0.0, 500.0)
	# a: continent, peak and erosion weights, hole depth
	# b: the scars' scale, density, size and shift, so the bake carves a hole
	#    under each one the shader draws
	p["detail"] = _detail([
		r.between(0.4, 0.7), r.between(0.3, 0.6), r.between(0.1, 0.2), r.between(0.3, 0.5),
		p["quake_scale"], p["quake_density"], p["quake_size"], p["quake_shift"],
	])
	return p


## Brown-grey barren ground, craterless, with a few great massifs shaped like
## the Mandelbrot set: the set's bulbs domes, its filaments lower ridges,
## coloured with height from navy up through purple to yellow crowns.
static func _roll_fractal(r: Roller) -> Dictionary:
	var p: Dictionary = _base(r)
	var hue: float = r.between(0.05, 0.1)
	var saturation: float = r.between(0.08, 0.25)
	p["land"] = [
		r.tone(hue, 0.01, saturation, r.between(0.25, 0.32)),
		r.tone(hue, 0.01, saturation, r.between(0.32, 0.4)),
		r.tone(hue, 0.01, saturation, r.between(0.4, 0.48)),
		r.hsv(Vector2(0.62, 0.66), Vector2(0.7, 0.9), Vector2(0.28, 0.42)),
		r.hsv(Vector2(0.74, 0.8), Vector2(0.55, 0.8), Vector2(0.5, 0.65)),
		r.hsv(Vector2(0.12, 0.16), Vector2(0.6, 0.85), Vector2(0.85, 0.95)),
	]
	# The massifs take the top of the range: filaments navy, dome flanks
	# purple, crowns yellow. The plains stay below ~0.25.
	p["stops"] = _stops(r, [
		Vector2(0.08, 0.12), Vector2(0.16, 0.22), Vector2(0.3, 0.38),
		Vector2(0.55, 0.65), Vector2(0.9, 0.97),
	])
	p["rock"] = r.hsv(Vector2(0.7, 0.76), Vector2(0.4, 0.6), Vector2(0.25, 0.35))
	p["slope_rock"] = r.between(0.1, 0.3)
	p["dry"] = r.tone(hue, 0.01, saturation, r.between(0.42, 0.5))
	p["dry_amount"] = r.between(0.2, 0.5)
	p["atmo"] = r.hsv(Vector2(0.7, 0.76), Vector2(0.3, 0.5), Vector2(0.8, 0.95))
	p["atmo_strength"] = r.between(0.1, 0.3)
	p["relief"] = r.between(0.06, 0.1)
	p["bump"] = r.between(3.0, 5.0)
	p["frequency"] = r.between(1.3, 2.0)
	# a: continent, peak and erosion weights, massif height
	p["detail"] = _detail([
		r.between(0.2, 0.35), r.between(0.05, 0.15), r.between(0.05, 0.12), r.between(1.8, 2.6),
	])

	p["sigil_mode"] = FeatureMode.BAKE_ONLY
	# style: rotation, zoom (how much of the set spans the massif), view offset
	# x and y from the set's usual centre.
	# style.y is kept above ~1.2 so the whole set, filaments and all, fits
	# inside the massif's fade.
	p["sigils"] = _place_features(r, r.whole(2, 4), Vector2(0.65, 0.9), 1.0,
		func(_i: int) -> Array:
			return [
				Vector4(r.between(0.0, TAU), r.between(1.2, 1.35), r.between(-0.05, 0.1), r.between(-0.08, 0.08)),
				Vector4.ZERO,
			]
	)
	return p


## Almost any colour, crossed pole to pole by a crowd of mountain ridges and
## carved valleys, each on a course of its own - straight, curving or
## zig-zagging, leaning this way or that - so they wander and cross rather
## than run in step. Pink-and-white seas fill the low ground, running up the
## valleys as channels. Colour follows height: the colour's near-black in the
## valleys that stay dry, the colour itself on the plains, its near-white on
## the crests.
static func _roll_meridian(r: Roller) -> Dictionary:
	var p: Dictionary = _base(r)
	# Pink belongs to the sea: the land never rolls pink, magenta or red.
	var base: Color = r.hsv(Vector2(0.03, 0.8), Vector2(0.35, 0.75), Vector2(0.4, 0.6))
	var dark := Color.from_hsv(base.h, minf(base.s * 1.2, 1.0), r.between(0.08, 0.14))
	var light := Color.from_hsv(base.h, base.s * 0.3, r.between(0.88, 0.95))
	p["land"] = [dark, base.darkened(0.25), base, base, base.lerp(light, 0.5), light]
	# From the shore up: a thin dark rim where the land climbs out of the sea,
	# the plains in the colour itself, then steeply to the pale crests.
	p["stops"] = _stops(r, [
		Vector2(0.015, 0.03), Vector2(0.06, 0.1), Vector2(0.3, 0.38),
		Vector2(0.48, 0.56), Vector2(0.66, 0.76),
	])

	p["liquid"] = true
	p["coverage"] = r.between(0.3, 0.45)
	var sea_hue: float = r.between(0.9, 0.96)
	p["deep"] = Color.from_hsv(sea_hue, r.between(0.45, 0.65), r.between(0.55, 0.72))
	p["shallow"] = Color.from_hsv(sea_hue, r.between(0.08, 0.2), r.between(0.93, 1.0))
	p["gloss"] = r.between(0.5, 0.8)
	p["rock"] = base.darkened(0.45)
	p["slope_rock"] = r.between(0.15, 0.3)
	p["atmo"] = Color.from_hsv(base.h, base.s * 0.5, 1.0)
	p["atmo_strength"] = r.between(0.3, 0.6)
	p["haze"] = r.between(0.0, 0.05)
	p["relief"] = r.between(0.05, 0.09)
	p["bump"] = r.between(3.0, 4.5)
	p["frequency"] = r.between(1.2, 1.8)
	# a: continent, peak and erosion weights, line weight. Gentle plains, so
	# the lines stand out of them.
	p["detail"] = _detail([
		r.between(0.12, 0.22), r.between(0.05, 0.1), r.between(0.04, 0.08), r.between(1.0, 1.4),
	])

	# One slot per line (see meridian_relief() in the bake): spread round the
	# globe, then each given its own course.
	# style: longitude at the equator, swing (radians), swings pole to pole,
	# phase. extra: course (0 straight, 1 curving, 2 zig-zag), lean (radians
	# pole to pole), half-width (radians), height (< 0 a valley).
	p["sigil_mode"] = FeatureMode.BAKE_ONLY
	var lines: Array = []
	var count: int = r.whole(14, MAX_SIGILS)
	var start: float = r.between(0.0, TAU)
	for i in range(count):
		var course: int = r.pick([0.3, 0.4, 0.3])
		var swing := 0.0
		var swings := 0.0
		if course == 1:
			swing = r.between(0.08, 0.35)
			swings = r.between(0.5, 2.0)
		elif course == 2:
			swing = r.between(0.04, 0.14)
			swings = r.between(2.0, 5.0)
		var height: float = r.between(0.6, 1.0) if r.chance(0.5) else -r.between(0.5, 0.9)
		lines.append({
			"direction": Vector3.ZERO, "size": 0.0, "reach": 0.0,
			"style": Vector4(start + TAU * (float(i) + r.between(-0.3, 0.3)) / float(count), swing, swings, r.between(0.0, 1.0)),
			"extra": Vector4(float(course), r.between(-0.6, 0.6) if r.chance(0.5) else 0.0, r.between(0.025, 0.06), height),
		})
	p["sigils"] = lines
	return p


## Everything the bake reads besides kind, seed, size and pole.
static func _bake_values(params: Dictionary) -> PackedFloat32Array:
	var storm: Dictionary = params["storm"]
	var values := PackedFloat32Array([
		params["frequency"], float(params["bands"]), params["sea_fixed"],
		storm["strength"], storm["width"], storm["latitude"], 1.0 if storm["bright"] else 0.0,
	])
	values.append_array(PackedFloat32Array(params["recipe"]))
	values.append_array(params["detail"])
	values.append_array(_sigil_floats(params))
	return values


## The sigil block of the bake's settings: `sigil_info`, then the three
## arrays, as laid out in `Params` in planet_terrain_bake.glsl.
static func _sigil_floats(params: Dictionary) -> PackedFloat32Array:
	var arrays: Dictionary = sigil_arrays(params)
	var floats := PackedFloat32Array([float(arrays["count"]), 0.0, 0.0, 0.0])
	for key in ["centres", "styles", "extras"]:
		for v in arrays[key]:
			floats.append_array(PackedFloat32Array([v.x, v.y, v.z, v.w]))
	return floats


static func cache_key(
	kind: Kind, terrain_seed: int, resolution: int, pole: Vector3, params: Dictionary
) -> String:
	return "%d|%d|%d|%s|%.4f|%d" % [
		kind, terrain_seed, resolution, pole, params["coverage"], hash(_bake_values(params))
	]


static func cached(key: String) -> Dictionary:
	return _cache.get(key, {})


static func store(key: String, data: Dictionary) -> void:
	_cache[key] = data


## Drops every finished bake. A bake is ~25 MB of heights at full resolution,
## so a world reroll clears the old world's rather than piling them up.
static func clear_cache() -> void:
	_cache.clear()


## Bakes the heightmap on the GPU (planet_terrain_bake.glsl) through a local
## RenderingDevice. Safe on a worker thread; bakes queue up one at a time.
## Returns { size, faces: Array[PackedFloat32Array] (0..1 heights), images:
## Array[Image] (the same, mipmapped, for the GPU), sea_level } - sea_level is
## where `params.coverage` of the surface area lies below, or -1 for a dry
## world. Empty when there is no RenderingDevice (headless, Compatibility).
static func bake(
	kind: Kind, terrain_seed: int, resolution: int, pole: Vector3, params: Dictionary
) -> Dictionary:
	var n: int = clampi(resolution, MIN_RESOLUTION, MAX_RESOLUTION)
	var bytes := PackedByteArray()
	var histogram := PackedInt64Array()

	_gpu_mutex.lock()
	var rd: RenderingDevice = RenderingServer.create_local_rendering_device()
	if rd != null:
		bytes = _dispatch(rd, kind, terrain_seed, n, pole, params, histogram)
		rd.free()
	_gpu_mutex.unlock()

	if bytes.is_empty():
		return {}

	var face_bytes: int = n * n * 4
	var faces: Array[PackedFloat32Array] = []
	var images: Array[Image] = []
	for face in range(6):
		var slice: PackedByteArray = bytes.slice(face * face_bytes, (face + 1) * face_bytes)
		faces.append(slice.to_float32_array())
		var image := Image.create_from_data(n, n, false, Image.FORMAT_RF, slice)
		image.generate_mipmaps()
		images.append(image)

	var sea_level: float = -1.0
	if params["liquid"]:
		sea_level = _level_at_coverage(histogram, params["coverage"])
		# A kind whose land is a shape of its own (Lotus flowers) pins the sea
		# between its ocean floor and that land instead.
		if params.get("sea_fixed", -1.0) >= 0.0:
			sea_level = params["sea_fixed"]

	return { "size": n, "faces": faces, "images": images, "sea_level": sea_level }


## Runs both bake passes and reads the heights back; fills `histogram`.
static func _dispatch(
	rd: RenderingDevice, kind: Kind, terrain_seed: int, n: int, pole: Vector3,
	params: Dictionary, histogram: PackedInt64Array
) -> PackedByteArray:
	var spirv: RDShaderSPIRV = BAKE_SHADER.get_spirv()
	var shader: RID = rd.shader_create_from_spirv(spirv)
	if not shader.is_valid():
		push_error("PlanetTerrain: bake shader failed to compile: %s" % spirv.compile_error_compute)
		return PackedByteArray()

	var storm: Dictionary = _roll_storm(terrain_seed, pole, params["storm"])
	var center: Vector3 = storm["center"]
	var east: Vector3 = storm["east"]
	var north: Vector3 = storm["north"]
	var recipe: Array = params["recipe"]
	# Layout mirrors `Params` in planet_terrain_bake.glsl, one vec4 per line.
	var settings := PackedFloat32Array([
		float(kind), float(n), params["frequency"], float(params["bands"]),
		pole.x, pole.y, pole.z, 0.0,
		center.x, center.y, center.z, storm["width"],
		east.x, east.y, east.z, 1.0 if storm["bright"] else 0.0,
		north.x, north.y, north.z, storm["strength"],
		recipe[0], recipe[1], recipe[2], recipe[3],
	])
	settings.append_array(params["detail"])
	settings.append_array(_sigil_floats(params))

	var stats := PackedInt32Array([-1, 0, 0, 0])  # low starts at 0xFFFFFFFF
	stats.resize(4 + HISTOGRAM_BINS)

	var heights_buffer: RID = rd.storage_buffer_create(6 * n * n * 4)
	var stats_bytes: PackedByteArray = stats.to_byte_array()
	var stats_buffer: RID = rd.storage_buffer_create(stats_bytes.size(), stats_bytes)
	var settings_bytes: PackedByteArray = settings.to_byte_array()
	var settings_buffer: RID = rd.storage_buffer_create(settings_bytes.size(), settings_bytes)

	var uniforms: Array[RDUniform] = []
	for binding in range(3):
		var uniform := RDUniform.new()
		uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
		uniform.binding = binding
		uniform.add_id([heights_buffer, stats_buffer, settings_buffer][binding])
		uniforms.append(uniform)
	var uniform_set: RID = rd.uniform_set_create(uniforms, shader, 0)
	var pipeline: RID = rd.compute_pipeline_create(shader)

	var groups: int = ceili(n / 8.0)
	var list: int = rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(list, pipeline)
	rd.compute_list_bind_uniform_set(list, uniform_set, 0)
	for pass_index in range(2):
		var push := PackedInt32Array([pass_index, hash(terrain_seed ^ NOISE_SALT), 0, 0])
		rd.compute_list_set_push_constant(list, push.to_byte_array(), 16)
		rd.compute_list_dispatch(list, groups, groups, 6)
		rd.compute_list_add_barrier(list)
	rd.compute_list_end()
	rd.submit()
	rd.sync()

	var bytes: PackedByteArray = rd.buffer_get_data(heights_buffer)
	var counts: PackedByteArray = rd.buffer_get_data(stats_buffer, 16, HISTOGRAM_BINS * 4)
	histogram.resize(HISTOGRAM_BINS)
	for bin in range(HISTOGRAM_BINS):
		histogram[bin] = counts.decode_u32(bin * 4)

	rd.free_rid(pipeline)
	rd.free_rid(uniform_set)
	rd.free_rid(settings_buffer)
	rd.free_rid(stats_buffer)
	rd.free_rid(heights_buffer)
	rd.free_rid(shader)
	return bytes


## Up to four cyclones for the cloud deck (planet_clouds.gdshaderinc): a centre
## on the sphere and a spin that turns the way the hemisphere's Coriolis force
## would. Wetter skies brew more. Unused slots are zero, which the shader skips.
static func roll_cyclones(terrain_seed: int, pole: Vector3, coverage: float) -> PackedVector4Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(terrain_seed ^ PALETTE_SALT ^ 0x2545F491)
	var cyclones := PackedVector4Array()
	cyclones.resize(4)

	var count: int = 0 if coverage <= 0.0 else clampi(roundi(coverage * 6.0) - rng.randi_range(0, 1), 1, 4)
	var helper: Vector3 = Vector3.RIGHT if absf(pole.x) < 0.9 else Vector3.BACK
	var east: Vector3 = pole.cross(helper).normalized()
	for i in range(count):
		var hemisphere: float = 1.0 if rng.randf() < 0.5 else -1.0
		var latitude: float = rng.randf_range(0.2, 0.6) * hemisphere
		var around: Vector3 = east.rotated(pole, rng.randf() * TAU)
		var centre: Vector3 = (around * sqrt(1.0 - latitude * latitude) + pole * latitude).normalized()
		var spin: float = rng.randf_range(4.0, 7.0) * hemisphere
		cyclones[i] = Vector4(centre.x, centre.y, centre.z, spin)

	return cyclones


## Places a giant's oval storm: size, latitude, brightness and strength come
## rolled in `storm` (strength 0 = no storm); only its longitude is rolled here.
static func _roll_storm(terrain_seed: int, pole: Vector3, storm: Dictionary) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(terrain_seed ^ NOISE_SALT ^ PALETTE_SALT)

	var helper: Vector3 = Vector3.RIGHT if absf(pole.x) < 0.9 else Vector3.BACK
	var east: Vector3 = pole.cross(helper).normalized()
	east = east.rotated(pole, rng.randf() * TAU)
	var latitude: float = clampf(storm["latitude"], -0.95, 0.95)
	var center: Vector3 = (east * sqrt(1.0 - latitude * latitude) + pole * latitude).normalized()

	return {
		"center": center,
		"east": pole.cross(center).normalized(),
		"north": pole,
		# The bake divides by the width, so it never reaches 0.
		"width": maxf(storm["width"], 0.05),
		"bright": storm["bright"],
		"strength": storm["strength"],
	}


## Height below which `coverage` of the sphere's area lies, from the bake's
## solid-angle-weighted histogram.
static func _level_at_coverage(histogram: PackedInt64Array, coverage: float) -> float:
	var total := 0.0
	for count in histogram:
		total += count

	var target: float = total * coverage
	var running := 0.0
	for bin in range(histogram.size()):
		running += histogram[bin]
		if running >= target:
			return (float(bin) + 1.0) / histogram.size()

	return 1.0


## Uploads a bake as a 6-layer, mipmapped texture array for the shader.
static func make_texture(data: Dictionary) -> Texture2DArray:
	var texture := Texture2DArray.new()
	texture.create_from_images(data["images"])
	return texture


## Which face a direction falls on, and its (u, v) there in -1..1. Mirror of
## face_uv() in planet_terrain.gdshader.
static func face_uv(dir: Vector3) -> Vector3:
	var a: Vector3 = dir.abs()
	var face: int
	if a.x >= a.y and a.x >= a.z:
		face = 0 if dir.x > 0.0 else 1
	elif a.y >= a.z:
		face = 2 if dir.y > 0.0 else 3
	else:
		face = 4 if dir.z > 0.0 else 5

	var forward: float = dir.dot(FACE_FORWARD[face])
	return Vector3(
		dir.dot(FACE_RIGHT[face]) / forward, dir.dot(FACE_UP[face]) / forward, float(face)
	)


## Height 0..1 under a planet-space direction, bilinear like the GPU sampler,
## so gameplay (landing, spawning on land or sea) agrees with the picture.
static func height_at(data: Dictionary, dir: Vector3) -> float:
	if data.is_empty():
		return 0.0

	var n: int = data["size"]
	var uv: Vector3 = face_uv(dir.normalized())
	var heights: PackedFloat32Array = data["faces"][int(uv.z)]

	var fx: float = clampf((uv.x * 0.5 + 0.5) * float(n - 1), 0.0, float(n - 1))
	var fy: float = clampf((uv.y * 0.5 + 0.5) * float(n - 1), 0.0, float(n - 1))
	var x0: int = mini(int(fx), n - 2)
	var y0: int = mini(int(fy), n - 2)
	var tx: float = fx - float(x0)
	var ty: float = fy - float(y0)

	var top: float = lerpf(heights[y0 * n + x0], heights[y0 * n + x0 + 1], tx)
	var bottom: float = lerpf(heights[(y0 + 1) * n + x0], heights[(y0 + 1) * n + x0 + 1], tx)
	return lerpf(top, bottom, ty)

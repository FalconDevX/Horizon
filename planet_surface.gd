class_name PlanetSurface
extends RefCounted

## Canonical definition of a planet's surface.
##
## A surface is a list of "blobs". Each blob is a direction on the unit sphere
## plus an index into a palette. The colour at any direction is the colour of
## the NEAREST blob - a spherical Voronoi lookup. Nothing stores the shapes of
## the regions; they are implied by the nearest-blob rule.
##
## The same lookup runs per pixel on the GPU in planet_surface.gdshader, so the
## CPU and the shader always agree about what is where. Keep blob_at() and the
## loop in the shader in sync.

const MAX_BLOBS := 256
const MAX_COLORS := 8
const WARP_OCTAVES := 3

## How a planet lays its colours out. Every style produces the same thing - a
## list of directions with colour indices - so the shader, the warp and the
## gameplay lookup never learn which one a planet used.
enum Style {
	AUTO,
	## Colours sprinkled over evenly spread points. Mottled and speckled.
	SCATTERED,
	## Colours seeded and grown into solid landmasses.
	CONTINENTS,
	## Points laid along meridians that bend as they run pole to pole, so
	## colours come out as curved segments like the peel of an orange.
	BANDS,
}

## Odds per style, in Style order from SCATTERED.
const STYLE_ODDS: Array[float] = [0.30, 0.54, 0.16]

## What a palette slot is made of. The values double as layer indices into the
## material texture array, so the order here is the layer order there. Named
## Terrain rather than Material because Material is already a Godot class.
enum Terrain {
	OCEAN,
	SAND,
	MOUNTAINS,
}

## Side length of each generated material texture, in texels.
const MATERIAL_TEXTURE_SIZE := 256

## Generated once and shared by every planet; see default_material_textures().
static var _material_textures: Texture2DArray = null

## Golden angle (137.5 degrees) as a fraction of a turn. Spacing hues by it
## keeps any number of them maximally far apart without a lookup table.
const GOLDEN_FRACTION := 0.381966

## Angle between successive points of a Fibonacci sphere, in radians.
## Literal rather than PI * (3.0 - sqrt(5.0)), because a const initialiser has
## to fold at parse time.
const GOLDEN_ANGLE := 2.399963229728653

## How far points are nudged off the Fibonacci lattice, as a fraction of the
## mean cell radius. Enough to hide the spiral, not enough to cause clumping.
const POINT_JITTER := 0.45

## Neighbours each cell is linked to when growing regions. A Voronoi cell on a
## sphere has about six edges, and because the points are evenly spread the six
## nearest points are its actual neighbours - which is only true for an even
## spread, and is why nearest-neighbour adjacency is good enough here.
const NEIGHBOR_COUNT := 6

## Roughly how many cells one landmass gets before a colour is given another
## separate one. Lower means more, smaller islands.
const CELLS_PER_SEED := 12

const MAX_SEEDS := 6

## Band style. Meridians are kept few enough to read as segments, and the
## wobble is how far one drifts in longitude as it runs from pole to pole.
const MIN_BANDS := 6
const MAX_BANDS := 24
const BAND_JITTER := 0.12
const BAND_WOBBLE_MIN := 0.12
const BAND_WOBBLE_MAX := 0.42

const STYLE_SALT := 0xC2B2AE35

## Odds of each colour count, starting at 3. More colours is rarer, which is
## what the rarity tier will read from.
const COLOR_COUNT_ODDS: Array[float] = [0.54, 0.26, 0.12, 0.05, 0.02, 0.01]

## Separate RNG streams, so changing the palette does not reshuffle the points.
const PALETTE_SALT := 0x9E3779B9
const COUNT_SALT := 0x85EBCA6B
const TERRAIN_SALT := 0x27D4EB2F
const ELEVATION_SALT := 0x165667B1

## Upper bound on each component of the elevation offset. Kept small because
## the shader's hash loses precision as its input grows.
const ELEVATION_OFFSET_RANGE := 64.0

# The 60/30/10 split. Every colour past the third takes another ACCENT_SHARE,
# drawn from the dominant and secondary in a 2:1 ratio.
const DOMINANT_SHARE := 0.60
const SECONDARY_SHARE := 0.30
const ACCENT_SHARE := 0.10


static func roll_style(surface_seed: int) -> Style:
	var rng := RandomNumberGenerator.new()
	rng.seed = surface_seed ^ STYLE_SALT
	var roll: float = rng.randf()
	var cumulative := 0.0

	for i in range(STYLE_ODDS.size()):
		cumulative += STYLE_ODDS[i]
		if roll < cumulative:
			return (Style.SCATTERED + i) as Style

	return Style.CONTINENTS


## What each palette slot is made of, indexed by slot like the palette itself.
##
## Two coin flips per planet: whether ocean takes the 60% or the 30%, and
## whether the main land is sand or mountains. The main land takes whichever of
## those two slots ocean did not, and every 10% slot gets the opposite land
## type, so a planet always has one ocean, one main land and one contrast.
##
##   ocean world:  60% OCEAN      30% main land   10%+ opposite land
##   land world:   60% main land  30% OCEAN       10%+ opposite land
static func roll_slot_terrain(surface_seed: int, color_count: int) -> PackedInt32Array:
	var count: int = clampi(color_count, 1, MAX_COLORS)
	var rng := RandomNumberGenerator.new()
	rng.seed = surface_seed ^ TERRAIN_SALT

	var ocean_dominant: bool = rng.randf() < 0.5
	var main_land: int = Terrain.SAND if rng.randf() < 0.5 else Terrain.MOUNTAINS
	var opposite_land: int = (
		Terrain.MOUNTAINS if main_land == Terrain.SAND else Terrain.SAND
	)

	var terrain := PackedInt32Array()
	terrain.append(Terrain.OCEAN if ocean_dominant else main_land)

	if count >= 2:
		terrain.append(main_land if ocean_dominant else Terrain.OCEAN)

	for _i in range(count - 2):
		terrain.append(opposite_land)

	return terrain


## The dark and light ends of a slot's colour ramp. The palette colour itself is
## the middle stop, so everything the palette generator already does - hue
## choice, the three brightness bands - still decides what the planet looks
## like; the texture only decides where along the ramp each pixel sits.
##
## Each material shapes its ramp differently: oceans go deep, sand stays in a
## narrow band so it reads as fine grain, and mountains run up to near-white
## so ridges read as peaks.
static func ramp_ends(base: Color, material: int) -> Array[Color]:
	var hue: float = base.h
	var saturation: float = base.s
	var value: float = base.v

	var ends: Array[Color] = []

	match material:
		Terrain.OCEAN:
			ends.append(Color.from_hsv(hue, minf(1.0, saturation * 1.15), value * 0.35))
			ends.append(Color.from_hsv(hue, saturation * 0.8, lerpf(value, 1.0, 0.35)))
		Terrain.SAND:
			ends.append(Color.from_hsv(hue, saturation, value * 0.7))
			ends.append(Color.from_hsv(hue, saturation * 0.7, lerpf(value, 1.0, 0.4)))
		_:
			ends.append(Color.from_hsv(hue, minf(1.0, saturation * 1.1), value * 0.3))
			ends.append(Color.from_hsv(hue, saturation * 0.25, lerpf(value, 1.0, 0.75)))

	return ends


## The shared grayscale material textures, one layer per Terrain in enum
## order. Generated from noise on first use and cached, so every planet reads
## the same three layers and only their colour ramps differ. A hand-made
## Texture2DArray can replace this any time, as long as its layers follow the
## same order.
static func default_material_textures() -> Texture2DArray:
	if _material_textures != null:
		return _material_textures

	var images: Array[Image] = [
		_material_image(_ocean_noise()),
		_material_image(_sand_noise()),
		_material_image(_mountain_noise()),
	]

	var textures := Texture2DArray.new()
	if textures.create_from_images(images) != OK:
		push_error("PlanetSurface: could not build the material texture array")
		return null

	_material_textures = textures
	return textures


static func _material_image(noise: FastNoiseLite) -> Image:
	# Seamless, because the shader repeats the texture across the planet and a
	# visible seam would show on every tile.
	var image: Image = noise.get_seamless_image(MATERIAL_TEXTURE_SIZE, MATERIAL_TEXTURE_SIZE)
	image.convert(Image.FORMAT_L8)
	image.generate_mipmaps()
	return image


static func _ocean_noise() -> FastNoiseLite:
	# Broad, soft swells with the domain warped so they curl like currents.
	var noise := FastNoiseLite.new()
	noise.seed = 101
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = 0.012
	noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	noise.fractal_octaves = 4
	noise.domain_warp_enabled = true
	noise.domain_warp_amplitude = 30.0
	return noise


static func _sand_noise() -> FastNoiseLite:
	# Short, fine ripples with little large-scale variation - grain, not relief.
	var noise := FastNoiseLite.new()
	noise.seed = 202
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	noise.frequency = 0.05
	noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	noise.fractal_octaves = 2
	return noise


static func _mountain_noise() -> FastNoiseLite:
	# Ridged fractal folds each octave into sharp creases, which is what reads
	# as ridgelines and valleys rather than soft hills.
	var noise := FastNoiseLite.new()
	noise.seed = 303
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	noise.frequency = 0.02
	noise.fractal_type = FastNoiseLite.FRACTAL_RIDGED
	noise.fractal_octaves = 5
	noise.fractal_lacunarity = 2.1
	return noise


## The seed a planet actually generates from: the world seed mixed with the
## planet's own. The golden-ratio multiply spreads neighbouring planet seeds
## (1001, 1002, ...) far apart before they meet the world seed.
static func planet_seed(world_seed: int, local_seed: int) -> int:
	var rng := RandomNumberGenerator.new()
	rng.seed = world_seed ^ (local_seed * 0x9E3779B1)
	return rng.randi()


## Where in the noise field this planet's height is read from. Shifting the
## sample point is what gives each planet its own relief from one shader.
static func elevation_offset(surface_seed: int) -> Vector3:
	var rng := RandomNumberGenerator.new()
	rng.seed = surface_seed ^ ELEVATION_SALT

	return Vector3(
		rng.randf_range(0.0, ELEVATION_OFFSET_RANGE),
		rng.randf_range(0.0, ELEVATION_OFFSET_RANGE),
		rng.randf_range(0.0, ELEVATION_OFFSET_RANGE)
	)


static func roll_color_count(surface_seed: int) -> int:
	var rng := RandomNumberGenerator.new()
	rng.seed = surface_seed ^ COUNT_SALT
	var roll: float = rng.randf()
	var cumulative := 0.0

	for i in range(COLOR_COUNT_ODDS.size()):
		cumulative += COLOR_COUNT_ODDS[i]
		if roll < cumulative:
			return mini(3 + i, MAX_COLORS)

	return 3


## Area each colour should cover, as fractions summing to 1.
static func color_weights(color_count: int) -> PackedFloat64Array:
	var count: int = clampi(color_count, 1, MAX_COLORS)
	var weights := PackedFloat64Array()

	if count == 1:
		weights.append(1.0)
		return weights

	if count == 2:
		weights.append(DOMINANT_SHARE / (DOMINANT_SHARE + SECONDARY_SHARE))
		weights.append(SECONDARY_SHARE / (DOMINANT_SHARE + SECONDARY_SHARE))
		return weights

	# Each extra colour costs ACCENT_SHARE, taken 2:1 from dominant and
	# secondary: a 4th colour pulls 6.67 points off the 60 and 3.33 off the 30.
	var extras: float = float(count - 3)
	weights.append(maxf(ACCENT_SHARE, DOMINANT_SHARE - extras * ACCENT_SHARE * (2.0 / 3.0)))
	weights.append(maxf(ACCENT_SHARE, SECONDARY_SHARE - extras * ACCENT_SHARE * (1.0 / 3.0)))

	for _i in range(count - 2):
		weights.append(ACCENT_SHARE)

	# Renormalise in case the clamps above kicked in at extreme colour counts.
	var total := 0.0
	for weight in weights:
		total += weight

	for i in range(weights.size()):
		weights[i] /= total

	return weights


static func generate_palette(surface_seed: int, color_count: int) -> PackedColorArray:
	var count: int = clampi(color_count, 1, MAX_COLORS)
	var rng := RandomNumberGenerator.new()
	rng.seed = surface_seed ^ PALETTE_SALT
	var palette := PackedColorArray()
	var base_hue: float = rng.randf()

	# Three value bands, so the roles separate by brightness and not just hue.
	# A palette that only varies hue reads as mush at a glance.

	# Dominant: muted and dark. It is the backdrop, so it must not shout.
	palette.append(
		Color.from_hsv(base_hue, rng.randf_range(0.28, 0.48), rng.randf_range(0.30, 0.44))
	)

	if count == 1:
		return palette

	# Secondary: analogous hue so it feels related to the dominant, but a clear
	# step up in both saturation and brightness.
	var direction: float = 1.0 if rng.randf() < 0.5 else -1.0
	var shift: float = rng.randf_range(0.07, 0.19) * direction
	palette.append(
		Color.from_hsv(
			fposmod(base_hue + shift, 1.0),
			rng.randf_range(0.42, 0.62),
			rng.randf_range(0.54, 0.68)
		)
	)

	if count == 2:
		return palette

	# Accents: hues flung away by the golden angle, saturated and bright so the
	# 10% slices actually register against the dominant.
	for i in range(2, count):
		var hue: float = fposmod(
			base_hue + GOLDEN_FRACTION * float(i - 1) + rng.randf_range(-0.03, 0.03),
			1.0
		)
		palette.append(
			Color.from_hsv(hue, rng.randf_range(0.62, 0.88), rng.randf_range(0.78, 0.94))
		)

	return palette


static func generate_blobs(
	surface_seed: int,
	blob_count: int,
	color_count: int,
	style: Style = Style.AUTO
) -> PackedVector4Array:
	var count: int = clampi(blob_count, 0, MAX_BLOBS)
	var colors: int = clampi(color_count, 1, MAX_COLORS)
	var rng := RandomNumberGenerator.new()
	rng.seed = surface_seed
	var blobs := PackedVector4Array()

	if count == 0:
		return blobs

	if style == Style.AUTO:
		style = roll_style(surface_seed)

	var weights: PackedFloat64Array = color_weights(colors)
	var directions: PackedVector3Array
	var assignment: PackedInt32Array

	match style:
		Style.BANDS:
			# Points come out ordered band by band, so colouring whole bands is
			# just a matter of reading off the band each point belongs to.
			var layout: Vector2i = choose_band_layout(count, weights)
			directions = distribute_bands(rng, layout.x, layout.y)
			assignment = band_colors(weights, layout.x, layout.y)
		Style.SCATTERED:
			directions = distribute_points(rng, count)
			assignment = scatter_colors(weights, count, rng)
		_:
			directions = distribute_points(rng, count)
			assignment = grow_colors(
				weights, count, rng, build_adjacency(directions)
			)

	for i in range(directions.size()):
		var direction: Vector3 = directions[i]
		blobs.append(
			Vector4(direction.x, direction.y, direction.z, float(assignment[i]))
		)

	return blobs


## How many meridian bands to use, and how many points up each one.
##
## Because a whole band takes one colour, the band count decides how finely the
## 60/30/10 split can be expressed: 12 bands cannot spell 60/30/10, but 10 can
## exactly (6/3/1). So rather than picking a band count from the point count
## alone, try every workable count and keep whichever spells the weights best.
## Rows are held at four or more, or the meridians have too few points to curve.
static func choose_band_layout(count: int, weights: PackedFloat64Array) -> Vector2i:
	var ceiling: int = clampi(count / 4, MIN_BANDS, MAX_BANDS)
	var best_bands: int = MIN_BANDS
	var best_error := INF

	for bands in range(MIN_BANDS, ceiling + 1):
		var quota: PackedInt32Array = apportion(weights, bands)
		var error := 0.0

		for i in range(weights.size()):
			error = maxf(error, absf(float(quota[i]) / float(bands) - weights[i]))

		if error < best_error - 1e-9:
			best_error = error
			best_bands = bands

	return Vector2i(best_bands, maxi(2, count / best_bands))


## Points laid along meridians that bend as they run from pole to pole. Equal
## steps in z rather than in latitude, because a sphere's area depends only on
## height, so the rows stay equal-area instead of crowding at the poles.
static func distribute_bands(
	rng: RandomNumberGenerator,
	bands: int,
	rows: int
) -> PackedVector3Array:
	var points := PackedVector3Array()

	if bands <= 0 or rows <= 0:
		return points

	while bands * rows > MAX_BLOBS and rows > 2:
		rows -= 1

	var spin := Quaternion(random_unit_vector(rng), rng.randf_range(0.0, TAU))
	var wobble: float = rng.randf_range(BAND_WOBBLE_MIN, BAND_WOBBLE_MAX)
	var wobble_rate: float = rng.randf_range(1.5, 3.5)
	var phase: float = rng.randf_range(0.0, TAU)
	var spacing: float = TAU / float(bands)

	for band in range(bands):
		var base_longitude: float = spacing * float(band)

		for row in range(rows):
			var z: float = 1.0 - 2.0 * (float(row) + 0.5) / float(rows)
			var ring: float = sqrt(maxf(0.0, 1.0 - z * z))

			# The bend. Longitude drifts with height, so a meridian that starts
			# at one pole arrives at the other having curved on the way.
			var longitude: float = (
				base_longitude + wobble * sin(z * wobble_rate * PI + phase)
			)

			var point := Vector3(ring * cos(longitude), ring * sin(longitude), z)
			point = (
				point + random_unit_vector(rng) * spacing * BAND_JITTER
			).normalized()
			points.append(spin * point)

	return points


## The order colours appear in as you go round the sphere.
##
## Handing each colour one unbroken run would spend 60% of the planet on a
## single arc, leaving one hemisphere flatly dominant and only the smallest
## colour reading as a stripe. Instead every colour is spread around the ring:
## each one's slots are placed at even fractions of a turn, and merging those
## sequences interleaves them. With 6/3/1 the order comes out A B A A B C A A B A,
## so the dominant is the widest and most frequent stripe rather than a
## hemisphere, and every colour curves pole to pole.
static func interleave_bands(quota: PackedInt32Array) -> PackedInt32Array:
	var keyed: Array = []

	for color in range(quota.size()):
		var slots: int = quota[color]

		for j in range(slots):
			keyed.append([(float(j) + 0.5) / float(slots), color])

	keyed.sort_custom(func(a, b): return a[0] < b[0])

	var order := PackedInt32Array()
	for entry in keyed:
		order.append(entry[1])

	return order


## One colour per band, interleaved around the sphere, applied to every point
## in that band. Whole bands rather than exact cell counts is what keeps the
## stripes unbroken; choose_band_layout picks a count that keeps the resulting
## area split honest.
static func band_colors(
	weights: PackedFloat64Array,
	bands: int,
	rows: int
) -> PackedInt32Array:
	var order: PackedInt32Array = interleave_bands(apportion(weights, bands))
	var assignment := PackedInt32Array()

	for band in range(bands):
		var color: int = order[band] if band < order.size() else 0

		for _row in range(rows):
			assignment.append(color)

	return assignment


## Colours sprinkled at random over the points. Hits the area targets but only
## the dominant holds together; everything else breaks into specks. Kept as a
## style in its own right, for mottled and barren-looking worlds.
static func scatter_colors(
	weights: PackedFloat64Array,
	total: int,
	rng: RandomNumberGenerator
) -> PackedInt32Array:
	var quota: PackedInt32Array = apportion(weights, total)
	var pool := PackedInt32Array()

	for color in range(quota.size()):
		for _i in range(quota[color]):
			pool.append(color)

	shuffle(pool, rng)
	return pool


## Evenly spread points, jittered. Purely random points clump, which makes cell
## areas wildly uneven and pulls the finished colour split away from its target.
## A Fibonacci spiral spaces them almost perfectly; the jitter puts the disorder
## back without reintroducing the clumping. Measured worst-case error against a
## 60/30/10 target drops from about 7 points to under 3.
static func distribute_points(
	rng: RandomNumberGenerator,
	count: int
) -> PackedVector3Array:
	var points := PackedVector3Array()

	if count <= 0:
		return points

	var spacing: float = mean_cell_radius(count)

	# Rotate the whole set, so no two planets share the spiral's pole artefacts.
	var spin := Quaternion(random_unit_vector(rng), rng.randf_range(0.0, TAU))

	for i in range(count):
		var z: float = 1.0 - 2.0 * (float(i) + 0.5) / float(count)
		var ring: float = sqrt(maxf(0.0, 1.0 - z * z))
		var theta: float = GOLDEN_ANGLE * float(i)
		var point := Vector3(ring * cos(theta), ring * sin(theta), z)

		# Normalising afterwards discards the radial part of the nudge, so this
		# slides the point across the surface rather than off it.
		point = (point + random_unit_vector(rng) * spacing * POINT_JITTER).normalized()
		points.append(spin * point)

	return points


## Which cells border which. Each cell is linked to its NEIGHBOR_COUNT nearest
## points, selected directly rather than by sorting the whole list, so this
## stays O(cells * neighbours) instead of O(cells * log cells).
static func build_adjacency(points: PackedVector3Array) -> Array:
	var count: int = points.size()
	var adjacency: Array = []

	for i in range(count):
		var best_dot := PackedFloat64Array()
		var best_index := PackedInt32Array()

		for j in range(count):
			if j == i:
				continue

			var towards: float = points[i].dot(points[j])
			var slot: int = best_dot.size()

			while slot > 0 and best_dot[slot - 1] < towards:
				slot -= 1

			if slot >= NEIGHBOR_COUNT:
				continue

			best_dot.insert(slot, towards)
			best_index.insert(slot, j)

			if best_dot.size() > NEIGHBOR_COUNT:
				best_dot.resize(NEIGHBOR_COUNT)
				best_index.resize(NEIGHBOR_COUNT)

		adjacency.append(best_index)

	return adjacency


## Split `total` cells between colours in proportion to `weights`, exactly.
## Largest-remainder apportionment: floor everything, then hand the leftover
## slots to whoever was rounded down hardest.
static func apportion(weights: PackedFloat64Array, total: int) -> PackedInt32Array:
	var counts := PackedInt32Array()
	var remainders: Array = []
	var assigned := 0

	for i in range(weights.size()):
		var exact: float = weights[i] * float(total)
		var whole: int = int(floor(exact))
		counts.append(whole)
		assigned += whole
		remainders.append([exact - float(whole), i])

	remainders.sort_custom(func(a, b): return a[0] > b[0])

	var step := 0
	while assigned < total and remainders.size() > 0:
		counts[remainders[step % remainders.size()][1]] += 1
		assigned += 1
		step += 1

	return counts


## Hand out colour indices so each colour's share of cells matches its target
## weight AND lands in a few connected masses rather than scattered specks.
##
## Scattering colours at random does hit the area targets, but only the 60%
## dominant survives it: at 30% and 10% a colour breaks into eight or so
## disconnected cells and reads as confetti instead of terrain. So instead each
## colour is seeded in a handful of places and grown outward through the
## adjacency graph until its quota is spent. Cell counts are unchanged, so the
## 60/30/10 split is untouched - only where they sit changes.
static func grow_colors(
	weights: PackedFloat64Array,
	total: int,
	rng: RandomNumberGenerator,
	adjacency: Array
) -> PackedInt32Array:
	var quota: PackedInt32Array = apportion(weights, total)
	var color_count: int = quota.size()
	var assignment := PackedInt32Array()
	assignment.resize(total)
	assignment.fill(-1)

	var remaining := PackedInt32Array()
	for value in quota:
		remaining.append(value)

	var order := PackedInt32Array()
	for i in range(total):
		order.append(i)
	shuffle(order, rng)

	# Drop seeds first, so every colour has somewhere to grow from. Bigger
	# colours get more starting points and so more separate landmasses.
	var frontier: Array = []
	var cursor := 0

	for color in range(color_count):
		frontier.append([])
		var seeds: int = clampi(
			roundi(float(quota[color]) / float(CELLS_PER_SEED)), 1, MAX_SEEDS
		)

		for _seed in range(seeds):
			if cursor >= order.size() or remaining[color] <= 0:
				break

			var cell: int = order[cursor]
			cursor += 1
			assignment[cell] = color
			remaining[color] -= 1
			frontier[color].append(cell)

	# Grow every colour a cell at a time, round robin, so none of them races
	# ahead and walls the others in. Picking a random frontier cell rather than
	# the oldest keeps the shapes ragged instead of circular.
	var growing := true

	while growing:
		growing = false

		for color in range(color_count):
			if remaining[color] <= 0 or frontier[color].is_empty():
				continue

			growing = true
			var pick: int = rng.randi_range(0, frontier[color].size() - 1)
			var cell: int = frontier[color][pick]
			var options := PackedInt32Array()

			for neighbor in adjacency[cell]:
				if assignment[neighbor] == -1:
					options.append(neighbor)

			if options.is_empty():
				# Hemmed in on all sides; stop growing from here.
				frontier[color].remove_at(pick)
				continue

			var chosen: int = options[rng.randi_range(0, options.size() - 1)]
			assignment[chosen] = color
			remaining[color] -= 1
			frontier[color].append(chosen)

	# Anything a colour could not reach goes to whichever still-short colour
	# already owns the most of its neighbours, so stragglers join a coastline
	# rather than becoming a speck. Totals match, so this always terminates.
	for cell in range(total):
		if assignment[cell] != -1:
			continue

		var best_color := -1
		var best_score := -1

		for color in range(color_count):
			if remaining[color] <= 0:
				continue

			var score := 0
			for neighbor in adjacency[cell]:
				if assignment[neighbor] == color:
					score += 1

			if best_color == -1 or score > best_score:
				best_score = score
				best_color = color
			elif score == best_score and remaining[color] > remaining[best_color]:
				best_color = color

		if best_color == -1:
			best_color = 0

		assignment[cell] = best_color
		remaining[best_color] -= 1

	return assignment


static func shuffle(values: PackedInt32Array, rng: RandomNumberGenerator) -> void:
	for i in range(values.size() - 1, 0, -1):
		var j: int = rng.randi_range(0, i)
		var swap: int = values[i]
		values[i] = values[j]
		values[j] = swap


static func random_unit_vector(rng: RandomNumberGenerator) -> Vector3:
	# Uniform over the sphere. Rolling a latitude directly would bunch points
	# at the poles, because lines of latitude get shorter as you go north.
	# Rolling z uniformly and deriving the ring radius from it does not.
	var z: float = rng.randf_range(-1.0, 1.0)
	var phi: float = rng.randf_range(0.0, TAU)
	var ring: float = sqrt(maxf(0.0, 1.0 - z * z))

	return Vector3(ring * cos(phi), ring * sin(phi), z)


static func surface_warp(p: Vector3, base_frequency: float) -> Vector3:
	# Must stay identical to surface_warp() in planet_surface.gdshader.
	#
	# Built from sines rather than a hash on purpose. A hash is chaotic, so the
	# shader's 32-bit floats and GDScript's 64-bit floats would diverge into
	# completely different fields and this lookup would stop matching what is
	# drawn. Sines are smooth, so the two agree to far below a pixel.
	var sum := Vector3.ZERO
	var amplitude := 1.0
	var frequency: float = base_frequency

	for _i in range(WARP_OCTAVES):
		sum += amplitude * Vector3(
			sin(p.y * frequency + 1.7) * cos(p.z * frequency * 1.31 + 0.3),
			sin(p.z * frequency + 3.1) * cos(p.x * frequency * 1.27 + 1.9),
			sin(p.x * frequency + 5.3) * cos(p.y * frequency * 1.19 + 4.1)
		)
		amplitude *= 0.5
		frequency *= 2.17

	return sum


static func warped_direction(
	direction: Vector3,
	warp_strength: float,
	warp_frequency: float
) -> Vector3:
	if warp_strength <= 0.0:
		return direction

	return (
		direction + surface_warp(direction, warp_frequency) * warp_strength
	).normalized()


static func blob_at(
	blobs: PackedVector4Array,
	direction: Vector3,
	warp_strength: float = 0.0,
	warp_frequency: float = 3.0
) -> int:
	# Mirror of the loop in planet_surface.gdshader. This is the gameplay-side
	# query: "which blob is the ship standing on". Returns -1 if there are none.
	# Pass the body's warp settings or the answer will disagree with the pixels.
	var warped: Vector3 = warped_direction(direction, warp_strength, warp_frequency)
	var best := -1
	var best_dot := -2.0

	for i in range(blobs.size()):
		var blob: Vector4 = blobs[i]
		var towards: float = warped.dot(Vector3(blob.x, blob.y, blob.z))

		if towards > best_dot:
			best_dot = towards
			best = i

	return best


static func color_index_at(
	blobs: PackedVector4Array,
	direction: Vector3,
	warp_strength: float = 0.0,
	warp_frequency: float = 3.0
) -> int:
	var index: int = blob_at(blobs, direction, warp_strength, warp_frequency)

	if index < 0:
		return -1

	return int(blobs[index].w)


## Mean angular radius of one cell. Each covers 4*PI/count of the sphere, so a
## cell behaves like a cap of about this size.
static func mean_cell_radius(blob_count: int) -> float:
	return 2.0 / sqrt(float(maxi(blob_count, 1)))


## Every blob painted in a given colour. This is the whole "where is green"
## question - it is a filter over an array you already have, not a search.
static func blobs_with_color(
	blobs: PackedVector4Array,
	color_index: int
) -> PackedInt32Array:
	var found := PackedInt32Array()

	for i in range(blobs.size()):
		if int(blobs[i].w) == color_index:
			found.append(i)

	return found


## A direction drawn uniformly from the cap of half-angle `max_angle` around
## `axis`. Uniform in cosine rather than in angle, or results would bunch up
## towards the axis - the same reason latitudes bunch at the poles.
static func random_in_cone(
	axis: Vector3,
	max_angle: float,
	rng: RandomNumberGenerator
) -> Vector3:
	var cos_max: float = cos(max_angle)
	var cos_theta: float = 1.0 - rng.randf() * (1.0 - cos_max)
	var sin_theta: float = sqrt(maxf(0.0, 1.0 - cos_theta * cos_theta))
	var phi: float = rng.randf_range(0.0, TAU)

	# Any vector not parallel to the axis will do to start the basis off.
	var helper := Vector3.UP if absf(axis.y) < 0.9 else Vector3.RIGHT
	var tangent: Vector3 = axis.cross(helper).normalized()
	var bitangent: Vector3 = axis.cross(tangent)

	return (
		axis * cos_theta
		+ tangent * (sin_theta * cos(phi))
		+ bitangent * (sin_theta * sin(phi))
	).normalized()


## A random surface direction that lands on `color_index`, or Vector3.ZERO if
## none could be found.
##
## Rather than guessing at the whole planet and throwing away misses - which
## costs about ten tries for a 10% colour - this picks a blob already wearing
## the colour and samples inside it, landing on target better than four times
## in five. The check is still needed because warping moves boundaries and a
## sample can stray into a neighbour.
static func sample_in_color(
	blobs: PackedVector4Array,
	color_index: int,
	rng: RandomNumberGenerator,
	warp_strength: float = 0.0,
	warp_frequency: float = 3.0,
	attempts: int = 24
) -> Vector3:
	var candidates: PackedInt32Array = blobs_with_color(blobs, color_index)

	if candidates.is_empty():
		return Vector3.ZERO

	var spread: float = mean_cell_radius(blobs.size())

	for _attempt in range(attempts):
		var blob: Vector4 = blobs[candidates[rng.randi_range(0, candidates.size() - 1)]]
		var center := Vector3(blob.x, blob.y, blob.z)
		var candidate: Vector3 = random_in_cone(center, spread, rng)

		if color_index_at(blobs, candidate, warp_strength, warp_frequency) == color_index:
			return candidate

	return Vector3.ZERO

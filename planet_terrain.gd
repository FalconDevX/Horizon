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

enum Kind { NONE, TERRAN, DESERT, VOLCANIC, ICE, BARREN, TOXIC, GAS_GIANT, ICE_GIANT }

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

const BAKE_SHADER: RDShaderFile = preload("res://planet_terrain_bake.glsl")

## Weighted-histogram resolution used to place sea level at a coverage.
const HISTOGRAM_BINS := 1024

const PALETTE_SALT := 0x3C6EF372
const NOISE_SALT := 0x1B873593

## How far one seed may drift a kind's look, so two deserts are not twins.
const HUE_JITTER := 0.03
const SATURATION_JITTER := 0.12
const VALUE_JITTER := 0.07
const COVERAGE_JITTER := 0.06
const FREQUENCY_JITTER := 0.15

## Finished bakes, keyed by everything that shapes them. Main-thread only:
## looked up before a bake is started, filled when one lands. Survives scene
## reloads, so going back to the menu and in again does not bake twice.
static var _cache: Dictionary = {}

## One GPU bake at a time: each opens its own local RenderingDevice.
static var _gpu_mutex := Mutex.new()


## The authored look of one kind. Colours are sRGB; `land` is a height
## gradient, one colour per entry of `stops` (0 = shoreline or lowest ground,
## 1 = the highest peak). `dry` is the arid-biome tint laid over the lowlands
## where a moisture noise says so (`dry_amount` = how much); `strata` bands the
## rock on cliffs. Everything here is jittered per seed by resolve().
static func preset(kind: Kind) -> Dictionary:
	match kind:
		Kind.TERRAN:
			return {
				"liquid": true, "coverage": 0.60,
				"shallow": Color(0.16, 0.55, 0.62), "deep": Color(0.02, 0.07, 0.24),
				"emission": 0.0, "gloss": 0.85,
				"land": [
					Color(0.80, 0.74, 0.52), Color(0.32, 0.55, 0.21), Color(0.12, 0.33, 0.13),
					Color(0.42, 0.36, 0.24), Color(0.50, 0.48, 0.46), Color(0.95, 0.96, 0.98),
				],
				"stops": [0.0, 0.04, 0.25, 0.55, 0.74, 0.88],
				"rock": Color(0.38, 0.34, 0.30), "slope_rock": 0.5,
				"dry": Color(0.62, 0.55, 0.36), "dry_amount": 0.75, "strata": 0.0,
				"cap": Color(0.93, 0.96, 1.0), "cap_latitude": 0.80,
				"atmo": Color(0.40, 0.65, 1.0), "atmo_strength": 0.9, "haze": 0.03,
				"clouds": 0.40, "cloud_color": Color(1, 1, 1),
				"relief": 0.07, "bump": 3.5, "frequency": 1.4, "bands": 0,
			}
		Kind.DESERT:
			return {
				"liquid": false, "coverage": 0.0,
				"shallow": Color.BLACK, "deep": Color.BLACK, "emission": 0.0, "gloss": 0.0,
				"land": [
					Color(0.42, 0.17, 0.10), Color(0.64, 0.29, 0.14), Color(0.80, 0.45, 0.22),
					Color(0.88, 0.62, 0.38), Color(0.62, 0.40, 0.30), Color(0.90, 0.80, 0.68),
				],
				"stops": [0.0, 0.22, 0.42, 0.62, 0.82, 0.96],
				"rock": Color(0.33, 0.15, 0.10), "slope_rock": 0.5,
				"dry": Color(0.93, 0.74, 0.50), "dry_amount": 0.5, "strata": 1.0,
				"cap": Color(0.96, 0.91, 0.86), "cap_latitude": 0.90,
				"atmo": Color(0.95, 0.60, 0.40), "atmo_strength": 0.5, "haze": 0.05,
				"clouds": 0.0, "cloud_color": Color(1, 1, 1),
				"relief": 0.09, "bump": 3.0, "frequency": 1.8, "bands": 0,
			}
		Kind.VOLCANIC:
			return {
				"liquid": true, "coverage": 0.28,
				"shallow": Color(1.0, 0.58, 0.12), "deep": Color(0.85, 0.16, 0.02),
				"emission": 1.3, "gloss": 0.1,
				"land": [
					Color(0.10, 0.08, 0.08), Color(0.18, 0.13, 0.12), Color(0.28, 0.20, 0.17),
					Color(0.36, 0.28, 0.24), Color(0.22, 0.18, 0.17), Color(0.46, 0.43, 0.41),
				],
				"stops": [0.0, 0.10, 0.35, 0.60, 0.80, 0.95],
				"rock": Color(0.07, 0.06, 0.06), "slope_rock": 0.6,
				"dry": Color(0.30, 0.16, 0.12), "dry_amount": 0.45, "strata": 0.4,
				"cap": Color.WHITE, "cap_latitude": 2.0,
				"atmo": Color(1.0, 0.45, 0.20), "atmo_strength": 0.6, "haze": 0.04,
				"clouds": 0.22, "cloud_color": Color(0.35, 0.30, 0.28),
				"relief": 0.10, "bump": 3.0, "frequency": 1.6, "bands": 0,
			}
		Kind.ICE:
			return {
				"liquid": true, "coverage": 0.22,
				"shallow": Color(0.25, 0.60, 0.75), "deep": Color(0.04, 0.16, 0.32),
				"emission": 0.0, "gloss": 0.9,
				"land": [
					Color(0.62, 0.78, 0.86), Color(0.75, 0.88, 0.94), Color(0.86, 0.93, 0.97),
					Color(0.70, 0.80, 0.88), Color(0.55, 0.62, 0.72), Color(0.96, 0.98, 1.0),
				],
				"stops": [0.0, 0.15, 0.35, 0.60, 0.80, 0.95],
				"rock": Color(0.40, 0.48, 0.58), "slope_rock": 0.4,
				"dry": Color(0.80, 0.84, 0.90), "dry_amount": 0.4, "strata": 0.3,
				"cap": Color(0.97, 0.99, 1.0), "cap_latitude": 0.70,
				"atmo": Color(0.60, 0.85, 1.0), "atmo_strength": 0.7, "haze": 0.08,
				"clouds": 0.25, "cloud_color": Color(0.90, 0.95, 1.0),
				"relief": 0.06, "bump": 4.0, "frequency": 1.5, "bands": 0,
			}
		Kind.BARREN:
			return {
				"liquid": false, "coverage": 0.0,
				"shallow": Color.BLACK, "deep": Color.BLACK, "emission": 0.0, "gloss": 0.0,
				"land": [
					Color(0.20, 0.16, 0.13), Color(0.33, 0.26, 0.21), Color(0.45, 0.35, 0.28),
					Color(0.55, 0.45, 0.37), Color(0.62, 0.55, 0.48), Color(0.72, 0.66, 0.60),
				],
				"stops": [0.0, 0.20, 0.40, 0.60, 0.80, 1.0],
				"rock": Color(0.25, 0.20, 0.17), "slope_rock": 0.4,
				"dry": Color(0.50, 0.44, 0.40), "dry_amount": 0.45, "strata": 0.6,
				"cap": Color.WHITE, "cap_latitude": 2.0,
				"atmo": Color(0.5, 0.45, 0.40), "atmo_strength": 0.0, "haze": 0.0,
				"clouds": 0.0, "cloud_color": Color(1, 1, 1),
				"relief": 0.09, "bump": 3.0, "frequency": 1.7, "bands": 0,
			}
		Kind.TOXIC:
			return {
				"liquid": true, "coverage": 0.45,
				"shallow": Color(0.62, 0.78, 0.22), "deep": Color(0.20, 0.33, 0.07),
				"emission": 0.15, "gloss": 0.5,
				"land": [
					Color(0.30, 0.22, 0.36), Color(0.42, 0.30, 0.52), Color(0.52, 0.38, 0.62),
					Color(0.38, 0.28, 0.44), Color(0.60, 0.52, 0.66), Color(0.80, 0.74, 0.86),
				],
				"stops": [0.0, 0.08, 0.30, 0.55, 0.78, 0.93],
				"rock": Color(0.22, 0.16, 0.26), "slope_rock": 0.5,
				"dry": Color(0.46, 0.44, 0.24), "dry_amount": 0.6, "strata": 0.3,
				"cap": Color.WHITE, "cap_latitude": 2.0,
				"atmo": Color(0.65, 0.45, 0.95), "atmo_strength": 1.0, "haze": 0.18,
				"clouds": 0.40, "cloud_color": Color(0.72, 0.60, 0.88),
				"relief": 0.07, "bump": 3.5, "frequency": 1.5, "bands": 0,
			}
		Kind.GAS_GIANT:
			return {
				"liquid": false, "coverage": 0.0,
				"shallow": Color.BLACK, "deep": Color.BLACK, "emission": 0.0, "gloss": 0.0,
				"land": [
					Color(0.55, 0.36, 0.18), Color(0.78, 0.58, 0.32), Color(0.92, 0.80, 0.58),
					Color(0.85, 0.66, 0.40), Color(0.70, 0.45, 0.25), Color(0.96, 0.90, 0.76),
				],
				"stops": [0.0, 0.2, 0.4, 0.6, 0.8, 1.0],
				"rock": Color.BLACK, "slope_rock": 0.0,
				"dry": Color.BLACK, "dry_amount": 0.0, "strata": 0.0,
				"cap": Color.WHITE, "cap_latitude": 2.0,
				"atmo": Color(1.0, 0.85, 0.55), "atmo_strength": 0.7, "haze": 0.0,
				"clouds": 0.0, "cloud_color": Color(1, 1, 1),
				"relief": 0.0, "bump": 0.0, "frequency": 1.2, "bands": 7,
			}
		Kind.ICE_GIANT:
			return {
				"liquid": false, "coverage": 0.0,
				"shallow": Color.BLACK, "deep": Color.BLACK, "emission": 0.0, "gloss": 0.0,
				"land": [
					Color(0.10, 0.18, 0.45), Color(0.20, 0.36, 0.68), Color(0.40, 0.58, 0.85),
					Color(0.28, 0.44, 0.76), Color(0.14, 0.26, 0.58), Color(0.75, 0.85, 0.98),
				],
				"stops": [0.0, 0.2, 0.4, 0.6, 0.8, 1.0],
				"rock": Color.BLACK, "slope_rock": 0.0,
				"dry": Color.BLACK, "dry_amount": 0.0, "strata": 0.0,
				"cap": Color.WHITE, "cap_latitude": 2.0,
				"atmo": Color(0.45, 0.65, 1.0), "atmo_strength": 0.8, "haze": 0.0,
				"clouds": 0.0, "cloud_color": Color(1, 1, 1),
				"relief": 0.0, "bump": 0.0, "frequency": 1.4, "bands": 5,
			}

	return {}


static func is_gas(kind: Kind) -> bool:
	return kind == Kind.GAS_GIANT or kind == Kind.ICE_GIANT


## The preset with this seed's drift applied: every colour shifted together in
## hue (so the palette stays coherent), liquid coverage and noise scale nudged.
## `coverage_override` >= 0 pins the liquid share instead.
static func resolve(kind: Kind, terrain_seed: int, coverage_override: float = -1.0) -> Dictionary:
	var params: Dictionary = preset(kind).duplicate(true)
	if params.is_empty():
		return params

	var rng := RandomNumberGenerator.new()
	rng.seed = hash(terrain_seed ^ PALETTE_SALT)

	var hue_shift: float = rng.randf_range(-HUE_JITTER, HUE_JITTER)
	var saturation: float = 1.0 + rng.randf_range(-SATURATION_JITTER, SATURATION_JITTER)
	var value: float = 1.0 + rng.randf_range(-VALUE_JITTER, VALUE_JITTER)

	for key in ["shallow", "deep", "rock", "dry", "cap", "atmo", "cloud_color"]:
		params[key] = _drift(params[key], hue_shift, saturation, value)

	var land: Array = params["land"]
	for i in range(land.size()):
		land[i] = _drift(land[i], hue_shift, saturation, value)

	if params["liquid"]:
		params["coverage"] = clampf(
			params["coverage"] + rng.randf_range(-COVERAGE_JITTER, COVERAGE_JITTER), 0.05, 0.95
		)
	if coverage_override >= 0.0:
		params["coverage"] = clampf(coverage_override, 0.0, 0.98)
		params["liquid"] = coverage_override > 0.0

	params["frequency"] *= 1.0 + rng.randf_range(-FREQUENCY_JITTER, FREQUENCY_JITTER)
	return params


static func _drift(c: Color, hue_shift: float, saturation: float, value: float) -> Color:
	return Color.from_hsv(
		fposmod(c.h + hue_shift, 1.0),
		clampf(c.s * saturation, 0.0, 1.0),
		clampf(c.v * value, 0.0, 1.0)
	)


static func cache_key(
	kind: Kind, terrain_seed: int, resolution: int, pole: Vector3, params: Dictionary
) -> String:
	return "%d|%d|%d|%s|%.4f|%.4f" % [
		kind, terrain_seed, resolution, pole, params["coverage"], params["frequency"]
	]


static func cached(key: String) -> Dictionary:
	return _cache.get(key, {})


static func store(key: String, data: Dictionary) -> void:
	_cache[key] = data


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

	var storm: Dictionary = _roll_storm(terrain_seed, pole)
	var center: Vector3 = storm["center"]
	var east: Vector3 = storm["east"]
	var north: Vector3 = storm["north"]
	var settings := PackedFloat32Array([
		float(kind), float(n), params["frequency"], float(params["bands"]),
		pole.x, pole.y, pole.z, 0.0,
		center.x, center.y, center.z, storm["width"],
		east.x, east.y, east.z, 1.0 if storm["bright"] else 0.0,
		north.x, north.y, north.z, 0.0,
	])

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


## One oval storm for the giants, parked at a random southern-ish latitude.
static func _roll_storm(terrain_seed: int, pole: Vector3) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(terrain_seed ^ NOISE_SALT ^ PALETTE_SALT)

	var helper: Vector3 = Vector3.RIGHT if absf(pole.x) < 0.9 else Vector3.BACK
	var east: Vector3 = pole.cross(helper).normalized()
	east = east.rotated(pole, rng.randf() * TAU)
	var latitude: float = rng.randf_range(-0.45, -0.2)
	var center: Vector3 = (east * sqrt(1.0 - latitude * latitude) + pole * latitude).normalized()

	return {
		"center": center,
		"east": pole.cross(center).normalized(),
		"north": pole,
		"width": rng.randf_range(0.16, 0.26),
		"bright": rng.randf() < 0.5,
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

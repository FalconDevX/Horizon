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
	var counts: PackedByteArray = rd.buffer_get_data(stats_buffer, 16)
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



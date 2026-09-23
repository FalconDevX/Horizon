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



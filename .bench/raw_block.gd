static func _raw_height(
	kind: Kind,
	dir: Vector3,
	noises: Dictionary,
	pole: Vector3,
	bands: int,
	storm: Dictionary
) -> float:
	var continent: float = (noises["continent"] as FastNoiseLite).get_noise_3dv(dir)
	var ridge: float = (noises["ridge"] as FastNoiseLite).get_noise_3dv(dir) * 0.5 + 0.5

	if kind == Kind.GAS_GIANT or kind == Kind.ICE_GIANT:
		return _gas_height(dir, continent, ridge, pole, bands, storm)

	# Squared ridges keep valleys broad and peaks knife-edged.
	var belt: float = smoothstep(
		-0.15, 0.35, (noises["mountains"] as FastNoiseLite).get_noise_3dv(dir)
	)
	var peaks: float = ridge * ridge * (0.25 + 0.75 * belt)

	match kind:
		Kind.TERRAN, Kind.TOXIC:
			# Lowlands flattened into plains, the relief piled onto the land.
			var land: float = smoothstep(-0.05, 0.3, continent)
			return continent * (1.0 - 0.35 * land) + land * peaks * 0.75
		Kind.DESERT:
			var crater: float = _crater_at(noises, "craters", "crater_sizes", dir)
			var base: float = continent * 0.8 + smoothstep(-0.2, 0.4, continent) * peaks * 0.6
			base += crater * 0.1
			# Mesas: flat terraces with steep steps between them.
			var t: float = base * 7.0
			var stepped: float = (floorf(t) + smoothstep(0.25, 0.75, t - floorf(t))) / 7.0
			return lerpf(base, stepped, 0.55)
		Kind.VOLCANIC:
			# Cellular distance turned upside down makes cones; the dip in the
			# very middle of each is the caldera.
			var d0: float = (noises["craters"] as FastNoiseLite).get_noise_3dv(dir) + 1.0
			var cone: float = pow(maxf(1.0 - d0 / 0.65, 0.0), 2.0)
			cone -= (1.0 - smoothstep(0.0, 0.12, d0)) * 0.35
			return continent * 0.6 + peaks * 0.5 + cone * 0.55
		Kind.ICE:
			var edge: float = (noises["cracks"] as FastNoiseLite).get_noise_3dv(dir) + 1.0
			var crack: float = 1.0 - smoothstep(0.0, 0.06, edge)
			return continent * 0.7 + peaks * 0.3 - crack * 0.12
		Kind.BARREN:
			var big: float = _crater_at(noises, "craters", "crater_sizes", dir)
			var small: float = _crater_at(noises, "small_craters", "small_crater_sizes", dir)
			var tiny: float = _crater_at(noises, "tiny_craters", "tiny_crater_sizes", dir)
			return continent * 0.45 + peaks * 0.15 + big * 0.35 + small * 0.15 + tiny * 0.05

	return continent


## One crater layer: the distance to the nearest cell centre shaped into a
## crater, with that cell's own roll picking its size - or that it has none.
static func _crater_at(noises: Dictionary, cells: String, sizes: String, dir: Vector3) -> float:
	var roll: float = (noises[sizes] as FastNoiseLite).get_noise_3dv(dir) * 0.5 + 0.5
	if roll < 0.25:
		return 0.0

	var d0: float = (noises[cells] as FastNoiseLite).get_noise_3dv(dir) + 1.0
	return _crater(d0, lerpf(0.2, 0.5, (roll - 0.25) / 0.75))


## Crater profile from the distance to its centre: a bowl inside the radius
## and a raised rim around it, flat further out.
static func _crater(d0: float, crater_radius: float) -> float:
	var rim: float = exp(-pow((d0 - crater_radius) / (crater_radius * 0.22), 2.0)) * 0.4

	if d0 < crater_radius:
		var t: float = d0 / crater_radius
		return -(1.0 - t * t) * 0.8 + rim

	return rim



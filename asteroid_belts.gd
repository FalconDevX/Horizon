class_name AsteroidBelts
extends Node3D
## Asteroid belts round the sun - scenery only. They exert no gravity, never
## collide, and nothing in the SOI, autopilot or planner layers knows they
## exist. Each belt is one MultiMesh of rocks whose orbits are advanced on the
## GPU (asteroid_belt.gdshader), so thousands of rocks cost no CPU per frame.
##
## Belts sit in the gaps between planets' SOIs; SOI grows with distance from
## the sun, so check the gaps before moving one.

const SHADER := preload("res://asteroid_belt.gdshader")

## Sim time is sent to the shader as a multiple of this plus a remainder.
const TIME_SPLIT := 4096.0

## Smallest a rock is drawn, in screen pixels (radius).
const MIN_SCREEN_RADIUS := 1.1

## Rock shapes per belt; each gets its own MultiMesh.
const VARIANTS := 3

## Detail levels (icosahedron splits: 20 / 80 / 320 triangles), picked from how
## big a belt's largest rocks are on screen - a speck needs no craters, and a
## dense belt drawn in full detail from afar would cost millions of triangles.
const LOD_SUBDIVISIONS: Array[int] = [0, 1, 2]
const LOD_SCREEN_RADIUS: Array[float] = [6.0, 40.0]

const BELTS := [
	{
		# Between Duskveil and Thornix SOIs (all belt radii are at 4x world scale).
		"inner": 154000.0,
		"outer": 177200.0,
		"count": 3600,
		"size": Vector2(18.0, 180.0),
		"colors": [
			Color(0.36, 0.32, 0.29), Color(0.45, 0.39, 0.33),
			Color(0.3, 0.29, 0.28), Color(0.55, 0.42, 0.32),
		],
	},
	{
		# The main belt, between Marrow and Vantauri.
		"inner": 752000.0,
		"outer": 864000.0,
		"count": 14000,
		"size": Vector2(36.0, 510.0),
		"colors": [
			Color(0.42, 0.4, 0.38), Color(0.5, 0.44, 0.37), Color(0.33, 0.31, 0.3),
			Color(0.58, 0.5, 0.42), Color(0.52, 0.36, 0.28),
		],
	},
	{
		# Icy outer belt past Oruvel.
		"inner": 4160000.0,
		"outer": 4800000.0,
		"count": 10500,
		"size": Vector2(60.0, 720.0),
		"colors": [
			Color(0.74, 0.8, 0.86), Color(0.62, 0.7, 0.8), Color(0.85, 0.88, 0.9),
			Color(0.4, 0.42, 0.46), Color(0.56, 0.62, 0.72),
		],
	},
]

var _material: ShaderMaterial
## One entry per MultiMesh: {multimesh, meshes (one per LOD), size_max}.
var _layers: Array[Dictionary] = []


func setup(sun_center: Vector2, mu: float, world_seed: int) -> void:
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF

	_material = ShaderMaterial.new()
	_material.shader = SHADER
	_material.set_shader_parameter("mu", mu)
	_material.set_shader_parameter("sun_center", sun_center)

	var rng := RandomNumberGenerator.new()
	rng.seed = hash(world_seed) ^ 0xA57E

	for belt: Dictionary in BELTS:
		for _variant in range(VARIANTS):
			add_child(_build_belt(belt, sun_center, rng, VARIANTS))


## Call every frame with the sim clock and the 2D camera zoom.
func update_view(sim_time: float, camera_zoom: float) -> void:
	if _material == null:
		return

	var hi: float = floorf(sim_time / TIME_SPLIT) * TIME_SPLIT
	_material.set_shader_parameter("time_hi", hi)
	_material.set_shader_parameter("time_lo", sim_time - hi)
	_material.set_shader_parameter("min_size", MIN_SCREEN_RADIUS / maxf(camera_zoom, 1e-6))

	for layer: Dictionary in _layers:
		var screen_radius: float = layer["size_max"] * camera_zoom
		var lod: int = LOD_SUBDIVISIONS.size() - 1
		for i in range(LOD_SCREEN_RADIUS.size()):
			if screen_radius < LOD_SCREEN_RADIUS[i]:
				lod = i
				break
		var mesh: ArrayMesh = layer["meshes"][lod]
		var multimesh: MultiMesh = layer["multimesh"]
		if multimesh.mesh != mesh:
			multimesh.mesh = mesh


## One shape variant of a belt: `1 / share` of its rocks.
func _build_belt(
	belt: Dictionary,
	sun_center: Vector2,
	rng: RandomNumberGenerator,
	share: int
) -> MultiMeshInstance3D:
	var inner: float = belt["inner"]
	var outer: float = belt["outer"]
	var count: int = int(belt["count"]) / share
	var size_range: Vector2 = belt["size"]
	var colors: Array = belt["colors"]

	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_colors = true
	multimesh.use_custom_data = true
	var rock_seed: int = rng.randi()
	var meshes: Array[ArrayMesh] = []
	for subdivisions in LOD_SUBDIVISIONS:
		meshes.append(_make_rock(rock_seed, subdivisions))
	multimesh.mesh = meshes[0]
	multimesh.instance_count = count
	_layers.append({"multimesh": multimesh, "meshes": meshes, "size_max": size_range.y})

	for i in range(count):
		# Sum of two uniforms: densest mid-belt, thinning to the edges.
		var t: float = (rng.randf() + rng.randf()) * 0.5
		var orbit_radius: float = lerpf(inner, outer, t)
		var phase: float = rng.randf() * TAU
		# Mostly small, the odd big one.
		var size: float = size_range.x * pow(size_range.y / size_range.x, pow(rng.randf(), 3.0))
		var spin: float = rng.randf_range(-0.6, 0.6)

		var axis := Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 1), rng.randf_range(-1, 1))
		if axis.length_squared() < 1e-4:
			axis = Vector3.UP
		var shape := Basis(axis.normalized(), rng.randf() * TAU) * Basis.from_scale(
			Vector3(1.0, rng.randf_range(0.55, 1.0), rng.randf_range(0.65, 1.0)) * size
		)
		multimesh.set_instance_transform(i, Transform3D(shape, Vector3.ZERO))

		var tint: Color = colors[rng.randi() % colors.size()]
		tint = tint.lerp(Color.BLACK, rng.randf_range(0.0, 0.25))
		multimesh.set_instance_color(i, tint.srgb_to_linear())
		multimesh.set_instance_custom_data(i, Color(orbit_radius, phase, size, spin))

	var instance := MultiMeshInstance3D.new()
	instance.multimesh = multimesh
	instance.material_override = _material
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	instance.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	# The shader moves every rock, so the instances' own bounds mean nothing.
	var reach: float = outer + size_range.y * 4.0
	instance.custom_aabb = AABB(
		Vector3(sun_center.x - reach, -reach * 0.01, sun_center.y - reach),
		Vector3(reach * 2.0, reach * 0.02, reach * 2.0)
	)
	return instance


## A lumpy unit rock: an icosahedron split `subdivisions` times, each vertex
## pushed in or out by random waves over the sphere. The same seed gives the
## same rock at every subdivision, so LOD swaps don't change its shape.
static func _make_rock(seed_value: int, subdivisions: int) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value

	var g: float = (1.0 + sqrt(5.0)) * 0.5
	var points: Array[Vector3] = [
		Vector3(-1, g, 0), Vector3(1, g, 0), Vector3(-1, -g, 0), Vector3(1, -g, 0),
		Vector3(0, -1, g), Vector3(0, 1, g), Vector3(0, -1, -g), Vector3(0, 1, -g),
		Vector3(g, 0, -1), Vector3(g, 0, 1), Vector3(-g, 0, -1), Vector3(-g, 0, 1),
	]
	var faces: Array = [
		[0, 11, 5], [0, 5, 1], [0, 1, 7], [0, 7, 10], [0, 10, 11],
		[1, 5, 9], [5, 11, 4], [11, 10, 2], [10, 7, 6], [7, 1, 8],
		[3, 9, 4], [3, 4, 2], [3, 2, 6], [3, 6, 8], [3, 8, 9],
		[4, 9, 5], [2, 4, 11], [6, 2, 10], [8, 6, 7], [9, 8, 1],
	]
	for i in range(points.size()):
		points[i] = points[i].normalized()

	# Split every triangle in four, sharing midpoints between neighbours.
	for _level in range(subdivisions):
		var midpoints := {}
		var split: Array = []
		for face: Array in faces:
			var m: Array[int] = []
			for e in range(3):
				var a: int = face[e]
				var b: int = face[(e + 1) % 3]
				var key: int = mini(a, b) * 100000 + maxi(a, b)
				if not midpoints.has(key):
					midpoints[key] = points.size()
					points.append(((points[a] + points[b]) * 0.5).normalized())
				m.append(midpoints[key])
			split.append([face[0], m[0], m[2]])
			split.append([face[1], m[1], m[0]])
			split.append([face[2], m[2], m[1]])
			split.append([m[0], m[1], m[2]])
		faces = split

	# Broad lumps first, then finer knobbles that only the finer LODs resolve.
	var waves: Array = []
	for i in range(9):
		var k := Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 1), rng.randf_range(-1, 1))
		var fine: bool = i >= 5
		waves.append([
			k.normalized() * (rng.randf_range(5.0, 9.0) if fine else rng.randf_range(1.5, 4.0)),
			rng.randf() * TAU,
			rng.randf_range(0.02, 0.05) if fine else rng.randf_range(0.05, 0.13),
		])

	var vertices := PackedVector3Array()
	for p: Vector3 in points:
		var bump: float = 0.0
		for w: Array in waves:
			bump += sin(p.dot(w[0]) + w[1]) * w[2]
		vertices.append(p * (1.0 + bump))

	var indices := PackedInt32Array()
	for tri: Array in faces:
		indices.append_array(tri)

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh

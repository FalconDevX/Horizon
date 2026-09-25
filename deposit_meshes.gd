class_name DepositMeshes
extends RefCounted

## The shapes of resource deposits, built procedurally from a seed so no two
## are alike. Every mesh is in cluster units: about one unit across, standing
## on +Y, with its feet sunk a little below zero so it stays planted where the
## planet's mesh runs a touch above or below the heightmap. Vertex colours
## carry the shading within a deposit (stem vs leaf, rust vs steel); the
## material multiplies them by the type's colour.
##
## To add a look: write a builder here and add it to build().


static func build(style: StringName, mesh_seed: int) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = mesh_seed
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	match style:
		&"crystals":
			_crystals(st, rng)
		&"tiles":
			_tiles(st, rng)
		&"scrap":
			_scrap(st, rng)
		&"beanstalk":
			_beanstalk(st, rng, &"green")
		&"beanstalk_frozen":
			_beanstalk(st, rng, &"frozen")
		&"beanstalk_dried":
			_beanstalk(st, rng, &"dried")
		&"spikes":
			_spikes(st, rng)
		&"jelly":
			_jelly(st, rng)
		&"tumbleweed":
			_tumbleweed(st, rng)
		&"geyser":
			_geyser(st, rng)
		&"pillars":
			_pillars(st, rng)
		&"egg":
			_egg(st, rng)
		&"pebbles":
			_pebbles(st, rng)
		&"bones":
			_bones(st, rng)
		&"slabs":
			_slabs(st, rng)
		_:
			push_error("DepositMeshes: no look called %s" % style)
	return st.commit()


# ---- looks -------------------------------------------------------------------

## A few six-sided crystals of different heights and leans, the tallest in the
## middle.
static func _crystals(st: SurfaceTool, rng: RandomNumberGenerator) -> void:
	for i in range(rng.randi_range(3, 6)):
		var outward: float = 0.0 if i == 0 else rng.randf_range(0.2, 0.5)
		var around: float = rng.randf_range(0.0, TAU)
		var foot := Vector3(cos(around), 0.0, sin(around)) * outward
		var height: float = rng.randf_range(0.7, 1.1) if i == 0 else rng.randf_range(0.35, 0.8)
		var width: float = rng.randf_range(0.13, 0.2) * (1.3 if i == 0 else 1.0)
		var lean: Vector3 = (Vector3.UP + foot * rng.randf_range(0.8, 1.6)).normalized()
		var tone: float = rng.randf_range(0.85, 1.0)
		_crystal(st, foot - lean * 0.3, lean, width, height + 0.3, rng.randf_range(0.0, TAU), Color(tone, tone, tone))


## Squarish plates - almost square, never quite - lying nearly flat and
## overlapping, a little thick so they catch the light on their edges.
static func _tiles(st: SurfaceTool, rng: RandomNumberGenerator) -> void:
	for i in range(rng.randi_range(2, 4)):
		var side: float = rng.randf_range(0.35, 0.55)
		var corners := PackedVector2Array()
		for k in range(4):
			var a: float = TAU * float(k) / 4.0 + PI / 4.0 + rng.randf_range(-0.18, 0.18)
			corners.append(Vector2(cos(a), sin(a)) * side * 0.72 * rng.randf_range(0.85, 1.15))
		var around: float = rng.randf_range(0.0, TAU)
		var at := Vector3(cos(around), 0.0, sin(around)) * (0.0 if i == 0 else rng.randf_range(0.15, 0.4))
		at.y = -0.04 + 0.05 * float(i)
		var tilt := Basis(Vector3(rng.randf_range(-1.0, 1.0), 0.0, rng.randf_range(-1.0, 1.0)).normalized(), rng.randf_range(0.0, 0.2))
		var basis := tilt * Basis(Vector3.UP, rng.randf_range(0.0, TAU))
		var tone: float = rng.randf_range(0.82, 1.0)
		_slab(st, Transform3D(basis, at), corners, rng.randf_range(0.07, 0.11), 0.92, Color(tone, tone, tone))


## Old wreckage: a half-buried girder, a length of pipe, a bent plate and a
## crate, in rust and tired steel.
static func _scrap(st: SurfaceTool, rng: RandomNumberGenerator) -> void:
	var rust := Color(0.48, 0.24, 0.11)
	var steel := Color(0.36, 0.37, 0.4)
	var faded := Color(0.55, 0.5, 0.44)

	# Girder, one end dug in.
	var girder := Basis(Vector3.UP, rng.randf_range(0.0, TAU)) * Basis(Vector3.RIGHT, rng.randf_range(0.2, 0.5))
	_box(st, Transform3D(girder, Vector3(rng.randf_range(-0.2, 0.2), 0.05, rng.randf_range(-0.2, 0.2))),
		Vector3(0.14, 0.14, rng.randf_range(0.9, 1.2)), rust)
	# Pipe lying on its side.
	var pipe := Basis(Vector3.UP, rng.randf_range(0.0, TAU)) * Basis(Vector3.FORWARD, PI / 2.0)
	_cylinder(st, Transform3D(pipe, Vector3(rng.randf_range(-0.35, 0.35), 0.06, rng.randf_range(-0.35, 0.35))),
		0.09, rng.randf_range(0.5, 0.8), 8, steel)
	# A plate bent in two.
	var plate_yaw := Basis(Vector3.UP, rng.randf_range(0.0, TAU))
	var plate_at := Vector3(rng.randf_range(-0.3, 0.3), 0.0, rng.randf_range(-0.3, 0.3))
	_box(st, Transform3D(plate_yaw * Basis(Vector3.RIGHT, -0.15), plate_at), Vector3(0.45, 0.04, 0.35), faded)
	_box(st, Transform3D(plate_yaw * Basis(Vector3.RIGHT, 0.9), plate_at + plate_yaw * Vector3(0.0, 0.12, -0.3)),
		Vector3(0.45, 0.04, 0.3), faded)
	# A dented crate.
	if rng.randf() < 0.7:
		var crate := Basis(Vector3.UP, rng.randf_range(0.0, TAU)) * Basis(Vector3.RIGHT, rng.randf_range(-0.15, 0.15))
		_box(st, Transform3D(crate, Vector3(rng.randf_range(-0.35, 0.35), 0.08, rng.randf_range(-0.35, 0.35))),
			Vector3.ONE * rng.randf_range(0.25, 0.35), rust.lerp(steel, 0.5))


## A long, tapering beanstalk sprout curling over at the tip like a fiddlehead,
## with a few leaves along it and sometimes a small sprout beside it. `state`:
## &"green"; &"frozen" - still green at the foot, iced over further up;
## &"dried" - withered brown and wilting over.
static func _beanstalk(st: SurfaceTool, rng: RandomNumberGenerator, state: StringName) -> void:
	var stem := Color(0.22, 0.55, 0.18)
	var leaf := Color(0.45, 0.8, 0.28)
	var tip := stem
	var wilt := 0.0
	if state == &"frozen":
		var ice := Color(0.82, 0.93, 1.0)
		tip = ice
		leaf = leaf.lerp(ice, rng.randf_range(0.5, 0.8))
	elif state == &"dried":
		stem = Color(0.45, 0.33, 0.18)
		tip = Color(0.6, 0.5, 0.32)
		leaf = Color(0.55, 0.42, 0.24)
		wilt = rng.randf_range(0.8, 1.6)
	_sprout(st, rng, Vector3.ZERO, rng.randf_range(2.6, 3.6), 0.13, stem, leaf, rng.randi_range(3, 5), tip, wilt)
	for i in range(rng.randi_range(0, 2)):
		var around: float = rng.randf_range(0.0, TAU)
		var at := Vector3(cos(around), 0.0, sin(around)) * rng.randf_range(0.25, 0.4)
		_sprout(st, rng, at, rng.randf_range(0.9, 1.5), 0.07, stem, leaf, rng.randi_range(1, 2), tip, wilt)


## Ice crystals: a sheaf of long, thin, four-sided spikes leaning out from one
## foot.
static func _spikes(st: SurfaceTool, rng: RandomNumberGenerator) -> void:
	for i in range(rng.randi_range(4, 7)):
		var around: float = rng.randf_range(0.0, TAU)
		var out := Vector3(cos(around), 0.0, sin(around))
		var axis: Vector3 = (Vector3.UP * 2.5 + out * (0.0 if i == 0 else rng.randf_range(0.5, 1.4))).normalized()
		var length: float = rng.randf_range(1.3, 1.9) if i == 0 else rng.randf_range(0.7, 1.4)
		var tone: float = rng.randf_range(0.85, 1.0)
		_spike(st, out * rng.randf_range(0.0, 0.15) - axis * 0.3, axis, rng.randf_range(0.06, 0.1), length + 0.3,
			rng.randf_range(0.0, TAU), Color(tone, tone, tone))


## A slime jelly: a glossy, wobbly dome with a couple of bubbles trapped on top.
static func _jelly(st: SurfaceTool, rng: RandomNumberGenerator) -> void:
	_dome(st, Vector3(0.0, -0.08, 0.0), Vector3(0.48, 0.55, 0.48), Color.WHITE, rng, 0.05)
	for i in range(rng.randi_range(1, 3)):
		var around: float = rng.randf_range(0.0, TAU)
		var at := Vector3(cos(around) * 0.2, 0.3 + rng.randf_range(0.0, 0.1), sin(around) * 0.2)
		_dome(st, at, Vector3.ONE * rng.randf_range(0.07, 0.11), Color.WHITE, rng, 0.0)


## A tumbleweed: a ball of dry, tangled twigs.
static func _tumbleweed(st: SurfaceTool, rng: RandomNumberGenerator) -> void:
	var centre := Vector3(0.0, 0.42, 0.0)
	for i in range(rng.randi_range(12, 16)):
		# Each twig an arc round the ball, on its own tilted circle.
		var axis := Vector3(rng.randf_range(-1.0, 1.0), rng.randf_range(-1.0, 1.0), rng.randf_range(-1.0, 1.0)).normalized()
		var start: Vector3 = axis.cross(Vector3.UP if absf(axis.y) < 0.9 else Vector3.RIGHT).normalized()
		var radius: float = rng.randf_range(0.34, 0.46)
		var arc: float = rng.randf_range(1.5, 3.5)
		var from: float = rng.randf_range(0.0, TAU)
		var path := PackedVector3Array()
		var radii := PackedFloat32Array()
		for k in range(9):
			var t: float = from + arc * float(k) / 8.0
			path.append(centre + start.rotated(axis, t) * radius)
			radii.append(0.025)
		var tone: float = rng.randf_range(0.8, 1.1)
		_tube(st, path, radii, 4, Color(tone, tone, tone))


## A geyser: a low vent of pale sinter with a plume of steam standing out of it,
## widening as it climbs.
static func _geyser(st: SurfaceTool, rng: RandomNumberGenerator) -> void:
	var corners := PackedVector2Array()
	for k in range(9):
		var a: float = TAU * float(k) / 9.0
		corners.append(Vector2(cos(a), sin(a)) * 0.42 * rng.randf_range(0.85, 1.1))
	_slab(st, Transform3D(Basis(), Vector3(0.0, -0.2, 0.0)), corners, 0.35, 0.45, Color(0.72, 0.74, 0.78))
	var height: float = rng.randf_range(2.5, 4.0)
	var path := PackedVector3Array()
	var radii := PackedFloat32Array()
	var lean := Vector3(rng.randf_range(-0.15, 0.15), 0.0, rng.randf_range(-0.15, 0.15))
	for k in range(13):
		var t: float = float(k) / 12.0
		path.append(Vector3(0.0, 0.1 + t * height, 0.0) + lean * t * t * height)
		radii.append(lerpf(0.1, 0.38, pow(t, 0.7)) * (1.0 - smoothstep(0.85, 1.0, t) * 0.7))
	_tube(st, path, radii, 8, Color(0.97, 0.98, 1.0))


## Golden columns of different heights rising out of the water, their tops
## cut on a slant.
static func _pillars(st: SurfaceTool, rng: RandomNumberGenerator) -> void:
	for i in range(rng.randi_range(3, 6)):
		var around: float = rng.randf_range(0.0, TAU)
		var reach: float = 0.0 if i == 0 else rng.randf_range(0.2, 0.45)
		# Their feet well under the water.
		var at := Vector3(cos(around) * reach, -0.4, sin(around) * reach)
		var radius: float = rng.randf_range(0.12, 0.2) * (1.3 if i == 0 else 1.0)
		var height: float = (rng.randf_range(1.3, 1.9) if i == 0 else rng.randf_range(0.6, 1.3)) + 0.4
		var sides: int = 6 if rng.randf() < 0.7 else 4
		var corners := PackedVector2Array()
		var twist: float = rng.randf_range(0.0, TAU)
		for k in range(sides):
			var a: float = twist + TAU * float(k) / float(sides)
			corners.append(Vector2(cos(a), sin(a)) * radius)
		var lean := Basis(Vector3(rng.randf_range(-1.0, 1.0), 0.0, rng.randf_range(-1.0, 1.0)).normalized(), rng.randf_range(0.0, 0.12))
		var tone: float = rng.randf_range(0.85, 1.0)
		_slab(st, Transform3D(lean, at), corners, height, 1.0, Color(tone, tone, tone),
			Vector2(rng.randf_range(-0.25, 0.25), rng.randf_range(-0.25, 0.25)))


## One egg, narrower at the top, sitting a little tilted. The spots are the
## shader's.
static func _egg(st: SurfaceTool, rng: RandomNumberGenerator) -> void:
	var tilt := Basis(Vector3(rng.randf_range(-1.0, 1.0), 0.0, rng.randf_range(-1.0, 1.0)).normalized(), rng.randf_range(0.05, 0.3))
	var rings := 14
	var sides := 16
	var half_width := 0.42
	var half_height := 0.58
	var centre := Vector3(0.0, half_height - 0.12, 0.0)
	var points: Array[PackedVector3Array] = []
	var normals: Array[PackedVector3Array] = []
	for i in range(rings + 1):
		var v: float = float(i) / float(rings)
		var y: float = -cos(v * PI)
		# Egg profile: a sphere pinched toward the top.
		var ring_radius: float = sin(v * PI) * (1.0 - 0.16 * y) * half_width
		var ring := PackedVector3Array()
		var ring_normals := PackedVector3Array()
		for k in range(sides + 1):
			var a: float = TAU * float(k) / float(sides)
			var local := Vector3(cos(a) * ring_radius, y * half_height, sin(a) * ring_radius)
			ring.append(tilt * local + centre)
			# Normal of the stretched sphere, near enough for shading.
			var n := Vector3(local.x / (half_width * half_width), local.y / (half_height * half_height), local.z / (half_width * half_width))
			ring_normals.append((tilt * n).normalized())
		points.append(ring)
		normals.append(ring_normals)
	_grid(st, points, normals, Color.WHITE)


## A few smooth, rounded pebbles in a little heap - small and glossy.
static func _pebbles(st: SurfaceTool, rng: RandomNumberGenerator) -> void:
	for i in range(rng.randi_range(2, 4)):
		var around: float = rng.randf_range(0.0, TAU)
		var at := Vector3(cos(around), 0.0, sin(around)) * (0.0 if i == 0 else rng.randf_range(0.2, 0.4))
		var size: float = rng.randf_range(0.22, 0.34) * (1.2 if i == 0 else 1.0)
		at.y = size * 0.25
		var tone: float = rng.randf_range(0.85, 1.0)
		_rock(st, rng, at, Vector3(size, size * 0.65, size * rng.randf_range(0.8, 1.1)), Color(tone, tone, tone), 0.12)


## Bone-white spikes curving up and out like ribs or tusks, from a knobbly
## base.
static func _bones(st: SurfaceTool, rng: RandomNumberGenerator) -> void:
	var spikes: int = rng.randi_range(3, 6)
	var start: float = rng.randf_range(0.0, TAU)
	for i in range(spikes):
		var around: float = start + TAU * float(i) / float(spikes) + rng.randf_range(-0.3, 0.3)
		var out := Vector3(cos(around), 0.0, sin(around))
		var foot: Vector3 = out * rng.randf_range(0.05, 0.25) + Vector3(0.0, -0.3, 0.0)
		var length: float = rng.randf_range(1.1, 1.9)
		# Rising steeply, bending outward along the way.
		var heading: Vector3 = (Vector3.UP * 2.0 + out * rng.randf_range(0.2, 0.6)).normalized()
		var bend_axis: Vector3 = out.cross(Vector3.UP).normalized()
		var bend: float = rng.randf_range(0.5, 1.1)
		var path := _curve(foot, heading, length, bend_axis, func(t: float) -> float: return bend * (0.6 + t))
		var radii := PackedFloat32Array()
		for k in range(path.size()):
			var t: float = float(k) / float(path.size() - 1)
			radii.append(lerpf(0.1, 0.008, pow(t, 0.8)))
		_tube(st, path, radii, 7, Color(1.0, 0.96, 0.9))
	# The knobbly joint they grow from.
	_rock(st, rng, Vector3(0.0, -0.05, 0.0), Vector3(0.3, 0.18, 0.3), Color(0.9, 0.85, 0.75), 0.15)


## Flat, jagged rocks stacked on each other, smaller toward the top.
static func _slabs(st: SurfaceTool, rng: RandomNumberGenerator) -> void:
	var y: float = -0.1
	var count: int = rng.randi_range(3, 5)
	for i in range(count):
		var radius: float = lerpf(0.5, 0.2, float(i) / float(count)) * rng.randf_range(0.85, 1.1)
		var sides: int = rng.randi_range(6, 8)
		var corners := PackedVector2Array()
		for k in range(sides):
			var a: float = TAU * float(k) / float(sides) + rng.randf_range(-0.2, 0.2)
			corners.append(Vector2(cos(a), sin(a)) * radius * rng.randf_range(0.75, 1.15))
		var thickness: float = rng.randf_range(0.1, 0.16)
		var at := Vector3(rng.randf_range(-0.08, 0.08), y, rng.randf_range(-0.08, 0.08))
		var tilt := Basis(Vector3(rng.randf_range(-1.0, 1.0), 0.0, rng.randf_range(-1.0, 1.0)).normalized(), rng.randf_range(0.0, 0.15))
		var tone: float = rng.randf_range(0.7, 1.0)
		_slab(st, Transform3D(tilt, at), corners, thickness, rng.randf_range(0.75, 0.9), Color(tone, tone, tone))
		y += thickness * 0.85


# ---- parts -------------------------------------------------------------------

## One sprout: a tube that rises, leans and curls over at the tip, with
## `leaves` leaves along it.
static func _sprout(
	st: SurfaceTool, rng: RandomNumberGenerator, foot: Vector3, length: float, width: float,
	stem: Color, leaf: Color, leaves: int, tip: Color, wilt: float
) -> void:
	var lean_way: float = rng.randf_range(0.0, TAU)
	var lean := Vector3(cos(lean_way), 0.0, sin(lean_way))
	var heading: Vector3 = (Vector3.UP * 3.0 + lean * rng.randf_range(0.3, 0.9)).normalized()
	var bend_axis: Vector3 = lean.cross(Vector3.UP).normalized() * (1.0 if rng.randf() < 0.5 else -1.0)
	# A wilting stalk bends right over under its own weight.
	var sway: float = rng.randf_range(0.2, 0.6) + wilt
	var curl: float = rng.randf_range(5.0, 9.0) / length
	# Gentle bend up the stalk, then a tight curl over the last stretch.
	var path := _curve(foot + Vector3(0.0, -0.3, 0.0), heading, length + 0.3, bend_axis,
		func(t: float) -> float: return sway + curl * pow(t, 4.0))
	var radii := PackedFloat32Array()
	for k in range(path.size()):
		var t: float = float(k) / float(path.size() - 1)
		radii.append(lerpf(width, width * 0.12, pow(t, 0.7)))
	_tube(st, path, radii, 8, stem, tip)

	for i in range(leaves):
		var k: int = int(lerpf(0.25, 0.75, (float(i) + rng.randf_range(0.0, 0.8)) / float(leaves)) * float(path.size() - 1))
		var along: Vector3 = (path[k + 1] - path[k]).normalized()
		var side: Vector3 = along.cross(Vector3.UP).normalized()
		if side.length_squared() < 0.5:
			side = Vector3.RIGHT
		var out: Vector3 = side.rotated(along, rng.randf_range(0.0, TAU))
		out = (out + Vector3.UP * 0.35).normalized()
		_leaf(st, path[k], out, along, rng.randf_range(0.35, 0.55) * width / 0.13 + 0.1, leaf)


## Points along a curve from `start`, first heading `heading`, turning about
## `axis` by `bend.call(t)` radians per unit of length (t = 0..1 along it).
static func _curve(start: Vector3, heading: Vector3, length: float, axis: Vector3, bend: Callable) -> PackedVector3Array:
	var steps := 24
	var step: float = length / float(steps)
	var points := PackedVector3Array([start])
	var at: Vector3 = start
	var way: Vector3 = heading
	for i in range(steps):
		var t: float = float(i) / float(steps)
		way = way.rotated(axis, float(bend.call(t)) * step).normalized()
		at += way * step
		points.append(at)
	return points


## A round tube along `path`, `radii` wide at each point, smooth-shaded, its
## colour running from `color` at the start to `tip` at the end.
static func _tube(
	st: SurfaceTool, path: PackedVector3Array, radii: PackedFloat32Array, sides: int, color: Color,
	tip := Color(-1.0, 0.0, 0.0)
) -> void:
	if tip.r < 0.0:
		tip = color
	var rings: Array[PackedVector3Array] = []
	var normals: Array[PackedVector3Array] = []
	var normal := Vector3.ZERO
	for i in range(path.size()):
		var tangent: Vector3 = (path[mini(i + 1, path.size() - 1)] - path[maxi(i - 1, 0)]).normalized()
		# Carried along from ring to ring, so the tube does not twist.
		if i == 0:
			normal = tangent.cross(Vector3.RIGHT if absf(tangent.x) < 0.9 else Vector3.FORWARD).normalized()
		else:
			normal = (normal - tangent * normal.dot(tangent)).normalized()
		var binormal: Vector3 = tangent.cross(normal)
		var ring := PackedVector3Array()
		var ring_normals := PackedVector3Array()
		for k in range(sides + 1):
			var a: float = TAU * float(k) / float(sides)
			var out: Vector3 = normal * cos(a) + binormal * sin(a)
			ring.append(path[i] + out * radii[i])
			ring_normals.append(out)
		rings.append(ring)
		normals.append(ring_normals)
	if tip == color:
		_grid(st, rings, normals, color)
		return
	# Colour by ring, fading from one end to the other.
	for i in range(rings.size() - 1):
		var along: float = float(i) / float(rings.size() - 2)
		var c: Color = color.lerp(tip, smoothstep(0.35, 0.85, along))
		var pair: Array[PackedVector3Array] = [rings[i], rings[i + 1]]
		var pair_normals: Array[PackedVector3Array] = [normals[i], normals[i + 1]]
		_grid(st, pair, pair_normals, c)


## A leaf: a flat, pointed oval from `base` along `out`, drooping a little,
## seen from both sides.
static func _leaf(st: SurfaceTool, base: Vector3, out: Vector3, along: Vector3, length: float, color: Color) -> void:
	var side: Vector3 = out.cross(along).normalized()
	var up: Vector3 = side.cross(out).normalized()
	var steps := 6
	var left := PackedVector3Array()
	var right := PackedVector3Array()
	var middle := PackedVector3Array()
	for i in range(steps + 1):
		var t: float = float(i) / float(steps)
		var droop: Vector3 = -up * t * t * length * 0.3
		var centre: Vector3 = base + out * t * length + droop
		var half: float = sin(t * PI) * length * 0.28
		middle.append(centre)
		left.append(centre + side * half)
		right.append(centre - side * half)
	for i in range(steps):
		for half: PackedVector3Array in [left, right]:
			for face in [[middle[i], half[i], half[i + 1]], [middle[i], half[i + 1], middle[i + 1]]]:
				var n: Vector3 = up
				_triangle(st, face[0], face[1], face[2], n, n, n, color)
				_triangle(st, face[0], face[2], face[1], -n, -n, -n, color)


## A smooth dome (the top of a squashed sphere, sunk a little at the foot),
## its outline wobbled by `wobble`.
static func _dome(st: SurfaceTool, centre: Vector3, size: Vector3, color: Color, rng: RandomNumberGenerator, wobble: float) -> void:
	var rings := 8
	var sides := 14
	var points: Array[PackedVector3Array] = []
	var normals: Array[PackedVector3Array] = []
	var bumps: Array = []
	for k in range(sides):
		bumps.append(1.0 + rng.randf_range(-wobble, wobble))
	bumps.append(bumps[0])
	for i in range(rings + 1):
		var v: float = float(i) / float(rings)
		var y: float = lerpf(-0.3, 1.0, v)
		var r: float = sqrt(maxf(1.0 - y * y, 0.0))
		var ring := PackedVector3Array()
		var ring_normals := PackedVector3Array()
		for k in range(sides + 1):
			var a: float = TAU * float(k) / float(sides)
			var unit := Vector3(cos(a) * r * bumps[k], y, sin(a) * r * bumps[k])
			ring.append(centre + unit * size)
			ring_normals.append(Vector3(unit.x / size.x, unit.y / size.y, unit.z / size.z).normalized())
		points.append(ring)
		normals.append(ring_normals)
	_grid(st, points, normals, color)


## A four-sided spike from `base` along `axis`, straight to a point.
static func _spike(st: SurfaceTool, base: Vector3, axis: Vector3, width: float, length: float, twist: float, color: Color) -> void:
	var side := axis.cross(Vector3.FORWARD if absf(axis.z) < 0.9 else Vector3.RIGHT).normalized()
	var other := axis.cross(side)
	var tip: Vector3 = base + axis * length
	var middle: Vector3 = base + axis * length * 0.3
	var foot := PackedVector3Array()
	for k in range(4):
		var a: float = twist + TAU * float(k) / 4.0
		foot.append(base + (side * cos(a) + other * sin(a)) * width)
	for k in range(4):
		_face(st, [foot[k], foot[(k + 1) % 4], tip], middle, color)


## A lumpy, flat-shaded rock: a squashed sphere with its points jittered.
static func _rock(st: SurfaceTool, rng: RandomNumberGenerator, centre: Vector3, size: Vector3, color: Color, jitter: float) -> void:
	var rings := 4
	var sides := 7
	var points: Array[PackedVector3Array] = []
	for i in range(rings + 1):
		var v: float = float(i) / float(rings)
		var ring := PackedVector3Array()
		for k in range(sides):
			var a: float = TAU * float(k) / float(sides)
			var p := Vector3(cos(a) * sin(v * PI), -cos(v * PI), sin(a) * sin(v * PI))
			if i > 0 and i < rings:
				p *= 1.0 + rng.randf_range(-jitter, jitter)
			ring.append(centre + p * size)
		points.append(ring)
	for i in range(rings):
		for k in range(sides):
			var next: int = (k + 1) % sides
			_face(st, [points[i][k], points[i][next], points[i + 1][next]], centre, color)
			_face(st, [points[i][k], points[i + 1][next], points[i + 1][k]], centre, color)


## One six-sided crystal with a pointed tip, flat-shaded, along `axis` from
## `base`. `length` includes the tip.
static func _crystal(
	st: SurfaceTool, base: Vector3, axis: Vector3, width: float, length: float, twist: float, color: Color
) -> void:
	var side := axis.cross(Vector3.FORWARD if absf(axis.z) < 0.9 else Vector3.RIGHT).normalized()
	var other := axis.cross(side)
	var shoulder: float = length * 0.72
	var middle: Vector3 = base + axis * shoulder * 0.5
	var tip: Vector3 = base + axis * length
	var bottom := PackedVector3Array()
	var top := PackedVector3Array()
	for k in range(6):
		var a: float = twist + TAU * float(k) / 6.0
		var spoke: Vector3 = (side * cos(a) + other * sin(a)) * width
		bottom.append(base + spoke)
		top.append(base + axis * shoulder + spoke)
	for k in range(6):
		var next: int = (k + 1) % 6
		_face(st, [bottom[k], bottom[next], top[next]], middle, color)
		_face(st, [bottom[k], top[next], top[k]], middle, color)
		_face(st, [top[k], top[next], tip], middle, color)


## A prism: the polygon `corners` (in its XZ plane) extruded `height` up its
## Y, the top shrunk by `top_scale` and slid by `top_shift`, then placed by
## `xform`. Flat-shaded, closed.
static func _slab(
	st: SurfaceTool, xform: Transform3D, corners: PackedVector2Array, height: float,
	top_scale: float, color: Color, top_shift := Vector2.ZERO
) -> void:
	var bottom := PackedVector3Array()
	var top := PackedVector3Array()
	var centre := Vector2.ZERO
	for c in corners:
		centre += c / float(corners.size())
	for c in corners:
		var shrunk: Vector2 = centre + (c - centre) * top_scale
		bottom.append(xform * Vector3(c.x, 0.0, c.y))
		# A slanted top: some corners stand taller than others.
		var lift: float = height + top_shift.dot(c) * height
		top.append(xform * Vector3(shrunk.x, lift, shrunk.y))
	var inside: Vector3 = xform * Vector3(centre.x, height * 0.5, centre.y)
	var bottom_middle: Vector3 = xform * Vector3(centre.x, 0.0, centre.y)
	var top_middle := Vector3.ZERO
	for p in top:
		top_middle += p / float(top.size())
	var n: int = corners.size()
	for k in range(n):
		var next: int = (k + 1) % n
		_face(st, [bottom[k], bottom[next], top[next]], inside, color)
		_face(st, [bottom[k], top[next], top[k]], inside, color)
		_face(st, [top[k], top[next], top_middle], inside, color)
		_face(st, [bottom[k], bottom[next], bottom_middle], inside, color)


static func _box(st: SurfaceTool, xform: Transform3D, size: Vector3, color: Color) -> void:
	var corners := PackedVector2Array([
		Vector2(-size.x, -size.z) * 0.5, Vector2(size.x, -size.z) * 0.5,
		Vector2(size.x, size.z) * 0.5, Vector2(-size.x, size.z) * 0.5,
	])
	_slab(st, xform.translated_local(Vector3(0.0, -size.y * 0.5, 0.0)), corners, size.y, 1.0, color)


## A cylinder `length` long along its local Y, centred on its origin.
static func _cylinder(st: SurfaceTool, xform: Transform3D, radius: float, length: float, sides: int, color: Color) -> void:
	var corners := PackedVector2Array()
	for k in range(sides):
		var a: float = TAU * float(k) / float(sides)
		corners.append(Vector2(cos(a), sin(a)) * radius)
	_slab(st, xform.translated_local(Vector3(0.0, -length * 0.5, 0.0)), corners, length, 1.0, color)


## Rings of points (each closing on itself: last point = first) stitched into
## a smooth-shaded surface.
static func _grid(st: SurfaceTool, rings: Array[PackedVector3Array], normals: Array[PackedVector3Array], color: Color) -> void:
	for i in range(rings.size() - 1):
		for k in range(rings[i].size() - 1):
			var a: Vector3 = rings[i][k]
			var b: Vector3 = rings[i][k + 1]
			var c: Vector3 = rings[i + 1][k + 1]
			var d: Vector3 = rings[i + 1][k]
			var na: Vector3 = normals[i][k]
			var nb: Vector3 = normals[i][k + 1]
			var nc: Vector3 = normals[i + 1][k + 1]
			var nd: Vector3 = normals[i + 1][k]
			_triangle(st, a, b, c, na, nb, nc, color)
			_triangle(st, a, c, d, na, nc, nd, color)


## One flat triangle facing away from `inside`.
static func _face(st: SurfaceTool, corners: Array, inside: Vector3, color: Color) -> void:
	var a: Vector3 = corners[0]
	var b: Vector3 = corners[1]
	var c: Vector3 = corners[2]
	var normal: Vector3 = (b - a).cross(c - a)
	if normal.length_squared() < 1e-12:
		return
	normal = normal.normalized()
	if normal.dot((a + b + c) / 3.0 - inside) < 0.0:
		normal = -normal
	_triangle(st, a, b, c, normal, normal, normal, color)


## One triangle with its own normals, wound clockwise seen from the side the
## normals face (Godot's front face) whichever order it came in.
static func _triangle(
	st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, na: Vector3, nb: Vector3, nc: Vector3, color: Color
) -> void:
	var facing: Vector3 = (b - a).cross(c - a)
	if facing.length_squared() < 1e-12:
		return
	# (b - a) x (c - a) points out of a counter-clockwise triangle: flip it.
	if facing.dot(na + nb + nc) > 0.0:
		var swap: Vector3 = b
		b = c
		c = swap
		swap = nb
		nb = nc
		nc = swap
	for vertex in [[a, na], [b, nb], [c, nc]]:
		st.set_color(color)
		st.set_normal(vertex[1])
		st.add_vertex(vertex[0])

@tool
extends Node2D

const GLOW_TEXTURE := preload("res://textures/glow.png")
const SURFACE_SHADER := preload("res://planet_surface.gdshader")
const SURFACE_SHADER_3D := preload("res://planet_surface_3d.gdshader")
const TERRAIN_SHADER := preload("res://planet_terrain.gdshader")
const STAR_SHADER := preload("res://planet_star.gdshader")
const CORONA_SHADER := preload("res://planet_corona.gdshader")
const CLOUDS_SHADER := preload("res://planet_clouds.gdshader")
const ATMOSPHERE_SHADER := preload("res://planet_atmosphere.gdshader")

## How far the atmosphere's glow reaches past the surface, in radii.
const ATMOSPHERE_DEPTH := 0.12

## How far the cloud deck floats above the lowlands, in radii.
const CLOUD_CLEARANCE := 0.01

## The corona plane's half-width, in stellar radii. Planets' glow is 2.
const CORONA_EXTENT := 5.0

## Maps the surface's view space (x right, y up the screen, z toward the
## viewer) into the 3D world seen by the top-down camera (x right, -z up the
## screen, +y toward the camera). With this in the sphere's basis,
## surface_rotation keeps meaning exactly what it did on the flat disc, so
## is_surface_point_visible() and surface_point_to_local() need no changes.
const VIEW_TO_WORLD := Basis(Vector3(1, 0, 0), Vector3(0, 0, -1), Vector3(0, 1, 0))

## Quads along one edge of each cube face of the sphere mesh.
const SPHERE_SUBDIVISIONS_LOW := 12
const SPHERE_SUBDIVISIONS_HIGH := 160

## Shared by every body; each one just scales and rotates its instance.
static var _sphere_low: ArrayMesh = null
static var _sphere_high: ArrayMesh = null

@export var radius: float = 20.0:
	set(value):
		radius = value
		update_surface_scale()
		queue_redraw()

@export var visual_radius := 0.0:
	set(value):
		visual_radius = value
		update_surface_scale()
		queue_redraw()

@export var color: Color = Color.GREEN:
	set(value):
		color = value
		_update_visual_colors()
		queue_redraw()

@export var mass: float = 1.0

@export var body_name: String = "Unnamed"

@export var atmosphere: String = "None"

@export var show_soi := false:
	set(value):
		show_soi = value
		queue_redraw()

@export var soi_radius := 0.0:
	set(value):
		soi_radius = value
		queue_redraw()

@export var soi_line_width := 1.0:
	set(value):
		soi_line_width = value
		queue_redraw()

## 0 = none, 1 = radar contact, 2 = weapon lock (draw ring in _draw).
var fov_contact: int = 0:
	set(value):
		if fov_contact == value:
			return
		fov_contact = value
		queue_redraw()

# Surface. A blob count of 0 means "no surface" - the body falls back to the
# flat disc, which is what the sun wants. Values are hardcoded per planet in
# solar_system.tscn for now; a generator will roll them later.
@export var surface_seed: int = 0

## Draws the body as a star: a churning photosphere and a corona around it
## (planet_star.gdshader, planet_corona.gdshader) instead of a flat ball.
@export var is_star: bool = false

@export var surface_blob_count: int = 0

## Leave at 0 to roll the count from the seed - more colours is rarer, and is
## what the rarity tier reads. Set it above 0 only to pin a planet for testing.
@export var surface_color_count: int = 0

## Terrain layout. Auto rolls it from the seed; the rest pin a planet.
@export_enum("Auto", "Scattered", "Continents", "Bands")
var surface_style: int = 0

## Radians per second. Positive spins the surface toward screen-right
## around `surface_spin_axis`.
@export var surface_spin_speed: float = 0.25

## Axis this body spins around, in its own local (view) space. Vector3.UP is
## a plain vertical spin, the same as a globe with no tilt; lean it toward X
## or Z to give the planet an axial tilt, the way Earth cants ~23 degrees
## and Uranus tips almost onto its side.
@export var surface_spin_axis: Vector3 = Vector3.UP:
	set(value):
		surface_spin_axis = value.normalized() if value.length() > 0.0001 else Vector3.UP

## How far the lookup direction is bent before the nearest-blob test. This is
## what turns straight Voronoi edges into ragged coastlines. 0.0 disables it.
@export_range(0.0, 0.5, 0.005) var surface_warp_strength: float = 0.12:
	set(value):
		surface_warp_strength = value
		push_surface_parameter("warp_strength", value)

## Scale of the bending. Higher means finer, more frequent wobble.
@export_range(0.5, 12.0, 0.1) var surface_warp_frequency: float = 3.0:
	set(value):
		surface_warp_frequency = value
		push_surface_parameter("warp_frequency", value)

## Blend width between the nearest and second-nearest blob. 0.0 is a hard step.
@export_range(0.0, 0.2, 0.001) var surface_edge_softness: float = 0.02:
	set(value):
		surface_edge_softness = value
		push_surface_parameter("edge_softness", value)

## One texture per palette slot, as layers of a Texture2DArray. Leave empty for
## flat colours. Which layer a slot reads is offset per planet, so bodies that
## rolled the same colour count still differ.
@export var surface_textures: Texture2DArray = null:
	set(value):
		surface_textures = value
		push_surface_textures()

## How many times a texture repeats across the planet.
@export_range(0.5, 32.0, 0.1) var surface_texture_scale: float = 4.0:
	set(value):
		surface_texture_scale = value
		push_surface_parameter("texture_scale", value)

## 1.0 multiplies textures by the planet's generated colour, 0.0 leaves the
## texture's own colours alone.
@export_range(0.0, 1.0, 0.01) var surface_texture_tint: float = 1.0:
	set(value):
		surface_texture_tint = value
		push_surface_parameter("texture_tint", value)

## How far the highest ground rises, as a fraction of the radius. Exaggerated
## on purpose - true-scale mountains would be invisible from orbit.
@export_range(0.0, 0.2, 0.005) var surface_relief: float = 0.06:
	set(value):
		surface_relief = value
		push_surface_parameter("relief", value)
		_update_visual_bounds()
		update_surface_scale()

## Frequency of the ridge noise over the terrain. Higher means more, narrower
## ridges.
@export_range(1.0, 16.0, 0.1) var surface_ridge_frequency: float = 5.0:
	set(value):
		surface_ridge_frequency = value
		push_surface_parameter("ridge_frequency", value)

## Heightmap terrain (see PlanetTerrain). Anything but None replaces the blob
## surface in the running game with a baked heightmap: its own palette, relief,
## and - for kinds that have one - a liquid sea. The editor keeps showing the
## blob preview. Seeded from surface_seed.
@export_enum(
	"None", "Terran", "Desert", "Volcanic", "Ice", "Barren", "Toxic", "Gas giant", "Ice giant"
)
var terrain_kind: int = 0

## Texels along one edge of each of the six heightmap faces.
@export_range(32, 1024, 16) var terrain_resolution: int = 1024

## Share of the surface under liquid, 0..1. Negative keeps the kind's own
## (seed-jittered) value; 0 dries out a kind that would have a sea.
@export_range(-1.0, 0.98, 0.01) var terrain_liquid_coverage: float = -1.0

var velocity: Vector2 = Vector2.ZERO

## Orientation of the surface, mapping planet space into view space. This is
## the whole surface state: a point on the sphere plus a heading, in one value.
## Later this stops auto-spinning and gets driven by the landed ship instead.
var surface_rotation := Quaternion.IDENTITY

var surface_blobs := PackedVector4Array()

## Colours actually in use. Its size is the rolled colour count, which is what
## a rarity tier reads: three is common, more is rarer.
var surface_palette := PackedColorArray()

## The style this body actually ended up with, once AUTO has been rolled out.
var resolved_style: PlanetSurface.Style = PlanetSurface.Style.AUTO

## Editor preview only - the running game draws the sphere in 3D instead.
var surface_sprite: Sprite2D = null
var surface_material: ShaderMaterial = null

# Runtime 3D visual. A Node3D ignores its Node2D parent's transform, so the
# anchor is placed on the orbital plane by hand every physics tick. Position
# lives on the (physics-interpolated) anchor; spin and zoom-driven scale live
# on the children, which move in _process and so must not be interpolated.
var _anchor_3d: Node3D = null
var _sphere_3d: MeshInstance3D = null
var _glow_3d: MeshInstance3D = null
## The cloud deck, a child of the sphere so it spins and scales with it.
var _clouds_3d: MeshInstance3D = null
## The atmosphere's glow shell, likewise. Only worlds with weather (or giants)
## get one - an airless rock shows a hard edge against space.
var _atmosphere_3d: MeshInstance3D = null

## Resolved terrain look (PlanetTerrain.resolve) and, once baked, the heightmap
## itself (PlanetTerrain.bake). Empty until then.
var terrain_params: Dictionary = {}
var terrain_data: Dictionary = {}
var terrain_material: ShaderMaterial = null
var _terrain_task: int = -1
var _terrain_holder: Dictionary = {}
var _terrain_key: String = ""


func _ready() -> void:
	if not Engine.is_editor_hint():
		_build_visual_3d()

	if is_star and _sphere_3d != null:
		build_star()
	elif _uses_terrain():
		build_terrain()
	elif surface_blob_count > 0:
		build_surface()

	set_process(
		(surface_material != null or terrain_material != null or is_star)
		and not Engine.is_editor_hint()
	)
	set_physics_process(_anchor_3d != null)


func _exit_tree() -> void:
	# A task must be waited on before its id is dropped.
	if _terrain_task >= 0:
		WorkerThreadPool.wait_for_task_completion(_terrain_task)
		_terrain_task = -1


func _uses_terrain() -> bool:
	return terrain_kind != PlanetTerrain.Kind.NONE and _sphere_3d != null


func _process(delta: float) -> void:
	if _terrain_task >= 0 and WorkerThreadPool.is_task_completed(_terrain_task):
		WorkerThreadPool.wait_for_task_completion(_terrain_task)
		_terrain_task = -1
		_apply_terrain(_terrain_holder.get("data", {}))

	# Composing rotations cannot push the surface off the sphere, so there is
	# nothing to correct afterwards regardless of how surface_spin_axis tilts.
	surface_rotation = (
		Quaternion(surface_spin_axis, surface_spin_speed * delta) * surface_rotation
	).normalized()

	push_surface_rotation()


# solar_system.gd is the parent and physics-processes first, so the orbit has
# already been stepped this tick and the 2D and 3D copies interpolate alike.
func _physics_process(_delta: float) -> void:
	_sync_visual_position()


func _build_visual_3d() -> void:
	_anchor_3d = Node3D.new()
	_anchor_3d.name = "Visual3D"
	_anchor_3d.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_ON
	add_child(_anchor_3d)

	_sphere_3d = MeshInstance3D.new()
	_sphere_3d.mesh = _shared_sphere(false)
	_sphere_3d.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_sphere_3d.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_anchor_3d.add_child(_sphere_3d)

	# Bodies without a surface (the sun) are a plain lit-from-within ball.
	var flat := StandardMaterial3D.new()
	flat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_sphere_3d.material_override = flat

	# Flat plane below the sphere, facing the camera. Being further from the
	# camera than the ball, it only shows around the rim - the 2D glow did the
	# same by being drawn first.
	var glow_mesh := PlaneMesh.new()
	glow_mesh.size = Vector2.ONE
	var glow_material := StandardMaterial3D.new()
	glow_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	glow_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glow_material.albedo_texture = GLOW_TEXTURE
	_glow_3d = MeshInstance3D.new()
	_glow_3d.mesh = glow_mesh
	_glow_3d.material_override = glow_material
	_glow_3d.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_glow_3d.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_anchor_3d.add_child(_glow_3d)

	_update_visual_colors()
	_update_visual_bounds()
	update_surface_scale()
	_sync_visual_position()
	_anchor_3d.reset_physics_interpolation()


func _sync_visual_position() -> void:
	var planar: Vector2 = global_position
	_anchor_3d.position = Vector3(planar.x, 0.0, planar.y)


func _update_visual_colors() -> void:
	if _sphere_3d == null:
		return

	var flat := _sphere_3d.material_override as StandardMaterial3D
	if flat != null:
		flat.albedo_color = color

	var glow := _glow_3d.material_override as StandardMaterial3D
	if glow != null:
		glow.albedo_color = Color(color, 0.6)


# The shader pushes vertices out past the unit sphere, which the mesh's own
# bounds know nothing about - without this the planet would be culled early.
func _update_visual_bounds() -> void:
	if _sphere_3d == null:
		return

	var extent: float = 1.0 + _visual_relief()
	_sphere_3d.custom_aabb = AABB(-Vector3.ONE * extent, Vector3.ONE * extent * 2.0)
	if _clouds_3d != null:
		extent += CLOUD_CLEARANCE
		_clouds_3d.custom_aabb = AABB(-Vector3.ONE * extent, Vector3.ONE * extent * 2.0)
	if _atmosphere_3d != null:
		extent = _atmosphere_shell_radius()
		_atmosphere_3d.custom_aabb = AABB(-Vector3.ONE * extent, Vector3.ONE * extent * 2.0)


func _visual_relief() -> float:
	if terrain_material != null:
		return terrain_params.get("relief", 0.0)

	return surface_relief


## Swaps between a coarse and a fine sphere. solar_system.gd calls this from
## how big the body is on screen - a few-pixel dot does not need 18k vertices.
func set_detail_high(high: bool) -> void:
	if _sphere_3d == null:
		return

	var mesh: ArrayMesh = _shared_sphere(high)
	if _sphere_3d.mesh != mesh:
		_sphere_3d.mesh = mesh
	if _clouds_3d != null and _clouds_3d.mesh != mesh:
		_clouds_3d.mesh = mesh
	if _atmosphere_3d != null and _atmosphere_3d.mesh != mesh:
		_atmosphere_3d.mesh = mesh


static func _shared_sphere(high: bool) -> ArrayMesh:
	if high:
		if _sphere_high == null:
			_sphere_high = _make_sphere(SPHERE_SUBDIVISIONS_HIGH)
		return _sphere_high

	if _sphere_low == null:
		_sphere_low = _make_sphere(SPHERE_SUBDIVISIONS_LOW)
	return _sphere_low


## Unit cube-sphere: the six faces of PlanetTerrain's cube, each a grid of
## `subdivisions` quads pushed out onto the sphere. Spread evenly in angle
## (tan), so there is no crowding at the poles like a UV sphere has and every
## part of the heightmap gets the same vertex density.
static func _make_sphere(subdivisions: int) -> ArrayMesh:
	var side: int = subdivisions + 1
	var vertices := PackedVector3Array()
	var indices := PackedInt32Array()

	for face in range(6):
		var forward: Vector3 = PlanetTerrain.FACE_FORWARD[face]
		var right: Vector3 = PlanetTerrain.FACE_RIGHT[face]
		var up: Vector3 = PlanetTerrain.FACE_UP[face]
		var first: int = vertices.size()

		for y in range(side):
			var v: float = _cube_coordinate(y, subdivisions)
			for x in range(side):
				var u: float = _cube_coordinate(x, subdivisions)
				vertices.append((forward + right * u + up * v).normalized())

		# right x up = forward on every face, so this winding is clockwise
		# seen from outside - Godot's front face.
		for y in range(subdivisions):
			for x in range(subdivisions):
				var a: int = first + y * side + x
				var c: int = a + side
				indices.append_array([c, c + 1, a + 1, c, a + 1, a])

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = vertices
	arrays[Mesh.ARRAY_INDEX] = indices

	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


## Grid line `i` of `subdivisions` across a cube face, -1..1, even in angle.
## The edges are pinned to exactly +-1 so neighbouring faces share vertices
## bit for bit and the seams cannot crack.
static func _cube_coordinate(i: int, subdivisions: int) -> float:
	if i == 0:
		return -1.0
	if i == subdivisions:
		return 1.0
	return tan((float(i) / subdivisions * 2.0 - 1.0) * PI / 4.0)


func build_surface() -> void:
	if surface_material != null:
		return

	var color_count: int = surface_color_count

	if color_count <= 0:
		color_count = PlanetSurface.roll_color_count(surface_seed)

	resolved_style = surface_style as PlanetSurface.Style

	if resolved_style == PlanetSurface.Style.AUTO:
		resolved_style = PlanetSurface.roll_style(surface_seed)

	surface_palette = PlanetSurface.generate_palette(surface_seed, color_count)
	surface_blobs = PlanetSurface.generate_blobs(
		surface_seed, surface_blob_count, surface_palette.size(), resolved_style
	)

	var in_3d: bool = _sphere_3d != null

	surface_material = ShaderMaterial.new()
	surface_material.shader = SURFACE_SHADER_3D if in_3d else SURFACE_SHADER
	surface_material.set_shader_parameter("blobs", surface_blobs)
	# 3D shading works in linear space; the 2D disc writes sRGB straight out.
	surface_material.set_shader_parameter("palette", palette_to_vectors(surface_palette, in_3d))
	surface_material.set_shader_parameter("blob_count", surface_blobs.size())
	surface_material.set_shader_parameter("warp_strength", surface_warp_strength)
	surface_material.set_shader_parameter("warp_frequency", surface_warp_frequency)
	surface_material.set_shader_parameter("edge_softness", surface_edge_softness)
	surface_material.set_shader_parameter("texture_scale", surface_texture_scale)
	surface_material.set_shader_parameter("texture_tint", surface_texture_tint)
	push_surface_textures()

	if in_3d:
		surface_material.set_shader_parameter("relief", surface_relief)
		surface_material.set_shader_parameter("ridge_frequency", surface_ridge_frequency)
		surface_material.set_shader_parameter(
			"height_blend", PlanetSurface.height_blend_for(surface_blobs.size())
		)
		_sphere_3d.material_override = surface_material
	else:
		# The sprite only needs to supply a quad and its UVs - the shader writes
		# COLOR outright and never samples TEXTURE, so which texture this is does
		# not matter. Reusing the glow avoids building a throwaway image.
		surface_sprite = Sprite2D.new()
		surface_sprite.texture = GLOW_TEXTURE
		surface_sprite.material = surface_material
		add_child(surface_sprite)

	push_surface_rotation()
	update_surface_scale()


## The cloud deck: the same mesh as the planet, pushed out past its peaks by
## the shader, drawn see-through on top (planet_clouds.gdshader).
func _build_clouds(p: Dictionary, cyclones: PackedVector4Array) -> void:
	var material := ShaderMaterial.new()
	material.shader = CLOUDS_SHADER
	# Over the plains, not the summits: only the odd peak ever reaches this
	# high, and a deck at full relief would hover visibly off the limb.
	material.set_shader_parameter("shell_height", p["relief"] * 0.45 + CLOUD_CLEARANCE)
	material.set_shader_parameter("pole_axis", surface_spin_axis)
	material.set_shader_parameter("seed_offset", float(surface_seed % 997) * 1.37)
	material.set_shader_parameter("cloud_color", p["cloud_color"])
	material.set_shader_parameter("cloud_coverage", p["clouds"])
	material.set_shader_parameter("cyclones", cyclones)
	material.set_shader_parameter("atmo_color", p["atmo"])
	material.set_shader_parameter("atmo_strength", p["atmo_strength"])

	_clouds_3d = MeshInstance3D.new()
	_clouds_3d.mesh = _sphere_3d.mesh
	_clouds_3d.material_override = material
	_clouds_3d.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_clouds_3d.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_sphere_3d.add_child(_clouds_3d)
	_update_visual_bounds()


## The air: an additive glow shell reaching ATMOSPHERE_DEPTH past the ground
## (planet_atmosphere.gdshader).
func _build_atmosphere(p: Dictionary) -> void:
	var material := ShaderMaterial.new()
	material.shader = ATMOSPHERE_SHADER
	material.set_shader_parameter("shell_radius", _atmosphere_shell_radius())
	# Thick enough near the ground to soften the planet's hard edge.
	material.set_shader_parameter("scale_height", ATMOSPHERE_DEPTH * 0.3)
	material.set_shader_parameter("atmo_color", p["atmo"])
	material.set_shader_parameter("strength", maxf(p["atmo_strength"], 0.4))

	_atmosphere_3d = MeshInstance3D.new()
	_atmosphere_3d.mesh = _sphere_3d.mesh
	_atmosphere_3d.material_override = material
	_atmosphere_3d.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_atmosphere_3d.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_sphere_3d.add_child(_atmosphere_3d)
	_update_visual_bounds()


func _atmosphere_shell_radius() -> float:
	return 1.0 + terrain_params.get("relief", 0.0) * 0.45 + ATMOSPHERE_DEPTH


## A stand-alone copy of this body's 3D look at unit radius - surface, cloud
## deck, air and corona sharing the live materials - for the planet catalog.
## The returned root's first child is the sphere; turn that to spin the globe.
func make_preview() -> Node3D:
	var root := Node3D.new()
	if _sphere_3d == null:
		return root

	var extent: float = CORONA_EXTENT if is_star else _atmosphere_shell_radius() + 0.1
	var bounds := AABB(-Vector3.ONE * extent, Vector3.ONE * extent * 2.0)

	var sphere := MeshInstance3D.new()
	sphere.mesh = _shared_sphere(true)
	sphere.material_override = _sphere_3d.material_override
	sphere.custom_aabb = bounds
	sphere.basis = _sphere_3d.basis.orthonormalized()
	root.add_child(sphere)

	for shell: MeshInstance3D in [_clouds_3d, _atmosphere_3d]:
		if shell == null:
			continue
		var copy := MeshInstance3D.new()
		copy.mesh = sphere.mesh
		copy.material_override = shell.material_override
		copy.custom_aabb = bounds
		sphere.add_child(copy)

	if is_star:
		var corona := MeshInstance3D.new()
		corona.mesh = _glow_3d.mesh
		corona.material_override = _glow_3d.material_override
		corona.scale = Vector3(CORONA_EXTENT * 2.0, 1.0, CORONA_EXTENT * 2.0)
		corona.position = Vector3(0.0, -1.5, 0.0)
		root.add_child(corona)

	return root


## Swaps the flat ball and its glow sprite for the star shaders.
func build_star() -> void:
	var seed_offset: float = float(surface_seed % 997) * 1.37
	# The photosphere churns on its own; spinning the ball as well only makes
	# the granules smear sideways.
	surface_spin_speed = 0.0

	var photosphere := ShaderMaterial.new()
	photosphere.shader = STAR_SHADER
	photosphere.set_shader_parameter("star_color", color)
	photosphere.set_shader_parameter("seed_offset", seed_offset)
	_sphere_3d.material_override = photosphere

	var corona := ShaderMaterial.new()
	corona.shader = CORONA_SHADER
	corona.set_shader_parameter("star_color", color)
	corona.set_shader_parameter("extent", CORONA_EXTENT)
	corona.set_shader_parameter("seed_offset", seed_offset)
	_glow_3d.material_override = corona
	update_surface_scale()


## Sets up the heightmap planet. Everything but the heightmap is known at once;
## the heightmap bakes on a worker thread (or comes from the cache), and until
## it lands the body stays the plain flat-coloured ball.
func build_terrain() -> void:
	if terrain_material != null:
		return

	var kind := terrain_kind as PlanetTerrain.Kind
	terrain_params = PlanetTerrain.resolve(kind, surface_seed, terrain_liquid_coverage)
	var p: Dictionary = terrain_params

	terrain_material = ShaderMaterial.new()
	terrain_material.shader = TERRAIN_SHADER
	terrain_material.set_shader_parameter("relief", p["relief"])
	terrain_material.set_shader_parameter("bump", p["bump"])
	terrain_material.set_shader_parameter("is_gas", PlanetTerrain.is_gas(kind))
	terrain_material.set_shader_parameter(
		"land_colors", palette_to_vectors(PackedColorArray(p["land"]), true)
	)
	terrain_material.set_shader_parameter("land_stops", PackedFloat32Array(p["stops"]))
	terrain_material.set_shader_parameter("liquid_shallow", p["shallow"])
	terrain_material.set_shader_parameter("liquid_deep", p["deep"])
	terrain_material.set_shader_parameter("liquid_emission", p["emission"])
	terrain_material.set_shader_parameter("liquid_gloss", p["gloss"])
	terrain_material.set_shader_parameter("rock_color", p["rock"])
	terrain_material.set_shader_parameter("dry_color", p["dry"])
	terrain_material.set_shader_parameter("dry_amount", p["dry_amount"])
	terrain_material.set_shader_parameter("strata", p["strata"])
	terrain_material.set_shader_parameter("slope_rock", p["slope_rock"])
	terrain_material.set_shader_parameter("cap_color", p["cap"])
	terrain_material.set_shader_parameter("cap_latitude", p["cap_latitude"])
	terrain_material.set_shader_parameter("pole_axis", surface_spin_axis)
	terrain_material.set_shader_parameter("atmo_color", p["atmo"])
	terrain_material.set_shader_parameter("atmo_strength", p["atmo_strength"])
	terrain_material.set_shader_parameter("atmo_haze", p["haze"])
	# The terrain needs the weather too, for the shadows the clouds cast.
	var cyclones: PackedVector4Array = PlanetTerrain.roll_cyclones(
		surface_seed, surface_spin_axis, p["clouds"]
	)
	terrain_material.set_shader_parameter("cloud_color", p["cloud_color"])
	terrain_material.set_shader_parameter("cloud_coverage", p["clouds"])
	terrain_material.set_shader_parameter("cyclones", cyclones)
	if p["clouds"] > 0.0:
		_build_clouds(p, cyclones)
	if p["clouds"] > 0.0 or PlanetTerrain.is_gas(kind):
		_build_atmosphere(p)
	terrain_material.set_shader_parameter("seed_offset", float(surface_seed % 997) * 1.37)

	_update_visual_bounds()
	update_surface_scale()

	var resolution: int = terrain_resolution
	var terrain_seed: int = surface_seed
	var pole: Vector3 = surface_spin_axis
	_terrain_key = PlanetTerrain.cache_key(kind, terrain_seed, resolution, pole, p)

	var cached: Dictionary = PlanetTerrain.cached(_terrain_key)
	if not cached.is_empty():
		_apply_terrain(cached)
		return

	# The task only ever sees copies and a holder of its own, never this node.
	var holder := {}
	var params: Dictionary = p.duplicate(true)
	_terrain_holder = holder
	_terrain_task = WorkerThreadPool.add_task(
		func() -> void:
			holder["data"] = PlanetTerrain.bake(kind, terrain_seed, resolution, pole, params),
		true,
		"Bake terrain %s" % body_name
	)


func _apply_terrain(data: Dictionary) -> void:
	if data.is_empty():
		return

	if not data.has("texture"):
		data["texture"] = PlanetTerrain.make_texture(data)
		# The GPU has its copy now; the CPU keeps only `faces`, for gameplay.
		data.erase("images")
		PlanetTerrain.store(_terrain_key, data)

	terrain_data = data
	var sea_level: float = data["sea_level"]
	terrain_material.set_shader_parameter("height_faces", data["texture"])
	terrain_material.set_shader_parameter("face_size", float(data["size"]))
	terrain_material.set_shader_parameter("has_liquid", sea_level >= 0.0)
	terrain_material.set_shader_parameter("sea_level", maxf(sea_level, 0.0))
	_sphere_3d.material_override = terrain_material


## Terrain height 0..1 under a planet-space direction (0 until the bake lands).
## Multiply by the kind's relief and the radius for a distance above the sea.
func terrain_height_at(planet_direction: Vector3) -> float:
	return PlanetTerrain.height_at(terrain_data, planet_direction)


## Whether a planet-space direction is under the sea (or lava, or acid).
func is_liquid_at(planet_direction: Vector3) -> bool:
	if terrain_data.is_empty() or terrain_data["sea_level"] < 0.0:
		return false

	return terrain_height_at(planet_direction) < terrain_data["sea_level"]


func palette_to_vectors(palette: PackedColorArray, linear: bool) -> PackedVector4Array:
	var vectors := PackedVector4Array()

	for entry in palette:
		var c: Color = entry.srgb_to_linear() if linear else entry
		vectors.append(Vector4(c.r, c.g, c.b, c.a))

	return vectors


func push_surface_textures() -> void:
	if surface_material == null:
		return

	var layers: int = 0
	if surface_textures != null:
		layers = surface_textures.get_layers()

	surface_material.set_shader_parameter("surface_textures", surface_textures)
	surface_material.set_shader_parameter("use_textures", layers > 0)
	surface_material.set_shader_parameter("texture_layers", maxi(layers, 1))
	surface_material.set_shader_parameter(
		"texture_offset", PlanetSurface.roll_texture_offset(surface_seed, layers)
	)


func push_surface_parameter(parameter: String, value: Variant) -> void:
	if surface_material == null:
		return

	surface_material.set_shader_parameter(parameter, value)


func push_surface_rotation() -> void:
	if _sphere_3d != null:
		_apply_sphere_transform()
		return

	if surface_material == null:
		return

	surface_material.set_shader_parameter(
		"planet_rotation",
		Vector4(
			surface_rotation.x,
			surface_rotation.y,
			surface_rotation.z,
			surface_rotation.w
		)
	)


func update_surface_scale() -> void:
	# Tracks the drawn radius rather than the physical one, because
	# solar_system.gd inflates visual_radius to keep distant bodies visible
	# when zoomed out.
	if _sphere_3d != null:
		_apply_sphere_transform()
		var glow_diameter: float = get_draw_radius() * (CORONA_EXTENT if is_star else 2.0) * 2.0
		_glow_3d.scale = Vector3(glow_diameter, 1.0, glow_diameter)
		_glow_3d.position = Vector3(0.0, -get_draw_radius() * (1.0 + _visual_relief()) - 1.0, 0.0)
		return

	if surface_sprite == null:
		return

	# Scale the sprite's own pixel size up to the planet's diameter.
	var diameter: float = get_draw_radius() * 2.0
	var texture_size := Vector2(
		maxf(1.0, float(surface_sprite.texture.get_width())),
		maxf(1.0, float(surface_sprite.texture.get_height()))
	)
	surface_sprite.scale = Vector2(diameter, diameter) / texture_size


func _apply_sphere_transform() -> void:
	_sphere_3d.basis = (VIEW_TO_WORLD * Basis(surface_rotation)).scaled(
		Vector3.ONE * get_draw_radius()
	)


func get_draw_radius() -> float:
	if visual_radius > 0.0:
		return visual_radius

	return radius


## Which blob is under a direction in planet space. For gameplay queries once
## a ship is landed; the shader runs the identical lookup per pixel, warp
## included, so this answer matches the colour actually drawn there.
func blob_under(planet_direction: Vector3) -> int:
	return PlanetSurface.blob_at(
		surface_blobs,
		planet_direction,
		surface_warp_strength,
		surface_warp_frequency
	)


## Which palette colour is under a direction, or -1 if this body has no
## surface. Cheap enough to call on placement; store the answer rather than
## asking again every frame.
func color_under(planet_direction: Vector3) -> int:
	return PlanetSurface.color_index_at(
		surface_blobs,
		planet_direction,
		surface_warp_strength,
		surface_warp_frequency
	)


## Every blob wearing a given palette colour. Spawning is usually a matter of
## walking these and placing inside each, rather than hunting the whole sphere.
func blobs_with_color(color_index: int) -> PackedInt32Array:
	return PlanetSurface.blobs_with_color(surface_blobs, color_index)


## A random spot on this body painted in `color_index`, or Vector3.ZERO when
## the colour is absent. Seed `rng` from the body seed and the blob to get the
## same layout every run without storing any of it.
func sample_point_in_color(color_index: int, rng: RandomNumberGenerator) -> Vector3:
	return PlanetSurface.sample_in_color(
		surface_blobs,
		color_index,
		rng,
		surface_warp_strength,
		surface_warp_frequency
	)


## Whether a surface direction is on the hemisphere facing the camera. Far-side
## points still project onto the disc, they are just behind the planet.
func is_surface_point_visible(planet_direction: Vector3) -> bool:
	return (surface_rotation * planet_direction).z > 0.0


## Where a surface direction lands on the drawn disc, in this body's own local
## space. Add global_position for a world coordinate.
func surface_point_to_local(planet_direction: Vector3) -> Vector2:
	var view: Vector3 = surface_rotation * planet_direction

	# 2D screen space points down while view space points up.
	return Vector2(view.x, -view.y) * get_draw_radius()


func _draw() -> void:
	var draw_radius: float = get_draw_radius()

	# In game the ball and its glow are 3D; only the rings stay 2D. They are
	# wider than the planet, so drawing them over the 3D view hides nothing.
	if _anchor_3d == null:
		_draw_glow(draw_radius)

		if surface_sprite == null:
			draw_circle(Vector2.ZERO, draw_radius, color)

	if show_soi and soi_radius > 0.0:
		draw_arc(
			Vector2.ZERO,
			soi_radius,
			0.0,
			TAU,
			128,
			Color(1, 1, 1, 0.15),
			soi_line_width
		)

	if fov_contact > 0:
		var ring_r: float = draw_radius + maxf(6.0, draw_radius * 0.12)
		var ring_color := (
			Color(1.0, 0.4, 0.25, 0.85) if fov_contact >= 2
			else Color(0.4, 0.9, 1.0, 0.75)
		)
		draw_arc(Vector2.ZERO, ring_r, 0.0, TAU, 64, ring_color, maxf(soi_line_width, 1.5))
		draw_arc(
			Vector2.ZERO,
			ring_r + maxf(4.0, soi_line_width * 2.0),
			0.0,
			TAU,
			64,
			Color(ring_color, ring_color.a * 0.35),
			maxf(soi_line_width * 0.7, 1.0)
		)


func _draw_glow(draw_radius: float) -> void:
	var diameter: float = draw_radius * 4.0
	var rect := Rect2(Vector2(-diameter, -diameter) * 0.5, Vector2(diameter, diameter))
	draw_texture_rect(GLOW_TEXTURE, rect, false, Color(color, 0.6))

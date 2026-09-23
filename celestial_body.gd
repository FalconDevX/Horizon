@tool
extends Node2D

const GLOW_TEXTURE := preload("res://textures/glow.png")
const SURFACE_SHADER := preload("res://planet_surface.gdshader")
const SURFACE_SHADER_3D := preload("res://planet_surface_3d.gdshader")

## Maps the surface's view space (x right, y up the screen, z toward the
## viewer) into the 3D world seen by the top-down camera (x right, -z up the
## screen, +y toward the camera). With this in the sphere's basis,
## surface_rotation keeps meaning exactly what it did on the flat disc, so
## is_surface_point_visible() and surface_point_to_local() need no changes.
const VIEW_TO_WORLD := Basis(Vector3(1, 0, 0), Vector3(0, 0, -1), Vector3(0, 1, 0))

const SPHERE_SEGMENTS_LOW := 32
const SPHERE_RINGS_LOW := 16
const SPHERE_SEGMENTS_HIGH := 192
const SPHERE_RINGS_HIGH := 96

## Shared by every body; each one just scales and rotates its instance.
static var _sphere_low: SphereMesh = null
static var _sphere_high: SphereMesh = null

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
# flat disc, which is what the sun wants.

## This planet's own seed. It is mixed with the world_seed on the scene root
## (solar_system.gd), so the same planet looks different in every world.
@export var surface_seed: int = 42

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

var velocity: Vector2 = Vector2.ZERO

## Orientation of the surface, mapping planet space into view space. This is
## the whole surface state: a point on the sphere plus a heading, in one value.
## Later this stops auto-spinning and gets driven by the landed ship instead.
var surface_rotation := Quaternion.IDENTITY

## What the surface was actually generated from: the world seed mixed with
## surface_seed.
var generation_seed: int = 0

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


func _ready() -> void:
	if not Engine.is_editor_hint():
		_build_visual_3d()

	if surface_blob_count > 0:
		build_surface()

	set_process(surface_material != null and not Engine.is_editor_hint())
	set_physics_process(_anchor_3d != null)


func _process(delta: float) -> void:
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

	(_glow_3d.material_override as StandardMaterial3D).albedo_color = Color(color, 0.6)


# The shader pushes vertices out past the unit sphere, which the mesh's own
# bounds know nothing about - without this the planet would be culled early.
func _update_visual_bounds() -> void:
	if _sphere_3d == null:
		return

	var extent: float = 1.0 + surface_relief
	_sphere_3d.custom_aabb = AABB(-Vector3.ONE * extent, Vector3.ONE * extent * 2.0)


## Swaps between a coarse and a fine sphere. solar_system.gd calls this from
## how big the body is on screen - a few-pixel dot does not need 18k vertices.
func set_detail_high(high: bool) -> void:
	if _sphere_3d == null:
		return

	var mesh: SphereMesh = _shared_sphere(high)
	if _sphere_3d.mesh != mesh:
		_sphere_3d.mesh = mesh


static func _shared_sphere(high: bool) -> SphereMesh:
	if high:
		if _sphere_high == null:
			_sphere_high = _make_sphere(SPHERE_SEGMENTS_HIGH, SPHERE_RINGS_HIGH)
		return _sphere_high

	if _sphere_low == null:
		_sphere_low = _make_sphere(SPHERE_SEGMENTS_LOW, SPHERE_RINGS_LOW)
	return _sphere_low


static func _make_sphere(segments: int, rings: int) -> SphereMesh:
	var sphere := SphereMesh.new()
	sphere.radius = 1.0
	sphere.height = 2.0
	sphere.radial_segments = segments
	sphere.rings = rings
	return sphere


func build_surface() -> void:
	if surface_material != null:
		return

	generation_seed = PlanetSurface.planet_seed(get_world_seed(), surface_seed)
	var color_count: int = surface_color_count

	if color_count <= 0:
		color_count = PlanetSurface.roll_color_count(generation_seed)

	resolved_style = surface_style as PlanetSurface.Style

	if resolved_style == PlanetSurface.Style.AUTO:
		resolved_style = PlanetSurface.roll_style(generation_seed)

	surface_palette = PlanetSurface.generate_palette(generation_seed, color_count)
	surface_blobs = PlanetSurface.generate_blobs(
		generation_seed, surface_blob_count, surface_palette.size(), resolved_style
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


## Generate the surface again from scratch, e.g. after the world seed changes.
## In game the new material replaces the old one on the 3D sphere.
func rebuild_surface() -> void:
	if surface_sprite != null:
		surface_sprite.queue_free()
		surface_sprite = null

	surface_material = null

	if surface_blob_count > 0:
		build_surface()


## Read from the scene root, which owns every planet in solar_system.tscn.
## A body with no world falls back to 0.
func get_world_seed() -> int:
	if owner == null:
		return 0

	var value: Variant = owner.get("world_seed")
	return int(value) if value is int else 0


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
		"texture_offset", PlanetSurface.roll_texture_offset(generation_seed, layers)
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
		var glow_diameter: float = get_draw_radius() * 4.0
		_glow_3d.scale = Vector3(glow_diameter, 1.0, glow_diameter)
		_glow_3d.position = Vector3(0.0, -get_draw_radius() * (1.0 + surface_relief) - 1.0, 0.0)
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

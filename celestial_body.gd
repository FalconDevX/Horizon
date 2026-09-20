@tool
extends Node2D

const GLOW_TEXTURE := preload("res://textures/glow.png")
const SURFACE_SHADER := preload("res://planet_surface.gdshader")

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

# Surface. A blob count of 0 means "no surface" - the body falls back to the
# flat disc, which is what the sun wants. Values are hardcoded per planet in
# solar_system.tscn for now; a generator will roll them later.
@export var surface_seed: int = 0

@export var surface_blob_count: int = 0

## Leave at 0 to roll the count from the seed - more colours is rarer, and is
## what the rarity tier reads. Set it above 0 only to pin a planet for testing.
@export var surface_color_count: int = 0

## Terrain layout. Auto rolls it from the seed; the rest pin a planet.
@export_enum("Auto", "Scattered", "Continents", "Bands")
var surface_style: int = 0

## Radians per second. Positive spins the surface toward screen-right.
@export var surface_spin_speed: float = 0.25

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

var surface_sprite: Sprite2D = null
var surface_material: ShaderMaterial = null


func _ready() -> void:
	if surface_blob_count > 0:
		build_surface()

	set_process(surface_sprite != null and not Engine.is_editor_hint())


func _process(delta: float) -> void:
	# Spinning toward screen-right means rolling about the screen-up axis, the
	# same way a globe turns. Composing rotations cannot push the surface off
	# the sphere, so there is nothing to correct afterwards.
	surface_rotation = (
		Quaternion(Vector3.UP, surface_spin_speed * delta) * surface_rotation
	).normalized()

	push_surface_rotation()


func build_surface() -> void:
	if surface_sprite != null:
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

	surface_material = ShaderMaterial.new()
	surface_material.shader = SURFACE_SHADER
	surface_material.set_shader_parameter("blobs", surface_blobs)
	surface_material.set_shader_parameter("palette", palette_to_vectors(surface_palette))
	surface_material.set_shader_parameter("blob_count", surface_blobs.size())
	surface_material.set_shader_parameter("warp_strength", surface_warp_strength)
	surface_material.set_shader_parameter("warp_frequency", surface_warp_frequency)
	surface_material.set_shader_parameter("edge_softness", surface_edge_softness)

	# The sprite only needs to supply a quad and its UVs - the shader writes
	# COLOR outright and never samples TEXTURE, so which texture this is does
	# not matter. Reusing the glow avoids building a throwaway image.
	surface_sprite = Sprite2D.new()
	surface_sprite.texture = GLOW_TEXTURE
	surface_sprite.material = surface_material
	add_child(surface_sprite)

	push_surface_rotation()
	update_surface_scale()


func palette_to_vectors(palette: PackedColorArray) -> PackedVector4Array:
	var vectors := PackedVector4Array()

	for entry in palette:
		vectors.append(Vector4(entry.r, entry.g, entry.b, entry.a))

	return vectors


func push_surface_parameter(parameter: String, value: Variant) -> void:
	if surface_material == null:
		return

	surface_material.set_shader_parameter(parameter, value)


func push_surface_rotation() -> void:
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
	if surface_sprite == null:
		return

	# Scale the sprite's own pixel size up to the planet's diameter. It tracks
	# the drawn radius rather than the physical one, because solar_system.gd
	# inflates visual_radius to keep distant bodies visible when zoomed out.
	var diameter: float = get_draw_radius() * 2.0
	var texture_size := Vector2(
		maxf(1.0, float(surface_sprite.texture.get_width())),
		maxf(1.0, float(surface_sprite.texture.get_height()))
	)
	surface_sprite.scale = Vector2(diameter, diameter) / texture_size


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


func _draw_glow(draw_radius: float) -> void:
	var diameter: float = draw_radius * 4.0
	var rect := Rect2(Vector2(-diameter, -diameter) * 0.5, Vector2(diameter, diameter))
	draw_texture_rect(GLOW_TEXTURE, rect, false, Color(color, 0.6))

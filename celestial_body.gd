@tool
extends Node2D

const GLOW_TEXTURE := preload("res://textures/glow.png")
const SURFACE_SHADER := preload("res://planet_surface.gdshader")

const LIGHT_GROUP := &"light_sources"

## Screen-space heading of the light when there is no light source, as in the
## editor with a scene that has no sun: from the upper left.
const DEFAULT_LIGHT_HEADING := Vector2(-0.70710678, -0.70710678)

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
		push_pole_axis()

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

## Draw terrain textures over the flat palette colours.
@export var surface_textured := true:
	set(value):
		surface_textured = value
		push_surface_textures()

## Grayscale terrain textures, one layer per PlanetSurface.Terrain in enum
## order (ocean, sand, mountains). Leave empty to use the noise-generated set.
@export var surface_textures: Texture2DArray = null:
	set(value):
		surface_textures = value
		push_surface_textures()

## How many times a texture repeats across the planet.
@export_range(0.5, 32.0, 0.1) var surface_texture_scale: float = 4.0:
	set(value):
		surface_texture_scale = value
		push_surface_parameter("texture_scale", value)

## 0.0 shows flat palette colours, 1.0 the full colour ramp.
@export_range(0.0, 1.0, 0.01) var surface_texture_strength: float = 1.0:
	set(value):
		surface_texture_strength = value
		push_surface_parameter("texture_strength", value)

## Shade each region by a procedural height field seeded from the planet's
## seed, so every planet gets its own relief. Rendering only - gameplay lookups
## never see it.
@export var surface_elevation := true:
	set(value):
		surface_elevation = value
		push_surface_parameter("use_elevation", value)

## Scale of the relief. Higher means smaller, more numerous features.
@export_range(0.5, 8.0, 0.1) var surface_elevation_frequency: float = 2.0:
	set(value):
		surface_elevation_frequency = value
		push_surface_parameter("elevation_frequency", value)

## Noise layers. Each adds detail at twice the frequency of the last.
@export_range(1, 8) var surface_elevation_octaves: int = 5:
	set(value):
		surface_elevation_octaves = value
		push_surface_parameter("elevation_octaves", value)

## How much the tiled texture adds on top of the height field, as fine grain.
@export_range(0.0, 1.0, 0.01) var surface_texture_detail: float = 0.6:
	set(value):
		surface_texture_detail = value
		push_surface_parameter("texture_detail", value)

## Light the surface from the nearest node in LIGHT_GROUP (the sun) instead of
## only darkening the rim.
@export var surface_lit := true:
	set(value):
		surface_lit = value
		push_surface_parameter("use_lighting", value)

## Brightness of the night side. 0.0 is black.
@export_range(0.0, 1.0, 0.01) var surface_ambient: float = 0.15:
	set(value):
		surface_ambient = value
		push_surface_parameter("ambient_light", value)

## How far the light leans out of the orbital plane towards the camera. The
## sun sits in the plane, so 0 lights exactly half the disc; tilting it keeps
## more of the surface readable. 90 lights the whole face.
@export_range(0.0, 90.0, 1.0, "degrees") var surface_light_tilt: float = 25.0:
	set(value):
		surface_light_tilt = value
		push_light_direction()

## How far relief tilts the lighting, so mountains and dunes catch the light.
## 0.0 is flat. Needs surface_elevation.
@export_range(0.0, 0.5, 0.005) var surface_bump_strength: float = 0.12:
	set(value):
		surface_bump_strength = value
		push_surface_parameter("bump_strength", value)

## How far out from the coast the water reaches full depth, in the same units
## as surface_edge_softness. Wider means broader shallows.
@export_range(0.01, 0.3, 0.005) var surface_ocean_shelf: float = 0.06:
	set(value):
		surface_ocean_shelf = value
		push_surface_parameter("ocean_shelf_width", value)

## Brightness of the sun's reflection on open water.
@export_range(0.0, 1.0, 0.01) var surface_ocean_glint: float = 0.5:
	set(value):
		surface_ocean_glint = value
		push_surface_parameter("ocean_glint", value)

## Polar ice, sea ice, snowy peaks and tundra, from latitude and altitude.
@export var surface_biomes := true:
	set(value):
		surface_biomes = value
		push_surface_parameter("use_biomes", value)

## Share of the surface under polar ice at sea level; peaks freeze further
## from the poles. 0.0 means no ice at all, for hot worlds.
@export_range(0.0, 1.0, 0.01) var surface_polar_cap: float = 0.12:
	set(value):
		surface_polar_cap = value
		push_surface_parameter("polar_cap", value)

var velocity: Vector2 = Vector2.ZERO

## What lights this body's surface. Found through LIGHT_GROUP on ready.
var light_source: Node2D = null

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

## What each palette slot is made of, as PlanetSurface.Terrain values, indexed
## by slot like surface_palette. A blob's terrain is surface_terrain[blob.w] -
## every blob in a slot shares it, so nothing is stored per blob.
var surface_terrain := PackedInt32Array()

var surface_sprite: Sprite2D = null
var surface_material: ShaderMaterial = null


func _ready() -> void:
	if surface_blob_count > 0:
		light_source = get_tree().get_first_node_in_group(LIGHT_GROUP) as Node2D
		build_surface()

	set_process(surface_sprite != null and not Engine.is_editor_hint())


func _process(delta: float) -> void:
	# Composing rotations cannot push the surface off the sphere, so there is
	# nothing to correct afterwards regardless of how surface_spin_axis tilts.
	surface_rotation = (
		Quaternion(surface_spin_axis, surface_spin_speed * delta) * surface_rotation
	).normalized()

	push_surface_rotation()
	push_light_direction()


func build_surface() -> void:
	if surface_sprite != null:
		return

	generation_seed = PlanetSurface.planet_seed(get_world_seed(), surface_seed)
	var color_count: int = surface_color_count

	if color_count <= 0:
		color_count = PlanetSurface.roll_color_count(generation_seed)

	resolved_style = surface_style as PlanetSurface.Style

	if resolved_style == PlanetSurface.Style.AUTO:
		resolved_style = PlanetSurface.roll_style(generation_seed)

	surface_palette = PlanetSurface.generate_palette(generation_seed, color_count)
	surface_terrain = PlanetSurface.roll_slot_terrain(generation_seed, surface_palette.size())
	surface_blobs = PlanetSurface.generate_blobs(
		generation_seed, surface_blob_count, surface_palette.size(), resolved_style
	)

	surface_material = ShaderMaterial.new()
	surface_material.shader = SURFACE_SHADER
	surface_material.set_shader_parameter("blobs", surface_blobs)
	surface_material.set_shader_parameter("palette", palette_to_vectors(surface_palette))
	surface_material.set_shader_parameter("blob_count", surface_blobs.size())
	surface_material.set_shader_parameter("warp_strength", surface_warp_strength)
	surface_material.set_shader_parameter("warp_frequency", surface_warp_frequency)
	surface_material.set_shader_parameter("edge_softness", surface_edge_softness)
	surface_material.set_shader_parameter("texture_scale", surface_texture_scale)
	surface_material.set_shader_parameter("texture_strength", surface_texture_strength)
	surface_material.set_shader_parameter("use_elevation", surface_elevation)
	surface_material.set_shader_parameter(
		"elevation_offset", PlanetSurface.elevation_offset(generation_seed)
	)
	surface_material.set_shader_parameter("elevation_frequency", surface_elevation_frequency)
	surface_material.set_shader_parameter("elevation_octaves", surface_elevation_octaves)
	surface_material.set_shader_parameter("texture_detail", surface_texture_detail)
	surface_material.set_shader_parameter("use_lighting", surface_lit)
	surface_material.set_shader_parameter("ambient_light", surface_ambient)
	surface_material.set_shader_parameter("bump_strength", surface_bump_strength)
	surface_material.set_shader_parameter("ocean_shelf_width", surface_ocean_shelf)
	surface_material.set_shader_parameter("ocean_glint", surface_ocean_glint)
	surface_material.set_shader_parameter("use_biomes", surface_biomes)
	surface_material.set_shader_parameter("polar_cap", surface_polar_cap)
	push_pole_axis()
	push_surface_ramps()
	push_surface_textures()
	push_light_direction()

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


func palette_to_vectors(palette: PackedColorArray) -> PackedVector4Array:
	var vectors := PackedVector4Array()

	for entry in palette:
		vectors.append(Vector4(entry.r, entry.g, entry.b, entry.a))

	return vectors


## Per-slot terrain layer and colour ramp. The palette colour is the ramp's
## middle stop and is already pushed as `palette`, so only the ends go here.
func push_surface_ramps() -> void:
	if surface_material == null:
		return

	var terrain_layers := PackedFloat32Array()
	var low := PackedVector4Array()
	var high := PackedVector4Array()

	for slot in range(surface_palette.size()):
		var terrain: int = surface_terrain[slot] if slot < surface_terrain.size() else 0
		var ends: Array[Color] = PlanetSurface.ramp_ends(surface_palette[slot], terrain)
		terrain_layers.append(float(terrain))
		low.append(Vector4(ends[0].r, ends[0].g, ends[0].b, 1.0))
		high.append(Vector4(ends[1].r, ends[1].g, ends[1].b, 1.0))

	surface_material.set_shader_parameter("slot_terrain", terrain_layers)
	surface_material.set_shader_parameter("ramp_low", low)
	surface_material.set_shader_parameter("ramp_high", high)


func push_surface_textures() -> void:
	if surface_material == null:
		return

	var textures: Texture2DArray = surface_textures
	if textures == null and surface_textured:
		textures = PlanetSurface.default_material_textures()

	surface_material.set_shader_parameter("surface_textures", textures)
	surface_material.set_shader_parameter(
		"use_textures", surface_textured and textures != null
	)


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


## The spin axis in planet space, which is where the poles are. Spinning is a
## rotation about this very axis, so it stays put however far the planet
## turns and only needs pushing when the axis itself changes.
func push_pole_axis() -> void:
	if surface_material == null:
		return

	surface_material.set_shader_parameter(
		"pole_axis", surface_rotation.inverse() * surface_spin_axis
	)


func push_light_direction() -> void:
	if surface_material == null:
		return

	var heading: Vector2 = DEFAULT_LIGHT_HEADING

	if light_source != null and is_instance_valid(light_source):
		var offset: Vector2 = light_source.global_position - global_position
		if offset.length_squared() > 0.0001:
			heading = offset.normalized()

	# 2D screen space points down while view space points up.
	var tilt: float = deg_to_rad(surface_light_tilt)
	var direction := Vector3(
		heading.x * cos(tilt),
		-heading.y * cos(tilt),
		sin(tilt)
	)

	surface_material.set_shader_parameter("light_direction", direction)


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


## Terrain (a PlanetSurface.Terrain value) of a palette slot, or -1.
func terrain_of_slot(slot: int) -> int:
	if slot < 0 or slot >= surface_terrain.size():
		return -1

	return surface_terrain[slot]


## Terrain of one blob, or -1. Read through its slot - the slot is the address,
## and colour and terrain are both properties of it.
func terrain_of_blob(blob_index: int) -> int:
	if blob_index < 0 or blob_index >= surface_blobs.size():
		return -1

	return terrain_of_slot(int(surface_blobs[blob_index].w))


## Terrain under a direction in planet space, or -1 if this body has no surface.
## Same warp-aware lookup as color_under(), so it matches what is drawn.
func terrain_under(planet_direction: Vector3) -> int:
	return terrain_of_slot(color_under(planet_direction))


## Every palette slot made of a given terrain. With four or more colours the
## opposite land spans several slots, so this can return more than one.
func slots_with_terrain(terrain: int) -> PackedInt32Array:
	var slots := PackedInt32Array()

	for slot in range(surface_terrain.size()):
		if surface_terrain[slot] == terrain:
			slots.append(slot)

	return slots


## Every blob made of a given terrain, across all slots that share it.
func blobs_with_terrain(terrain: int) -> PackedInt32Array:
	var blobs := PackedInt32Array()

	for i in range(surface_blobs.size()):
		if terrain_of_blob(i) == terrain:
			blobs.append(i)

	return blobs


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

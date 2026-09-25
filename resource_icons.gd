class_name ResourceIcons
extends RefCounted

## Resources drawn as icons: each type's showcase model (the same mesh and
## shader as on a planet) in a small scene of its own, lit by a fixed light
## instead of the sun so it looks the same in any scene. `icon(id)` hands out a
## still Texture2D for plain UI (the tech tree); `make_stage(id)` builds a
## scene the caller owns and can animate (InventoryView spins its models).

## Towards the light, world space: up, and from the camera's left.
const LIGHT := Vector3(-0.55, 0.8, 0.45)
const ICON_PIXELS := 96
## How long a still icon keeps rendering before it is frozen - long enough for
## its shader to compile and draw.
const SETTLE_TIME := 0.6

static var _icons: Dictionary = {}
static var _holder: Node = null


## A still picture of the type, rendered once and cached.
static func icon(id: StringName) -> Texture2D:
	if _icons.has(id) and is_instance_valid(_icons[id]):
		return (_icons[id] as SubViewport).get_texture()
	if not ResourceDeposits.TYPES.has(id):
		return null
	var stage: Dictionary = make_stage(id, ICON_PIXELS)
	var viewport: SubViewport = stage["viewport"]
	_holder_node().add_child(viewport)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	(Engine.get_main_loop() as SceneTree).create_timer(SETTLE_TIME).timeout.connect(
		func() -> void:
			if is_instance_valid(viewport):
				viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	)
	_icons[id] = viewport
	return viewport.get_texture()


## The type's name as the game shows it.
static func display_name(id: StringName) -> String:
	return ResourceDeposits.TYPES.get(id, {}).get("name", String(id).capitalize())


static func color(id: StringName) -> Color:
	return ResourceDeposits.TYPES.get(id, {}).get("color", Color.WHITE)


## A SubViewport (not yet in the tree) holding the model, lit and framed:
## {viewport, pivot} - turn `pivot` to spin the model about its middle.
static func make_stage(id: StringName, pixels: int) -> Dictionary:
	var viewport := SubViewport.new()
	viewport.own_world_3d = true
	viewport.transparent_bg = true
	viewport.msaa_3d = Viewport.MSAA_4X
	viewport.size = Vector2i(pixels, pixels)

	var root := Node3D.new()
	viewport.add_child(root)
	var environment := Environment.new()
	environment.background_mode = Environment.BG_CLEAR_COLOR
	environment.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	var world_environment := WorldEnvironment.new()
	world_environment.environment = environment
	root.add_child(world_environment)

	var model: MeshInstance3D = ResourceDeposits.make_showcase(id)
	(model.material_override as ShaderMaterial).set_shader_parameter("fixed_light", LIGHT)
	# Turned about the middle of its bounds, not its foot.
	var bounds: AABB = model.mesh.get_aabb()
	model.position = -bounds.get_center()
	var pivot := Node3D.new()
	pivot.add_child(model)
	root.add_child(pivot)

	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = maxf(bounds.size.y, maxf(bounds.size.x, bounds.size.z)) * 1.35
	camera.near = 1.0
	camera.far = 200.0
	root.add_child(camera)
	# A little from above and in front. Set directly: look_at needs the tree.
	var eye := Vector3(0.0, 1.6, 4.0) * 10.0
	camera.transform = Transform3D(Basis.looking_at(-eye, Vector3.UP), eye)
	return {"viewport": viewport, "pivot": pivot}


static func _holder_node() -> Node:
	if _holder == null or not is_instance_valid(_holder):
		_holder = Node.new()
		_holder.name = "ResourceIcons"
		# Deferred: the first icons are asked for while a scene is still being
		# set up, when the root takes no new children.
		(Engine.get_main_loop() as SceneTree).root.add_child.call_deferred(_holder)
	return _holder

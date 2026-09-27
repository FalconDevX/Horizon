extends SceneTree

## A fast reel of planets: for every planet of solar_system.tscn across a few
## world seeds, a short shot - the camera pushing in while the surface turns -
## saved frame by frame for ffmpeg. Run with rendering (not --headless - the
## terrain bakes on the GPU):
##
##   godot --path . --resolution 1280x720 -s scripts/tools/planet_reel.gd -- --worlds 2 --out C:/tmp/reel
##   ffmpeg -framerate 30 -i C:/tmp/reel/%05d.png -pix_fmt yuv420p reel.mp4
##
## Options: --worlds N (default 2), --seed S (first world seed, default
## random), --frames F per planet (default 14), --out DIR (default
## user://planet_reel).

const SETTLE_FRAMES := 6
const BAKE_TIMEOUT_MS := 60000
## Surface time added per frame: the planets spin visibly within a shot.
const SPIN_PER_FRAME := 0.35
## Framing at the start and the end of a shot (planet diameters across the
## screen height): a quick push in.
const FRAME_FROM := 1.6
const FRAME_TO := 1.15

var world: Node
var caption: Label
var out_dir := "user://planet_reel"
var seeds: Array[int] = []
var frames_per_planet := 14

var world_index := 0
var planet_index := 0
var shot_frame := -SETTLE_FRAMES
var frame_number := 0
var waiting_for_bake := true
var bake_started_ms := 0
var surface_time := 0.0


func _initialize() -> void:
	var worlds := 2
	var first_seed: int = randi()
	var args: PackedStringArray = OS.get_cmdline_user_args()
	for i in range(args.size() - 1):
		match args[i]:
			"--worlds":
				worlds = maxi(1, args[i + 1].to_int())
			"--seed":
				first_seed = args[i + 1].to_int()
			"--frames":
				frames_per_planet = maxi(1, args[i + 1].to_int())
			"--out":
				out_dir = args[i + 1]
	for i in range(worlds):
		seeds.append(first_seed + i)
	DirAccess.make_dir_recursive_absolute(out_dir)

	world = load("res://solar_system.tscn").instantiate()
	world.set("world_seed", seeds[0])
	root.add_child(world)

	var layer := CanvasLayer.new()
	layer.layer = 100
	caption = Label.new()
	caption.add_theme_font_size_override("font_size", 30)
	caption.add_theme_color_override("font_outline_color", Color.BLACK)
	caption.add_theme_constant_override("outline_size", 8)
	layer.add_child(caption)
	root.add_child(layer)
	bake_started_ms = Time.get_ticks_msec()


func _process(_delta: float) -> bool:
	if world.planets.is_empty():
		return false
	world.get_node("HUD").visible = false
	world.camera_follow_ship = false
	var loading: CanvasLayer = world.get("loading_screen")
	if loading != null:
		loading.visible = false
	# Planets only: no orbit lines (Alt) and no enemy markers in shot.
	world.orbit_overlays_on = false
	world._set_space_overlays_visible(false)
	for child in world.get_children():
		if child is Enemy:
			(child as Enemy).visible = false

	if waiting_for_bake:
		return _wait_for_bakes()

	var planets: Array = _shootable()
	if planet_index >= planets.size():
		return _next_world()
	var planet: Node2D = planets[planet_index]
	surface_time += SPIN_PER_FRAME
	RenderingServer.global_shader_parameter_set("planet_time", surface_time)
	_frame(planet, clampf(float(shot_frame) / frames_per_planet, 0.0, 1.0))
	# The first frames of a shot let the camera and the planet settle.
	if shot_frame >= 1:
		var image: Image = root.get_texture().get_image()
		image.save_png("%s/%05d.png" % [out_dir, frame_number])
		frame_number += 1
	shot_frame += 1
	if shot_frame > frames_per_planet:
		planet_index += 1
		shot_frame = -SETTLE_FRAMES
	return false


## Planets worth a shot: the ones this system has, with a surface (not the
## black hole).
func _shootable() -> Array:
	return world.present_planets().filter(func(p: Node2D) -> bool: return int(p.get("terrain_kind")) != 0)


func _next_world() -> bool:
	world_index += 1
	if world_index >= seeds.size():
		print("Reel: %d frames in %s" % [frame_number, ProjectSettings.globalize_path(out_dir)])
		return true
	planet_index = 0
	shot_frame = -SETTLE_FRAMES
	waiting_for_bake = true
	bake_started_ms = Time.get_ticks_msec()
	world.set_world_seed(seeds[world_index])
	return false


func _wait_for_bakes() -> bool:
	for planet in world.planets:
		if not planet.call("is_surface_ready"):
			if Time.get_ticks_msec() - bake_started_ms > BAKE_TIMEOUT_MS:
				push_error("planet_reel: bakes did not land - is this running --headless?")
				return true
			return false
	print("World %d: baked in %d ms" % [seeds[world_index], Time.get_ticks_msec() - bake_started_ms])
	waiting_for_bake = false
	return false


## Camera on `planet`, `t` (0..1) of the way through its push in.
func _frame(planet: Node2D, t: float) -> void:
	var view: Vector2 = root.get_visible_rect().size
	var eased: float = 1.0 - pow(1.0 - t, 3.0)
	var across: float = lerpf(FRAME_FROM, FRAME_TO, eased)
	var zoom: float = view.y / (float(planet.get("radius")) * 2.0 * across)
	world.camera_zoom = zoom
	world.camera.zoom = Vector2(zoom, zoom)
	world.camera.position = planet.global_position
	world.camera.reset_smoothing()
	world.camera.reset_physics_interpolation()
	caption.position = Vector2(40.0, view.y - 80.0)
	caption.text = String(planet.get("body_name")).to_upper()

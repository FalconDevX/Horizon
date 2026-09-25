extends SceneTree

## Photographs every planet of solar_system.tscn across several world seeds,
## for checking procedural generation by eye. Run with rendering (not
## --headless - the terrain bakes on the GPU):
##
##   godot --path . -s scripts/tools/planet_gallery.gd -- --worlds 6 --seed 1000
##
## Options: --worlds N (default 4), --seed S (first world seed, default random;
## world i uses S + i), --chaos C (default: the scene's planet_chaos),
## --out DIR (default user://planet_gallery). Writes one captioned close-up per
## planet per world and a contact sheet, gallery.png, with a row per world.

const KIND_NAMES: Array[String] = [
	"None", "Terran", "Desert", "Volcanic", "Ice", "Barren", "Toxic", "Gas giant", "Ice giant",
	"Frozen", "Slime", "Occult", "Gloom", "Bloom", "Oasis",
	"Lotus", "Swirl", "Rings", "Quake", "Fractal", "Meridian",
]
const TILE := 360
const SETTLE_FRAMES := 10
const BAKE_TIMEOUT_MS := 60000

var world: Node
var caption: Label
var out_dir := "user://planet_gallery"
var seeds: Array[int] = []
var chaos := -1.0

var world_index := 0
var planet_index := 0
var wait_frames := 0
var waiting_for_bake := true
var bake_started_ms := 0
var rows: Array = []


func _initialize() -> void:
	var worlds := 4
	var first_seed: int = randi()
	var args: PackedStringArray = OS.get_cmdline_user_args()
	for i in range(args.size() - 1):
		match args[i]:
			"--worlds":
				worlds = maxi(1, args[i + 1].to_int())
			"--seed":
				first_seed = args[i + 1].to_int()
			"--chaos":
				chaos = args[i + 1].to_float()
			"--out":
				out_dir = args[i + 1]

	for i in range(worlds):
		seeds.append(first_seed + i)
	DirAccess.make_dir_recursive_absolute(out_dir)

	world = load("res://solar_system.tscn").instantiate()
	world.set("world_seed", seeds[0])
	if chaos >= 0.0:
		world.set("planet_chaos", chaos)
	root.add_child(world)

	var layer := CanvasLayer.new()
	layer.layer = 100
	caption = Label.new()
	caption.add_theme_font_size_override("font_size", 34)
	caption.add_theme_color_override("font_outline_color", Color.BLACK)
	caption.add_theme_constant_override("outline_size", 8)
	layer.add_child(caption)
	root.add_child(layer)

	rows.append([])
	bake_started_ms = Time.get_ticks_msec()


func _process(_delta: float) -> bool:
	if world.planets.is_empty():
		return false

	world.get_node("HUD").visible = false
	world.camera_follow_ship = false
	# The loading screen fades out on its own schedule; it must not be in shot.
	var loading: CanvasLayer = world.get("loading_screen")
	if loading != null:
		loading.visible = false

	if waiting_for_bake:
		return _wait_for_bakes()

	var planet: Node2D = world.planets[planet_index]
	_frame(planet)
	wait_frames -= 1
	if wait_frames > 0:
		return false

	_capture(planet)
	planet_index += 1
	wait_frames = SETTLE_FRAMES
	if planet_index < world.planets.size():
		return false

	world_index += 1
	if world_index >= seeds.size():
		_save_sheet()
		return true

	rows.append([])
	planet_index = 0
	waiting_for_bake = true
	bake_started_ms = Time.get_ticks_msec()
	world.set_world_seed(seeds[world_index])
	return false


func _wait_for_bakes() -> bool:
	for planet in world.planets:
		# Bodies with no heightmap (the black hole) never bake - don't wait on them.
		if int(planet.get("terrain_kind")) != 0 and planet.get("terrain_data").is_empty():
			if Time.get_ticks_msec() - bake_started_ms > BAKE_TIMEOUT_MS:
				push_error("planet_gallery: bakes did not land - is this running --headless?")
				return true
			return false

	print("World %d: baked in %d ms" % [seeds[world_index], Time.get_ticks_msec() - bake_started_ms])
	waiting_for_bake = false
	planet_index = 0
	wait_frames = SETTLE_FRAMES
	return false


func _frame(planet: Node2D) -> void:
	var view: Vector2 = root.get_visible_rect().size
	var zoom: float = view.y / (float(planet.get("radius")) * 2.0 * 1.35)
	world.camera_zoom = zoom
	world.camera.zoom = Vector2(zoom, zoom)
	world.camera.position = planet.global_position
	world.camera.reset_smoothing()
	world.camera.reset_physics_interpolation()

	var side: float = view.y * 0.8
	caption.position = Vector2((view.x - side) * 0.5 + 16.0, (view.y - side) * 0.5 + 12.0)
	caption.text = "%s\n%s\nworld %d" % [planet.get("body_name"), _kind_label(planet), seeds[world_index]]


func _kind_label(planet: Node2D) -> String:
	var kind: String = KIND_NAMES[int(planet.get("terrain_kind"))]
	var params: Dictionary = planet.get("terrain_params")
	if params.get("variant", "") == "cryo":
		return "Cryovolcanic"
	return kind


func _capture(planet: Node2D) -> void:
	var image: Image = root.get_texture().get_image()
	var size: Vector2i = image.get_size()
	var side: int = int(size.y * 0.8)
	var shot: Image = image.get_region(Rect2i((size.x - side) / 2, (size.y - side) / 2, side, side))
	shot.save_png("%s/world%d_%s.png" % [out_dir, seeds[world_index], String(planet.get("body_name")).to_lower()])

	shot.resize(TILE, TILE, Image.INTERPOLATE_LANCZOS)
	shot.convert(Image.FORMAT_RGBA8)
	rows[world_index].append(shot)


func _save_sheet() -> void:
	var columns: int = rows[0].size()
	var sheet := Image.create(columns * TILE, rows.size() * TILE, false, Image.FORMAT_RGBA8)
	for row in range(rows.size()):
		for column in range(rows[row].size()):
			sheet.blit_rect(rows[row][column], Rect2i(0, 0, TILE, TILE), Vector2i(column * TILE, row * TILE))
	var path := "%s/gallery.png" % out_dir
	sheet.save_png(path)
	print("Gallery: %s" % ProjectSettings.globalize_path(path))

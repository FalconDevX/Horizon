extends SceneTree

## A highlights reel for a trailer, frame by frame for ffmpeg: planets, black
## holes and anomalies, enemy craft in flight, the galaxy map and the ship
## builder. Looks for a world with a black hole or anomaly first. Run with
## rendering (not --headless):
##
##   godot --path . --resolution 1280x720 -s scripts/tools/highlights_reel.gd -- --out C:/tmp/hl
##   ffmpeg -framerate 30 -i C:/tmp/hl/%05d.png -pix_fmt yuv420p highlights.mp4
##
## Options: --seed S (first world tried, default random), --out DIR.

const BAKE_TIMEOUT_MS := 60000
const SETTLE_FRAMES := 6
const WORLD_TRIES := 8
const PLANET_SHOTS := 8
const PLANET_FRAMES := 14
const ODDITY_FRAMES := 50
const ENEMY_FRAMES := 90
const WINDOW_FRAMES := 60

var world: Node
var out_dir := "user://highlights_reel"
var seed_value := 0
var tries := 0
var frame_number := 0
var surface_time := 0.0
## The shots still to take: {kind, target, frames, done}.
var shots: Array[Dictionary] = []
var settle := SETTLE_FRAMES
var waiting := true
var bake_started_ms := 0
var enemies: Array[Enemy] = []


func _initialize() -> void:
	seed_value = randi()
	var args: PackedStringArray = OS.get_cmdline_user_args()
	for i in range(args.size() - 1):
		match args[i]:
			"--seed":
				seed_value = args[i + 1].to_int()
			"--out":
				out_dir = args[i + 1]
	DirAccess.make_dir_recursive_absolute(out_dir)
	world = load("res://solar_system.tscn").instantiate()
	world.set("world_seed", seed_value)
	root.add_child(world)
	bake_started_ms = Time.get_ticks_msec()


func _process(_delta: float) -> bool:
	if world.planets.is_empty():
		return false
	var loading: CanvasLayer = world.get("loading_screen")
	if loading != null:
		loading.visible = false
	var tutorial: Node = world.find_child("TutorialPanel", true, false)
	if tutorial != null:
		tutorial.queue_free()
	world.orbit_overlays_on = false
	world._set_space_overlays_visible(false)
	world.camera_follow_ship = false
	world.camera_follow_body = null

	if waiting:
		return _wait_for_world()
	if shots.is_empty():
		print("Highlights: %d frames in %s" % [frame_number, ProjectSettings.globalize_path(out_dir)])
		return true

	var shot: Dictionary = shots[0]
	var t: float = float(shot["done"]) / float(shot["frames"])
	surface_time += 0.25
	RenderingServer.global_shader_parameter_set("planet_time", surface_time)
	_set_up(shot, t)
	if settle > 0:
		settle -= 1
		return false
	root.get_texture().get_image().save_png("%s/%05d.png" % [out_dir, frame_number])
	frame_number += 1
	shot["done"] = int(shot["done"]) + 1
	if int(shot["done"]) >= int(shot["frames"]):
		_tear_down(shot)
		shots.pop_front()
		settle = SETTLE_FRAMES
	return false


## Waits for the bakes; a world with no black hole or anomaly is swapped for
## the next seed (up to WORLD_TRIES), then the shot list is made.
func _wait_for_world() -> bool:
	for planet in world.planets:
		if not planet.call("is_surface_ready"):
			if Time.get_ticks_msec() - bake_started_ms > BAKE_TIMEOUT_MS:
				push_error("highlights_reel: bakes did not land - is this running --headless?")
				return true
			return false
	var oddities: Array = world.present_planets().filter(
		func(p: Node2D) -> bool: return p.get("is_black_hole") or p.get("is_anomaly")
	)
	if oddities.is_empty() and tries < WORLD_TRIES:
		tries += 1
		seed_value += 1
		bake_started_ms = Time.get_ticks_msec()
		world.set_world_seed(seed_value)
		return false
	waiting = false
	print("World %d: %d black holes / anomalies" % [seed_value, oddities.size()])
	var surfaced: Array = world.present_planets().filter(
		func(p: Node2D) -> bool: return int(p.get("terrain_kind")) != 0 and not p.get("is_anomaly")
	)
	for i in mini(PLANET_SHOTS, surfaced.size()):
		shots.append({"kind": "planet", "target": surfaced[i], "frames": PLANET_FRAMES, "done": 0})
	for body: Node2D in oddities:
		shots.append({"kind": "oddity", "target": body, "frames": ODDITY_FRAMES, "done": 0})
	shots.append({"kind": "enemies", "target": null, "frames": ENEMY_FRAMES, "done": 0})
	shots.append({"kind": "map", "target": null, "frames": WINDOW_FRAMES, "done": 0})
	shots.append({"kind": "builder", "target": null, "frames": WINDOW_FRAMES, "done": 0})
	return false


func _set_up(shot: Dictionary, t: float) -> void:
	var hud: CanvasLayer = world.get_node("HUD")
	var eased: float = 1.0 - pow(1.0 - t, 3.0)
	match String(shot["kind"]):
		"planet":
			hud.visible = false
			_frame_body(shot["target"], lerpf(1.6, 1.15, eased))
		"oddity":
			hud.visible = false
			_frame_body(shot["target"], lerpf(4.0, 2.2, eased))
		"enemies":
			hud.visible = false
			if enemies.is_empty():
				_spawn_enemies()
			# Follow the pack at true scale.
			var centre := Vector2.ZERO
			var alive := 0
			for enemy: Enemy in enemies:
				if is_instance_valid(enemy):
					centre += enemy.global_position
					alive += 1
			if alive > 0:
				_camera(centre / alive, lerpf(1.2, 2.2, eased))
		"map":
			hud.visible = true
			if not world.galaxy_map_window.visible:
				world.galaxy_map_window.open()
		"builder":
			hud.visible = true
			if not world.ship_builder_panel.visible:
				world.open_ship_builder()


func _tear_down(shot: Dictionary) -> void:
	match String(shot["kind"]):
		"enemies":
			for enemy: Enemy in enemies:
				if is_instance_valid(enemy):
					enemy.queue_free()
			enemies.clear()
		"map":
			world.galaxy_map_window.visible = false
		"builder":
			world.ship_builder_panel.visible = false


## One of every enemy type, in a loose wedge out in open space, flying ahead.
func _spawn_enemies() -> void:
	var origin: Vector2 = world.ship.global_position + Vector2(0.0, -3000.0)
	var catalog: Array[Dictionary] = EnemyCatalog.all_enemies()
	for i in catalog.size():
		var entry: Dictionary = catalog[i]
		var enemy := (entry["scene"] as PackedScene).instantiate() as Enemy
		EnemyCatalog.configure(enemy, String(entry["id"]))
		enemy.player_controlled = false
		enemy.ai_forward = true
		enemy.ai_seek_ship = false
		enemy.black_hole_mode = false
		world.add_child(enemy)
		var row: int = i / 3
		var col: int = i % 3 - 1
		enemy.global_position = origin + Vector2(-row * 90.0, col * 80.0 + row * 20.0)
		enemy.rotation = 0.0
		enemies.append(enemy)


func _frame_body(body: Node2D, across: float) -> void:
	var view: Vector2 = root.get_visible_rect().size
	_camera(body.global_position, view.y / (float(body.get("radius")) * 2.0 * across))


func _camera(at: Vector2, zoom: float) -> void:
	world.camera_zoom = zoom
	world.camera.zoom = Vector2(zoom, zoom)
	world.camera.position = at
	world.camera.reset_smoothing()
	world.camera.reset_physics_interpolation()

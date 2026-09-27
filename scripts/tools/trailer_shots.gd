extends SceneTree

## Extra trailer shots, frame by frame, one folder each under --out:
##   fight/  - a pack of enemies closing on the ship, guns firing
##   gather/ - the ship landed on the home planet, surface and deposits
##   travel/ - a hyperspace jump
## Run with rendering (not --headless):
##
##   godot --path . --resolution 1280x720 -s scripts/tools/trailer_shots.gd -- --seed 101 --out C:/tmp/shots

const BAKE_TIMEOUT_MS := 60000
const SHOTS := [["fight", 90], ["gather", 75], ["travel", 150]]
const SETTLE := {"fight": 20, "gather": 45, "travel": 1}

var world: Node
var out_dir := "user://trailer_shots"
var waiting := true
var bake_started_ms := 0
var shot := 0
var frame := 0
var settle := -1
var jump: CanvasLayer = null


func _initialize() -> void:
	var seed_value: int = randi()
	var args: PackedStringArray = OS.get_cmdline_user_args()
	for i in range(args.size() - 1):
		match args[i]:
			"--seed":
				seed_value = args[i + 1].to_int()
			"--out":
				out_dir = args[i + 1]
	# Nothing may end the take early.
	PlayerProgress.god_mode = true
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
	world.get_node("HUD").visible = false

	if waiting:
		for planet in world.planets:
			if not planet.call("is_surface_ready"):
				if Time.get_ticks_msec() - bake_started_ms > BAKE_TIMEOUT_MS:
					push_error("trailer_shots: bakes did not land")
					return true
				return false
		waiting = false
	if shot >= SHOTS.size():
		print("Trailer shots done in %s" % ProjectSettings.globalize_path(out_dir))
		return true

	var name: String = SHOTS[shot][0]
	if settle < 0:
		_start(name)
		settle = SETTLE[name]
		DirAccess.make_dir_recursive_absolute("%s/%s" % [out_dir, name])
	if name == "fight":
		world.camera_follow_ship = true
		world.camera_zoom = 0.9
		world.camera.zoom = Vector2(0.9, 0.9)
	if settle > 0:
		settle -= 1
		return false
	root.get_texture().get_image().save_png("%s/%s/%05d.png" % [out_dir, name, frame])
	frame += 1
	if frame >= int(SHOTS[shot][1]):
		shot += 1
		frame = 0
		settle = -1
	return false


func _start(name: String) -> void:
	match name:
		"fight":
			world.set_time_scale(1.0)
			var ids: Array[String] = ["basic", "tank", "sniper", "basic", "fast"]
			for i in ids.size():
				var enemy := EnemyCatalog.scene_for(ids[i]).instantiate() as Enemy
				EnemyCatalog.configure(enemy, ids[i])
				enemy.player_controlled = false
				enemy.ai_forward = true
				enemy.ai_seek_ship = true
				world.add_child(enemy)
				var angle: float = TAU * i / ids.size()
				enemy.global_position = world.ship.global_position + Vector2.from_angle(angle) * 700.0
				enemy.rotation = angle + PI
		"gather":
			for child in world.get_children():
				if child is Enemy:
					child.queue_free()
			world.set_time_scale(1.0)
			var home: Node2D = world.planets[world.home_planet_index()]
			world.land_on(home)
		"travel":
			var hyper: Script = load("res://scripts/ui/HyperspaceJump.gd")
			jump = hyper.new()
			jump.set("destination_name", "Deep space")
			root.add_child(jump)

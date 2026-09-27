extends SceneTree

## One camera move for a trailer: from the widest zoom (the whole solar
## system, centred on the star) down to the player's ship - stopping on the view a
## new game opens on, where it is still drawn as its icon, not at true scale. No tutorial card and no
## orbit lines (as with Alt). Saved frame by frame for ffmpeg; run with
## rendering (not --headless):
##
##   godot --path . --resolution 1280x720 -s scripts/tools/ship_zoom_reel.gd -- --out C:/tmp/zoom
##   ffmpeg -framerate 30 -i C:/tmp/zoom/%05d.png -pix_fmt yuv420p zoom.mp4
##
## Options: --seed S (world seed, default random), --seconds T (length of the
## move, default 6), --out DIR (default user://ship_zoom_reel).

const FPS := 30
const HOLD_START := 0.8
const HOLD_END := 1.2
const SETTLE_FRAMES := 10
const BAKE_TIMEOUT_MS := 60000
## Surface time per frame, so the planets turn a little on the way in.
const SPIN_PER_FRAME := 0.05

var world: Node
var out_dir := "user://ship_zoom_reel"
var seconds := 6.0
var waiting := true
var settle := SETTLE_FRAMES
var frame := 0
var bake_started_ms := 0
var surface_time := 0.0
## Where the move ends: the zoom a new game opens on - the ship's orbit round
## its planet in view, the ship still an icon.
var end_zoom := -1.0


func _initialize() -> void:
	var seed_value: int = randi()
	var args: PackedStringArray = OS.get_cmdline_user_args()
	for i in range(args.size() - 1):
		match args[i]:
			"--seed":
				seed_value = args[i + 1].to_int()
			"--seconds":
				seconds = maxf(1.0, args[i + 1].to_float())
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
	# No tutorial card, no orbit lines.
	var tutorial: Node = world.find_child("TutorialPanel", true, false)
	if tutorial != null:
		tutorial.queue_free()
	world.orbit_overlays_on = false
	world._set_space_overlays_visible(false)
	if end_zoom < 0.0:
		# A little wider than a new game opens on (the orbit five times across
		# the screen): closer in, the planet glow can fill the whole view.
		var orbit: float = INF
		for planet: Node2D in world.present_planets():
			orbit = minf(orbit, planet.global_position.distance_to(world.ship.global_position))
		end_zoom = root.get_visible_rect().size.y / (orbit * 12.5)
	world.camera_follow_ship = false
	world.camera_follow_body = null

	if waiting:
		for planet in world.planets:
			if not planet.call("is_surface_ready"):
				if Time.get_ticks_msec() - bake_started_ms > BAKE_TIMEOUT_MS:
					push_error("ship_zoom_reel: bakes did not land - is this running --headless?")
					return true
				return false
		waiting = false

	var total: int = int((HOLD_START + seconds + HOLD_END) * FPS)
	var t: float = clampf((float(frame) / FPS - HOLD_START) / seconds, 0.0, 1.0)
	_frame(t)
	surface_time += SPIN_PER_FRAME
	RenderingServer.global_shader_parameter_set("planet_time", surface_time)
	if settle > 0:
		settle -= 1
		return false
	root.get_texture().get_image().save_png("%s/%05d.png" % [out_dir, frame])
	frame += 1
	if frame >= total:
		print("Zoom reel: %d frames in %s" % [frame, ProjectSettings.globalize_path(out_dir)])
		return true
	return false


## Camera `t` (0..1) of the way in: zoom eased in log space, the view sliding
## from the star to the ship as it closes.
func _frame(t: float) -> void:
	var eased: float = t * t * (3.0 - 2.0 * t)
	var far: float = world.ZOOM_MIN
	var near: float = end_zoom
	var zoom: float = exp(lerpf(log(far), log(near), eased))
	world.camera_zoom = zoom
	world.camera.zoom = Vector2(zoom, zoom)
	var star: Vector2 = world.sun.global_position
	var ship: Vector2 = world.ship.global_position
	# The ship only matters once the view is small enough to hold it.
	world.camera.position = star.lerp(ship, smoothstep(0.0, 0.4, eased))
	world.camera.reset_smoothing()
	world.camera.reset_physics_interpolation()

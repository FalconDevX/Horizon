extends Node2D

## World scale: every distance in the scene is 4x what the system was first
## built at, and G was 4^3 = 64x (periods unchanged, speeds 4x). With time
## warp gone G is another 16x on top: orbital speeds 4x again, every period a
## quarter as long, so planets visibly move in real time. SOI sizes depend
## only on mass ratios and are unaffected.
const G: float = 3072000.0
const PlanetGuardsScript := preload("res://scripts/enemy/PlanetGuards.gd")
const EnemyWavesScript := preload("res://scripts/enemy/EnemyWaves.gd")

## Seed for the whole system. Every planet's colours and terrain come from it
## mixed with the planet's own surface_seed, so changing it gives a new set of
## planets. N rerolls it in game.
@export var world_seed: int = 857931493

## How much of each kind's designed range a planet may use (see the _roll_*()
## functions in planet_terrain.gd): 0 is every kind's textbook look, 1 the full
## spread of colours and terrain the kind allows. Discrete rolls - palette
## family, cryovolcano, terrace count - stay random at any value.
@export_range(0.0, 1.0, 0.05) var planet_chaos: float = 1.0

@onready var sun = $Sun
@onready var planets_container: Node2D = $Planets
@onready var ship = $Ship
@onready var camera: Camera2D = $Camera2D
## Draws the 3D bodies. Slaved to `camera` every frame (see _sync_camera_3d),
## which stays the authority for everything else: 2D overlays, mouse aiming,
## clicks, zoom and pan.
@onready var camera_3d: Camera3D = $Camera3D
# Everything under BehindWorld used to be drawn before the planets; that layer
# sits behind the 3D view so it still passes under them.
@onready var orbit_lines_container: Node2D = $BehindWorld/OrbitLines
@onready var trajectory_prediction: Line2D = $BehindWorld/TrajectoryPrediction
@onready var osculating_orbit_line: Line2D = $BehindWorld/OsculatingOrbitLine
@onready var periapsis_marker: Node2D = $BehindWorld/PeriapsisMarker
@onready var apoapsis_marker: Node2D = $BehindWorld/ApoapsisMarker
@onready var speed_gauge: Control = $HUD/SpeedGauge
@onready var hud_status: Control = $HUD/HudStatus
@onready var resource_bars_panel: Control = $HUD/ResourceBarsPanel
@onready var ship_blueprint_panel: Control = $HUD/ShipBlueprintPanel
@onready var pe_gauge: Control = $HUD/PeGauge
@onready var ap_gauge: Control = $HUD/ApGauge
@onready var distance_label: Label = $HUD/PanelContainer/VBoxContainer/DistanceLabel
@onready var thrust_label: Label = $HUD/PanelContainer/VBoxContainer/ThrustLabel
@onready var orbit_label: Label = $HUD/PanelContainer/VBoxContainer/OrbitRow/OrbitLabel
@onready var orbit_info_button: Button = $HUD/PanelContainer/VBoxContainer/OrbitRow/OrbitInfoButton
@onready var planet_info_panel: Control = $HUD/PlanetInfoPanel
@onready var soi_label: Label = $HUD/PanelContainer/VBoxContainer/SOILabel
@onready var trajectory_label: Label = $HUD/PanelContainer/VBoxContainer/TrajectoryLabel
@onready var eccentricity_label: Label = $HUD/PanelContainer/VBoxContainer/EccentricityLabel
@onready var music_player: AudioStreamPlayer = $MusicPlayer
@onready var settings_menu: Control = $HUD/SettingsMenu
@onready var pause_menu: Control = $HUD/PauseMenu
@onready var ship_builder_panel: Control = $HUD/ShipBuilderPanel
@onready var enemy_menu_panel: EnemyMenu = $HUD/EnemyMenuPanel
@onready var music_toast: Control = $HUD/MusicToast
@onready var settings_button: Button = $HUD/PanelContainer/VBoxContainer/TitleRow/SettingsButton
@onready var background_mask: ColorRect = $Background/BackgroundMask
@onready var background_image: TextureRect = $Background/BackgroundImage

var settings_mgr: SettingsManager
var music_mgr: MusicManager
var _settings_opened_from_pause: bool = false
var _is_first_track_notification := true
var _builder_controller: ShipBuilderController
## Module tech tree window (T), created in _ready next to the planet catalog.
var tech_tree_window: TechTreeWindow
var galaxy_map_window: GalaxyMapWindow
## Enemies the radars see (top right) and the mounted guns
## (bottom, beside the resource bars); the enemy picked there is the target.
var enemy_contacts_panel: Control
var weapons_panel: Control
## The target picked in the contacts panel (mirrors combat.target).
var targeted_enemy: Enemy = null
## Sensors, radar scans, the lock and auto-fire (scripts/ship/CombatControl.gd).
var combat: CombatControl
## Reload times below this are rapid fire: the weapons panel shows them loaded.
const RAPID_FIRE_RELOAD := 0.3
## LMB went down over the map (not a HUD panel) with a weapon selected: the
## selected weapon fires for as long as it stays held.
var _firing_held := false
## Railgun and other multi-barrel guns: which barrel fires next, by instance id.
var _next_barrel: Dictionary = {}

## HUD button that fires the hyperdrive (lit once a course is set and the ship
## is past the last asteroid belt).
var warp_button: WarpButton
## The jump under way, or null. While it runs the sim and input are held.
var hyperspace_jump: HyperspaceJump = null
## Where the ship's run-up into hyperspace starts, and which way it goes.
var _warp_run_start: Vector2 = Vector2.ZERO
var _warp_run_dir: Vector2 = Vector2.RIGHT
## How far (in screen pixels) the ship shoots ahead during the run-up.
const WARP_RUN_PX := 2600.0

## Warp: the fast way between planets of one system (there is no time
## acceleration). Ctrl+LMB on a planet locks it as the warp target - if the
## straight path to it is clear and it is not too close - which lights the
## WARP button (or Q). The jump: the ship first turns its nose onto the
## target at its own turn rate (ALIGN), then surges
## ahead while space bends round it (WarpFX), crosses in a blink, and drops
## into a circular orbit next to the planet. Costs ship.warp_fuel by distance.
## (The jump between star systems is the HYPER WARP button below it.)
enum WarpPhase { NONE, ALIGN, SPOOL, JUMP, EXIT }
var warp_phase: WarpPhase = WarpPhase.NONE
## True while the ship is on rails in a jump (spool and crossing).
var warp_active := false
var warp_target: Node2D = null
var local_warp_button: WarpButton
var warp_fx: WarpFX
var warp_path_line: Line2D
var _warp_time := 0.0
var _warp_jump_time := 1.0
var _warp_start := Vector2.ZERO
var _warp_spool_end := Vector2.ZERO
var _warp_dir := Vector2.RIGHT
var _warp_arrive_distance := 0.0
## Why the last lock or jump failed (HUD panel text), for a few seconds.
var warp_notice := ""
var _warp_notice_time := 0.0
const WARP_SPOOL_TIME := 1.1
## The nose must be within this of the target before the spool starts.
const WARP_ALIGN_TOLERANCE := deg_to_rad(2.0)
## How far the ship surges ahead during the spool, in screen pixels.
const WARP_SPOOL_PX := 260.0
## A target must be at least this far off (and outside its SOI).
const WARP_MIN_DISTANCE := 20000.0
## The ship drops out this many radii off the target's centre (at least
## WARP_ARRIVE_MIN above its surface), in a circular orbit.
const WARP_ARRIVE_RADII := 4.0
const WARP_ARRIVE_MIN := 3000.0
## Other bodies block the path within this many of their radii.
const WARP_CLEARANCE_RADII := 1.6
const WARP_PATH_COLOR := Color(0.62, 0.55, 1.0, 0.55)
const SOUND_TARGET_OBSTRUCTED := preload("res://sounds/target--obstructed.wav")
const SOUND_WARP_INITIATED := preload("res://sounds/warp-initiated.wav")
const SOUND_TARGET_DESTROYED := preload("res://sounds/target--destroyed.wav")
var _obstructed_player: AudioStreamPlayer
var _warp_initiated_player: AudioStreamPlayer
var _target_destroyed_player: AudioStreamPlayer
var _last_destroyed_sound_time: float = -10.0

var planets: Array[Node2D] = []
var orbit_lines: Array[Line2D] = []
var orbit_line_radii: Array[float] = []
var celestial_bodies: Array[Node2D] = []

const HOME_PLANET_INDEX := 1
## Planets this system does not have (PlanetRoster) are parked this far out,
## each on its own orbit, hidden and without an SOI.
const PARK_RADIUS := 45000000.0
const PARK_SPACING := 20000.0
## A body is charted once the ship is inside its sphere of influence, or
## within this many of its radii for bodies whose SOI is barely bigger than
## they are.
const CHART_RADII := 12.0
## Close enough to land on a planet: within this many of its radii of its
## centre (or inside its SOI, if that is smaller). 1 = only while the ship is
## over the planet's disc.
const LANDING_RANGE_RADII := 1.0
## How much of a landed planet the view spans, top to bottom, in its radii,
## and the most the wheel may zoom out to while landed. Zooming in is only held
## by ZOOM_MAX, so the ship can be seen at true scale over the surface.
const LANDED_VIEW_RADII := 1.1
const LANDED_VIEW_MAX_RADII := 3.0
## Driving over a surface: WASD / arrows move in screen directions, RMB
## heads for the cursor, Shift is slow. Top speed in planet radii per second
## (slow, so the ground can be read); how long the ship takes to reach it,
## stop or change course (seconds - a heavy, sluggish ease); how fast the nose
## turns to face the way it goes; how sharply it slows nearing the cursor.
const GROUND_SPEED_RADII := 0.2
const GROUND_RESPONSE := 0.6
const GROUND_TURN_RESPONSE := 3.0
const GROUND_FOLLOW_GAIN := 3.0
## Taking off drops the ship into a circular orbit at least this many radii
## out, and inside the SOI.
const TAKE_OFF_MIN_RADII := 1.3

var camera_zoom := 1.0
var is_dragging := false
var camera_follow_ship := false
## The body the camera stays centred on after it was clicked, until the view is
## panned (middle mouse) or released with the period key. Null = none.
var camera_follow_body: Node2D = null

## Extra reach, in screen pixels, for clicking a body drawn only a few pixels
## across.
const BODY_PICK_SCREEN_RADIUS := 14.0
var _test_enemy: Enemy = null ## Sandbox (E menu) ship being test-flown, if any.
## Hostile craft orbiting planets (PlanetGuards); cleared on world travel.
var _planet_guards: Array[Enemy] = []
## True after a seed change until every surface has baked and guards respawn.
var _planet_guards_pending: bool = false
## Timed hunt waves (EnemyWaves): how many have already fired this save.
var _enemy_waves_spawned: int = 0
## Live craft from the latest wave(s); pruned as they die.
var _wave_enemies: Array[Enemy] = []
var _clock_wave_label: Label = null
var trajectory_status := "ORBIT"
var trajectory_target := ""
var trajectory_candidate_status := ""
var trajectory_candidate_target := ""
var trajectory_candidate_frames := 0
var time_scale := 1.0
var _user_paused := false
## Alt shows / hides the flight prediction, orbits and orbit gauges.
var orbit_overlays_on := true
## Node2D -> [position at the previous physics tick, at the last one].
var _tick_positions: Dictionary = {}

## Game calendar. One second of simulation is one hour on the clock, which
## happens to give Coralyss a year of about 345 days and a 25-hour day.
const CLOCK_HOURS_PER_SIM_SECOND := 1.0 / 60.0
const CLOCK_EPOCH := {"year": 2387, "month": 3, "day": 14, "hour": 8, "minute": 0, "second": 0}
const MONTH_NAMES := ["JAN", "FEB", "MAR", "APR", "MAY", "JUN", "JUL", "AUG", "SEP", "OCT", "NOV", "DEC"]

## Simulated seconds since the start, advancing with time warp and stopping
## on pause.
var sim_time := 0.0

## Clock for the planet shaders' animation (clouds, waves, lava, the sun's
## granules): follows game time and stops on pause, but runs no faster than
## real time under warp - clouds sweeping round 200x would only flicker.
var planet_visual_time := 0.0
const PLANET_VISUAL_MAX_RATE := 1.0
var _clock_epoch_unix: int = 0
var _clock_date_label: Label = null
var _clock_day_label: Label = null
var simulation_accumulator := 0.0
var prediction_update_accumulator := 1.0
var current_periapsis := 0.0
var current_apoapsis := 0.0
var current_eccentricity := 0.0
var current_periapsis_altitude := 0.0
var current_apoapsis_altitude := 0.0
var has_bound_orbit := false
var osculating_periapsis_direction := Vector2.RIGHT
## Each planet's orbit radius as the scene has it, and whether this system has
## it (PlanetRoster.roll(world_seed)).
var orbit_radii: PackedFloat64Array = []
var planet_present: Array[bool] = []
## The PhysicsBody of every planet this system has - the only ones stepped.
var _active_physics_planets: Array = []
var trajectory_task_id := -1
var trajectory_task_holder: Dictionary = {}
## The last finished prediction: absolute points, each point's sim time after
## `_trajectory_t0`. Redrawn every frame from the ship onward (see
## refresh_trajectory_line), so the line stays on the ship between the 10 Hz
## predictions instead of trailing behind and jumping.
var _trajectory_points := PackedVector2Array()
var _trajectory_times := PackedFloat32Array()
var _trajectory_t0 := 0.0
## Index into `planets` when the whole prediction stays inside that planet's
## SOI - the line is then drawn relative to the planet (a clean ellipse that
## rides along with it) from `_trajectory_rel_points`. -1 draws it round the sun.
var _trajectory_ref := -1
var _trajectory_rel_points := PackedVector2Array()
var total_sim_time := 0.0
## Scenery only - see asteroid_belts.gd.
var asteroid_belts: AsteroidBelts
var asteroid_belt_map: AsteroidBeltMap
## Up while the planets are still generating; the sim and input wait for it.
var loading_screen: LoadingScreen
var physics_planets: Array[PhysicsBody] = []
var physics_ship: PhysicsBody
var soi_radii_cache: PackedFloat64Array = []

## Bodies the ship has surveyed in this system by flying near them; the log
## (J) shows only these in full - the rest are dark and redacted. The sun and
## the home planet are known from the start. Charting a body records the
## variant it is in the Journal, which - unlike this - outlives travel, along
## with every find (mark_resource_found). Scenery (tumbleweeds, dead
## stalks) is in plain sight, so it counts as found on any charted planet.
var charted_bodies: Dictionary = {}

## The planet the ship is landed on, or null out in space. While landed the
## ship is pinned to the planet's centre - where the camera sits - and flies
## over the surface by rolling the planet under it (CelestialBody.roll_surface).
var landed_body: Node2D = null
## The planet close enough to land on right now (ENTER), for the prompt.
var landing_candidate: Node2D = null
## The ship's speed over the ground while landed, world units per second.
var ground_velocity := Vector2.ZERO
## What landing changed, to put back on take-off: where the ship was relative
## to the planet, which way it was going round, and the camera.
var _landing_state: Dictionary = {}
var landing_prompt: Control
## "E - collect" under the landing prompt, while the ship is over a deposit.
var collect_prompt: Control
## What the ship carries (collect_under_ship fills it); shown by
## inventory_screen, toggled with I. PlayerProgress owns it, so it outlives
## scene reloads and the tech tree spends from it.
var inventory: Inventory = PlayerProgress.inventory
var inventory_screen: Control
var mu_sun := 0.0
var mu_planets: PackedFloat64Array = []

const ZOOM_MIN := 0.00002
const ZOOM_MAX := 50.0
const MIN_BODY_SCREEN_RADIUS := 4.0
## On-screen radius, in pixels, above which a body switches to its fine sphere.
const DETAIL_HIGH_SCREEN_RADIUS := 40.0
## How far above the orbital plane the top-down 3D camera sits. Only needs to
## clear the tallest mountain; orthographic, so it does not change the size.
const CAMERA_3D_HEIGHT := 50000.0
const ZOOM_STEP := 1.2
## Planets pull on the ship this much less than their scene mass says, so
## orbits are slower and easier to leave. Applied to the planets' `mass` once at
## start, so the sim, predictor, SOI sizes and the catalog all agree.
## (Planets themselves only feel the sun, so their own orbits are unaffected.)
const PLANET_GRAVITY_SCALE := 0.4
## Smallest a planet's SOI may be, in planet radii (see get_soi_radius).
const MIN_SOI_RADII := 5.0
## Finer and shorter than under the old time warp (orbits are 4x faster now,
## G): 6000 x 0.4 s looks 40 min ahead.
const PREDICTION_STEPS := 6000
const PREDICTION_DT := 0.4
## A predicted point is kept at least every this many steps...
const PREDICTION_DRAW_INTERVAL := 10
## ...and sooner wherever the path has turned by this much (radians), so tight
## loops round a planet come out round instead of as a polygon.
const PREDICTION_DRAW_TURN := 0.025
const SIM_DT := 1.0 / 120.0
## Real time only (no time warp): a slow frame catches up, a stall does not
## spiral.
const MAX_SIM_STEPS_PER_FRAME := 60
const TRAJECTORY_CONFIRM_FRAMES := 10
## Re-predicted about every other frame, so the line keeps up with the ship.
const PREDICTION_UPDATE_INTERVAL := 0.03
const ORBIT_LINE_SCREEN_WIDTH := 1.0
const TRAJECTORY_LINE_SCREEN_WIDTH := 2.0
const SOI_LINE_SCREEN_WIDTH := 1.0
## A warp drops the ship in no further out than this share of the target SOI.
const WARP_MAX_SOI_FACTOR := 0.8
const SHIP_TRUE_SCALE_ZOOM_THRESHOLD := 4.0
class PhysicsBody:
	var node: Node2D
	var x := 0.0
	var y := 0.0
	var vx := 0.0
	var vy := 0.0

	func _init(body: Node2D) -> void:
		node = body
		pull_from_node()

	func pull_from_node() -> void:
		var velocity: Vector2 = node.get("velocity")
		x = node.position.x
		y = node.position.y
		vx = velocity.x
		vy = velocity.y

	func push_to_node() -> void:
		node.position = Vector2(x, y)
		node.set("velocity", Vector2(vx, vy))

	func advance_position(a0: Vector2, dt: float) -> void:
		x += vx * dt + 0.5 * a0.x * dt * dt
		y += vy * dt + 0.5 * a0.y * dt * dt

	func advance_velocity(a0: Vector2, a1: Vector2, dt: float) -> void:
		vx += 0.5 * (a0.x + a1.x) * dt
		vy += 0.5 * (a0.y + a1.y) * dt


func set_ship_state(new_position: Vector2, new_velocity: Vector2) -> void:
	ship.position = new_position
	ship.velocity = new_velocity
	# A teleport: no drawing it as a slide from where it was.
	_tick_positions.erase(ship)
	if physics_ship != null:
		physics_ship.pull_from_node()


## ENTER lands and takes off. Caught here, ahead of the GUI, or a HUD button
## that happens to hold focus would take the key for itself - but only when no
## menu or panel is open, so those keep ENTER for their own use.
func _input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	if event.keycode != KEY_ENTER and event.keycode != KEY_KP_ENTER:
		return
	if loading_screen != null or hyperspace_jump != null or planet_info_panel.visible or inventory_screen.visible:
		return
	for menu: Control in [settings_menu, pause_menu, ship_builder_panel]:
		if menu != null and menu.visible:
			return
	if landed_body != null:
		take_off()
	elif landing_candidate != null:
		land_on(landing_candidate)
	else:
		return
	get_viewport().set_input_as_handled()


func _unhandled_input(event: InputEvent) -> void:
	if loading_screen != null or hyperspace_jump != null:
		return
	# The cargo hold and the planet catalog sit over everything and keep the
	# keyboard to themselves.
	if inventory_screen.visible:
		if event is InputEventKey and event.pressed and not event.echo and (
			event.keycode == KEY_ESCAPE or event.keycode == KEY_I
		):
			inventory_screen.hide_panel()
		elif event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_J:
			inventory_screen.hide_panel()
			planet_info_panel.toggle()
		elif event is InputEventKey and event.pressed and event.keycode in [KEY_LEFT, KEY_RIGHT, KEY_UP, KEY_DOWN]:
			inventory_screen.view.step(
				int(event.keycode == KEY_RIGHT) - int(event.keycode == KEY_LEFT),
				int(event.keycode == KEY_DOWN) - int(event.keycode == KEY_UP)
			)
		if event is InputEventKey:
			get_viewport().set_input_as_handled()
		return
	if planet_info_panel.visible:
		if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_I:
			planet_info_panel.hide_panel()
			inventory_screen.open()
			get_viewport().set_input_as_handled()
		elif event is InputEventKey and event.pressed and not event.echo and (
			event.keycode == KEY_ESCAPE or event.keycode == KEY_J
		):
			planet_info_panel.hide_panel()
			get_viewport().set_input_as_handled()
		elif event is InputEventKey and event.pressed and (event.keycode == KEY_DOWN or event.keycode == KEY_UP):
			planet_info_panel.step(1 if event.keycode == KEY_DOWN else -1)
			get_viewport().set_input_as_handled()
		elif event is InputEventKey and event.pressed and not event.echo and (
			event.keycode == KEY_TAB or event.keycode == KEY_LEFT or event.keycode == KEY_RIGHT
		):
			planet_info_panel.switch_tab()
			get_viewport().set_input_as_handled()
		return

	# The tech tree window likewise.
	if tech_tree_window != null and tech_tree_window.visible:
		if event is InputEventKey and event.pressed and not event.echo and (
			event.keycode == KEY_ESCAPE or event.keycode == KEY_T
		):
			tech_tree_window.hide_window()
			get_viewport().set_input_as_handled()
		return

	# And the galaxy map.
	if galaxy_map_window != null and galaxy_map_window.visible:
		if event is InputEventKey and event.pressed and not event.echo and (
			event.keycode == KEY_ESCAPE or event.keycode == KEY_M
		):
			galaxy_map_window.hide_window()
			get_viewport().set_input_as_handled()
		return

	if (
		event is InputEventKey
		and event.pressed
		and not event.echo
		and event.keycode in [KEY_I, KEY_J, KEY_T, KEY_M]
		and (ship_builder_panel == null or not ship_builder_panel.visible)
		and (pause_menu == null or not pause_menu.visible)
		and (settings_menu == null or not settings_menu.visible)
	):
		# I - the cargo hold, J - the planetary log, T - the tech tree, M - the
		# galaxy map.
		match event.keycode:
			KEY_I:
				inventory_screen.open()
			KEY_J:
				planet_info_panel.toggle()
			KEY_M:
				galaxy_map_window.open()
			_:
				tech_tree_window.open()
		get_viewport().set_input_as_handled()
		return

	if (
		event is InputEventKey
		and event.pressed
		and not event.echo
		and event.keycode == KEY_ESCAPE
		and (ship_builder_panel == null or not ship_builder_panel.visible)
	):
		_handle_escape()
		get_viewport().set_input_as_handled()
		return

	if settings_menu != null and settings_menu.visible:
		return

	if pause_menu != null and pause_menu.visible:
		return

	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_B:
		toggle_ship_builder()
		get_viewport().set_input_as_handled()
		return

	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_E:
		# On a planet E gathers what the ship is over; out in space it is the
		# enemy menu.
		if landed_body != null:
			collect_under_ship()
		else:
			toggle_enemy_menu()
		get_viewport().set_input_as_handled()
		return

	if ship_builder_panel != null and ship_builder_panel.visible:
		return

	if (
		event is InputEventKey and event.pressed and not event.echo
		and (event.keycode == KEY_Z or event.keycode == KEY_C) and _test_enemy == null
	):
		# 1 = prograde, 2 = retrograde (ship.gd AttitudeHold).
		ship.toggle_attitude_hold(1 if event.keycode == KEY_Z else 2)
		get_viewport().set_input_as_handled()
		return

	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_V:
		ship.toggle_flight_assist()
		get_viewport().set_input_as_handled()
		return

	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_G:
		_try_fire_fov_weapon()
		get_viewport().set_input_as_handled()
		return

	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_Q:
			start_warp_jump()
		elif event.keycode == KEY_ALT:
			toggle_orbit_overlays()
		elif event.keycode == KEY_R and landed_body == null:
			combat.scan_all()
		elif event.keycode == KEY_P or event.keycode == KEY_0:
			toggle_pause()
		elif event.keycode == KEY_SPACE and _test_enemy == null:
			toggle_pause()
		elif event.keycode >= KEY_1 and event.keycode <= KEY_9:
			# 1-9 pick a weapon, in the weapons panel's order (again to put it away).
			_select_weapon_slot(event.keycode - KEY_1)
		elif event.keycode == KEY_PERIOD:
			if camera_follow_body != null:
				camera_follow_body = null
			else:
				camera_follow_ship = not camera_follow_ship
		elif event.keycode == KEY_N and PlayerProgress.god_mode:
			# Debug only: a stray key must not throw away the whole system.
			reroll_world()

	if event is InputEventMouseButton:
		if event.pressed:
			var zoom_step: float = settings_mgr.camera_zoom_speed if settings_mgr != null else ZOOM_STEP
			if event.button_index == MOUSE_BUTTON_WHEEL_UP:
				camera_zoom *= zoom_step

			elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				camera_zoom /= zoom_step

		camera_zoom = clamp(camera_zoom, ZOOM_MIN, ZOOM_MAX)
		if landed_body != null:
			camera_zoom = maxf(camera_zoom, _landed_zoom(LANDED_VIEW_MAX_RADII))
		camera.zoom = Vector2(camera_zoom, camera_zoom)

		# Landed, the camera stays on the ship: no panning or picking bodies.
		if landed_body != null:
			return

		if event.button_index == MOUSE_BUTTON_MIDDLE:
			is_dragging = event.pressed

			if event.pressed:
				camera_follow_ship = false
				camera_follow_body = null

		if event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
			_firing_held = false
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed and event.ctrl_pressed:
			# Ctrl+LMB on a planet: lock (or drop) the warp target.
			var warp_pick: Node2D = _body_under_mouse()
			if warp_pick != null and planets.has(warp_pick):
				toggle_warp_target(warp_pick)
				get_viewport().set_input_as_handled()
				return
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed and ship.selected_weapon >= 0:
			# A weapon is picked: LMB fires it instead of picking bodies.
			_firing_held = true
			get_viewport().set_input_as_handled()
			return
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			var picked: Node2D = _body_under_mouse()
			if picked != null:
				camera_follow_body = picked
				camera_follow_ship = false

	if event is InputEventMouseMotion and is_dragging:
		var pan_factor: float = settings_mgr.camera_pan_speed if settings_mgr != null else 1.0
		camera.position -= (event.relative * pan_factor) / camera_zoom


## Regenerates every planet from a new world seed. The old world's cached
## bakes are dropped first - nothing will ask for them again.
func set_world_seed(value: int) -> void:
	# Other worlds (galaxy-map travel, or N): the ship lifts off first, and
	# what it charted here no longer describes these bodies - they are charted
	# again. The Journal keeps every variant seen and everything found. The
	# system left behind is saved (GalaxyMap.save_state), and one visited
	# before gets back what was charted and collected there.
	if landed_body != null:
		take_off()
	if value != world_seed:
		GalaxyMap.save_state(world_seed, _capture_system_state())
	world_seed = value
	GalaxyMap.visit(world_seed)
	PlanetTerrain.clear_cache()
	var saved: Dictionary = GalaxyMap.saved_state(world_seed)
	_restore_system_state(saved)
	_update_system_title()

	_roll_roster()
	for i in planets.size():
		var collected: Dictionary = saved.get("collected", {}).get(i, {})
		planets[i].set("collected_deposit_seeds", collected.duplicate())
		planets[i].call("rebuild_surface")
		# An anomaly re-rolls its size (and mass) with the world.
		if i < mu_planets.size():
			mu_planets[i] = G * float(planets[i].get("mass"))
	var phase_rng := RandomNumberGenerator.new()
	phase_rng.randomize()
	_apply_roster(phase_rng)
	_show_roster()
	_chart_known_bodies()
	_clear_planet_guards()
	_clear_wave_enemies()
	_planet_guards_pending = true

	print("World seed: %d" % world_seed)


func reroll_world() -> void:
	set_world_seed(randi())


## What the player did in this system, by body index (celestial_bodies for
## charts, planets for collected deposits), so it can be put back when the
## ship returns. Finds live in the Journal, which is not per system.
func _capture_system_state() -> Dictionary:
	var charted: Array[int] = []
	for body: Node2D in charted_bodies:
		charted.append(celestial_bodies.find(body))
	var collected: Dictionary = {}
	for i in planets.size():
		var seeds: Dictionary = planets[i].get("collected_deposit_seeds")
		if not seeds.is_empty():
			collected[i] = seeds.duplicate()
	return {"charted": charted, "collected": collected}


## Charts from a saved state; an empty one is a new system, charted afresh.
func _restore_system_state(state: Dictionary) -> void:
	charted_bodies.clear()
	for index: int in state.get("charted", []):
		if index >= 0 and index < celestial_bodies.size():
			charted_bodies[celestial_bodies[index]] = true


## The HUD panel's header names the system the ship is in.
func _update_system_title() -> void:
	var label: Label = $HUD/PanelContainer/VBoxContainer/TitleRow/TitleLabel
	label.text = "%s SYSTEM" % GalaxyMap.system_name(world_seed).to_upper()


## Galaxy map picked a course: say where to go to use it.
func _on_course_set(system_seed: int) -> void:
	music_toast.show_message(
		"COURSE SET: %s. Fly past the outer belt and press WARP" % GalaxyMap.system_name(system_seed).to_upper()
	)


## Ctrl+LMB on a planet: lock it as the warp target, or let go of it.
func toggle_warp_target(body: Node2D) -> void:
	if body == null or not planets.has(body) or not planet_present[planets.find(body)]:
		return
	if body == warp_target:
		warp_target = null
		return
	# Locked even if a jump cannot go yet (inside an SOI, path blocked...):
	# the WARP button says why until it can.
	warp_target = body
	music_toast.show_message("WARP TARGET LOCKED: %s" % String(body.get("body_name")).to_upper())
	var problem: String = _warp_problem(body)
	if "blocked" in problem.to_lower():
		_play_obstructed_sound()


func _play_obstructed_sound() -> void:
	if _obstructed_player == null:
		_obstructed_player = AudioStreamPlayer.new()
		_obstructed_player.name = "ObstructedSoundPlayer"
		_obstructed_player.stream = SOUND_TARGET_OBSTRUCTED
		_obstructed_player.bus = &"SFX"
		add_child(_obstructed_player)
	_obstructed_player.play()


func _play_warp_initiated_sound() -> void:
	if _warp_initiated_player == null:
		_warp_initiated_player = AudioStreamPlayer.new()
		_warp_initiated_player.name = "WarpInitiatedPlayer"
		_warp_initiated_player.stream = SOUND_WARP_INITIATED
		_warp_initiated_player.bus = &"SFX"
		add_child(_warp_initiated_player)
	_warp_initiated_player.play()


func play_target_destroyed_sound(enemy: Enemy = null) -> void:
	if enemy != null and enemy == _test_enemy:
		return
	var now: float = float(Time.get_ticks_msec()) * 0.001
	if now - _last_destroyed_sound_time < 1.2:
		return
	_last_destroyed_sound_time = now
	if _target_destroyed_player == null:
		_target_destroyed_player = AudioStreamPlayer.new()
		_target_destroyed_player.name = "TargetDestroyedPlayer"
		_target_destroyed_player.stream = SOUND_TARGET_DESTROYED
		_target_destroyed_player.bus = &"SFX"
		add_child(_target_destroyed_player)
	_target_destroyed_player.play()


## "" when a jump to `body` can go now, else why not.
func _warp_problem(body: Node2D) -> String:
	if landed_body != null:
		return "Take off first"
	var index: int = planets.find(body)
	var target := Vector2(physics_planets[index].x, physics_planets[index].y)
	var from := Vector2(physics_ship.x, physics_ship.y)
	var inside: int = _ship_soi_index_precise()
	if inside >= 0:
		return "Leave %s's SOI first" % String(planets[inside].get("body_name"))
	var distance: float = from.distance_to(target)
	var soi: float = soi_radii_cache[index] if index < soi_radii_cache.size() else 0.0
	if distance < maxf(soi, WARP_MIN_DISTANCE):
		return "Too close to %s" % String(body.get("body_name"))
	var arrive: Vector2 = target - (target - from).normalized() * _warp_arrive_radius(index)
	if not ship.has_warp_fuel_for(from.distance_to(arrive)):
		return "Not enough warp fuel"
	# Anything else within reach of the straight path blocks it.
	var sun_reach: float = float(sun.get("radius")) * WARP_CLEARANCE_RADII
	if LaserBolt._segment_hits_circle(from, arrive, sun.position, sun_reach):
		return "Path blocked by %s" % String(sun.get("body_name"))
	for i in range(planets.size()):
		# Planets this system does not have are parked far out: not in the way.
		if i == index or not planet_present[i]:
			continue
		var reach: float = float(planets[i].get("radius")) * WARP_CLEARANCE_RADII
		if LaserBolt._segment_hits_circle(from, arrive, Vector2(physics_planets[i].x, physics_planets[i].y), reach):
			return "Path blocked by %s" % String(planets[i].get("body_name"))
	return ""


## Share of a full warp tank the jump to the locked target would burn now
## (0 with no target).
func _warp_cost_share() -> float:
	if warp_target == null or PlayerProgress.god_mode:
		return 0.0
	var index: int = planets.find(warp_target)
	if index < 0:
		return 0.0
	var target := Vector2(physics_planets[index].x, physics_planets[index].y)
	var distance: float = Vector2(physics_ship.x, physics_ship.y).distance_to(target) - _warp_arrive_radius(index)
	return maxf(distance, 0.0) / ship.WARP_RANGE


func _warp_arrive_radius(index: int) -> float:
	var radius: float = float(planets[index].get("radius"))
	var arrive: float = maxf(radius * WARP_ARRIVE_RADII, radius + WARP_ARRIVE_MIN)
	if index < soi_radii_cache.size() and soi_radii_cache[index] > 0.0:
		arrive = minf(arrive, soi_radii_cache[index] * WARP_MAX_SOI_FACTOR)
	return arrive


## The WARP button (or Q): jump to the locked target.
func start_warp_jump() -> void:
	if warp_phase != WarpPhase.NONE or hyperspace_jump != null or loading_screen != null:
		return
	if warp_target == null:
		_warp_notify("No target. Ctrl+click a planet")
		music_toast.show_message("WARP: NO TARGET")
		return
	var problem: String = _warp_problem(warp_target)
	if problem != "":
		_warp_notify(problem)
		music_toast.show_message("WARP: %s" % problem.to_upper())
		if "blocked" in problem.to_lower():
			_play_obstructed_sound()
		return
	ship.disengage_manual_main_engine()
	ship.attitude_hold = ship.AttitudeHold.NONE
	warp_phase = WarpPhase.ALIGN
	_warp_time = 0.0
	camera_follow_ship = true
	camera_follow_body = null
	_play_warp_initiated_sound()


## Aligned: the fuel is paid and the ship leaves its orbit for the rails.
func _begin_warp_spool() -> void:
	var index: int = planets.find(warp_target)
	var target := Vector2(physics_planets[index].x, physics_planets[index].y)
	_warp_start = Vector2(physics_ship.x, physics_ship.y)
	_warp_spool_end = _warp_start
	_warp_dir = (target - _warp_start).normalized()
	_warp_arrive_distance = _warp_arrive_radius(index)
	var distance: float = _warp_start.distance_to(target) - _warp_arrive_distance
	ship.burn_warp_fuel(distance)
	# Longer hops take a little longer, never more than two seconds.
	_warp_jump_time = clampf(0.45 + distance / 3000000.0, 0.5, 2.0)
	warp_phase = WarpPhase.SPOOL
	warp_active = true
	_warp_time = 0.0
	trajectory_prediction.visible = false
	warp_fx.play()


## One sim step of aligning: the nose turns onto the target at the ship's
## normal turn rate while it flies on as usual; any manual turn or burn
## calls the warp off.
func _advance_warp_align(dt: float) -> void:
	if warp_target == null or _warp_problem(warp_target) != "":
		var problem: String = _warp_problem(warp_target) if warp_target != null else "Target lost"
		_warp_notify(problem)
		music_toast.show_message("WARP: %s" % problem.to_upper())
		if "blocked" in problem.to_lower():
			_play_obstructed_sound()
		warp_phase = WarpPhase.NONE
		return
	var wanted: float = (warp_target.position - ship.position).angle()
	ship.rotation = rotate_toward(ship.rotation, wanted, ship.get_turn_rate() * dt)
	if absf(angle_difference(ship.rotation, wanted)) <= WARP_ALIGN_TOLERANCE:
		_begin_warp_spool()


## Stops a jump where it is (respawn, hyperspace).
func cancel_warp() -> void:
	if warp_phase == WarpPhase.NONE:
		return
	var was_on_rails: bool = warp_active
	warp_phase = WarpPhase.NONE
	warp_active = false
	warp_fx.stop()
	if was_on_rails:
		set_ship_state(Vector2(physics_ship.x, physics_ship.y), _warp_frame_velocity())
	trajectory_prediction.visible = settings_mgr == null or settings_mgr.show_trajectory
	_restart_trajectory_prediction()


func _warp_notify(text: String) -> void:
	warp_notice = text
	_warp_notice_time = 3.0


## Velocity of the body whose SOI holds the ship (zero for the sun).
func _warp_frame_velocity() -> Vector2:
	var index: int = _ship_soi_index_precise()
	if index < 0:
		return Vector2.ZERO
	return Vector2(physics_planets[index].vx, physics_planets[index].vy)


## One sim step of a jump: the ship on rails, planets moving on as usual.
func _advance_warp(dt: float) -> void:
	_warp_time += dt
	var index: int = planets.find(warp_target)
	if index < 0:
		cancel_warp()
		return
	if warp_phase == WarpPhase.SPOOL:
		# Swing onto the target and surge ahead, faster and faster.
		var s: float = clampf(_warp_time / WARP_SPOOL_TIME, 0.0, 1.0)
		var surge: float = WARP_SPOOL_PX / camera_zoom
		ship.rotation = lerp_angle(ship.rotation, _warp_dir.angle(), 1.0 - exp(-dt * 8.0))
		ship.throttle = s
		_warp_spool_end = _warp_start + _warp_dir * surge * s * s * s
		_place_warping_ship(_warp_spool_end, _warp_dir * surge * 3.0 * s * s / WARP_SPOOL_TIME)
		if s >= 1.0:
			warp_phase = WarpPhase.JUMP
			_warp_time = 0.0
		return
	# The crossing: eased from the spool's end to the arrival point, which
	# rides along with the planet.
	var planet: PhysicsBody = physics_planets[index]
	var u: float = clampf(_warp_time / _warp_jump_time, 0.0, 1.0)
	var eased: float = u * u * (3.0 - 2.0 * u)
	var arrive: Vector2 = Vector2(planet.x, planet.y) - _warp_dir * _warp_arrive_distance
	var previous := Vector2(physics_ship.x, physics_ship.y)
	var now: Vector2 = _warp_spool_end.lerp(arrive, eased)
	ship.rotation = _warp_dir.angle()
	_place_warping_ship(now, (now - previous) / dt)
	if u >= 1.0:
		_arrive_from_warp(index)


func _place_warping_ship(position_now: Vector2, velocity_now: Vector2) -> void:
	physics_ship.x = position_now.x
	physics_ship.y = position_now.y
	physics_ship.vx = velocity_now.x
	physics_ship.vy = velocity_now.y
	physics_ship.push_to_node()


## Drops out into a circular orbit round the target, going round the way the
## ship was already heading.
func _arrive_from_warp(index: int) -> void:
	var planet: PhysicsBody = physics_planets[index]
	var offset: Vector2 = -_warp_dir * _warp_arrive_distance
	var along: Vector2 = offset.orthogonal().normalized()
	if along.dot(_warp_dir) < 0.0:
		along = -along
	var speed: float = sqrt(mu_planets[index] / _warp_arrive_distance)
	set_ship_state(Vector2(planet.x, planet.y) + offset, Vector2(planet.vx, planet.vy) + along * speed)
	ship.rotation = along.angle()
	ship.throttle = 0.0
	ship.reset_physics_interpolation()
	camera.position = ship.position
	warp_active = false
	warp_phase = WarpPhase.EXIT
	_warp_time = 0.0
	warp_fx.arrive()
	music_toast.show_message("ARRIVED: %s" % String(warp_target.get("body_name")).to_upper())
	warp_target = null
	trajectory_prediction.visible = settings_mgr == null or settings_mgr.show_trajectory
	_restart_trajectory_prediction()


## Every frame: the effect follows the ship, the exit runs out, and the
## WARP button and the path line show whether a jump can go.
func _update_warp(delta: float) -> void:
	_warp_notice_time = maxf(_warp_notice_time - delta, 0.0)
	if warp_phase == WarpPhase.EXIT and warp_fx.is_idle():
		warp_phase = WarpPhase.NONE
	if warp_target != null and not is_instance_valid(warp_target):
		warp_target = null
	var screen_size: Vector2 = get_viewport().get_visible_rect().size
	warp_fx.set_center(ship.get_global_transform_with_canvas().origin / screen_size, screen_size)
	if warp_phase == WarpPhase.ALIGN and (
		Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_A)
		or Input.is_key_pressed(KEY_D)
	):
		warp_phase = WarpPhase.NONE
		_warp_notify("Warp aborted")
	if warp_phase == WarpPhase.SPOOL:
		warp_fx.set_spool(clampf(_warp_time / WARP_SPOOL_TIME, 0.0, 1.0))
	elif warp_phase == WarpPhase.JUMP:
		warp_fx.set_jump(clampf(_warp_time / _warp_jump_time, 0.0, 1.0))

	var show_path: bool = warp_target != null and warp_phase == WarpPhase.NONE and landed_body == null
	warp_path_line.visible = show_path
	if show_path:
		warp_path_line.width = 1.5 / camera_zoom
		var target_index: int = planets.find(warp_target)
		var to_target: Vector2 = warp_target.position - ship.position
		var arrive: Vector2 = warp_target.position - to_target.normalized() * _warp_arrive_radius(target_index)
		var ring := PackedVector2Array([ship.position, arrive])
		var ring_radius: float = 10.0 / camera_zoom
		for k in 25:
			ring.append(arrive + Vector2.RIGHT.rotated(TAU * k / 24.0) * ring_radius)
		warp_path_line.points = ring

	var panel: Control = $HUD/PanelContainer
	local_warp_button.position = Vector2(panel.position.x, panel.position.y + panel.size.y + 10.0)
	local_warp_button.visible = hyperspace_jump == null
	if warp_phase == WarpPhase.ALIGN:
		local_warp_button.set_state(false, "ALIGNING", "Turning onto %s" % String(warp_target.get("body_name")))
	elif warp_phase != WarpPhase.NONE:
		local_warp_button.set_state(false, "WARPING", "")
	elif warp_target == null:
		local_warp_button.set_state(false, "WARP", "Ctrl+click a planet to lock a target")
	else:
		var title: String = "WARP TO %s" % String(warp_target.get("body_name")).to_upper()
		var problem: String = _warp_problem(warp_target)
		if problem != "":
			local_warp_button.set_state(false, title, problem)
		else:
			var cost: float = _warp_cost_share()
			var left: float = ship.warp_fuel / ship.WARP_FUEL_CAPACITY - cost
			local_warp_button.set_state(
				true, title, "Fuel -%d%%, %d%% left after" % [maxi(roundi(cost * 100.0), 1), roundi(left * 100.0)]
			)


## How far from the sun the hyperdrive may fire: past the outer edge of the
## last asteroid belt.
func _warp_clearance() -> float:
	var edge: float = 0.0
	for belt: Dictionary in AsteroidBelts.BELTS:
		edge = maxf(edge, float(belt["outer"]))
	return edge


func _update_warp_button() -> void:
	var panel: Control = $HUD/PanelContainer
	warp_button.position = Vector2(
		panel.position.x, panel.position.y + panel.size.y + 10.0 + local_warp_button.size.y + 6.0
	)
	warp_button.visible = hyperspace_jump == null
	if not GalaxyMap.has_target():
		warp_button.set_state(false, "HYPER WARP", "No course set. Open the map (M)")
		return
	var title: String = "HYPER WARP TO %s" % GalaxyMap.system_name(GalaxyMap.target_seed()).to_upper()
	if landed_body != null:
		warp_button.set_state(false, title, "Take off first")
		return
	var to_go: float = _warp_clearance() - ship.global_position.distance_to(sun.global_position)
	if to_go > 0.0 and not PlayerProgress.god_mode:
		warp_button.set_state(false, title, "Clear the outer belt: %s to go" % _short_distance(to_go))
		return
	warp_button.set_state(true, title, "Hyperdrive ready")


## A whole number with thin thousands groups: 2 185 046.
static func _grouped(value: float) -> String:
	var digits: String = str(absi(roundi(value)))
	var out: String = ""
	while digits.length() > 3:
		out = " " + digits.right(3) + out
		digits = digits.left(digits.length() - 3)
	return ("-" if value < 0.0 else "") + digits + out


func _short_distance(value: float) -> String:
	if value >= 1000000.0:
		return "%.2fM" % (value / 1000000.0)
	if value >= 1000.0:
		return "%dk" % int(value / 1000.0)
	return "%d" % int(value)


## Fires the hyperdrive at the course set on the galaxy map: the ship runs
## ahead along its nose while the stars stretch, the new system is built
## behind the tunnel, and the ship drops out next to one of its planets.
func start_hyperspace_jump() -> void:
	if hyperspace_jump != null or not GalaxyMap.has_target() or landed_body != null:
		return
	if ship.global_position.distance_to(sun.global_position) < _warp_clearance() and not PlayerProgress.god_mode:
		return
	cancel_warp()
	camera_follow_ship = true
	camera_follow_body = null
	_warp_run_start = ship.position
	_warp_run_dir = Vector2.RIGHT.rotated(ship.rotation)

	var target: int = GalaxyMap.target_seed()
	hyperspace_jump = HyperspaceJump.new()
	hyperspace_jump.destination_name = GalaxyMap.system_name(target)
	hyperspace_jump.ready_check = _all_surfaces_ready
	hyperspace_jump.midpoint.connect(_arrive_in_system.bind(target))
	hyperspace_jump.finished.connect(func() -> void:
		hyperspace_jump = null
		music_toast.show_message("ARRIVED: %s" % GalaxyMap.system_name(world_seed).to_upper())
	)
	add_child(hyperspace_jump)


## The run-up: the ship shoots ahead faster and faster (the sim is held, so
## this only moves the node; the arrival places it properly).
func _advance_warp_run_up() -> void:
	var s: float = hyperspace_jump.spool_progress()
	if s >= 1.0:
		return
	ship.position = _warp_run_start + _warp_run_dir * (WARP_RUN_PX * s * s * s / camera_zoom)
	ship.reset_physics_interpolation()


func _all_surfaces_ready() -> bool:
	for body: Node2D in celestial_bodies:
		if not body.call("is_surface_ready"):
			return false
	return true


## Behind the tunnel: build system `system_seed`, spread its planets round
## their orbits, and put the ship in a circular orbit round one of them.
func _arrive_in_system(system_seed: int) -> void:
	set_world_seed(system_seed)

	var sun_mass: float = sun.get("mass")
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	for i in planets.size():
		var planet: Node2D = planets[i]
		var distance: float = (planet.position - sun.position).length()
		planet.position = sun.position + Vector2(distance, 0.0).rotated(rng.randf() * TAU)
		planet.velocity = get_circular_orbit_velocity(planet.position, sun.position, sun_mass)
		physics_planets[i].pull_from_node()
		planet.call("snap_visual_position")
		soi_radii_cache[i] = get_soi_radius(planet)

	var candidates: Array[int] = []
	for i in planets.size():
		if planet_present[i] and not planets[i].get("is_anomaly") and not planets[i].get("is_black_hole"):
			candidates.append(i)
	var index: int = candidates[rng.randi_range(0, candidates.size() - 1)]
	var planet: Node2D = planets[index]
	var radius: float = planet.get("radius")
	var orbit: float = clampf(radius * 5.0, radius * TAKE_OFF_MIN_RADII, maxf(soi_radii_cache[index] * 0.5, radius * TAKE_OFF_MIN_RADII))
	var outward: Vector2 = Vector2.from_angle(rng.randf() * TAU)
	var along: Vector2 = outward.orthogonal()
	set_ship_state(
		planet.position + outward * orbit,
		(planet.velocity as Vector2) + along * sqrt(mu_planets[index] / orbit)
	)
	ship.rotation = along.angle()
	ship.reset_physics_interpolation()
	simulation_accumulator = 0.0

	camera_follow_ship = true
	camera_follow_body = null
	camera_zoom = clampf(get_viewport().get_visible_rect().size.y / (orbit * 5.0), ZOOM_MIN, ZOOM_MAX)
	camera.zoom = Vector2(camera_zoom, camera_zoom)
	camera.position = ship.position
	for i in planets.size():
		update_orbit_line(planets[i], orbit_lines[i], i)
	_restart_trajectory_prediction()


func _ready() -> void:
	# Moved every frame in _process (after the ship's interpolated pose), so
	# it must not be interpolated between physics ticks itself.
	camera.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	for child in planets_container.get_children():
		if child is Node2D:
			planets.append(child)

	celestial_bodies = [sun]
	celestial_bodies.append_array(planets)

	var sun_mass: float = sun.get("mass")
	mu_sun = G * sun_mass

	# Each launch starts every planet at a random point on its orbit; only the
	# orbit radius comes from the scene. The system's roster parks the planets
	# it does not have. Velocity below follows from the new position.
	for planet in planets:
		orbit_radii.append((planet.position - sun.position).length())
		planet_present.append(true)
	var phase_rng := RandomNumberGenerator.new()
	phase_rng.randomize()
	_apply_roster(phase_rng)

	for planet in planets:
		planet.set("mass", float(planet.get("mass")) * PLANET_GRAVITY_SCALE)

	for planet in planets:
		planet.velocity = get_circular_orbit_velocity(
			planet.position,
			sun.position,
			sun_mass
		)
		physics_planets.append(PhysicsBody.new(planet))
		mu_planets.append(G * float(planet.get("mass")))

		var line := Line2D.new()
		line.width = ORBIT_LINE_SCREEN_WIDTH
		line.antialiased = true
		var orbit_color: Color = planet.get("color")
		orbit_color.a = 0.85
		# A black hole's own orbit line would be lensed into a ring and
		# streaks right through it; leave it out.
		if planet.get("is_black_hole"):
			orbit_color.a = 0.0
		line.default_color = orbit_color
		orbit_lines_container.add_child(line)
		orbit_lines.append(line)
		orbit_line_radii.append(-1.0)
		line.add_point(planet.position)
	for i in planets.size():
		if planet_present[i]:
			_active_physics_planets.append(physics_planets[i])
	_show_roster()


	_push_starfield_to_black_holes()

	asteroid_belts = AsteroidBelts.new()
	asteroid_belts.name = "AsteroidBelts"
	add_child(asteroid_belts)
	asteroid_belts.setup(sun.global_position, mu_sun, world_seed)
	asteroid_belt_map = AsteroidBeltMap.new()
	asteroid_belt_map.name = "AsteroidBeltMap"
	$BehindWorld.add_child(asteroid_belt_map)
	# Under the orbit lines.
	$BehindWorld.move_child(asteroid_belt_map, 0)
	asteroid_belt_map.setup(sun.global_position)

	# The planets' terrain bakes started in their own _ready; hold the sim and
	# input behind the loading screen until every one has landed. Coming from
	# the menu the screen is already up (on the root); run straight from the
	# editor, make one.
	loading_screen = LoadingScreen.current
	if loading_screen == null:
		loading_screen = LoadingScreen.new()
		add_child(loading_screen)
	loading_screen.status_text = "Generating planets"
	loading_screen.target_progress = LoadingScreen.SCENE_SHARE
	loading_screen.track_bodies(celestial_bodies)
	loading_screen.finished.connect(func() -> void:
		loading_screen = null
		_spawn_planet_guards()
	)

	var home: Node2D = planets[home_planet_index()]
	var home_mass: float = home.get("mass")

	ship.position = home.position + Vector2(4000, 0)
	var local_ship_velocity: Vector2 = get_circular_orbit_velocity(
		ship.position,
		home.position,
		home_mass
	)
	ship.velocity = home.velocity + local_ship_velocity
	ship.reset_physics_interpolation()
	physics_ship = PhysicsBody.new(ship)
	ship.ship_clicked.connect(_on_ship_clicked)
	ship_blueprint_panel.clicked.connect(_on_ship_clicked)
	# The ship status schematic bottom right, the weapons left of it; the
	# resource bars sit left of the centre gauges.
	ship_blueprint_panel.setup(self)
	ship_blueprint_panel.offset_left = -278.0
	ship_blueprint_panel.offset_top = -448.0
	resource_bars_panel.anchor_left = 0.5
	resource_bars_panel.anchor_right = 0.5
	resource_bars_panel.offset_left = -470.0
	resource_bars_panel.offset_right = -230.0
	resource_bars_panel.offset_top = -324.0
	resource_bars_panel.offset_bottom = -28.0
	orbit_info_button.pressed.connect(_on_orbit_info_pressed)
	_build_clock()
	planet_info_panel.setup(self)
	inventory_screen = preload("res://inventory_screen.gd").new()
	$HUD.add_child(inventory_screen)
	inventory_screen.setup(self, inventory)
	landing_prompt = preload("res://landing_prompt.gd").new()
	$HUD.add_child(landing_prompt)
	collect_prompt = preload("res://landing_prompt.gd").new("E", 1)
	$HUD.add_child(collect_prompt)
	_chart_known_bodies()
	tech_tree_window = TechTreeWindow.new()
	tech_tree_window.name = "TechTreeWindow"
	planet_info_panel.get_parent().add_child(tech_tree_window)
	GalaxyMap.visit(world_seed)
	_update_system_title()
	galaxy_map_window = GalaxyMapWindow.new()
	galaxy_map_window.name = "GalaxyMapWindow"
	galaxy_map_window.course_set.connect(_on_course_set)
	planet_info_panel.get_parent().add_child(galaxy_map_window)
	enemy_contacts_panel = preload("res://enemy_contacts_panel.gd").new()
	enemy_contacts_panel.name = "EnemyContactsPanel"
	enemy_contacts_panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	enemy_contacts_panel.offset_left = -312.0
	enemy_contacts_panel.offset_right = -12.0
	enemy_contacts_panel.offset_top = 12.0
	enemy_contacts_panel.offset_bottom = 300.0
	enemy_contacts_panel.target_picked.connect(_set_target_enemy)
	enemy_contacts_panel.lock_requested.connect(func(enemy: Node2D) -> void: combat.toggle_lock(enemy as Enemy))
	combat = CombatControl.new()
	combat.name = "CombatControl"
	combat.game = self
	combat.ship = ship
	add_child(combat)
	$HUD.add_child(enemy_contacts_panel)
	$HUD.move_child(enemy_contacts_panel, $HUD/PanelContainer.get_index() + 1)
	weapons_panel = preload("res://weapons_panel.gd").new()
	weapons_panel.name = "WeaponsPanel"
	# The module rack, EVE-style: right of the centre gauges.
	weapons_panel.anchor_left = 0.5
	weapons_panel.anchor_right = 0.5
	weapons_panel.anchor_top = 1.0
	weapons_panel.anchor_bottom = 1.0
	weapons_panel.offset_left = 228.0
	weapons_panel.offset_right = 510.0
	weapons_panel.offset_top = -152.0
	weapons_panel.offset_bottom = -28.0
	weapons_panel.weapon_picked.connect(func(id: int) -> void:
		if combat.is_locked():
			combat.toggle_auto_fire(id)
		else:
			_select_weapon(id)
	)
	weapons_panel.radar_scan_requested.connect(func(id: int) -> void: combat.start_scan(id))
	weapons_panel.order_changed.connect(func(ids: Array) -> void:
		ship.weapon_order.clear()
		for id: int in ids:
			ship.weapon_order.append(id)
	)
	$HUD.add_child(weapons_panel)
	$HUD.move_child(weapons_panel, $HUD/ResourceBarsPanel.get_index() + 1)
	warp_button = WarpButton.new()
	warp_button.name = "WarpButton"
	warp_button.size = Vector2(266.0, 44.0)
	warp_button.warp_pressed.connect(start_hyperspace_jump)
	$HUD.add_child(warp_button)
	# Under every window and menu in the HUD, just above the left panel.
	$HUD.move_child(warp_button, $HUD/PanelContainer.get_index() + 1)
	local_warp_button = WarpButton.new()
	local_warp_button.name = "LocalWarpButton"
	local_warp_button.size = Vector2(266.0, 44.0)
	local_warp_button.lit_color = WarpFX.COLOR
	local_warp_button.warp_pressed.connect(start_warp_jump)
	$HUD.add_child(local_warp_button)
	$HUD.move_child(local_warp_button, warp_button.get_index())
	# The warp's space-bending effect draws between the world and the HUD.
	$HUD.layer = 2
	warp_fx = WarpFX.new()
	warp_fx.name = "WarpFX"
	add_child(warp_fx)
	warp_path_line = Line2D.new()
	warp_path_line.name = "WarpPath"
	warp_path_line.default_color = WARP_PATH_COLOR
	warp_path_line.visible = false
	add_child(warp_path_line)

	settings_mgr = SettingsManager.new()
	# In-flight music defaults to off regardless of the saved preference (the
	# main menu keeps its own default). Not saved, so it doesn't clobber what
	# the player picked in the menu - only this scene's starting state.
	settings_mgr.music_muted = true
	settings_mgr.apply_audio_settings()
	music_mgr = MusicManager.new()
	add_child(music_mgr)
	music_mgr.setup(music_player, settings_mgr.autoplay_music)

	settings_menu.setup(settings_mgr, music_mgr)
	settings_button.pressed.connect(toggle_settings_menu)
	settings_menu.closed.connect(_on_settings_menu_closed)
	pause_menu.settings_requested.connect(_on_pause_settings_requested)
	pause_menu.exit_requested.connect(_on_pause_exit_requested)
	ship_builder_panel.closed.connect(close_ship_builder)
	enemy_menu_panel.enemy_selected.connect(_on_enemy_selected)
	_bind_ship_builder_to_ship()
	if ResourceLoader.exists("res://textures/icons/settings.svg"):
		var gear_icon: Texture2D = load("res://textures/icons/settings.svg") as Texture2D
		if gear_icon != null:
			settings_button.icon = gear_icon
			settings_button.text = ""
			settings_button.expand_icon = true
			settings_button.custom_minimum_size = Vector2(20.0, 20.0)
			settings_button.modulate = HudPanelStyle.COLOR_CYAN
	settings_menu.setting_changed.connect(_on_setting_changed)

	music_mgr.track_changed.connect(func(title: String) -> void:
		if _is_first_track_notification:
			_is_first_track_notification = false
			return
		if settings_mgr != null and settings_mgr.show_music_notifications:
			music_toast.show_track(title)
	)

	_apply_all_settings()
	pause_menu.save_requested.connect(save_game)
	# A new game starts with the stock layout in the yard (a loaded one
	# puts its own back in _apply_pending_save).
	if SaveGame.pending.is_empty():
		_build_starter_ship()
	_apply_pending_save()


## A loaded game names its system before the planets generate: they read
## world_seed in their own _ready, which runs before this scene's.
func _enter_tree() -> void:
	if SaveGame.pending.has("world_seed"):
		world_seed = int(SaveGame.pending["world_seed"])
	# Before the planets' own _ready: the ones this system lacks skip building.
	var roster: Dictionary = PlanetRoster.roll(world_seed)
	for child in get_node("Planets").get_children():
		if child is Node2D:
			var name: String = child.get("body_name")
			child.set("present", not PlanetRoster.TIERS.has(name) or roster.has(name))


## Everything about the flight a saved game needs (SaveGame adds the galaxy
## and the player's progress). Positions come from the float64 physics state,
## not the float32 nodes, so far-out planets land back exactly.
func build_save_data() -> Dictionary:
	var planet_states: Array = []
	for body: PhysicsBody in physics_planets:
		planet_states.append([body.x, body.y, body.vx, body.vy])
	var hull_modules: Array = []
	if _builder_controller != null and _builder_controller.get_hull() != null:
		for placed: PlacedModule in _builder_controller.get_hull().get_all_modules():
			hull_modules.append({
				"id": placed.data.id, "origin": placed.origin,
				"rotation": placed.rotation, "health": placed.current_health,
			})
	var day: int = int(sim_time * CLOCK_HOURS_PER_SIM_SECOND / 24.0) + 1
	var system: String = GalaxyMap.system_name(world_seed)
	return {
		"meta": {
			"name": "%s  Day %d" % [system, day],
			"system": system,
			"day": day,
			"saved_unix": int(Time.get_unix_time_from_system()),
		},
		"world_seed": world_seed,
		"sim_time": sim_time,
		"total_sim_time": total_sim_time,
		"planet_visual_time": planet_visual_time,
		"planets": planet_states,
		"ship": [physics_ship.x, physics_ship.y, physics_ship.vx, physics_ship.vy, ship.rotation],
		"landed": planets.find(landed_body) if landed_body != null else -1,
		"landing_offset": _landing_state.get("offset", Vector2.ZERO) if landed_body != null else Vector2.ZERO,
		"camera_zoom": camera_zoom,
		"system_state": _capture_system_state(),
		"hull": hull_modules,
		"ship_resources": [ship.fuel, ship.energy, ship.shield, ship.hull_hp],
		"warp_fuel": ship.warp_fuel,
		"enemy_waves_spawned": _enemy_waves_spawned,
	}


## Saves into this session's slot (pause menu), with a notice.
func save_game() -> void:
	if hyperspace_jump != null or loading_screen != null:
		music_toast.show_message("CAN'T SAVE DURING A JUMP")
		return
	if SaveGame.save_session(build_save_data()).is_empty():
		music_toast.show_message("SAVE FAILED")
	else:
		music_toast.show_message("GAME SAVED")


## Puts a loaded game back (SaveGame.pending), once the scene is built. The
## world seed was already applied in _enter_tree.
func _apply_pending_save() -> void:
	var data: Dictionary = SaveGame.pending
	if data.is_empty():
		return
	SaveGame.pending = {}

	sim_time = float(data.get("sim_time", 0.0))
	total_sim_time = float(data.get("total_sim_time", 0.0))
	planet_visual_time = float(data.get("planet_visual_time", 0.0))
	# Older saves lack the field - mark every past wave as already done so load
	# does not dump a stack of fleets at once.
	if data.has("enemy_waves_spawned"):
		_enemy_waves_spawned = int(data["enemy_waves_spawned"])
	else:
		_enemy_waves_spawned = EnemyWavesScript.waves_due(sim_time, CLOCK_HOURS_PER_SIM_SECOND)

	var planet_states: Array = data.get("planets", [])
	for i in mini(planet_states.size(), physics_planets.size()):
		var state: Array = planet_states[i]
		var body: PhysicsBody = physics_planets[i]
		body.x = state[0]
		body.y = state[1]
		body.vx = state[2]
		body.vy = state[3]
		body.push_to_node()
		planets[i].call("snap_visual_position")
	soi_radii_cache.resize(planets.size())
	for i in planets.size():
		soi_radii_cache[i] = get_soi_radius(planets[i])
		update_orbit_line(planets[i], orbit_lines[i], i)

	var ship_state: Array = data.get("ship", [])
	if ship_state.size() >= 5:
		physics_ship.x = ship_state[0]
		physics_ship.y = ship_state[1]
		physics_ship.vx = ship_state[2]
		physics_ship.vy = ship_state[3]
		physics_ship.push_to_node()
		ship.rotation = ship_state[4]
		ship.reset_physics_interpolation()

	# Charts, finds and collected deposits here; the planets may already have
	# placed deposits from a cached bake, so drop the collected ones now too.
	var state: Dictionary = data.get("system_state", {})
	_restore_system_state(state)
	for i in planets.size():
		var collected: Dictionary = state.get("collected", {}).get(i, {})
		planets[i].set("collected_deposit_seeds", collected.duplicate())
		planets[i].call("drop_collected_deposits")

	_restore_hull(data.get("hull", []))
	ship.warp_fuel = clampf(float(data.get("warp_fuel", ship.WARP_FUEL_CAPACITY)), 0.0, ship.WARP_FUEL_CAPACITY)
	var resources: Array = data.get("ship_resources", [])
	if resources.size() >= 4 and ship.resources_enabled:
		ship.fuel = minf(float(resources[0]), ship.fuel_capacity)
		ship.energy = minf(float(resources[1]), ship.energy_capacity)
		ship.shield = minf(float(resources[2]), ship.shield_strength)
		ship.hull_hp = clampf(float(resources[3]), 1.0, ship.max_hull_hp)

	camera_zoom = clampf(float(data.get("camera_zoom", camera_zoom)), ZOOM_MIN, ZOOM_MAX)
	camera.zoom = Vector2(camera_zoom, camera_zoom)
	camera_follow_ship = true
	camera_follow_body = null
	camera.position = ship.position

	var landed_index: int = int(data.get("landed", -1))
	if landed_index >= 0 and landed_index < planets.size():
		# land_on() reads where the ship came down from, relative to the planet.
		var planet: Node2D = planets[landed_index]
		var body_xy: PackedFloat64Array = get_precise_xy(planet)
		var offset: Vector2 = data.get("landing_offset", Vector2.ZERO)
		set_ship_state(Vector2(body_xy[0], body_xy[1]) + offset, planet.get("velocity"))
		land_on(planet)
	_restart_trajectory_prediction()
	_update_system_title()


## The ship a new game starts with: a light hull holding a fabricator,
## generator, repair module and battery, a chemical engine aft, a DEW laser
## on the ring, and the cockpit forward on a connector. [module id, cell,
## rotation], laid out round the middle of the 40x40 yard.
const STARTER_SHIP := [
	[&"hull_light", Vector2i(18, 18), 0],
	[&"engine_chemical_s", Vector2i(17, 20), 0],
	[&"util_fabricator", Vector2i(18, 20), 0],
	[&"util_generator", Vector2i(20, 20), 0],
	[&"util_repair", Vector2i(22, 20), 0],
	[&"battery_s", Vector2i(22, 21), 0],
	[&"weapon_laser", Vector2i(23, 19), 0],
	[&"connector_straight", Vector2i(23, 21), 0],
	[&"cockpit", Vector2i(24, 20), 0],
]


func _build_starter_ship() -> void:
	var saved: Array = []
	for entry: Array in STARTER_SHIP:
		saved.append({"id": entry[0], "origin": entry[1], "rotation": entry[2]})
	_restore_hull(saved)


## Rebuilds the ship's modules in the builder. Placement rules depend on what
## is already there (engines need their hull), so modules that don't fit yet
## are retried until a pass places nothing more.
func _restore_hull(saved: Array) -> void:
	if saved.is_empty() or _builder_controller == null:
		return
	var hull: ShipHull = _builder_controller.get_hull()
	if hull == null:
		return
	var catalog: Dictionary = {}
	for module: ModuleData in ModuleCatalog.all_buildable_modules():
		catalog[module.id] = module
	for placed: PlacedModule in hull.get_all_modules():
		hull.detach_module(placed.instance_id)
	var remaining: Array = saved.duplicate()
	while not remaining.is_empty():
		var left: Array = []
		for entry: Dictionary in remaining:
			var module: ModuleData = catalog.get(entry["id"])
			if module == null:
				continue
			var attached: PlacedModule = hull.attach_module(module, entry["origin"], int(entry["rotation"]))
			if attached == null:
				left.append(entry)
			else:
				attached.current_health = float(entry.get("health", attached.current_health))
		if left.size() == remaining.size():
			push_warning("Save: %d ship modules could not be placed back" % left.size())
			break
		remaining = left
	_sync_ship_from_builder()


func _process(delta: float) -> void:
	_refresh_time_scale()
	planet_visual_time += delta * minf(time_scale, PLANET_VISUAL_MAX_RATE)
	RenderingServer.global_shader_parameter_set("planet_time", planet_visual_time)
	if _clock_date_label != null:
		_update_clock()
	_update_enemy_waves()
	if _planet_guards_pending and loading_screen == null and _all_surfaces_ready():
		_planet_guards_pending = false
		_spawn_planet_guards()
	update_screen_space_visuals()
	update_soi_visuals()

	update_trajectory_prediction_async(delta)
	refresh_trajectory_line()

	update_osculating_orbit_line()
	if time_scale > 0.0 and loading_screen == null and hyperspace_jump == null:
		combat.update(delta)
	update_hud()
	_update_landing_prompt()
	_update_warp(delta)
	_update_warp_button()
	_update_combat_panels()
	_update_weapon_control(delta)
	if hyperspace_jump != null:
		_advance_warp_run_up()

	if camera_follow_body != null:
		var catch_up_body: float = 1.0 if (settings_mgr != null and not settings_mgr.camera_smoothing) else clampf(5.0 * delta, 0.0, 1.0)
		camera.position = camera.position.lerp(_drawn_position(camera_follow_body), catch_up_body)
	elif camera_follow_ship:
		# Locked dead on the ship: at any speed it stays in the middle of the
		# screen (smoothing only eases the camera onto a planet it follows).
		camera.position = _drawn_position(_test_enemy if _test_enemy != null else ship)

	_sync_camera_3d()
	asteroid_belts.update_view(total_sim_time, camera_zoom)
	asteroid_belt_map.set_zoom(camera_zoom)


## Where `node` is drawn this frame. The ship and planets move in physics
## ticks and are drawn interpolated between the last two; following their
## raw position instead (a tick ahead of the picture) made the ship shake on
## screen when the camera was locked on it, zoomed in. 2D nodes have no
## interpolated-transform getter, so the two tick positions are kept here
## (_record_tick_positions) for whatever the cameras follow.
func _drawn_position(node: Node2D) -> Vector2:
	if node == null or not node.is_physics_interpolated_and_enabled():
		return node.global_position if node != null else Vector2.ZERO
	var ticks: Array = _tick_positions.get(node, [])
	# Unknown, or moved since the tick (a teleport): no in-between to show.
	if ticks.is_empty() or ticks[1] != node.global_position:
		return node.global_position
	return (ticks[0] as Vector2).lerp(ticks[1], Engine.get_physics_interpolation_fraction())


## End of each physics tick: the positions the followed nodes are drawn
## between until the next one.
func _record_tick_positions() -> void:
	var tracked: Dictionary = {}
	for node: Node2D in [ship, camera_follow_body, _test_enemy]:
		if node == null or not is_instance_valid(node):
			continue
		var ticks: Array = _tick_positions.get(node, [])
		var now: Vector2 = node.global_position
		tracked[node] = [ticks[1] if not ticks.is_empty() else now, now]
	_tick_positions = tracked


# The top-down orthographic 3D camera shows exactly what the Camera2D shows:
# the orbital plane (x, y) is the 3D plane (x, 0, z=y), and an ortho `size` is
# the visible height in world units, which is the 2D view height over zoom.
func _sync_camera_3d() -> void:
	# Settle the 2D camera now, so both read the same frame's position.
	camera.force_update_scroll()
	var center: Vector2 = camera.get_screen_center_position()
	camera_3d.position = Vector3(center.x, CAMERA_3D_HEIGHT, center.y)
	camera_3d.size = get_viewport().get_visible_rect().size.y / camera.zoom.y


func update_screen_space_visuals() -> void:
	var inverse_zoom: float = 1.0 / camera_zoom

	for line in orbit_lines:
		line.width = ORBIT_LINE_SCREEN_WIDTH * inverse_zoom
	trajectory_prediction.width = TRAJECTORY_LINE_SCREEN_WIDTH * inverse_zoom
	osculating_orbit_line.width = ORBIT_LINE_SCREEN_WIDTH * inverse_zoom

	for planet in planets:
		planet.soi_line_width = SOI_LINE_SCREEN_WIDTH * inverse_zoom

	for body in celestial_bodies:
		var physical_radius: float = body.get("radius")
		var drawn_radius: float = maxf(
			physical_radius,
			MIN_BODY_SCREEN_RADIUS * inverse_zoom
		)
		if not is_equal_approx(body.get("visual_radius"), drawn_radius):
			body.set("visual_radius", drawn_radius)
		body.call("set_detail_high", drawn_radius * camera_zoom > DETAIL_HIGH_SCREEN_RADIUS)

	var screen_scale := Vector2(inverse_zoom, inverse_zoom)
	periapsis_marker.scale = screen_scale
	apoapsis_marker.scale = screen_scale

	var ship_true_scale: bool = camera_zoom >= SHIP_TRUE_SCALE_ZOOM_THRESHOLD
	ship.scale = Vector2.ONE if ship_true_scale else screen_scale
	ship.true_scale = ship_true_scale

	# Same screen-space marker treatment as the player ship, so hostiles stay
	# readable when the camera is pulled back.
	for child in get_children():
		if child is Enemy:
			var enemy := child as Enemy
			enemy.scale = Vector2.ONE if ship_true_scale else screen_scale
			enemy.true_scale = ship_true_scale


func get_precise_xy(body: Node2D) -> PackedFloat64Array:
	if physics_ship != null and body == physics_ship.node:
		return PackedFloat64Array([physics_ship.x, physics_ship.y])
	for physics_body in physics_planets:
		if physics_body.node == body:
			return PackedFloat64Array([physics_body.x, physics_body.y])
	return PackedFloat64Array([body.position.x, body.position.y])


func get_relative_position_precise(from_body: Node2D, to_body: Node2D) -> Vector2:
	var from_xy: PackedFloat64Array = get_precise_xy(from_body)
	var to_xy: PackedFloat64Array = get_precise_xy(to_body)
	return Vector2(from_xy[0] - to_xy[0], from_xy[1] - to_xy[1])


func _exit_tree() -> void:
	if trajectory_task_id != -1:
		WorkerThreadPool.wait_for_task_completion(trajectory_task_id)


const COLOR_MONO := Color(0.82, 0.85, 0.9)
const COLOR_DIM := Color(0.55, 0.55, 0.62)
const COLOR_GOOD := Color(0.4, 0.9, 0.5)
const COLOR_WARN := Color(0.92, 0.85, 0.35)
const COLOR_BAD := Color(0.95, 0.45, 0.3)
const COLOR_ORBIT_INFO := Color(0.4, 0.9, 1)
func update_hud() -> void:
	# Speed relative to the body whose SOI the ship is in (the sun out in deep
	# space) - what the player actually steers. Against the sun, a planet's own
	# orbital speed would swing the reading as the nose turns.
	var speed_body: Node2D = get_current_orbit_body()
	var speed_body_velocity: Vector2 = Vector2.ZERO if speed_body == sun else speed_body.get("velocity")
	var speed: float = (ship.velocity - speed_body_velocity).length()
	if landed_body != null:
		speed = ground_velocity.length()
	var distance: float = ship.position.distance_to(sun.position)

	speed_gauge.speed = speed
	speed_gauge.zoom = camera_zoom
	distance_label.text = hud_row("Sun distance", "%s SU" % _grouped(distance))
	distance_label.add_theme_color_override("font_color", COLOR_MONO)

	hud_status.set_state(ship.flight_assist and not ship.throttle_locked, ship.throttle_locked, ship.throttle)
	var warp_share: float = ship.warp_fuel / ship.WARP_FUEL_CAPACITY
	var warp_cost: float = _warp_cost_share() if warp_phase == WarpPhase.NONE or warp_phase == WarpPhase.ALIGN else 0.0
	resource_bars_panel.set_warp(warp_share, warp_cost)
	var main_engine_display: float = ship.throttle
	ship_blueprint_panel.set_state(main_engine_display)
	# Placeholder demo values - no fuel/energy/shield gameplay system exists yet.
	if ship.resources_enabled:
		resource_bars_panel.set_values(
			ship.fuel, ship.fuel_capacity, ship.energy, ship.energy_capacity,
			ship.shield, ship.shield_strength, ship.hull_hp, ship.max_hull_hp, ship.powered
		)
	else:
		# The stock ship (nothing built yet) has no limits: shown full.
		resource_bars_panel.set_unlimited()

	var lock_suffix: String = "  [LOCK]" if ship.throttle_locked else ""
	if ship.flight_assist and not ship.throttle_locked:
		lock_suffix += "  [FA]"
	match int(ship.attitude_hold):
		1:
			lock_suffix += "  [PRO]"
		2:
			lock_suffix += "  [RETRO]"

	if time_scale == 0.0:
		thrust_label.text = hud_row("Thrust", "PAUSED" + lock_suffix)
		thrust_label.add_theme_color_override("font_color", COLOR_WARN)
	elif ship.throttle > 0.0:
		thrust_label.text = hud_row(
			"Thrust", "%d SU/s2%s" % [roundi(ship.thrust_force * ship.throttle / ship.ship_mass), lock_suffix]
		)
		thrust_label.add_theme_color_override("font_color", COLOR_MONO)
	else:
		thrust_label.text = hud_row("Thrust", "OFF" + lock_suffix)
		thrust_label.add_theme_color_override("font_color", COLOR_DIM)

	var orbit_node: Node2D = get_current_orbit_body()
	var orbit_body: String = get_orbiting_body()

	if landed_body != null:
		orbit_label.text = hud_row("Landed", landed_body.get("body_name"))
		orbit_label.add_theme_color_override("font_color", COLOR_GOOD)
	elif orbit_body == "None":
		orbit_label.text = hud_row("Orbit", "None")
		orbit_label.add_theme_color_override("font_color", COLOR_DIM)
	else:
		orbit_label.text = hud_row("Orbit", orbit_body)
		orbit_label.add_theme_color_override("font_color", COLOR_MONO)

	soi_label.text = hud_row("SOI", get_current_soi())
	soi_label.add_theme_color_override("font_color", COLOR_MONO)

	if ship.fov_devices.size() > 0:
		soi_label.text = hud_row("SOI", get_current_soi()) + "\n" + hud_row("Sensors", _sensor_summary())

	if landed_body != null:
		trajectory_label.text = hud_row("Trajectory", "Surface flight")
		trajectory_label.add_theme_color_override("font_color", COLOR_MONO)
	elif trajectory_status == "IMPACT":
		trajectory_label.text = hud_row("Trajectory", "IMPACT - " + trajectory_target)
		trajectory_label.add_theme_color_override("font_color", COLOR_MONO)
	else:
		trajectory_label.text = hud_row("Trajectory", trajectory_status)
		trajectory_label.add_theme_color_override("font_color", COLOR_MONO)

	if has_bound_orbit:
		eccentricity_label.text = hud_row("Eccentricity", "%.3f" % current_eccentricity)
		eccentricity_label.add_theme_color_override("font_color", COLOR_MONO)
		pe_gauge.set_value(current_periapsis_altitude, true)
		ap_gauge.set_value(current_apoapsis_altitude, true)
	else:
		eccentricity_label.text = hud_row("Eccentricity", "--")
		eccentricity_label.add_theme_color_override("font_color", COLOR_DIM)
		pe_gauge.set_value(0.0, false)
		ap_gauge.set_value(0.0, false)


# A two-column "Label    Value" row instead of "* Label: Value" - this only
# works because Theme_hud uses a monospace font (Cascadia Mono/Consolas/
# Courier New), so fixed space-padding actually lines up into columns,
# matching the reference HUD look.
const HUD_LABEL_WIDTH := 14


func hud_row(label: String, value: String) -> String:
	return label.rpad(HUD_LABEL_WIDTH) + value


func get_body_display_color(body: Node2D) -> Color:
	if body == null:
		return COLOR_DIM
	return body.get("color")


func get_delta_v_color(remaining: float) -> Color:
	if remaining <= 0.1:
		return COLOR_GOOD
	if remaining <= 1.0:
		return COLOR_WARN
	return COLOR_BAD


func get_body_name(body: Node2D) -> String:
	if body == null:
		return "None"

	return body.get("body_name")


func update_trajectory_prediction_async(delta: float) -> void:
	if trajectory_task_id != -1:
		if not WorkerThreadPool.is_task_completed(trajectory_task_id):
			return
		WorkerThreadPool.wait_for_task_completion(trajectory_task_id)
		trajectory_task_id = -1
		apply_trajectory_result(trajectory_task_holder.get("result", {}))

	# Nothing to predict with the ship pinned inside a planet; take_off()
	# starts a fresh prediction. None in warp either (on rails, no gravity).
	if landed_body != null or warp_active:
		return
	prediction_update_accumulator += delta
	if prediction_update_accumulator < PREDICTION_UPDATE_INTERVAL:
		return
	prediction_update_accumulator = 0.0

	var snapshot: Dictionary = build_trajectory_snapshot()
	var holder := {}
	trajectory_task_holder = holder
	trajectory_task_id = WorkerThreadPool.add_task(
		func() -> void: holder.result = predict_trajectory(snapshot)
	)


func build_trajectory_snapshot() -> Dictionary:
	# Only the planets this system has; `indices` maps back to planets[].
	var here: Array[Node2D] = present_planets()
	var indices := PackedInt32Array()
	for planet: Node2D in here:
		indices.append(planets.find(planet))
	var count: int = here.size()
	var positions := PackedVector2Array()
	var velocities := PackedVector2Array()
	var radii := PackedFloat64Array()
	var masses := PackedFloat64Array()
	var soi_radii := PackedFloat64Array()
	var names: Array[String] = []
	positions.resize(count)
	velocities.resize(count)
	radii.resize(count)
	masses.resize(count)
	soi_radii.resize(count)

	for i in range(count):
		positions[i] = here[i].position
		velocities[i] = here[i].velocity
		radii[i] = here[i].get("radius")
		masses[i] = here[i].get("mass")
		soi_radii[i] = get_soi_radius(here[i])
		names.append(get_body_name(here[i]))

	return {
		"ship_pos": ship.position,
		"ship_vel": ship.velocity,
		"ship_radius": ship.get("collision_radius"),
		"sun_pos": sun.position,
		"sun_mass": sun.get("mass"),
		"sun_radius": sun.get("radius"),
		"sun_name": get_body_name(sun),
		"positions": positions,
		"velocities": velocities,
		"radii": radii,
		"masses": masses,
		"soi_radii": soi_radii,
		"names": names,
		"t0": total_sim_time,
		"ref": here.find(get_current_orbit_body()),
		"indices": indices,
		"prediction_steps": 12000 if (settings_mgr != null and settings_mgr.trajectory_long_prediction) else PREDICTION_STEPS,
	}


func apply_trajectory_result(result: Dictionary) -> void:
	if result.is_empty():
		return

	_trajectory_points = result.get("points", PackedVector2Array())
	_trajectory_times = result.get("times", PackedFloat32Array())
	_trajectory_t0 = result.get("t0", total_sim_time)
	# The predictor saw only the planets that are here: back to planets[].
	var ref: int = result.get("ref", -1)
	var indices: PackedInt32Array = result.get("indices", PackedInt32Array())
	_trajectory_ref = indices[ref] if ref >= 0 and ref < indices.size() else -1
	_trajectory_rel_points = result.get("rel_points", PackedVector2Array())
	refresh_trajectory_line()
	update_trajectory_status(result.get("status", "ORBIT"), result.get("target", ""))

	match trajectory_status:
		"IMPACT":
			trajectory_prediction.default_color = Color.RED
		"ESCAPE":
			trajectory_prediction.default_color = Color.ORANGE
		"ORBIT":
			trajectory_prediction.default_color = Color.CYAN


## Draws the stored prediction from where the ship is now: points the ship has
## already flown past are dropped and the line starts at the ship itself.
## Cheap enough for every frame - it only slices the stored arrays.
func refresh_trajectory_line() -> void:
	if _trajectory_points.is_empty() or _trajectory_times.size() != _trajectory_points.size():
		return

	var elapsed: float = total_sim_time - _trajectory_t0
	var first: int = _trajectory_times.bsearch(elapsed, false)
	if first >= _trajectory_points.size():
		trajectory_prediction.points = PackedVector2Array([ship.position])
		return

	var drawn := PackedVector2Array([ship.position])
	if _trajectory_ref >= 0 and _trajectory_ref < planets.size():
		# Orbit round one planet: offsets from it, placed where it is now.
		var origin: Vector2 = planets[_trajectory_ref].position
		for i in range(first, _trajectory_rel_points.size()):
			drawn.append(origin + _trajectory_rel_points[i])
	else:
		drawn.append_array(_trajectory_points.slice(first))
	trajectory_prediction.points = drawn


static func predict_trajectory(snap: Dictionary) -> Dictionary:
	var points := PackedVector2Array()
	var times := PackedFloat32Array()
	var predicted_status := "ORBIT"
	var predicted_target := ""
	var collision_detected := false

	var ship_pos: Vector2 = snap.ship_pos
	var ship_vel: Vector2 = snap.ship_vel
	var ship_radius: float = snap.ship_radius
	var sun_pos: Vector2 = snap.sun_pos
	var sun_mass: float = snap.sun_mass
	var sun_radius: float = snap.sun_radius
	var positions: PackedVector2Array = snap.positions.duplicate()
	var velocities: PackedVector2Array = snap.velocities.duplicate()
	var radii: PackedFloat64Array = snap.radii
	var masses: PackedFloat64Array = snap.masses
	var soi_radii: PackedFloat64Array = snap.soi_radii
	var names: Array = snap.names
	var count: int = positions.size()

	# Relative copies for drawing round the starting SOI body, as long as the
	# ship never leaves its SOI.
	var ref: int = snap.get("ref", -1)
	var rel_points := PackedVector2Array()
	var stays_in_ref: bool = ref >= 0

	points.append(ship_pos)
	times.append(0.0)
	if stays_in_ref:
		rel_points.append(ship_pos - positions[ref])
	var last_heading: Vector2 = ship_vel.normalized()
	var steps_since_point: int = 0

	var accelerations := PackedVector2Array()
	accelerations.resize(count)
	for i in range(count):
		accelerations[i] = _gravity_at(positions[i], sun_pos, sun_mass)
	var ship_acc: Vector2 = _predicted_ship_gravity(
		ship_pos, positions, accelerations, masses, soi_radii, sun_pos, sun_mass
	)
	var prediction_dt_squared: float = PREDICTION_DT * PREDICTION_DT

	var next_positions := PackedVector2Array()
	var next_accelerations := PackedVector2Array()
	next_positions.resize(count)
	next_accelerations.resize(count)

	var total_steps: int = snap.get("prediction_steps", PREDICTION_STEPS)
	for step in range(total_steps):
		var previous_ship_pos: Vector2 = ship_pos
		var previous_positions: PackedVector2Array = positions.duplicate()

		for i in range(count):
			next_positions[i] = (
				positions[i]
				+ velocities[i] * PREDICTION_DT
				+ accelerations[i] * 0.5 * prediction_dt_squared
			)
		var next_ship_pos: Vector2 = (
			ship_pos
			+ ship_vel * PREDICTION_DT
			+ ship_acc * 0.5 * prediction_dt_squared
		)

		for i in range(count):
			next_accelerations[i] = _gravity_at(next_positions[i], sun_pos, sun_mass)
		var next_ship_acc: Vector2 = _predicted_ship_gravity(
			next_ship_pos, next_positions, next_accelerations, masses, soi_radii, sun_pos, sun_mass
		)

		for i in range(count):
			velocities[i] += (accelerations[i] + next_accelerations[i]) * 0.5 * PREDICTION_DT
		ship_vel += (ship_acc + next_ship_acc) * 0.5 * PREDICTION_DT

		positions = next_positions.duplicate()
		ship_pos = next_ship_pos
		accelerations = next_accelerations.duplicate()
		ship_acc = next_ship_acc

		var hit: Variant = null
		for i in range(count):
			hit = get_moving_collision(
				previous_ship_pos,
				ship_pos,
				previous_positions[i],
				positions[i],
				ship_radius + radii[i]
			)

			if hit != null:
				predicted_target = names[i]
				break

		if hit != null:
			points.append(hit)
			times.append((step + 1) * PREDICTION_DT)
			predicted_status = "IMPACT"
			collision_detected = true
			break

		hit = _segment_circle_collision(
			previous_ship_pos, ship_pos, sun_pos, sun_radius + ship_radius
		)

		if hit != null:
			points.append(hit)
			times.append((step + 1) * PREDICTION_DT)
			predicted_status = "IMPACT"
			predicted_target = snap.sun_name
			collision_detected = true
			break

		if stays_in_ref and ship_pos.distance_squared_to(positions[ref]) > soi_radii[ref] * soi_radii[ref]:
			stays_in_ref = false

		steps_since_point += 1
		var heading: Vector2 = (ship_pos - points[points.size() - 1]).normalized()
		if (
			steps_since_point >= PREDICTION_DRAW_INTERVAL
			or absf(last_heading.angle_to(heading)) > PREDICTION_DRAW_TURN
		):
			points.append(ship_pos)
			times.append((step + 1) * PREDICTION_DT)
			if stays_in_ref:
				rel_points.append(ship_pos - positions[ref])
			last_heading = ship_vel.normalized()
			steps_since_point = 0

	if not collision_detected:
		# Judged against whatever holds the ship where the prediction ends: a
		# planet whose SOI it is still in, else the sun. Against the sun alone,
		# a low orbit round a planet reads as an escape on every prograde half,
		# because the planet's own orbital speed is added on.
		var holder_pos: Vector2 = sun_pos
		var holder_vel := Vector2.ZERO
		var holder_mass: float = sun_mass
		for i in range(count):
			if ship_pos.distance_to(positions[i]) <= soi_radii[i]:
				holder_pos = positions[i]
				holder_vel = velocities[i]
				holder_mass = masses[i]
				break
		predicted_status = (
			"ESCAPE" if _is_escape_trajectory(ship_pos, ship_vel - holder_vel, holder_pos, holder_mass)
			else "ORBIT"
		)

	return {
		"points": points,
		"times": times,
		"t0": snap.get("t0", 0.0),
		"ref": ref if stays_in_ref and rel_points.size() == points.size() else -1,
		"indices": snap.get("indices", PackedInt32Array()),
		"rel_points": rel_points,
		"status": predicted_status,
		"target": predicted_target,
	}


static func _gravity_at(position: Vector2, source_position: Vector2, source_mass: float) -> Vector2:
	var offset: Vector2 = source_position - position
	var distance: float = offset.length()

	if distance < 1.0:
		return Vector2.ZERO

	return offset.normalized() * (G * source_mass / (distance * distance))


static func _predicted_ship_gravity(
	ship_position: Vector2,
	planet_positions: PackedVector2Array,
	planet_accelerations: PackedVector2Array,
	planet_masses: PackedFloat64Array,
	soi_radii: PackedFloat64Array,
	sun_pos: Vector2,
	sun_mass: float
) -> Vector2:
	for i in range(planet_positions.size()):
		if ship_position.distance_to(planet_positions[i]) <= soi_radii[i]:
			return _gravity_at(
				ship_position, planet_positions[i], planet_masses[i]
			) + planet_accelerations[i]
	return _gravity_at(ship_position, sun_pos, sun_mass)


static func get_moving_collision(
	ship_start: Vector2,
	ship_end: Vector2,
	body_start: Vector2,
	body_end: Vector2,
	combined_radius: float
) -> Variant:
	var relative_start: Vector2 = ship_start - body_start
	var relative_velocity: Vector2 = (
		(ship_end - ship_start)
		- (body_end - body_start)
	)

	if relative_start.length() <= combined_radius:
		return ship_start

	var a: float = relative_velocity.dot(relative_velocity)

	if a == 0.0:
		return null

	var b: float = 2.0 * relative_start.dot(relative_velocity)
	var c: float = (
		relative_start.dot(relative_start)
		- combined_radius * combined_radius
	)
	var discriminant: float = b * b - 4.0 * a * c

	if discriminant < 0.0:
		return null

	var sqrt_discriminant: float = sqrt(discriminant)
	var t1: float = (-b - sqrt_discriminant) / (2.0 * a)
	var t2: float = (-b + sqrt_discriminant) / (2.0 * a)
	var t := -1.0

	if t1 >= 0.0 and t1 <= 1.0:
		t = t1
	elif t2 >= 0.0 and t2 <= 1.0:
		t = t2

	if t < 0.0:
		return null

	return ship_start + (ship_end - ship_start) * t


static func _segment_circle_collision(
	start: Vector2,
	end: Vector2,
	center: Vector2,
	radius: float
) -> Variant:
	if start.distance_to(center) <= radius:
		return start

	var d: Vector2 = end - start
	var f: Vector2 = start - center
	var a: float = d.dot(d)

	if a == 0.0:
		return null

	var b: float = 2.0 * f.dot(d)
	var c: float = f.dot(f) - radius * radius
	var discriminant: float = b * b - 4.0 * a * c

	if discriminant < 0.0:
		return null

	discriminant = sqrt(discriminant)

	var t1: float = (-b - discriminant) / (2.0 * a)
	var t2: float = (-b + discriminant) / (2.0 * a)
	var t := -1.0

	if t1 >= 0.0 and t1 <= 1.0:
		t = t1
	elif t2 >= 0.0 and t2 <= 1.0:
		t = t2

	if t < 0.0:
		return null

	return start + d * t


static func _is_escape_trajectory(
	position: Vector2,
	velocity: Vector2,
	center: Vector2,
	center_mass: float
) -> bool:
	var distance: float = position.distance_to(center)

	if distance < 1.0:
		return false

	var escape_velocity: float = sqrt(2.0 * G * center_mass / distance)
	var radial_direction: Vector2 = (position - center).normalized()
	var radial_velocity: float = velocity.dot(radial_direction)

	return (
		velocity.length() >= escape_velocity
		and radial_velocity > 0.0
	)


func update_trajectory_status(
	predicted_status: String,
	predicted_target: String
) -> void:
	if predicted_status == "IMPACT":
		trajectory_status = predicted_status
		trajectory_target = predicted_target
		trajectory_candidate_status = ""
		trajectory_candidate_target = ""
		trajectory_candidate_frames = 0
		return

	if predicted_status == trajectory_status:
		trajectory_candidate_status = ""
		trajectory_candidate_target = ""
		trajectory_candidate_frames = 0
		return

	if (
		predicted_status != trajectory_candidate_status
		or predicted_target != trajectory_candidate_target
	):
		trajectory_candidate_status = predicted_status
		trajectory_candidate_target = predicted_target
		trajectory_candidate_frames = 1
		return

	trajectory_candidate_frames += 1

	if trajectory_candidate_frames >= TRAJECTORY_CONFIRM_FRAMES:
		trajectory_status = trajectory_candidate_status
		trajectory_target = trajectory_candidate_target
		trajectory_candidate_status = ""
		trajectory_candidate_target = ""
		trajectory_candidate_frames = 0


func _on_ship_clicked() -> void:
	camera_follow_ship = true
	camera_follow_body = null


## The sun or planet drawn under the mouse, if any - the nearest one when
## several overlap the click.
func _body_under_mouse() -> Node2D:
	var point: Vector2 = get_global_mouse_position()
	var pick_reach: float = BODY_PICK_SCREEN_RADIUS / camera_zoom
	var best: Node2D = null
	var best_distance: float = INF
	for body in celestial_bodies:
		var drawn_radius: float = body.get("visual_radius")
		var distance: float = point.distance_to(body.global_position)
		if distance <= drawn_radius + pick_reach and distance < best_distance:
			best = body
			best_distance = distance
	return best


## Date and mission-day readout under the panel title.
func _build_clock() -> void:
	_clock_epoch_unix = Time.get_unix_time_from_datetime_dict(CLOCK_EPOCH)

	var row := HBoxContainer.new()
	row.name = "ClockRow"
	_clock_date_label = Label.new()
	_clock_date_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_clock_date_label.add_theme_color_override("font_color", HudPanelStyle.COLOR_CYAN)
	_clock_date_label.add_theme_font_size_override("font_size", 13)
	_clock_day_label = Label.new()
	_clock_day_label.add_theme_color_override("font_color", HudPanelStyle.COLOR_TEXT_MUTED)
	_clock_day_label.add_theme_font_size_override("font_size", 12)
	row.add_child(_clock_date_label)
	row.add_child(_clock_day_label)

	_clock_wave_label = Label.new()
	_clock_wave_label.name = "WaveLabel"
	_clock_wave_label.add_theme_color_override("font_color", Color(1.0, 0.45, 0.32))
	_clock_wave_label.add_theme_font_size_override("font_size", 12)

	var title_row: Node = $HUD/PanelContainer/VBoxContainer/TitleRow
	title_row.add_sibling(row)
	row.add_sibling(_clock_wave_label)
	_update_clock()


func _update_clock() -> void:
	var hours: float = sim_time * CLOCK_HOURS_PER_SIM_SECOND
	var now: Dictionary = Time.get_datetime_dict_from_unix_time(
		_clock_epoch_unix + int(hours * 3600.0)
	)
	_clock_date_label.text = "%02d %s %d   %02d:%02d" % [
		now.day, MONTH_NAMES[now.month - 1], now.year, now.hour, now.minute
	]
	_clock_day_label.text = "DAY %d" % (int(hours / 24.0) + 1)
	_update_wave_label()


func _update_wave_label() -> void:
	if _clock_wave_label == null:
		return
	_prune_wave_enemies()
	var alive: int = _wave_enemies.size()
	if alive > 0:
		_clock_wave_label.text = "WAVE %d ACTIVE  ·  %d LEFT" % [
			_enemy_waves_spawned, alive
		]
		return
	var hours_left: int = EnemyWavesScript.hours_until_next(
		sim_time, CLOCK_HOURS_PER_SIM_SECOND, _enemy_waves_spawned
	)
	var next_wave: int = _enemy_waves_spawned + 1
	if hours_left <= 0:
		_clock_wave_label.text = "WAVE %d IMMINENT" % next_wave
	elif hours_left == 1:
		_clock_wave_label.text = "WAVE %d IN 1 HOUR" % next_wave
	else:
		_clock_wave_label.text = "WAVE %d IN %d HOURS" % [next_wave, hours_left]


## Fire any waves that are due for the current sim day (also catches up after load).
func _update_enemy_waves() -> void:
	if loading_screen != null or hyperspace_jump != null:
		return
	if time_scale <= 0.0:
		return
	var due: int = EnemyWavesScript.waves_due(sim_time, CLOCK_HOURS_PER_SIM_SECOND)
	while _enemy_waves_spawned < due:
		_spawn_enemy_wave()


func _spawn_enemy_wave() -> void:
	_enemy_waves_spawned += 1
	var spawned: Array[Enemy] = EnemyWavesScript.spawn_wave(self, ship, _enemy_waves_spawned)
	_wave_enemies.append_array(spawned)
	music_toast.show_message(
		"HOSTILE WAVE %d     %d contacts inbound" % [_enemy_waves_spawned, spawned.size()]
	)
	_update_wave_label()


func _prune_wave_enemies() -> void:
	var kept: Array[Enemy] = []
	for enemy: Enemy in _wave_enemies:
		if is_instance_valid(enemy) and not enemy.is_queued_for_deletion():
			kept.append(enemy)
	_wave_enemies = kept


func _clear_wave_enemies() -> void:
	for enemy: Enemy in _wave_enemies:
		if is_instance_valid(enemy):
			enemy.queue_free()
	_wave_enemies.clear()


func _on_orbit_info_pressed() -> void:
	if planet_info_panel.visible:
		planet_info_panel.hide_panel()
		return

	planet_info_panel.open_on(get_current_orbit_body())


func toggle_settings_menu() -> void:
	if settings_menu.visible:
		settings_menu.close_menu()
	else:
		_settings_opened_from_pause = false
		settings_menu.open_menu()


func _handle_escape() -> void:
	if settings_menu.visible:
		settings_menu.close_menu()
		return
	if pause_menu.visible:
		pause_menu.close()
		return
	pause_menu.open()


func _on_pause_settings_requested() -> void:
	pause_menu.close()
	_settings_opened_from_pause = true
	settings_menu.open_menu()


func _on_settings_menu_closed() -> void:
	if _settings_opened_from_pause:
		_settings_opened_from_pause = false
		pause_menu.open()


func _on_pause_exit_requested() -> void:
	save_game()
	get_tree().change_scene_to_file("res://scenes/menu/MainMenu.tscn")


func toggle_ship_builder() -> void:
	if ship_builder_panel.visible:
		close_ship_builder()
	else:
		open_ship_builder()


func open_ship_builder() -> void:
	ship_builder_panel.visible = true


func close_ship_builder() -> void:
	# A built ship needs a cockpit, at least one main engine, and all its
	# hulls and the cockpit joined into one; with nothing built the stock ship
	# flies as before.
	var problem: String = _builder_launch_problem()
	if problem != "":
		if _builder_controller != null:
			_builder_controller.show_warning(problem)
		return
	ship_builder_panel.visible = false
	_sync_ship_from_builder()


func _builder_launch_problem() -> String:
	if _builder_controller == null or _builder_controller.get_hull() == null:
		return ""
	var modules: Array[PlacedModule] = _builder_controller.get_hull().get_all_modules()
	if modules.is_empty():
		return ""
	var cockpit: bool = modules.any(func(m: PlacedModule) -> bool: return m.data.category == ModuleData.Category.COCKPIT)
	var engine: bool = modules.any(func(m: PlacedModule) -> bool: return m.data.is_main_engine())
	if not cockpit and not engine:
		return "The ship needs a cockpit and an engine before it can leave the yard."
	if not cockpit:
		return "The ship needs a cockpit before it can leave the yard."
	if not engine:
		return "The ship needs an engine before it can leave the yard."
	# Hull pieces and the cockpit must form one ship, joined by connectors.
	var loose: Array[PlacedModule] = _builder_controller.get_hull().unconnected_hull_like()
	if loose.any(func(m: PlacedModule) -> bool: return m.data.category == ModuleData.Category.COCKPIT):
		return "The cockpit is not joined to the hull: put a connector between them."
	if not loose.is_empty():
		return "%d hull%s not joined to the rest: link them with connectors." % [loose.size(), "" if loose.size() == 1 else "s"]
	var floating: Array[PlacedModule] = _builder_controller.get_hull().unattached_modules()
	if not floating.is_empty():
		var names: PackedStringArray = []
		for m: PlacedModule in floating:
			if not names.has(m.data.title):
				names.append(m.data.title)
		return "Not attached to the ship: %s. Move or remove %s." % [", ".join(names), "it" if floating.size() == 1 else "them"]
	return ""


func toggle_enemy_menu() -> void:
	if enemy_menu_panel == null:
		return
	if enemy_menu_panel.visible:
		enemy_menu_panel.visible = false
	else:
		enemy_menu_panel.refresh()
		enemy_menu_panel.visible = true


## Hostile craft in circular orbits around every non-anomaly planet except
## the one the ship is at (home on first load, arrival world after a jump).
## T3 deposit worlds get the elite roster; the rest get basic craft.
func _spawn_planet_guards() -> void:
	_clear_planet_guards()
	# Discovery order in the galaxy: first system = 0, each new jump +1.
	var system_depth: int = maxi(0, GalaxyMap.index_of(world_seed))
	_planet_guards = PlanetGuardsScript.spawn_system(
		self, present_planets(), G, _planet_nearest_ship(), system_depth
	)


## The planet the player is currently beside - no guards spawn there.
func _planet_nearest_ship() -> Node2D:
	var best: Node2D = null
	var best_d2: float = INF
	for planet: Node2D in planets:
		if planet.get("is_anomaly") or planet.get("is_black_hole"):
			continue
		var d2: float = ship.position.distance_squared_to(planet.position)
		if d2 < best_d2:
			best_d2 = d2
			best = planet
	return best


func _clear_planet_guards() -> void:
	for enemy: Enemy in _planet_guards:
		if is_instance_valid(enemy):
			enemy.queue_free()
	_planet_guards.clear()


## Spawns the chosen sandbox enemy at the player ship's position and hands
## WASD/Space control to it (see simulation_step's _test_enemy guard).
func _on_enemy_selected(enemy_id: String) -> void:
	var entry: Dictionary = EnemyCatalog.entry_for(enemy_id)
	if entry.is_empty():
		return

	if _test_enemy != null:
		_test_enemy.queue_free()
		_test_enemy = null

	var scene: PackedScene = entry.get("scene") as PackedScene
	if scene == null:
		return

	var enemy := scene.instantiate() as Enemy
	EnemyCatalog.configure(enemy, enemy_id)
	ship.get_parent().add_child(enemy)
	enemy.global_position = ship.global_position
	enemy.rotation = ship.rotation
	_test_enemy = enemy
	enemy.tree_exiting.connect(_on_test_enemy_exiting.bind(enemy))

	enemy_menu_panel.visible = false


func _on_test_enemy_exiting(enemy: Enemy) -> void:
	if _test_enemy == enemy:
		_test_enemy = null


func _bind_ship_builder_to_ship() -> void:
	_builder_controller = ship_builder_panel as ShipBuilderController
	if _builder_controller == null:
		return
	var hull: ShipHull = _builder_controller.get_hull()
	if hull == null:
		return
	if not hull.stats_changed.is_connected(_on_builder_stats_changed):
		hull.stats_changed.connect(_on_builder_stats_changed)
	_sync_ship_from_builder()


func _on_builder_stats_changed(_stats: Dictionary) -> void:
	_sync_ship_from_builder()


func _sync_ship_from_builder() -> void:
	if ship == null or _builder_controller == null:
		return
	ship.apply_module_stats(_builder_controller.get_stats_dictionary())
	ship.apply_fov_devices(_builder_controller.get_fov_devices())
	# What was built is what flies: its picture in space and in the HUD.
	var visual: Dictionary = ShipRender.compose(_builder_controller.get_hull()) if _builder_controller.get_hull() != null else {}
	ship.set_built_visual(visual)
	ship_blueprint_panel.set_built_texture(visual.get("texture"))


func _try_fire_fov_weapon() -> void:
	if ship == null or landed_body != null:
		return
	# Enemies first: the picked target if a gun covers it, else the nearest
	# enemy inside a weapon cone; each shot's damage goes to it.
	var target: Enemy = null
	var target_dist := INF
	if targeted_enemy != null and is_instance_valid(targeted_enemy) and targeted_enemy.is_alive():
		if _enemy_in_weapon_cone(targeted_enemy):
			target = targeted_enemy
			target_dist = -1.0
	for child in get_children():
		if child is Enemy and child != _test_enemy and (child as Enemy).is_alive():
			var dist: float = ship.global_position.distance_to(child.global_position)
			if dist < target_dist and ship.fov_devices.any(
				func(device: Dictionary) -> bool:
					return str(device.get("kind", "")) == "weapon" and ship.is_body_in_device_fov(device, child.global_position)
			):
				target = child
				target_dist = dist
	if target != null:
		_spawn_weapon_shots(ship.fire_weapons_at(target.global_position), target.global_position, target)


func _on_setting_changed(key: String, value: Variant) -> void:
	match key:
		"show_orbit_lines":
			for i in orbit_lines.size():
				orbit_lines[i].visible = value and planet_present[i]
		"show_soi_circles":
			for planet in planets:
				planet.show_soi = value
		"show_trajectory":
			trajectory_prediction.visible = value
		"starfield_brightness":
			if background_mask != null:
				background_mask.color.a = clampf(1.0 - float(value), 0.0, 1.0)
			_push_starfield_to_black_holes()
		"camera_smoothing":
			pass
		"god_mode":
			# Everything the catalog and tree show may have changed.
			if planet_info_panel.visible:
				planet_info_panel.queue_redraw()
			if tech_tree_window != null and tech_tree_window.visible:
				tech_tree_window.open()


## Black holes lens the star image directly (see celestial_body.set_starfield).
func _push_starfield_to_black_holes() -> void:
	if background_image == null:
		return
	var dim: float = background_mask.color.a if background_mask != null else 0.0
	for planet in planets:
		planet.call("set_starfield", background_image.texture, dim)


func _apply_all_settings() -> void:
	if settings_mgr == null:
		return
	for i in orbit_lines.size():
		orbit_lines[i].visible = settings_mgr.show_orbit_lines and planet_present[i]
	for planet in planets:
		planet.show_soi = settings_mgr.show_soi_circles
	trajectory_prediction.visible = settings_mgr.show_trajectory
	if background_mask != null:
		background_mask.color.a = clampf(1.0 - settings_mgr.starfield_brightness, 0.0, 1.0)
	_push_starfield_to_black_holes()


## Time runs at 1x or not at all: there is no time acceleration - long
## trips are made with the warp drive instead. `time_scale` is 0 while the
## player paused (P / Space / the panel) or while a full-screen panel is open
## (_is_menu_open), 1 otherwise.
func set_time_scale(value: float) -> void:
	_user_paused = value <= 0.0
	_refresh_time_scale()


func toggle_pause() -> void:
	set_time_scale(1.0 if _user_paused else 0.0)


## Galaxy map, builder, tech tree, catalog, cargo hold, settings, pause and
## enemy menus all hold the game while they are up.
func _is_menu_open() -> bool:
	for panel: Control in [
		galaxy_map_window, tech_tree_window, ship_builder_panel, planet_info_panel,
		inventory_screen, settings_menu, pause_menu, enemy_menu_panel,
	]:
		if panel != null and panel.visible:
			return true
	return false


func _refresh_time_scale() -> void:
	var held: bool = _user_paused or _is_menu_open()
	var scale: float = 0.0 if held else 1.0
	# Held, this runs every frame so whatever spawns meanwhile (fighters,
	# shots) freezes too; running, only once on the way out.
	if scale == time_scale and not held:
		return
	time_scale = scale
	if ship != null:
		ship.paused = held
	# Enemies, their shots and the player's shots run on their own _process
	# and know nothing of the sim clock: freeze them with it.
	for child in get_children():
		if child is Enemy or child is PlayerShot or child is LaserBolt or child is SniperBeam or child is DamageZone:
			child.process_mode = Node.PROCESS_MODE_DISABLED if held else Node.PROCESS_MODE_INHERIT


func get_circular_orbit_velocity(
	body_position: Vector2,
	center_position: Vector2,
	center_mass: float
) -> Vector2:
	var offset: Vector2 = body_position - center_position
	var distance: float = offset.length()

	if distance < 1.0:
		return Vector2.ZERO

	var speed: float = sqrt(G * center_mass / distance)
	var tangent := Vector2(-offset.y, offset.x).normalized()

	return tangent * speed


func get_orbital_energy(
	ship_position: Vector2,
	ship_velocity: Vector2,
	body_position: Vector2,
	body_velocity: Vector2,
	body_mass: float
) -> float:
	var relative_position: Vector2 = ship_position - body_position
	var relative_velocity: Vector2 = ship_velocity - body_velocity
	var distance: float = relative_position.length()

	if distance < 1.0:
		return INF

	return (
		relative_velocity.length_squared() / 2.0
		- G * body_mass / distance
	)


func get_orbiting_body() -> String:
	var body: Node2D = get_current_orbit_body()

	if not is_bound_orbit(body):
		return "None"

	return get_body_name(body)


func get_soi_radius(body: Node2D) -> float:
	if body.get("present") == false:
		return 0.0
	var distance_to_sun: float = body.position.distance_to(sun.position)
	var body_mass: float = body.get("mass")
	var sun_mass: float = sun.get("mass")

	var laplace: float = distance_to_sun * pow(
		body_mass / sun_mass,
		0.4
	)
	# Small, light planets close to the sun get a Laplace sphere barely wider
	# than the planet - no room to orbit. Give every planet at least
	# MIN_SOI_RADII of its own radius (checked against its neighbours' SOIs).
	if body == sun:
		return laplace
	return maxf(laplace, float(body.get("radius")) * MIN_SOI_RADII)


func is_inside_soi(
	object_position: Vector2,
	body: Node2D
) -> bool:
	if body == sun:
		return true

	var soi_radius: float = get_soi_radius(body)
	var distance: float = object_position.distance_to(body.position)

	return distance <= soi_radius


func get_current_soi() -> String:
	return get_body_name(get_current_orbit_body())


func get_current_orbit_body() -> Node2D:
	for planet in planets:
		if is_inside_soi(ship.position, planet):
			return planet

	return sun


func is_bound_orbit(body: Node2D) -> bool:
	var body_velocity := Vector2.ZERO

	if body != sun:
		body_velocity = body.get("velocity")

	var relative_position: Vector2 = ship.position - body.position
	var relative_velocity: Vector2 = ship.velocity - body_velocity
	var distance: float = relative_position.length()
	var body_radius: float = body.get("radius")

	if distance <= body_radius:
		return false

	var body_mass: float = body.get("mass")
	var specific_energy: float = (
		relative_velocity.length_squared() / 2.0
		- G * body_mass / distance
	)

	return specific_energy < 0.0


func update_osculating_orbit_line() -> void:
	osculating_orbit_line.clear_points()
	has_bound_orbit = false
	periapsis_marker.visible = false
	apoapsis_marker.visible = false

	var body: Node2D = get_current_orbit_body()
	var body_velocity: Vector2 = Vector2.ZERO

	if body != sun:
		body_velocity = body.get("velocity")

	var r_vec: Vector2 = ship.position - body.position
	var v_vec: Vector2 = ship.velocity - body_velocity
	var r: float = r_vec.length()

	if r <= 0.0:
		osculating_orbit_line.visible = false
		return

	var body_mass: float = body.get("mass")
	var mu: float = G * body_mass
	var v2: float = v_vec.length_squared()
	var energy: float = (
		v2 / 2.0
		- mu / r
	)

	if energy >= 0.0:
		osculating_orbit_line.visible = false
		return

	var a: float = -mu / (2.0 * energy)
	var rv: float = r_vec.dot(v_vec)
	var eccentricity_vector: Vector2 = (
		((v2 - mu / r) * r_vec - rv * v_vec)
		/ mu
	)
	var e: float = eccentricity_vector.length()

	if e >= 1.0:
		osculating_orbit_line.visible = false
		return

	var periapsis: float = a * (1.0 - e)
	var _apoapsis: float = a * (1.0 + e)
	var body_radius: float = body.get("radius")
	var ship_radius: float = ship.get("collision_radius")
	var minimum_radius: float = body_radius + ship_radius

	if periapsis <= minimum_radius:
		osculating_orbit_line.visible = false
		return

	current_periapsis = periapsis
	current_apoapsis = _apoapsis
	current_eccentricity = e
	current_periapsis_altitude = periapsis - body_radius
	current_apoapsis_altitude = _apoapsis - body_radius
	has_bound_orbit = true

	osculating_orbit_line.visible = true

	const MIN_MARKER_ECCENTRICITY := 0.02
	const PERIAPSIS_DIRECTION_SMOOTHING := 3.0
	var periapsis_direction: Vector2 = osculating_periapsis_direction

	if e >= MIN_MARKER_ECCENTRICITY:
		var raw_direction: Vector2 = eccentricity_vector.normalized()
		var smoothing: float = clampf(
			PERIAPSIS_DIRECTION_SMOOTHING * get_process_delta_time() * time_scale,
			0.0,
			1.0
		)
		osculating_periapsis_direction = (
			osculating_periapsis_direction
			.slerp(raw_direction, smoothing)
			.normalized()
		)
		periapsis_direction = osculating_periapsis_direction

	var periapsis_position: Vector2 = (
		body.position
		+ periapsis_direction * periapsis
	)
	var apoapsis_position: Vector2 = (
		body.position
		- periapsis_direction * _apoapsis
	)

	if e >= MIN_MARKER_ECCENTRICITY:
		periapsis_marker.position = periapsis_position
		apoapsis_marker.position = apoapsis_position
		periapsis_marker.visible = true
		apoapsis_marker.visible = true

	var perpendicular := Vector2(
		-periapsis_direction.y,
		periapsis_direction.x
	)

	const ORBIT_POINTS := 360

	for point_index in range(ORBIT_POINTS + 1):
		var theta: float = (
			TAU * float(point_index) / float(ORBIT_POINTS)
		)
		var orbit_radius: float = (
			a * (1.0 - e * e)
			/ (1.0 + e * cos(theta))
		)
		var relative_point: Vector2 = (
			periapsis_direction
			* cos(theta)
			* orbit_radius
			+
			perpendicular
			* sin(theta)
			* orbit_radius
		)

		osculating_orbit_line.add_point(
			body.position + relative_point
		)


func update_soi_visuals() -> void:
	for planet in planets:
		planet.soi_radius = get_soi_radius(planet)


## The planet close enough to land on, nearest first, or null.
func _find_landing_candidate() -> Node2D:
	if _test_enemy != null:
		return null
	var best: Node2D = null
	var best_distance: float = INF
	for i in range(planets.size()):
		var planet: Node2D = planets[i]
		if planet.get("is_black_hole") or not planet_present[i]:
			continue  # No surface to land on.
		var reach: float = float(planet.get("radius")) * LANDING_RANGE_RADII
		if i < soi_radii_cache.size():
			reach = minf(reach, soi_radii_cache[i])
		var distance: float = ship.global_position.distance_to(planet.global_position)
		if distance < reach and distance < best_distance:
			best = planet
			best_distance = distance
	return best


func _update_landing_prompt() -> void:
	if landed_body != null:
		landing_prompt.show_prompt(
			"TAKE OFF", "Surface of %s     WASD move     RMB go to cursor     Shift slow" % landed_body.get("body_name")
		)
		var index: int = landed_body.call("deposit_under_view", ship.get("collision_radius"))
		if index < 0:
			collect_prompt.hide_prompt()
		else:
			var type_name: StringName = landed_body.get("resource_deposits")[index]["type"]
			if is_resource_found_on(landed_body, type_name):
				collect_prompt.show_prompt(
					"COLLECT %s" % String(ResourceDeposits.TYPES[type_name]["name"]).to_upper(),
					"In the hold: %d     I to open" % inventory.count(type_name)
				)
			else:
				collect_prompt.show_prompt("COLLECT UNIDENTIFIED SAMPLE", "Unknown signal right under the ship")
		return
	collect_prompt.hide_prompt()
	landing_candidate = _find_landing_candidate()
	if landing_candidate == null:
		landing_prompt.hide_prompt()
	else:
		landing_prompt.show_prompt(
			"LAND ON %s" % String(landing_candidate.get("body_name")).to_upper(),
			"You are over its surface"
		)


## Camera zoom that shows `view_radii` of the landed planet's radii, top to
## bottom.
func _landed_zoom(view_radii: float) -> float:
	var radius: float = landed_body.get("radius")
	return get_viewport().get_visible_rect().size.y / (radius * view_radii)


## Lands on `body`: the ship leaves its orbit and flies over the surface, the
## camera close in over it, time at 1x and the space overlays hidden.
func land_on(body: Node2D) -> void:

	var body_xy: PackedFloat64Array = get_precise_xy(body)
	var offset := Vector2(physics_ship.x - body_xy[0], physics_ship.y - body_xy[1])
	var relative_velocity: Vector2 = ship.velocity - (body.get("velocity") as Vector2)
	_landing_state = {
		"offset": offset,
		"prograde": 1.0 if offset.cross(relative_velocity) >= 0.0 else -1.0,
		"zoom": camera_zoom,
		"follow_ship": camera_follow_ship,
		"follow_body": camera_follow_body,
	}

	landed_body = body
	ship.landed = true
	ground_velocity = Vector2.ZERO
	ship.disengage_manual_main_engine()
	body.set("surface_driven", true)
	_pin_ship_to(body)

	camera_follow_ship = true
	camera_follow_body = null
	camera_zoom = _landed_zoom(LANDED_VIEW_RADII)
	camera.zoom = Vector2(camera_zoom, camera_zoom)
	camera.position = ship.position
	_set_space_overlays_visible(false)
	_restart_trajectory_prediction()


## Takes off from the landed planet into a circular orbit round it, where the
## ship came down from (at least TAKE_OFF_MIN_RADII out, inside the SOI).
func take_off() -> void:
	var body: Node2D = landed_body
	var index: int = planets.find(body)
	var offset: Vector2 = _landing_state["offset"]
	var radius: float = body.get("radius")
	var distance: float = clampf(offset.length(), radius * TAKE_OFF_MIN_RADII, maxf(soi_radii_cache[index] * 0.8, radius * TAKE_OFF_MIN_RADII))
	var outward: Vector2 = offset.normalized() if offset.length() > 1.0 else Vector2.RIGHT
	var speed: float = sqrt(mu_planets[index] / distance)
	var along: Vector2 = outward.rotated(PI * 0.5) * float(_landing_state["prograde"])

	body.set("surface_driven", false)
	landed_body = null
	ship.landed = false
	ground_velocity = Vector2.ZERO
	ship.disengage_manual_main_engine()
	var body_xy: PackedFloat64Array = get_precise_xy(body)
	set_ship_state(
		Vector2(body_xy[0], body_xy[1]) + outward * distance,
		(body.get("velocity") as Vector2) + along * speed
	)

	camera_zoom = _landing_state["zoom"]
	camera.zoom = Vector2(camera_zoom, camera_zoom)
	camera_follow_ship = _landing_state["follow_ship"]
	camera_follow_body = _landing_state["follow_body"]
	_set_space_overlays_visible(true)
	_restart_trajectory_prediction()


## Forgets the old prediction and its status and predicts again on the next
## frame - after landing or taking off the ship is somewhere else entirely.
func _restart_trajectory_prediction() -> void:
	if trajectory_task_id != -1:
		WorkerThreadPool.wait_for_task_completion(trajectory_task_id)
		trajectory_task_id = -1
	trajectory_status = "ORBIT"
	trajectory_target = ""
	trajectory_candidate_status = ""
	trajectory_candidate_target = ""
	trajectory_candidate_frames = 0
	prediction_update_accumulator = PREDICTION_UPDATE_INTERVAL


## Gathers the deposit the landed ship is over, if there is one: it leaves the
## surface, goes into the inventory, and the catalog learns the resource
## (and that it grows on this planet).
func collect_under_ship() -> void:
	var index: int = landed_body.call("deposit_under_view", ship.get("collision_radius"))
	if index < 0:
		return
	var deposit: Dictionary = landed_body.call("collect_deposit", index)
	var type_name: StringName = deposit["type"]
	var first_find: bool = not is_resource_known(type_name)
	inventory.add(type_name, 1, String(landed_body.get("body_name")))
	mark_resource_found(landed_body, type_name)
	var label: String = String(ResourceDeposits.TYPES[type_name]["name"]).to_upper()
	music_toast.show_message(
		("NEW RESOURCE: %s     J to view" if first_find else "COLLECTED: %s") % label
		+ "     ×%d" % inventory.count(type_name)
	)
	if planet_info_panel.visible:
		planet_info_panel.queue_redraw()


## One step of driving over the surface: ground_velocity eases toward where
## the keys (or the cursor) say to go - no drift, it stops when they let go -
## and the nose turns smoothly to face the way the ship moves. The engine
## flame follows the speed, so it still reads as flying.
func _drive_on_ground(dt: float) -> void:
	var top_speed: float = float(landed_body.get("radius")) * GROUND_SPEED_RADII * ship.precision_scale()
	var target := Vector2.ZERO
	var keys := Vector2(
		float(Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT))
			- float(Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT)),
		float(Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN))
			- float(Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP))
	)
	if keys != Vector2.ZERO:
		target = keys.normalized() * top_speed
	elif Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
		var to_cursor: Vector2 = ship.get_global_mouse_position() - ship.global_position
		var distance: float = to_cursor.length()
		if distance > 1.0:
			target = to_cursor / distance * minf(top_speed, distance * GROUND_FOLLOW_GAIN)
	ground_velocity = ground_velocity.lerp(target, 1.0 - exp(-dt / GROUND_RESPONSE))
	if ground_velocity.length() < top_speed * 0.002 and target == Vector2.ZERO:
		ground_velocity = Vector2.ZERO
	var speed: float = ground_velocity.length()
	if speed > top_speed * 0.05:
		ship.rotation = lerp_angle(ship.rotation, ground_velocity.angle(), 1.0 - exp(-dt * GROUND_TURN_RESPONSE))
	ship.throttle = clampf(speed / maxf(top_speed, 1e-6), 0.0, 1.0)


## Picks the weapon in panel slot `slot` (0-based), or puts it away if it
## is already picked.
func _select_weapon_slot(slot: int) -> void:
	var weapons: Array[Dictionary] = ship.ordered_weapons()
	if slot < 0 or slot >= weapons.size():
		return
	_select_weapon(int(weapons[slot].get("instance_id", -1)))


func _select_weapon(instance_id: int) -> void:
	ship.selected_weapon = -1 if ship.selected_weapon == instance_id else instance_id
	_firing_held = false
	ship.queue_redraw()


## Every frame: RMB turns the selected turret toward the cursor, and a held
## LMB keeps firing the selected weapon (its reload sets the pace).
func _update_weapon_control(delta: float) -> void:
	if ship.selected_weapon >= 0 and ship.selected_device().is_empty():
		ship.selected_weapon = -1
	if ship.selected_weapon < 0 or landed_body != null or hyperspace_jump != null:
		_firing_held = false
		return
	if Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
		ship.aim_selected(ship.get_global_mouse_position(), delta)
	if _firing_held and not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		_firing_held = false
	if _firing_held:
		_fire_selected_weapon()


## Fires the selected weapon where it points: at the picked target if that is
## in its cone, else the nearest enemy in it, else straight out to its reach.
func _fire_selected_weapon() -> void:
	var device: Dictionary = ship.selected_device()
	if device.is_empty():
		return
	var target: Enemy = null
	if targeted_enemy != null and is_instance_valid(targeted_enemy) and targeted_enemy.is_alive() \
			and ship.is_body_in_device_fov(device, targeted_enemy.global_position):
		target = targeted_enemy
	else:
		var best := INF
		for child in get_children():
			if child is Enemy and child != _test_enemy and (child as Enemy).is_alive():
				var d: float = ship.global_position.distance_to(child.global_position)
				if d < best and ship.is_body_in_device_fov(device, child.global_position):
					best = d
					target = child
	var aim: Vector2
	if target != null:
		aim = target.global_position
	else:
		aim = ship.device_world_origin(device) + ship.device_world_facing(device) * float(device.get("range", 1000.0)) * 0.98
	_spawn_weapon_shots(ship.fire_weapons_at(aim, int(device.get("instance_id", -1))), aim, target)


## Turns weapons that just fired into shots: the sniper's beam hits at once;
## everything else flies as PlayerShot projectiles with that weapon's look -
## pellets, bursts and alternating barrels included.
func _spawn_weapon_shots(fired: Array[Dictionary], aim: Vector2, target: Enemy) -> void:
	for device: Dictionary in fired:
		if device.get("id", &"") == ship.SNIPER_ID:
			_spawn_sniper_beam(device, aim)
			continue
		var fx: Dictionary = PlayerShot.fx_for(device.get("id", &""))
		var burst: int = int(fx.get("burst", 1))
		var id: int = int(device.get("instance_id", -1))
		for b in burst:
			if b == 0:
				_spawn_projectiles(id, aim)
			else:
				get_tree().create_timer(float(fx.get("burst_gap", 0.1)) * b).timeout.connect(_spawn_projectiles.bind(id, aim))


## The player's Sniper Laser: one long yellow beam out to its full reach,
## like the enemy sniper's, hitting every enemy along it. It rides along with
## the ship's muzzle while it fades.
func _spawn_sniper_beam(device: Dictionary, aim: Vector2) -> void:
	var muzzle: Vector2 = ship.device_world_origin(device)
	var direction: Vector2 = ship.device_world_facing(device)
	if ship.is_body_in_device_fov(device, aim) and aim.distance_to(muzzle) > 1.0:
		direction = (aim - muzzle).normalized()
	var beam := SniperBeam.new()
	beam.direction = direction
	beam.reach = float(device.get("range", 16000.0))
	beam.damage = float(device.get("damage", 0.0))
	beam.glow_color = ship.SNIPER_GLOW_COLOR
	beam.core_color = ship.SNIPER_CORE_COLOR
	beam.hits_player = false
	beam.ignore_enemy = _test_enemy
	beam.carrier = ship
	beam.carrier_offset = (muzzle - ship.global_position).rotated(-ship.rotation)
	add_child(beam)
	beam.global_position = muzzle


func _spawn_projectiles(instance_id: int, aim: Vector2) -> void:
	var device: Dictionary = {}
	for candidate: Dictionary in ship.fov_devices:
		if int(candidate.get("instance_id", -1)) == instance_id:
			device = candidate
	if device.is_empty():
		return
	var fx: Dictionary = PlayerShot.fx_for(device.get("id", &""))
	var facing: Vector2 = ship.device_world_facing(device)
	var origin: Vector2 = ship.device_world_origin(device)
	# Out to the muzzle: from a turret's middle to the edge it fires from.
	var muzzle_reach: float = (device.get("local_origin", Vector2.ZERO) as Vector2).distance_to(device.get("center", device.get("local_origin", Vector2.ZERO)))
	var muzzle: Vector2 = origin + facing * muzzle_reach
	var barrels: int = int(fx.get("barrels", 1))
	if barrels > 1:
		var barrel: int = int(_next_barrel.get(instance_id, 0))
		_next_barrel[instance_id] = (barrel + 1) % barrels
		muzzle += facing.orthogonal() * FovUtil.WORLD_UNITS_PER_CELL * 0.3 * (1.0 if barrel == 0 else -1.0)
	# Toward the aim point if the gun covers it, else straight out.
	var direction: Vector2 = facing
	if ship.is_body_in_device_fov(device, aim) and aim.distance_to(muzzle) > 1.0:
		direction = (aim - muzzle).normalized()
	var pellets: int = int(fx.get("pellets", 1))
	var half_spread: float = deg_to_rad(float(fx.get("spread", 0.0))) * 0.5
	var half_cone: float = deg_to_rad(float(device.get("angle_deg", 0.0))) * 0.5
	var aim_offset: float = clampf(facing.angle_to(direction), -half_cone, half_cone)
	for p in pellets:
		var shot := PlayerShot.new()
		shot.fx = fx
		shot.damage = float(device.get("damage", 0.0)) / float(pellets)
		shot.max_distance = float(device.get("range", 1000.0))
		# Keep even a single imperfect shot inside the cone shown in the preview.
		var low: float = maxf(-half_spread, -half_cone - aim_offset)
		var high: float = minf(half_spread, half_cone - aim_offset)
		var offset: float = aim_offset + randf_range(low, high)
		var dir: Vector2 = facing.rotated(offset)
		shot.velocity = dir * float(fx["speed"]) * PlayerShot.SPEED_SCALE + ship.velocity
		shot.ignore = _test_enemy
		add_child(shot)
		shot.global_position = muzzle


func _enemy_in_weapon_cone(enemy: Node2D) -> bool:
	return ship.fov_devices.any(
		func(device: Dictionary) -> bool:
			return str(device.get("kind", "")) == "weapon" and ship.is_body_in_device_fov(device, enemy.global_position)
	)


func _set_target_enemy(enemy: Node2D) -> void:
	combat.set_target(enemy as Enemy)
	targeted_enemy = combat.target


## The HUD's Sensors row: contacts held, and what the radar is doing.
func _sensor_summary() -> String:
	var text: String = "%d contacts" % combat.contacts().size()
	for row: Dictionary in combat.radar_rows():
		if float(row["scan"]) > 0.0:
			return text + ", scanning"
		if float(row["reload"]) > 0.0:
			return text + ", radar recharging"
	return text + (", radar ready" if not combat.radar_devices().is_empty() else "")


## Contacts and weapons panels, every frame.
func _update_combat_panels() -> void:
	targeted_enemy = combat.target
	var contacts: Array = combat.contacts()
	var status: String = ""
	if combat.radar_devices().is_empty():
		status = "Sensors reach %s. Fit a radar to see further" % _short_distance(combat.passive_range())
	else:
		status = "No contacts. R scans with the radar"
	enemy_contacts_panel.set_state(contacts, status, targeted_enemy, combat.is_locked())
	# "LOCK" per gun: the target, or else the nearest contact, in its cone.
	var aim: Enemy = targeted_enemy
	if aim == null and not contacts.is_empty():
		aim = contacts[0]["enemy"]
	var weapons: Array = []
	for device: Dictionary in ship.ordered_weapons():
		var reload_time: float = maxf(float(device.get("reload_time", 0.0)), 0.05)
		var left: float = float(ship._weapon_cooldowns.get(int(device.get("instance_id", -1)), 0.0))
		# Rapid-fire guns (the DEW) show a steady full bar instead of a flicker.
		if reload_time < RAPID_FIRE_RELOAD:
			left = 0.0
		# Where it would shoot now: at the aim if its cone covers it, else ahead.
		var shoot_dir: Vector2 = ship.device_local_facing(device)
		if aim != null and ship.is_body_in_device_fov(device, aim.global_position):
			shoot_dir = ship.to_local(aim.global_position) - ship.device_local_origin(device)
		weapons.append({
			"blocked": ship.is_shot_blocked(device, shoot_dir),
			"id": int(device.get("instance_id", -1)),
			"module_id": device.get("id", &""),
			"title": device.get("title", "Weapon"),
			"reload": left / reload_time,
			"on_target": aim != null and ship.is_body_in_device_fov(device, aim.global_position),
			"auto": combat.auto_fire.has(int(device.get("instance_id", -1))),
		})
	weapons.append_array(combat.radar_rows())
	weapons_panel.set_state(weapons, ship.powered, ship.selected_weapon, combat.is_locked())


## The hull reached 0: the ship is rebuilt, full, in orbit round the home
## planet of this system - the hold and everything learned are kept.
func _respawn_destroyed_ship() -> void:
	if landed_body != null:
		take_off()
	cancel_warp()
	var index: int = home_planet_index()
	var home: Node2D = planets[index]
	var body: PhysicsBody = physics_planets[index]
	var distance: float = 4000.0
	var along := Vector2(0.0, 1.0)
	set_ship_state(
		Vector2(body.x, body.y) + Vector2(distance, 0.0),
		Vector2(body.vx, body.vy) + along * sqrt(mu_planets[index] / distance)
	)
	ship.reset_physics_interpolation()
	ship.refill()
	camera_follow_ship = true
	camera_follow_body = null
	camera.position = ship.position
	_restart_trajectory_prediction()
	music_toast.show_message("SHIP DESTROYED     Rebuilt in orbit of %s" % String(home.get("body_name")).to_upper())


## Holds the ship on the planet's centre, moving with it.
## Reads the planet's PhysicsBody, not its node: the nodes are only pushed once
## per physics tick, and this runs every sim step.
func _pin_ship_to(body: Node2D) -> void:
	var state: PhysicsBody = physics_planets[planets.find(body)]
	physics_ship.x = state.x
	physics_ship.y = state.y
	physics_ship.vx = state.vx
	physics_ship.vy = state.vy
	physics_ship.push_to_node()


## Orbit lines, trajectory, markers and the orbit gauges: off on a planet
## surface (where they mean nothing) and while the player has them hidden
## (Alt, `orbit_overlays_on`).
func _set_space_overlays_visible(shown: bool) -> void:
	shown = shown and orbit_overlays_on
	($BehindWorld as CanvasLayer).visible = shown
	pe_gauge.visible = shown
	ap_gauge.visible = shown


func toggle_orbit_overlays() -> void:
	orbit_overlays_on = not orbit_overlays_on
	_set_space_overlays_visible(landed_body == null)


## Whether the ship has surveyed `body` (see charted_bodies). God mode
## (debug) charts everything.
func is_charted(body: Node2D) -> bool:
	return PlayerProgress.god_mode or charted_bodies.has(body)


## Whether the player has found a resource of this type on `body` as it is
## now - on this planet, in the variant it has rolled, in any system.
func is_resource_found_on(body: Node2D, type_name: StringName) -> bool:
	if PlayerProgress.god_mode:
		return _has_deposit(body, type_name)
	if not ResourceDeposits.TYPES[type_name].get("collectible", true):
		return is_charted(body) and _has_deposit(body, type_name)
	return Journal.is_found(get_body_name(body), _variant_of(body), type_name)


## Whether the player has found a resource of this type anywhere.
func is_resource_known(type_name: StringName) -> bool:
	if PlayerProgress.god_mode:
		return true
	return Journal.is_known(type_name) or not bodies_where_found(type_name).is_empty()


## The bodies the player has found this type on, in catalog order.
func bodies_where_found(type_name: StringName) -> Array[Node2D]:
	var found: Array[Node2D] = []
	for body: Node2D in [sun] + planets:
		if is_resource_found_on(body, type_name):
			found.append(body)
	return found


## Records a find: this type, on this body - for gathering to call. Unlocks
## the resource in the catalog, and on that planet's page.
func mark_resource_found(body: Node2D, type_name: StringName) -> void:
	Journal.record_find(get_body_name(body), body.get("terrain_params"), type_name)


func _variant_of(body: Node2D) -> String:
	return (body.get("terrain_params") as Dictionary).get("variant", "")


## Charts `body` in this system and records the world it is in the Journal.
## True if that variant (or a trait of it) was new to the Journal.
func _chart(body: Node2D) -> bool:
	charted_bodies[body] = true
	if body == sun or body.get("is_anomaly"):
		return false
	var body_name: String = get_body_name(body)
	var params: Dictionary = body.get("terrain_params")
	var new: bool = not Journal.has_seen(body_name, params.get("variant", ""))
	for flag: String in PlanetLore.traits_of(body.get("terrain_kind")):
		if params.get(flag, false) == true and not Journal.has_seen_trait(body_name, flag):
			new = true
	Journal.record_world(body_name, params)
	return new


## The sun and the home planet: known from the start in every system.
func _chart_known_bodies() -> void:
	_chart(sun)
	_chart(planets[home_planet_index()])


## Places every planet for this system's roster (PlanetRoster): the ones it
## has at a random point `rng` picks on their own orbits, the rest parked far
## out and hidden. Velocities follow; the physics state too once it exists.
func _apply_roster(rng: RandomNumberGenerator) -> void:
	_roll_roster()
	var sun_mass: float = sun.get("mass")
	_active_physics_planets.clear()
	for i in planets.size():
		var planet: Node2D = planets[i]
		var here: bool = planet_present[i]
		var radius: float = orbit_radii[i] if here else PARK_RADIUS + float(i) * PARK_SPACING
		planet.position = sun.position + Vector2(radius, 0.0).rotated(rng.randf() * TAU)
		planet.velocity = get_circular_orbit_velocity(planet.position, sun.position, sun_mass)
		if i < physics_planets.size():
			physics_planets[i].pull_from_node()
		planet.call("set_present", here)
		planet.call("snap_visual_position")
		if i < soi_radii_cache.size():
			soi_radii_cache[i] = get_soi_radius(planet)
		if here and i < physics_planets.size():
			_active_physics_planets.append(physics_planets[i])


## Which planets this system has (PlanetRoster.roll(world_seed)), into
## planet_present and each planet's `present` - before rebuild_surface, so the
## ones it lacks build nothing.
func _roll_roster() -> void:
	var roster: Dictionary = PlanetRoster.roll(world_seed)
	for i in planets.size():
		var name: String = planets[i].get("body_name")
		planet_present[i] = not PlanetRoster.TIERS.has(name) or roster.has(name)
		planets[i].set("present", planet_present[i])


## The planets this system has.
func present_planets() -> Array[Node2D]:
	var result: Array[Node2D] = []
	for i in planets.size():
		if planet_present[i]:
			result.append(planets[i])
	return result


## Orbit lines for the planets this system has.
func _show_roster() -> void:
	for i in planets.size():
		if i < orbit_lines.size():
			orbit_lines[i].visible = planet_present[i] and (settings_mgr == null or settings_mgr.show_orbit_lines)


## The planet the ship starts and is rebuilt at: Coralyss if this system has
## it, else the first planet it has that is not a giant or an anomaly.
func home_planet_index() -> int:
	if planet_present.is_empty() or planet_present[HOME_PLANET_INDEX]:
		return HOME_PLANET_INDEX
	for i in planets.size():
		if planet_present[i] and not planets[i].get("is_anomaly") and not PlanetTerrain.is_gas(planets[i].get("terrain_kind")):
			return i
	for i in planets.size():
		if planet_present[i]:
			return i
	return HOME_PLANET_INDEX


func _has_deposit(body: Node2D, type_name: StringName) -> bool:
	for deposit: Dictionary in body.get("resource_deposits"):
		if deposit["type"] == type_name:
			return true
	return false


## Charts every body the ship has come close to, with a notice for each.
func _chart_nearby_bodies() -> void:
	for i in range(planets.size()):
		var planet: Node2D = planets[i]
		if charted_bodies.has(planet) or not planet_present[i]:
			continue
		var reach: float = maxf(soi_radii_cache[i], float(planet.get("radius")) * CHART_RADII)
		if ship.global_position.distance_to(planet.global_position) < reach:
			var label: String = String(planet.get("body_name")).to_upper()
			var new_variant: bool = _chart(planet)
			var variant: String = PlanetLore.variant_label(planet.get("terrain_kind"), planet.get("terrain_params"))
			if new_variant and variant != "":
				music_toast.show_message("NEW VARIANT: %s - %s     J to view" % [label, variant.to_upper()])
			else:
				music_toast.show_message("SURVEYED: %s     J to view" % label)
			if planet_info_panel.visible:
				planet_info_panel.queue_redraw()


func _physics_process(delta: float) -> void:
	if loading_screen != null or hyperspace_jump != null:
		return
	simulation_accumulator += delta * time_scale
	sim_time += delta * time_scale

	var steps := 0

	if soi_radii_cache.size() != planets.size():
		soi_radii_cache.resize(planets.size())
	for i in range(planets.size()):
		soi_radii_cache[i] = get_soi_radius(planets[i])
	_chart_nearby_bodies()

	while simulation_accumulator >= SIM_DT and steps < MAX_SIM_STEPS_PER_FRAME:
		simulation_step(SIM_DT)
		simulation_accumulator -= SIM_DT
		total_sim_time += SIM_DT
		steps += 1

	if steps > 0:
		for body: PhysicsBody in _active_physics_planets:
			body.push_to_node()
		for i in range(planets.size()):
			if planet_present[i]:
				update_orbit_line(planets[i], orbit_lines[i], i)

	_record_tick_positions()

	# Global so every planet shader lights itself from the sun without each
	# body needing to know where the sun is.
	RenderingServer.global_shader_parameter_set(
		"sun_position", Vector3(sun.global_position.x, 0.0, sun.global_position.y)
	)


func simulation_step(dt: float) -> void:
	ship.poll_lock_toggle(true)

	# While test-flying a sandbox enemy (E menu), the player ship stops reading
	# WASD/mouse-aim so both craft don't respond to the same keys at once.
	if _test_enemy == null and not warp_active:
		# Prograde / retrograde hold follows the orbit around the current SOI body
		# (from the SOI cache and the precise state - this runs every step).
		var hold_index: int = _ship_soi_index_precise()
		var hold_body_velocity: Vector2 = Vector2.ZERO
		if hold_index >= 0:
			var hold_body: PhysicsBody = physics_planets[hold_index]
			hold_body_velocity = Vector2(hold_body.vx, hold_body.vy)
		ship.hold_reference_velocity = ship.velocity - hold_body_velocity
		if landed_body != null:
			# Flight assist and the holds work against the ground.
			ship.hold_reference_velocity = ground_velocity

		if landed_body != null:
			pass # Ground driving steers the ship itself (below).
		elif warp_phase == WarpPhase.ALIGN:
			_advance_warp_align(dt)
		else:
			ship.update_rotation(dt)

		if landed_body == null:
			ship.update_throttle(dt)

	# Fuel, energy, shields and repairs, from what the engines are doing now.
	var engine_output: float = 0.0
	if landed_body == null and ship.has_fuel():
		engine_output = ship.throttle
	ship.update_resources(dt, engine_output, landed_body != null)
	if ship.is_destroyed():
		_respawn_destroyed_ship()
		return

	var landed: bool = landed_body != null

	# Ship acceleration at the start of the step, planets where they are now.
	# Landed, the ship is not integrated at all - it is pinned below.
	var ship_a0: Vector2 = Vector2.ZERO if (landed or warp_active) else get_ship_acceleration_precise()

	# Planets feel only the sun: a whole velocity-Verlet step each, inline -
	# this loop runs for every planet on every step, hundreds of times a frame
	# under time warp, so no per-planet calls or array allocations here.
	var sun_x: float = sun.position.x
	var sun_y: float = sun.position.y
	var half_dt: float = 0.5 * dt
	var half_dt2: float = 0.5 * dt * dt
	# Only the planets this system has; the parked ones stay put.
	for body: PhysicsBody in _active_physics_planets:
		var dx: float = sun_x - body.x
		var dy: float = sun_y - body.y
		var d2: float = dx * dx + dy * dy
		var k0: float = mu_sun / (d2 * sqrt(d2)) if d2 >= 1.0 else 0.0
		var ax0: float = dx * k0
		var ay0: float = dy * k0
		body.x += body.vx * dt + ax0 * half_dt2
		body.y += body.vy * dt + ay0 * half_dt2
		dx = sun_x - body.x
		dy = sun_y - body.y
		d2 = dx * dx + dy * dy
		var k1: float = mu_sun / (d2 * sqrt(d2)) if d2 >= 1.0 else 0.0
		body.vx += (ax0 + dx * k1) * half_dt
		body.vy += (ay0 + dy * k1) * half_dt

	if landed:
		# Over the ground: the engines push the ship across the surface, and the
		# surface rolls the other way under it, while the ship itself rides
		# the planet's centre round the sun. _pin_ship_to reads the precise
		# state, so it does not need the planets' nodes pushed this step.
		_drive_on_ground(dt)
		landed_body.roll_surface(ground_velocity * dt)
		_pin_ship_to(landed_body)
		return

	if warp_active:
		_advance_warp(dt)
		return

	physics_ship.advance_position(ship_a0, dt)
	var ship_a1: Vector2 = get_ship_acceleration_precise()
	physics_ship.advance_velocity(ship_a0, ship_a1, dt)

	# The ship's node every step (input and HUD read it); the
	# planets' nodes once per physics tick in _physics_process - anything that
	# needs them exactly mid-tick reads the PhysicsBody state instead.
	physics_ship.push_to_node()


## Index of the planet whose SOI holds the ship (first match, like the ship's
## gravity), from the per-tick SOI cache and the precise state; -1 for the sun.
func _ship_soi_index_precise() -> int:
	for i in range(physics_planets.size()):
		if is_inside_soi_precise(physics_planets[i], soi_radii_cache[i]):
			return i
	return -1


func get_gravity_precise(body: PhysicsBody, source_x: float, source_y: float, mu: float) -> Vector2:
	var dx: float = source_x - body.x
	var dy: float = source_y - body.y
	var d2: float = dx * dx + dy * dy

	if d2 < 1.0:
		return Vector2.ZERO

	var k: float = mu / (d2 * sqrt(d2))
	return Vector2(dx * k, dy * k)


func is_inside_soi_precise(planet: PhysicsBody, soi_radius: float) -> bool:
	var dx: float = physics_ship.x - planet.x
	var dy: float = physics_ship.y - planet.y
	return dx * dx + dy * dy <= soi_radius * soi_radius


func get_planet_acceleration_precise(planet: PhysicsBody) -> Vector2:
	return get_gravity_precise(
		planet, sun.position.x, sun.position.y, mu_sun
	)


func get_ship_acceleration_precise() -> Vector2:
	var acceleration: Vector2 = get_gravity_precise(
		physics_ship, sun.position.x, sun.position.y, mu_sun
	)

	# First planet whose SOI holds the ship (patched conics). Inline distance
	# test - this runs twice per sim step, hundreds of steps a frame on warp.
	var ship_x: float = physics_ship.x
	var ship_y: float = physics_ship.y
	for i in range(physics_planets.size()):
		var body: PhysicsBody = physics_planets[i]
		var dx: float = ship_x - body.x
		var dy: float = ship_y - body.y
		var soi: float = soi_radii_cache[i]
		if dx * dx + dy * dy <= soi * soi:
			acceleration = (
				get_gravity_precise(physics_ship, body.x, body.y, mu_planets[i])
				+ get_planet_acceleration_precise(body)
			)
			break

	acceleration += ship.get_manual_acceleration()

	return acceleration


const ORBIT_TRAIL_POINTS_PER_ORBIT := 300
# The line is a full circle (300+1 points) rebuilt from scratch - Line2D
# rebuilds its ENTIRE geometry on EVERY add_point, so doing this every
# frame (x8 planets) was very expensive and caused a noticeable FPS drop
# at high time_scale (where physics already eats more time per frame).
# The orbit radius changes very slowly, so we only rebuild when it has
# actually moved by more than a tenth of a percent, instead of every frame.
const ORBIT_RADIUS_REBUILD_THRESHOLD := 0.001


func update_orbit_line(planet: Node2D, line: Line2D, index: int) -> void:
	var orbit_radius: float = planet.position.distance_to(sun.position)
	var last_radius: float = orbit_line_radii[index]

	if last_radius >= 0.0 and absf(orbit_radius - last_radius) < last_radius * ORBIT_RADIUS_REBUILD_THRESHOLD:
		return

	orbit_line_radii[index] = orbit_radius
	line.clear_points()
	for i in range(ORBIT_TRAIL_POINTS_PER_ORBIT + 1):
		var angle: float = TAU * float(i) / float(ORBIT_TRAIL_POINTS_PER_ORBIT)
		line.add_point(sun.position + Vector2(cos(angle), sin(angle)) * orbit_radius)

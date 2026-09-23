extends Node2D

const G: float = 3000.0

enum AutopilotPhase {
	OFF,
	ESCAPE_BURN,
	INTERPLANETARY_CRUISE,
	CAPTURE_BURN,
	WAIT_FIRST_BURN,
	FIRST_BURN,
	COAST,
	SECOND_BURN,
	COMPLETE,
	STATION_KEEPING_WAIT,
	STATION_KEEPING_BURN,
	DEPARTURE_WAIT,
	DEPARTURE_BURN,
	DEPARTURE_COAST,
	TRANSFER_BURN,
	TRANSFER_COAST,
	ARRIVAL_COAST,
	ARRIVAL_BURN
}

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
@onready var target_orbit: Line2D = $BehindWorld/TargetOrbit
@onready var interplanetary_route_line: Line2D = $BehindWorld/InterplanetaryRoute
@onready var departure_burn_marker: Node2D = $BehindWorld/DepartureBurnMarker
@onready var transfer_burn_marker: Node2D = $BehindWorld/TransferBurnMarker
@onready var arrival_marker: Node2D = $BehindWorld/ArrivalMarker
@onready var periapsis_marker: Node2D = $BehindWorld/PeriapsisMarker
@onready var apoapsis_marker: Node2D = $BehindWorld/ApoapsisMarker
@onready var speed_gauge: Control = $HUD/SpeedGauge
@onready var hud_status: Control = $HUD/HudStatus
@onready var autopilot_panel: Control = $HUD/AutopilotPanel
@onready var resource_bars_panel: Control = $HUD/ResourceBarsPanel
@onready var ship_blueprint_panel: Control = $HUD/ShipBlueprintPanel
@onready var time_warp_panel: Control = $HUD/TimeWarpPanel
@onready var main_thruster_toggle: CheckButton = $HUD/AutopilotPanel/MainThrusterToggle
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

var settings_mgr: SettingsManager
var music_mgr: MusicManager
var _settings_opened_from_pause: bool = false
var _is_first_track_notification := true
var _builder_controller: ShipBuilderController

var planets: Array[Node2D] = []
var orbit_lines: Array[Line2D] = []
var orbit_line_radii: Array[float] = []
var celestial_bodies: Array[Node2D] = []

const HOME_PLANET_INDEX := 1

var camera_zoom := 1.0
var is_dragging := false
var camera_follow_ship := false
var _test_enemy: Enemy = null ## Sandbox (E menu) ship being test-flown, if any.
var trajectory_status := "ORBIT"
var trajectory_target := ""
var trajectory_candidate_status := ""
var trajectory_candidate_target := ""
var trajectory_candidate_frames := 0
var time_scale := 1.0
var previous_time_scale := 1.0
var simulation_accumulator := 0.0
var prediction_update_accumulator := 1.0
var current_periapsis := 0.0
var current_apoapsis := 0.0
var current_eccentricity := 0.0
var current_periapsis_altitude := 0.0
var current_apoapsis_altitude := 0.0
var has_bound_orbit := false
var osculating_periapsis_direction := Vector2.RIGHT
var target_orbit_flash := 0.0
var autopilot_selecting := false
var autopilot_active := false
var autopilot_main_thruster_allowed := true
var autopilot_body: Node2D = null
var autopilot_target_altitude := 500.0
var autopilot_target_pe_altitude := 500.0
var autopilot_target_ap_altitude := 500.0
var autopilot_phase: AutopilotPhase = AutopilotPhase.OFF
var autopilot_raising := true
var autopilot_planned_delta_v1 := 0.0
var autopilot_planned_delta_v2 := 0.0
var autopilot_remaining_delta_v := 0.0
var station_keeping_correcting_apoapsis := true
var station_keeping_wait_time := 0.0
var autopilot_departure_body: Node2D = null
var autopilot_selectable_bodies: Array[Node2D] = []
var interplanetary_correction_timer := 0.0
var route_plan: Dictionary = {}
var route_task_id := -1
var route_task_holder: Dictionary = {}
var trajectory_task_id := -1
var trajectory_task_holder: Dictionary = {}
var route_task_phase: AutopilotPhase = AutopilotPhase.OFF
var route_replan_timer := 0.0
var transfer_dv := Vector2.ZERO
var transfer_delivered := Vector2.ZERO
var last_transfer_burn_end := -INF
var total_sim_time := 0.0
var physics_planets: Array[PhysicsBody] = []
var physics_ship: PhysicsBody
var soi_radii_cache: PackedFloat64Array = []
var mu_sun := 0.0
var mu_planets: PackedFloat64Array = []

const TARGET_ORBIT_COLOR := Color(0.55, 1.0, 0.62, 0.8)
const TARGET_ORBIT_FLASH_COLOR := Color(0.8, 1.0, 0.85, 1.0)
const TARGET_ORBIT_FLASH_FADE := 4.0
const ZOOM_MIN := 0.001
const ZOOM_MAX := 50.0
const MIN_BODY_SCREEN_RADIUS := 4.0
## On-screen radius, in pixels, above which a body switches to its fine sphere.
const DETAIL_HIGH_SCREEN_RADIUS := 40.0
## How far above the orbital plane the top-down 3D camera sits. Only needs to
## clear the tallest mountain; orthographic, so it does not change the size.
const CAMERA_3D_HEIGHT := 50000.0
const ZOOM_STEP := 1.2
const PREDICTION_STEPS := 6000
const PREDICTION_DT := 0.8
const PREDICTION_DRAW_INTERVAL := 20
const SIM_DT := 1.0 / 120.0
const MAX_SIM_STEPS_PER_FRAME := 6000
const TRAJECTORY_CONFIRM_FRAMES := 10
const PREDICTION_UPDATE_INTERVAL := 0.1
const ORBIT_LINE_SCREEN_WIDTH := 1.0
const TRAJECTORY_LINE_SCREEN_WIDTH := 2.0
const SOI_LINE_SCREEN_WIDTH := 1.0
const AUTOPILOT_TOLERANCE := 10.0
const STATION_KEEPING_TRIGGER := 150.0
const STATION_KEEPING_EMERGENCY_FACTOR := 2.5
const STATION_KEEPING_MAX_WAIT_FRACTION := 0.55
const AUTOPILOT_SCROLL_STEP := 250.0
const AUTOPILOT_SCROLL_STEP_FRACTION := 0.02
const AUTOPILOT_MIN_ALTITUDE := 100.0
const AUTOPILOT_MAX_SOI_FACTOR := 0.8
const APSIS_BURN_WINDOW := 15.0
const APSIS_BURN_MAX_ANGLE := deg_to_rad(60.0)
const SHIP_TRUE_SCALE_ZOOM_THRESHOLD := 4.0
const INTERPLANETARY_WINDOW_TOLERANCE := 0.12
const INTERPLANETARY_ESCAPE_SOI_FACTOR := 1.5
const INTERPLANETARY_HOMING_SOI_FACTOR := 4.0
const INTERPLANETARY_APPROACH_TIME := 90.0
const INTERPLANETARY_CORRECTION_INTERVAL := 20.0
const ROUTE_REPLAN_INTERVAL := 0.5
const ROUTE_CORRECTION_COOLDOWN := 300.0
const ROUTE_MIN_CORRECTION_DV := 0.003
const ROUTE_MIN_TIME_TO_ARRIVAL := 200.0


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
	if physics_ship != null:
		physics_ship.pull_from_node()


func _unhandled_input(event: InputEvent) -> void:
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
		toggle_enemy_menu()
		get_viewport().set_input_as_handled()
		return

	if ship_builder_panel != null and ship_builder_panel.visible:
		return

	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_G:
		_try_fire_fov_weapon()
		get_viewport().set_input_as_handled()
		return

	if event is InputEventKey and event.keycode == KEY_F:
		if event.pressed and not event.echo:
			if autopilot_active:
				disengage_autopilot()
			else:
				start_autopilot_selection()
		elif not event.pressed and autopilot_selecting:
			engage_autopilot()

	if (
		event is InputEventKey
		and event.pressed
		and not event.echo
		and event.keycode == KEY_TAB
		and autopilot_selecting
	):
		cycle_autopilot_target_body()

	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_W:
			if settings_mgr != null and settings_mgr.auto_drop_warp_on_thrust and time_scale > 1.0:
				set_time_scale(1.0)
		elif event.keycode == KEY_P or event.keycode == KEY_0:
			toggle_pause()
		elif event.keycode == KEY_SPACE and _test_enemy == null:
			toggle_pause()
		elif event.keycode == KEY_1:
			set_time_scale(1.0)
		elif event.keycode == KEY_2:
			set_time_scale(2.0)
		elif event.keycode == KEY_3:
			set_time_scale(5.0)
		elif event.keycode == KEY_4:
			set_time_scale(10.0)
		elif event.keycode == KEY_5:
			set_time_scale(50.0)
		elif event.keycode == KEY_6:
			set_time_scale(100.0)
		elif event.keycode == KEY_7:
			set_time_scale(200.0)
		elif event.keycode == KEY_PERIOD:
			camera_follow_ship = not camera_follow_ship

	if (
		event is InputEventMouseButton
		and event.pressed
		and autopilot_selecting
	):
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			change_autopilot_altitude(1.0)
			return
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			change_autopilot_altitude(-1.0)
			return

	if event is InputEventMouseButton:
		if event.pressed:
			var zoom_step: float = settings_mgr.camera_zoom_speed if settings_mgr != null else ZOOM_STEP
			if event.button_index == MOUSE_BUTTON_WHEEL_UP:
				camera_zoom *= zoom_step

			elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				camera_zoom /= zoom_step

		camera_zoom = clamp(camera_zoom, ZOOM_MIN, ZOOM_MAX)
		camera.zoom = Vector2(camera_zoom, camera_zoom)

		if event.button_index == MOUSE_BUTTON_MIDDLE:
			is_dragging = event.pressed

			if event.pressed:
				camera_follow_ship = false

	if event is InputEventMouseMotion and is_dragging:
		var pan_factor: float = settings_mgr.camera_pan_speed if settings_mgr != null else 1.0
		camera.position -= (event.relative * pan_factor) / camera_zoom


func _ready() -> void:
	for child in planets_container.get_children():
		if child is Node2D:
			planets.append(child)

	celestial_bodies = [sun]
	celestial_bodies.append_array(planets)
	autopilot_selectable_bodies = planets.duplicate()
	autopilot_selectable_bodies.append(sun)

	var sun_mass: float = sun.get("mass")
	mu_sun = G * sun_mass

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
		line.default_color = orbit_color
		orbit_lines_container.add_child(line)
		orbit_lines.append(line)
		orbit_line_radii.append(-1.0)
		line.add_point(planet.position)

	var home: Node2D = planets[HOME_PLANET_INDEX]
	var home_mass: float = home.get("mass")

	ship.position = home.position + Vector2(1000, 0)
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
	main_thruster_toggle.toggled.connect(_on_main_thruster_toggled)
	time_warp_panel.time_scale_selected.connect(_on_time_scale_selected)
	time_warp_panel.pause_toggled.connect(toggle_pause)
	time_warp_panel.step_requested.connect(step_simulation_once)
	pe_gauge.scrolled.connect(change_autopilot_target_pe)
	ap_gauge.scrolled.connect(change_autopilot_target_ap)
	orbit_info_button.pressed.connect(_on_orbit_info_pressed)
	target_orbit.visible = false
	target_orbit.default_color = TARGET_ORBIT_COLOR

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
	if time_warp_panel != null:
		var gear_icon: Texture2D = time_warp_panel._load_icon("res://textures/icons/settings.svg")
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


func _process(delta: float) -> void:
	update_screen_space_visuals()
	update_soi_visuals()
	update_autopilot_hover_selection()

	update_trajectory_prediction_async(delta)

	update_osculating_orbit_line()
	update_target_orbit_visual()
	update_route_planning(delta)
	update_interplanetary_route_visual()
	update_fov_gameplay()
	update_hud()

	if camera_follow_ship:
		var catch_up: float = 1.0 if (settings_mgr != null and not settings_mgr.camera_smoothing) else clampf(5.0 * delta * maxf(time_scale, 1.0), 0.0, 1.0)
		var follow_pos: Vector2 = _test_enemy.position if _test_enemy != null else ship.position
		camera.position = camera.position.lerp(follow_pos, catch_up)

	_sync_camera_3d()


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
	target_orbit.width = TRAJECTORY_LINE_SCREEN_WIDTH * inverse_zoom
	interplanetary_route_line.width = TRAJECTORY_LINE_SCREEN_WIDTH * inverse_zoom

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
	departure_burn_marker.scale = screen_scale
	transfer_burn_marker.scale = screen_scale
	arrival_marker.scale = screen_scale

	var ship_true_scale: bool = camera_zoom >= SHIP_TRUE_SCALE_ZOOM_THRESHOLD
	ship.scale = Vector2.ONE if ship_true_scale else screen_scale
	ship.true_scale = ship_true_scale


func start_autopilot_selection() -> void:
	autopilot_selecting = true
	autopilot_active = false
	autopilot_phase = AutopilotPhase.OFF
	autopilot_body = get_current_orbit_body()
	ship.clear_autopilot_thrust()

	if autopilot_body == null:
		autopilot_selecting = false
		return

	var body_radius: float = autopilot_body.get("radius")
	var current_altitude: float = (
		ship.position.distance_to(autopilot_body.position)
		- body_radius
	)
	var rounded_altitude: float = round(
		current_altitude / AUTOPILOT_SCROLL_STEP
	) * AUTOPILOT_SCROLL_STEP

	autopilot_target_altitude = maxf(
		rounded_altitude,
		AUTOPILOT_MIN_ALTITUDE
	)


func get_autopilot_altitude_range(body: Node2D) -> Dictionary:
	var body_radius: float = body.get("radius")
	var max_radius: float

	if body == sun:
		max_radius = planets[-1].position.distance_to(sun.position) * 1.5
	else:
		max_radius = (
			get_soi_radius(body)
			* AUTOPILOT_MAX_SOI_FACTOR
		)

	var max_altitude: float = maxf(
		max_radius - body_radius,
		AUTOPILOT_MIN_ALTITUDE
	)

	var step: float = clampf(
		max_altitude * AUTOPILOT_SCROLL_STEP_FRACTION,
		AUTOPILOT_SCROLL_STEP,
		max_altitude * 0.25
	)

	return {"max_altitude": max_altitude, "step": step}


func change_autopilot_altitude(direction: float) -> void:
	if autopilot_body == null:
		return

	var altitude_range: Dictionary = get_autopilot_altitude_range(autopilot_body)

	autopilot_target_altitude = clampf(
		autopilot_target_altitude + direction * altitude_range.step,
		AUTOPILOT_MIN_ALTITUDE,
		altitude_range.max_altitude
	)
	flash_target_orbit()


func can_edit_autopilot_apsis_targets() -> bool:
	return (
		autopilot_active
		and not autopilot_selecting
		and autopilot_body != null
		and autopilot_body == get_current_orbit_body()
	)


func change_autopilot_target_pe(direction: float) -> void:
	if not can_edit_autopilot_apsis_targets():
		return

	var altitude_range: Dictionary = get_autopilot_altitude_range(autopilot_body)
	autopilot_target_pe_altitude = clampf(
		autopilot_target_pe_altitude + direction * altitude_range.step,
		AUTOPILOT_MIN_ALTITUDE,
		minf(altitude_range.max_altitude, autopilot_target_ap_altitude)
	)
	flash_target_orbit()


func change_autopilot_target_ap(direction: float) -> void:
	if not can_edit_autopilot_apsis_targets():
		return

	var altitude_range: Dictionary = get_autopilot_altitude_range(autopilot_body)
	autopilot_target_ap_altitude = clampf(
		autopilot_target_ap_altitude + direction * altitude_range.step,
		maxf(AUTOPILOT_MIN_ALTITUDE, autopilot_target_pe_altitude),
		altitude_range.max_altitude
	)
	flash_target_orbit()


func disengage_autopilot() -> void:
	autopilot_active = false
	autopilot_selecting = false
	autopilot_phase = AutopilotPhase.OFF
	autopilot_body = null
	autopilot_departure_body = null
	route_plan = {}
	ship.clear_autopilot_thrust()


func cycle_autopilot_target_body() -> void:
	if autopilot_selectable_bodies.is_empty():
		return

	var current_index: int = autopilot_selectable_bodies.find(autopilot_body)
	var next_index: int = (current_index + 1) % autopilot_selectable_bodies.size()
	set_autopilot_target_body(autopilot_selectable_bodies[next_index])


func set_autopilot_target_body(body: Node2D) -> void:
	if body == null or body == autopilot_body:
		return

	autopilot_body = body

	var body_radius: float = body.get("radius")
	var current_altitude: float = (
		ship.position.distance_to(body.position)
		- body_radius
	)
	var rounded_altitude: float = round(
		current_altitude / AUTOPILOT_SCROLL_STEP
	) * AUTOPILOT_SCROLL_STEP

	autopilot_target_altitude = maxf(
		rounded_altitude,
		AUTOPILOT_MIN_ALTITUDE
	)
	change_autopilot_altitude(0.0)


func update_autopilot_hover_selection() -> void:
	if not autopilot_selecting:
		return

	var mouse_position: Vector2 = get_global_mouse_position()
	var closest_body: Node2D = null
	var closest_distance: float = INF

	for body in autopilot_selectable_bodies:
		var body_radius: float = body.get("radius")
		var hover_radius: float = maxf(body_radius * 1.5, 40.0 / camera_zoom)
		var distance: float = mouse_position.distance_to(body.position)

		if distance <= hover_radius and distance < closest_distance:
			closest_distance = distance
			closest_body = body

	if closest_body != null:
		set_autopilot_target_body(closest_body)


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


func get_orbit_elements(body: Node2D) -> Dictionary:
	var body_velocity := Vector2.ZERO
	if body != sun: body_velocity = body.get("velocity")

	var r_vec: Vector2 = get_relative_position_precise(ship, body)
	var v_vec: Vector2 = ship.velocity - body_velocity
	var distance: float = r_vec.length()
	var mu: float = G * body.get("mass")
	var velocity_squared: float = v_vec.length_squared()
	var energy: float = velocity_squared / 2.0 - mu / distance

	if energy >= 0.0 or distance < 1.0:
		return {"bound": false, "pe_alt": 0.0, "ap_alt": 0.0}

	var a: float = -mu / (2.0 * energy)
	var rv: float = r_vec.dot(v_vec)
	var eccentricity_vector: Vector2 = (((velocity_squared - mu / distance) * r_vec - rv * v_vec) / mu)
	var e: float = eccentricity_vector.length()
	var body_radius: float = body.get("radius")

	return {
		"bound": true,
		"pe_alt": a * (1.0 - e) - body_radius,
		"ap_alt": a * (1.0 + e) - body_radius
	}


func engage_autopilot() -> void:
	autopilot_selecting = false

	ship.disengage_manual_main_engine()

	if autopilot_body == null:
		return

	var origin_body: Node2D = get_current_orbit_body()

	if autopilot_body == origin_body:
		engage_local_autopilot()
	else:
		engage_interplanetary_autopilot(origin_body)


func engage_local_autopilot() -> void:
	var elements = get_orbit_elements(autopilot_body)
	if not elements.bound:
		return

	var body_radius: float = autopilot_body.get("radius")
	var body_mass: float = autopilot_body.get("mass")
	var mu: float = G * body_mass
	var current_average_altitude: float = 0.5 * (
		elements.pe_alt + elements.ap_alt
	)
	var initial_radius: float = body_radius + current_average_altitude
	var target_radius: float = body_radius + autopilot_target_altitude

	if initial_radius <= 0.0 or target_radius <= 0.0:
		return

	var current_pe_radius: float = body_radius + elements.pe_alt
	var current_ap_radius: float = body_radius + elements.ap_alt

	if target_radius >= current_ap_radius:
		autopilot_raising = true
	elif target_radius <= current_pe_radius:
		autopilot_raising = false
	else:
		autopilot_raising = (
			absf(current_ap_radius - target_radius)
			>= absf(target_radius - current_pe_radius)
		)

	var transfer_semi_major_axis: float = 0.5 * (
		initial_radius + target_radius
	)
	var circular_velocity_1: float = sqrt(mu / initial_radius)
	var transfer_velocity_1: float = sqrt(
		mu * (
			2.0 / initial_radius
			- 1.0 / transfer_semi_major_axis
		)
	)
	var transfer_velocity_2: float = sqrt(
		mu * (
			2.0 / target_radius
			- 1.0 / transfer_semi_major_axis
		)
	)
	var circular_velocity_2: float = sqrt(mu / target_radius)

	autopilot_planned_delta_v1 = (
		transfer_velocity_1 - circular_velocity_1
	)
	autopilot_planned_delta_v2 = (
		circular_velocity_2 - transfer_velocity_2
	)
	autopilot_remaining_delta_v = absf(autopilot_planned_delta_v1)
	autopilot_target_pe_altitude = autopilot_target_altitude
	autopilot_target_ap_altitude = autopilot_target_altitude
	autopilot_active = true
	autopilot_phase = AutopilotPhase.WAIT_FIRST_BURN


func engage_interplanetary_autopilot(origin_body: Node2D) -> void:
	autopilot_departure_body = origin_body
	autopilot_planned_delta_v1 = 0.0
	autopilot_planned_delta_v2 = 0.0
	autopilot_remaining_delta_v = 0.0
	interplanetary_correction_timer = 0.0
	autopilot_active = true
	route_plan = {}
	route_replan_timer = ROUTE_REPLAN_INTERVAL

	if origin_body == sun:
		autopilot_phase = AutopilotPhase.INTERPLANETARY_CRUISE
	elif autopilot_body == sun:
		autopilot_phase = AutopilotPhase.ESCAPE_BURN
	else:
		autopilot_phase = AutopilotPhase.DEPARTURE_WAIT


func is_interplanetary_autopilot_phase(phase: AutopilotPhase) -> bool:
	return (
		phase == AutopilotPhase.ESCAPE_BURN
		or phase == AutopilotPhase.INTERPLANETARY_CRUISE
		or phase == AutopilotPhase.CAPTURE_BURN
		or is_route_phase(phase)
	)


func is_route_phase(phase: AutopilotPhase) -> bool:
	return (
		phase == AutopilotPhase.DEPARTURE_WAIT
		or phase == AutopilotPhase.DEPARTURE_BURN
		or phase == AutopilotPhase.DEPARTURE_COAST
		or phase == AutopilotPhase.TRANSFER_BURN
		or phase == AutopilotPhase.TRANSFER_COAST
		or phase == AutopilotPhase.ARRIVAL_COAST
		or phase == AutopilotPhase.ARRIVAL_BURN
	)


func update_orbit_autopilot(dt: float) -> void:
	if not autopilot_active or autopilot_body == null:
		ship.clear_autopilot_thrust()
		return

	if is_interplanetary_autopilot_phase(autopilot_phase):
		update_interplanetary_autopilot(dt)
	else:
		update_local_orbit_autopilot(dt)


func update_local_orbit_autopilot(dt: float) -> void:
	if not is_inside_soi(ship.position, autopilot_body):
		# Overshot the target's SOI (usually from arriving too fast to capture
		# in one pass). Chase it down and try again instead of giving up -
		# the same recovery path interplanetary arrivals already use.
		ship.clear_autopilot_thrust()
		autopilot_phase = AutopilotPhase.CAPTURE_BURN
		return

	var body_velocity: Vector2 = Vector2.ZERO
	if autopilot_body != sun:
		body_velocity = autopilot_body.get("velocity")

	var relative_velocity: Vector2 = ship.velocity - body_velocity
	var relative_position: Vector2 = get_relative_position_precise(ship, autopilot_body)
	var r: float = relative_position.length()

	if relative_velocity.length() < 0.001 or r < 1.0:
		ship.clear_autopilot_thrust()
		return

	var mu: float = G * autopilot_body.get("mass")
	var body_radius: float = autopilot_body.get("radius")
	var target_pe_radius: float = body_radius + autopilot_target_pe_altitude
	var target_ap_radius: float = body_radius + autopilot_target_ap_altitude

	var orbit: Dictionary = OrbitMath.elements(relative_position, relative_velocity, mu)
	if orbit.e >= 1.0:
		# Above escape velocity for this body - apsis burns assume an ellipse
		# and have no periapsis/apoapsis to aim at. Braking toward a bound
		# orbit (the same move used to capture on interplanetary arrival)
		# beats giving up and coasting out of the system.
		var radial_dir: Vector2 = relative_position.normalized()
		var tangent_dir := Vector2(-radial_dir.y, radial_dir.x)
		if relative_velocity.dot(tangent_dir) < 0.0:
			tangent_dir = -tangent_dir
		autopilot_remaining_delta_v = execute_apsis_targeting_burn(
			r, target_pe_radius, mu, tangent_dir, relative_velocity
		)
		return

	match autopilot_phase:
		AutopilotPhase.WAIT_FIRST_BURN:
			ship.clear_autopilot_thrust()
			var first_target: float = target_ap_radius if autopilot_raising else target_pe_radius
			var first_current: float = orbit.ra if autopilot_raising else orbit.rp
			if absf(first_current - first_target) <= AUTOPILOT_TOLERANCE:
				autopilot_phase = AutopilotPhase.COAST
			elif is_apsis_burn_window(orbit, mu, autopilot_raising, first_target):
				autopilot_phase = AutopilotPhase.FIRST_BURN

		AutopilotPhase.FIRST_BURN:
			var first_target_burn: float = target_ap_radius if autopilot_raising else target_pe_radius
			if execute_apsis_change_burn(
				autopilot_raising, first_target_burn, relative_position, relative_velocity, mu, dt
			):
				autopilot_phase = AutopilotPhase.COAST

		AutopilotPhase.COAST:
			ship.clear_autopilot_thrust()
			var second_target: float = target_pe_radius if autopilot_raising else target_ap_radius
			var second_current: float = orbit.rp if autopilot_raising else orbit.ra
			if absf(second_current - second_target) <= AUTOPILOT_TOLERANCE:
				finish_autopilot_maneuver()
			elif is_apsis_burn_window(orbit, mu, not autopilot_raising, second_target):
				autopilot_phase = AutopilotPhase.SECOND_BURN

		AutopilotPhase.SECOND_BURN:
			var second_target_burn: float = target_pe_radius if autopilot_raising else target_ap_radius
			if execute_apsis_change_burn(
				not autopilot_raising, second_target_burn, relative_position, relative_velocity, mu, dt
			):
				finish_autopilot_maneuver()

		AutopilotPhase.COMPLETE:
			ship.clear_autopilot_thrust()
			autopilot_remaining_delta_v = 0.0

			var pe_error: float = orbit.rp - target_pe_radius
			var ap_error: float = orbit.ra - target_ap_radius

			if absf(pe_error) > STATION_KEEPING_TRIGGER or absf(ap_error) > STATION_KEEPING_TRIGGER:
				station_keeping_correcting_apoapsis = absf(ap_error) >= absf(pe_error)
				station_keeping_wait_time = 0.0
				autopilot_phase = AutopilotPhase.STATION_KEEPING_WAIT

		AutopilotPhase.STATION_KEEPING_WAIT:
			ship.clear_autopilot_thrust()
			station_keeping_wait_time += dt

			var station_target: float = (
				target_ap_radius if station_keeping_correcting_apoapsis else target_pe_radius
			)
			var ready: bool = is_apsis_burn_window(
				orbit, mu, station_keeping_correcting_apoapsis, station_target
			)

			var worst_error: float = maxf(
				absf(orbit.rp - target_pe_radius),
				absf(orbit.ra - target_ap_radius)
			)
			var drift_critical: bool = (
				worst_error > STATION_KEEPING_TRIGGER * STATION_KEEPING_EMERGENCY_FACTOR
			)
			var wait_too_long: bool = (
				station_keeping_wait_time
				> OrbitMath.orbital_period(orbit.a, mu) * STATION_KEEPING_MAX_WAIT_FRACTION
			)
			var correctable_is_apoapsis: bool = cos(orbit.nu) >= 0.0
			var correctable_error: float = absf(
				(orbit.ra - target_ap_radius) if correctable_is_apoapsis
				else (orbit.rp - target_pe_radius)
			)
			var in_burn_arc: bool = absf(
				wrapf(orbit.nu - (0.0 if correctable_is_apoapsis else PI), -PI, PI)
			) <= APSIS_BURN_MAX_ANGLE

			if ready:
				station_keeping_wait_time = 0.0
				autopilot_phase = AutopilotPhase.STATION_KEEPING_BURN
			elif (
				(drift_critical or wait_too_long)
				and in_burn_arc
				and correctable_error > 0.5 * STATION_KEEPING_TRIGGER
			):
				station_keeping_correcting_apoapsis = correctable_is_apoapsis
				station_keeping_wait_time = 0.0
				autopilot_phase = AutopilotPhase.STATION_KEEPING_BURN

		AutopilotPhase.STATION_KEEPING_BURN:
			var station_target_burn: float = (
				target_ap_radius if station_keeping_correcting_apoapsis else target_pe_radius
			)
			if execute_apsis_change_burn(
				station_keeping_correcting_apoapsis,
				station_target_burn,
				relative_position,
				relative_velocity,
				mu,
				dt
			):
				autopilot_phase = AutopilotPhase.COMPLETE

		_:
			ship.clear_autopilot_thrust()


func is_apsis_burn_window(
	orbit: Dictionary,
	mu: float,
	at_periapsis: bool,
	target_radius: float
) -> bool:
	if orbit.ra - orbit.rp < 2.0 * APSIS_BURN_WINDOW:
		return true

	var apsis_radius: float = orbit.rp if at_periapsis else orbit.ra
	var delta_v: float = get_apsis_burn_delta_v(apsis_radius, orbit.a, target_radius, mu)
	var half_burn: float = 0.5 * delta_v / get_autopilot_max_acceleration()
	var period: float = OrbitMath.orbital_period(orbit.a, mu)
	var time_to_apsis: float = (
		OrbitMath.time_to_periapsis(orbit, mu) if at_periapsis
		else OrbitMath.time_to_apoapsis(orbit, mu)
	)

	return time_to_apsis <= half_burn or time_to_apsis >= period - half_burn


func get_apsis_burn_delta_v(
	apsis_radius: float,
	semi_major_axis: float,
	target_radius: float,
	mu: float
) -> float:
	var new_semi_major_axis: float = 0.5 * (apsis_radius + target_radius)
	var speed_now: float = sqrt(maxf(mu * (2.0 / apsis_radius - 1.0 / semi_major_axis), 0.0))
	var speed_after: float = sqrt(maxf(mu * (2.0 / apsis_radius - 1.0 / new_semi_major_axis), 0.0))
	return absf(speed_after - speed_now)


func execute_apsis_change_burn(
	adjust_apoapsis: bool,
	target_radius: float,
	relative_position: Vector2,
	relative_velocity: Vector2,
	mu: float,
	dt: float
) -> bool:
	var r: float = relative_position.length()
	var goal: float = (
		maxf(target_radius, r) if adjust_apoapsis
		else minf(target_radius, r)
	)
	var orbit: Dictionary = OrbitMath.elements(relative_position, relative_velocity, mu)

	var near_circular: bool = orbit.e < 1.0 and orbit.ra - orbit.rp < 2.0 * APSIS_BURN_WINDOW
	var angle_from_burn_point: float = absf(
		wrapf(orbit.nu - (0.0 if adjust_apoapsis else PI), -PI, PI)
	)
	if not near_circular and angle_from_burn_point > APSIS_BURN_MAX_ANGLE:
		ship.clear_autopilot_thrust()
		autopilot_remaining_delta_v = 0.0
		return true

	var prograde: Vector2 = relative_velocity.normalized()
	var value: float = get_apsis_radius(relative_position, relative_velocity, mu, adjust_apoapsis)
	var probe: float = 1e-3
	var sensitivity: float = (
		get_apsis_radius(relative_position, relative_velocity + prograde * probe, mu, adjust_apoapsis)
		- value
	) / probe
	var error: float = goal - value

	if (
		absf(error) <= 0.5 * AUTOPILOT_TOLERANCE
		or absf(sensitivity) < 1e-3
		or not is_finite(sensitivity)
	):
		ship.clear_autopilot_thrust()
		autopilot_remaining_delta_v = 0.0
		return true

	var needed_delta_v: float = error / sensitivity
	var max_acceleration: float = get_autopilot_max_acceleration()
	autopilot_remaining_delta_v = absf(needed_delta_v)
	set_autopilot_direction(
		prograde * signf(needed_delta_v),
		minf(1.0, absf(needed_delta_v) / (max_acceleration * dt))
	)
	return false


func get_apsis_radius(
	relative_position: Vector2,
	relative_velocity: Vector2,
	mu: float,
	apoapsis: bool
) -> float:
	var orbit: Dictionary = OrbitMath.elements(relative_position, relative_velocity, mu)
	if orbit.e >= 1.0:
		return INF if apoapsis else orbit.rp
	return orbit.ra if apoapsis else orbit.rp


func update_interplanetary_autopilot(dt: float) -> void:
	match autopilot_phase:
		AutopilotPhase.DEPARTURE_WAIT:
			update_departure_wait()

		AutopilotPhase.DEPARTURE_BURN:
			update_departure_burn()

		AutopilotPhase.DEPARTURE_COAST:
			update_departure_coast()

		AutopilotPhase.TRANSFER_BURN:
			update_transfer_burn(dt)

		AutopilotPhase.TRANSFER_COAST:
			update_transfer_coast()

		AutopilotPhase.ARRIVAL_COAST:
			update_arrival_coast()

		AutopilotPhase.ARRIVAL_BURN:
			update_circularization_burn()

		AutopilotPhase.ESCAPE_BURN:
			update_interplanetary_escape_burn()

		AutopilotPhase.INTERPLANETARY_CRUISE:
			update_interplanetary_cruise(dt)

		AutopilotPhase.CAPTURE_BURN:
			update_interplanetary_capture_burn()

		_:
			ship.clear_autopilot_thrust()



func update_departure_wait() -> void:
	ship.clear_autopilot_thrust()

	if route_plan.get("ok", false) and total_sim_time >= route_plan.t_start:
		autopilot_phase = AutopilotPhase.DEPARTURE_BURN


func update_departure_burn() -> void:
	var body_velocity: Vector2 = autopilot_departure_body.get("velocity")
	var relative_velocity: Vector2 = ship.velocity - body_velocity
	var r: float = ship.position.distance_to(autopilot_departure_body.position)
	var mu: float = G * autopilot_departure_body.get("mass")
	var eps_target: float = route_plan.get("eps_target", 0.0)
	var energy: float = relative_velocity.length_squared() * 0.5 - mu / r

	autopilot_remaining_delta_v = maxf(
		sqrt(maxf(2.0 * (eps_target + mu / r), 0.0)) - relative_velocity.length(),
		0.0
	)

	if energy >= eps_target:
		ship.clear_autopilot_thrust()
		autopilot_phase = AutopilotPhase.DEPARTURE_COAST
		return

	set_autopilot_direction(relative_velocity.normalized(), 1.0)


func update_departure_coast() -> void:
	ship.clear_autopilot_thrust()
	var exit_radius: float = (
		get_soi_radius(autopilot_departure_body) * INTERPLANETARY_ESCAPE_SOI_FACTOR
	)

	if ship.position.distance_to(autopilot_departure_body.position) > exit_radius:
		begin_transfer_burn(route_plan.get("dv", Vector2.ZERO))


func begin_transfer_burn(dv: Vector2) -> void:
	transfer_dv = dv
	transfer_delivered = Vector2.ZERO
	autopilot_phase = AutopilotPhase.TRANSFER_BURN


func update_transfer_burn(dt: float) -> void:
	var remaining: Vector2 = transfer_dv - transfer_delivered
	var remaining_length: float = remaining.length()
	autopilot_remaining_delta_v = remaining_length

	if remaining_length < 1e-4:
		ship.clear_autopilot_thrust()
		last_transfer_burn_end = total_sim_time
		autopilot_phase = AutopilotPhase.TRANSFER_COAST
		return

	var max_acceleration: float = get_autopilot_max_acceleration()
	var magnitude: float = minf(max_acceleration, remaining_length / dt)
	var direction: Vector2 = remaining / remaining_length
	set_autopilot_direction(direction, magnitude / max_acceleration)
	transfer_delivered += direction * magnitude * dt


func update_transfer_coast() -> void:
	ship.clear_autopilot_thrust()

	if is_inside_soi(ship.position, autopilot_body):
		autopilot_phase = AutopilotPhase.ARRIVAL_COAST


func update_arrival_coast() -> void:
	ship.clear_autopilot_thrust()

	if not is_inside_soi(ship.position, autopilot_body):
		autopilot_phase = AutopilotPhase.TRANSFER_COAST
		return

	var body_velocity: Vector2 = autopilot_body.get("velocity")
	var r_vec: Vector2 = ship.position - autopilot_body.position
	var v_vec: Vector2 = ship.velocity - body_velocity
	var mu: float = G * autopilot_body.get("mass")
	var elements: Dictionary = OrbitMath.elements(r_vec, v_vec, mu)
	var rp: float = elements.rp
	var speed_at_periapsis: float = sqrt(maxf(2.0 * (elements.energy + mu / rp), 0.0))
	var capture_delta_v: float = speed_at_periapsis - sqrt(mu / rp)
	var burn_time: float = capture_delta_v / get_autopilot_max_acceleration()
	var passed_periapsis: bool = r_vec.dot(v_vec) >= 0.0
	var time_to_periapsis: float = (
		0.0 if passed_periapsis
		else OrbitMath.time_to_periapsis(elements, mu)
	)
	autopilot_remaining_delta_v = capture_delta_v

	if passed_periapsis or time_to_periapsis <= 0.5 * burn_time:
		autopilot_phase = AutopilotPhase.ARRIVAL_BURN


func get_autopilot_max_acceleration() -> float:
	return get_autopilot_thrust_force() / ship.ship_mass


func get_autopilot_thrust_force() -> float:
	return ship.thrust_force if autopilot_main_thruster_allowed else ship.correction_thrust_force


func is_autopilot_using_main_engine() -> bool:
	return (
		autopilot_active
		and autopilot_main_thruster_allowed
		and ship.autopilot_thrust != Vector2.ZERO
	)


func build_route_context() -> Dictionary:
	var rel := PackedVector2Array()
	var omega := PackedFloat64Array()
	var mu := PackedFloat64Array()
	var soi := PackedFloat64Array()

	for planet in planets:
		var offset: Vector2 = planet.position - sun.position
		var planet_velocity: Vector2 = planet.get("velocity")
		rel.append(offset)
		omega.append(offset.cross(planet_velocity) / offset.length_squared())
		mu.append(G * planet.get("mass"))
		soi.append(get_soi_radius(planet))

	var dep_index: int = planets.find(autopilot_departure_body)
	var target_index: int = planets.find(autopilot_body)
	var target_radius: float = autopilot_body.get("radius")
	var a_transfer: float = 0.5 * (rel[dep_index].length() + rel[target_index].length())
	var mu_sun: float = G * sun.get("mass")

	return {
		"t0": total_sim_time,
		"sun_pos": sun.position,
		"mu_sun": mu_sun,
		"rel": rel,
		"omega": omega,
		"mu": mu,
		"soi": soi,
		"dep": dep_index,
		"target": target_index,
		"acc": get_autopilot_max_acceleration(),
		"exit_radius": soi[dep_index] * INTERPLANETARY_ESCAPE_SOI_FACTOR,
		"r_target": target_radius + autopilot_target_altitude,
		"target_radius": target_radius,
		"max_transfer_time": 2.5 * OrbitMath.half_period(a_transfer, mu_sun),
	}


func build_route_request() -> Dictionary:
	var request := {
		"pos": ship.position,
		"vel": ship.velocity,
		"t": total_sim_time,
	}

	match autopilot_phase:
		AutopilotPhase.DEPARTURE_WAIT:
			request.stage = InterplanetaryPlanner.Stage.COAST_TO_BURN
			if (
				route_plan.get("ok", false)
				and absf(route_plan.get("target_error", INF)) <= InterplanetaryPlanner.CORRECTION_TOLERANCE
				and route_plan.t_start > total_sim_time
			):
				request.t_start = route_plan.t_start
				request.eps_target = route_plan.eps_target
				request.dv_guess = route_plan.get("dv", Vector2.ZERO)
		AutopilotPhase.DEPARTURE_BURN:
			request.stage = InterplanetaryPlanner.Stage.ESCAPE_BURN
			request.eps_target = route_plan.eps_target
		AutopilotPhase.DEPARTURE_COAST:
			request.stage = InterplanetaryPlanner.Stage.ESCAPE_COAST
			request.eps_target = route_plan.eps_target
		AutopilotPhase.TRANSFER_BURN:
			request.stage = InterplanetaryPlanner.Stage.TRANSFER_BURN
			request.dv = transfer_dv
			request.delivered = transfer_delivered
		_:
			request.stage = InterplanetaryPlanner.Stage.TRANSFER_COAST

	return request


func update_route_planning(delta: float) -> void:
	if route_task_id != -1:
		if not WorkerThreadPool.is_task_completed(route_task_id):
			return
		WorkerThreadPool.wait_for_task_completion(route_task_id)
		route_task_id = -1

		if autopilot_active and autopilot_phase == route_task_phase:
			accept_route_plan(route_task_holder.get("result", {}))

	if not autopilot_active or not is_route_phase(autopilot_phase):
		return

	if autopilot_phase == AutopilotPhase.ARRIVAL_BURN:
		return

	route_replan_timer += delta
	if route_replan_timer < ROUTE_REPLAN_INTERVAL:
		return
	route_replan_timer = 0.0

	var ctx: Dictionary = build_route_context()
	var request: Dictionary = build_route_request()
	var holder := {}
	route_task_holder = holder
	route_task_phase = autopilot_phase
	route_task_id = WorkerThreadPool.add_task(
		func() -> void: holder.result = InterplanetaryPlanner.plan(ctx, request)
	)


func accept_route_plan(result: Dictionary) -> void:
	if result.is_empty():
		return

	match autopilot_phase:
		AutopilotPhase.DEPARTURE_WAIT, AutopilotPhase.DEPARTURE_BURN, AutopilotPhase.DEPARTURE_COAST:
			if not result.ok and route_plan.get("ok", false):
				return
			route_plan = result
			autopilot_planned_delta_v2 = result.get("dv", Vector2.ZERO).length()

		AutopilotPhase.TRANSFER_COAST:
			route_plan = result
			var dv: Vector2 = result.get("dv", Vector2.ZERO)
			var time_to_arrival: float = result.get("closest_t", INF) - total_sim_time
			if (
				result.get("correction", false)
				and dv.length() >= ROUTE_MIN_CORRECTION_DV
				and total_sim_time - last_transfer_burn_end >= ROUTE_CORRECTION_COOLDOWN
				and time_to_arrival >= ROUTE_MIN_TIME_TO_ARRIVAL
			):
				autopilot_planned_delta_v2 = dv.length()
				begin_transfer_burn(dv)

		_:
			route_plan = result


func _exit_tree() -> void:
	if route_task_id != -1:
		WorkerThreadPool.wait_for_task_completion(route_task_id)
	if trajectory_task_id != -1:
		WorkerThreadPool.wait_for_task_completion(trajectory_task_id)


func update_interplanetary_escape_burn() -> void:
	if autopilot_departure_body == null:
		autopilot_phase = AutopilotPhase.INTERPLANETARY_CRUISE
		return

	if not is_inside_soi(ship.position, autopilot_departure_body):
		ship.clear_autopilot_thrust()
		autopilot_phase = AutopilotPhase.INTERPLANETARY_CRUISE
		return

	var body_velocity: Vector2 = Vector2.ZERO
	if autopilot_departure_body != sun:
		body_velocity = autopilot_departure_body.get("velocity")

	var relative_velocity: Vector2 = ship.velocity - body_velocity
	var relative_position: Vector2 = ship.position - autopilot_departure_body.position
	var r: float = relative_position.length()

	if r < 1.0:
		ship.clear_autopilot_thrust()
		return

	var radial_dir: Vector2 = relative_position.normalized()
	var tangent_dir := Vector2(-radial_dir.y, radial_dir.x)
	if relative_velocity.dot(tangent_dir) < 0.0:
		tangent_dir = -tangent_dir

	var mu_departure: float = G * autopilot_departure_body.get("mass")
	var escape_target_radius: float = (
		get_soi_radius(autopilot_departure_body) * INTERPLANETARY_ESCAPE_SOI_FACTOR
	)
	var remaining: float = execute_apsis_targeting_burn(
		r, escape_target_radius, mu_departure, tangent_dir, relative_velocity
	)
	autopilot_remaining_delta_v = remaining

	if remaining <= 0.0:
		autopilot_phase = AutopilotPhase.INTERPLANETARY_CRUISE


func update_interplanetary_cruise(dt: float) -> void:
	ship.clear_autopilot_thrust()

	if (
		autopilot_departure_body != null
		and autopilot_departure_body != sun
		and is_inside_soi(ship.position, autopilot_departure_body)
	):
		return

	if is_inside_soi(ship.position, autopilot_body):
		autopilot_phase = AutopilotPhase.CAPTURE_BURN
		return

	var target_velocity: Vector2 = Vector2.ZERO
	if autopilot_body != sun:
		target_velocity = autopilot_body.get("velocity")

	var distance_to_target: float = ship.position.distance_to(autopilot_body.position)
	var homing_range: float = (
		get_soi_radius(autopilot_body) * INTERPLANETARY_HOMING_SOI_FACTOR
	)

	if distance_to_target <= homing_range:
		var relative_position: Vector2 = get_relative_position_precise(ship, autopilot_body)
		var relative_velocity: Vector2 = ship.velocity - target_velocity
		var desired_relative_velocity: Vector2 = (
			-relative_position / INTERPLANETARY_APPROACH_TIME
		)
		var error_vector: Vector2 = desired_relative_velocity - relative_velocity
		var error_mag: float = error_vector.length()
		autopilot_remaining_delta_v = error_mag

		if error_mag > 0.05:
			var throttle: float = clampf(error_mag, 0.2, 1.0)
			set_autopilot_direction(error_vector.normalized(), throttle)
		return

	interplanetary_correction_timer += dt
	if interplanetary_correction_timer < INTERPLANETARY_CORRECTION_INTERVAL:
		return
	interplanetary_correction_timer = 0.0

	var mu_sun: float = G * sun.get("mass")
	var ship_r_vec: Vector2 = ship.position - sun.position
	var ship_r: float = ship_r_vec.length()
	var target_r: float = autopilot_body.position.distance_to(sun.position)

	if ship_r < 1.0:
		return

	var radial_dir: Vector2 = ship_r_vec.normalized()
	var tangent_dir := Vector2(-radial_dir.y, radial_dir.x)
	if ship.velocity.dot(tangent_dir) < 0.0:
		tangent_dir = -tangent_dir

	var remaining: float = execute_apsis_targeting_burn(
		ship_r, target_r, mu_sun, tangent_dir, ship.velocity
	)
	autopilot_remaining_delta_v = remaining


func update_interplanetary_capture_burn() -> void:
	if not is_inside_soi(ship.position, autopilot_body):
		ship.clear_autopilot_thrust()
		autopilot_phase = AutopilotPhase.INTERPLANETARY_CRUISE
		return

	var body_velocity: Vector2 = Vector2.ZERO
	if autopilot_body != sun:
		body_velocity = autopilot_body.get("velocity")

	var relative_velocity: Vector2 = ship.velocity - body_velocity
	var relative_position: Vector2 = get_relative_position_precise(ship, autopilot_body)
	var r: float = relative_position.length()

	if r < 1.0:
		ship.clear_autopilot_thrust()
		return

	var radial_dir: Vector2 = relative_position.normalized()
	var tangent_dir := Vector2(-radial_dir.y, radial_dir.x)
	if relative_velocity.dot(tangent_dir) < 0.0:
		tangent_dir = -tangent_dir

	var body_radius: float = autopilot_body.get("radius")
	var mu: float = G * autopilot_body.get("mass")
	var target_radius: float = body_radius + autopilot_target_altitude
	var remaining: float = execute_apsis_targeting_burn(
		r, target_radius, mu, tangent_dir, relative_velocity
	)
	autopilot_remaining_delta_v = remaining

	if remaining <= 0.0:
		var elements = get_orbit_elements(autopilot_body)
		if elements.bound:
			begin_local_capture()


func begin_local_capture() -> void:
	var elements = get_orbit_elements(autopilot_body)
	var body_radius: float = autopilot_body.get("radius")
	var target_radius: float = body_radius + autopilot_target_altitude

	if elements.bound:
		var current_average_altitude: float = 0.5 * (elements.pe_alt + elements.ap_alt)
		var initial_radius: float = body_radius + current_average_altitude
		autopilot_raising = target_radius > initial_radius
	else:
		autopilot_raising = true

	autopilot_target_pe_altitude = autopilot_target_altitude
	autopilot_target_ap_altitude = autopilot_target_altitude
	autopilot_phase = AutopilotPhase.WAIT_FIRST_BURN


func set_autopilot_direction(
	direction: Vector2,
	throttle: float = 1.0
) -> void:
	if direction.length() < 0.0001:
		ship.clear_autopilot_thrust()
		return

	ship.set_autopilot_thrust(
		direction.normalized() * clampf(throttle, 0.0, 1.0)
	)


func update_circularization_burn() -> void:
	var body_velocity: Vector2 = Vector2.ZERO
	if autopilot_body != sun:
		body_velocity = autopilot_body.get("velocity")

	var r_vec: Vector2 = ship.position - autopilot_body.position
	var v_vec: Vector2 = ship.velocity - body_velocity
	var r: float = r_vec.length()

	if r < 1.0:
		ship.clear_autopilot_thrust()
		return

	var radial: Vector2 = r_vec.normalized()
	var tangent := Vector2(-radial.y, radial.x)
	if v_vec.dot(tangent) < 0.0:
		tangent = -tangent

	var mu: float = G * autopilot_body.get("mass")
	var target_velocity: Vector2 = tangent * sqrt(mu / r)
	var error_vector: Vector2 = target_velocity - v_vec
	var error_mag: float = error_vector.length()
	autopilot_remaining_delta_v = error_mag

	if error_mag <= 0.05:
		finish_autopilot_maneuver()
		return

	var throttle: float = clampf(error_mag, 0.2, 1.0)
	set_autopilot_direction(error_vector.normalized(), throttle)


func finish_autopilot_maneuver() -> void:
	ship.clear_autopilot_thrust()
	autopilot_phase = AutopilotPhase.COMPLETE


func execute_apsis_targeting_burn(
	r: float,
	target_radius: float,
	mu: float,
	tangent_dir: Vector2,
	relative_velocity: Vector2
) -> float:
	if r < 1.0 or target_radius <= 0.0:
		ship.clear_autopilot_thrust()
		return 0.0

	var transfer_semi_major_axis: float = 0.5 * (r + target_radius)
	var target_speed: float = sqrt(
		mu * (2.0 / r - 1.0 / transfer_semi_major_axis)
	)
	var target_velocity: Vector2 = tangent_dir * target_speed
	var error_vector: Vector2 = target_velocity - relative_velocity
	var error_mag: float = error_vector.length()

	if error_mag <= 0.05:
		ship.clear_autopilot_thrust()
		return 0.0

	var throttle: float = clampf(error_mag, 0.2, 1.0)
	set_autopilot_direction(error_vector.normalized(), throttle)
	return error_mag


func is_bound_to_body(
	object_position: Vector2,
	object_velocity: Vector2,
	body: Node2D
) -> bool:
	var body_velocity: Vector2 = Vector2.ZERO

	if body != sun:
		body_velocity = body.get("velocity")

	var body_mass: float = body.get("mass")
	var energy: float = get_orbital_energy(
		object_position,
		object_velocity,
		body.position,
		body_velocity,
		body_mass
	)

	return energy < 0.0


func refresh_orbit_parameters_for_body(body: Node2D) -> void:
	var body_velocity: Vector2 = Vector2.ZERO

	if body != sun:
		body_velocity = body.get("velocity")

	var r_vec: Vector2 = ship.position - body.position
	var v_vec: Vector2 = ship.velocity - body_velocity
	var distance: float = r_vec.length()
	var body_mass: float = body.get("mass")
	var body_radius: float = body.get("radius")
	var mu: float = G * body_mass

	if distance < 1.0:
		has_bound_orbit = false
		return

	var velocity_squared: float = v_vec.length_squared()
	var energy: float = velocity_squared / 2.0 - mu / distance

	if energy >= 0.0:
		has_bound_orbit = false
		return

	var semi_major_axis: float = -mu / (2.0 * energy)
	var radial_velocity_term: float = r_vec.dot(v_vec)
	var eccentricity_vector: Vector2 = (
		(
			(velocity_squared - mu / distance) * r_vec
			- radial_velocity_term * v_vec
		)
		/ mu
	)
	var eccentricity: float = eccentricity_vector.length()

	if eccentricity >= 1.0:
		has_bound_orbit = false
		return

	current_periapsis = semi_major_axis * (1.0 - eccentricity)
	current_apoapsis = semi_major_axis * (1.0 + eccentricity)
	current_periapsis_altitude = current_periapsis - body_radius
	current_apoapsis_altitude = current_apoapsis - body_radius
	current_eccentricity = eccentricity
	has_bound_orbit = true


func flash_target_orbit() -> void:
	target_orbit_flash = 1.0


func update_target_orbit_visual() -> void:
	target_orbit.clear_points()

	if not autopilot_selecting and not autopilot_active:
		target_orbit.visible = false
		target_orbit_flash = 0.0
		return

	if autopilot_body == null:
		target_orbit.visible = false
		target_orbit_flash = 0.0
		return

	target_orbit.visible = true

	target_orbit_flash = maxf(
		target_orbit_flash - get_process_delta_time() * TARGET_ORBIT_FLASH_FADE,
		0.0
	)
	target_orbit.default_color = TARGET_ORBIT_COLOR.lerp(
		TARGET_ORBIT_FLASH_COLOR,
		target_orbit_flash
	)

	var body_radius: float = autopilot_body.get("radius")
	var periapsis_radius: float
	var apoapsis_radius: float

	if autopilot_active and autopilot_body == get_current_orbit_body():
		periapsis_radius = body_radius + autopilot_target_pe_altitude
		apoapsis_radius = body_radius + autopilot_target_ap_altitude
	else:
		periapsis_radius = body_radius + autopilot_target_altitude
		apoapsis_radius = periapsis_radius

	if apoapsis_radius < periapsis_radius:
		var swapped: float = periapsis_radius
		periapsis_radius = apoapsis_radius
		apoapsis_radius = swapped

	var semi_major_axis: float = (periapsis_radius + apoapsis_radius) * 0.5

	if semi_major_axis <= 0.0:
		target_orbit.visible = false
		return

	var eccentricity: float = clampf(
		(apoapsis_radius - periapsis_radius)
		/ (apoapsis_radius + periapsis_radius),
		0.0,
		0.95
	)
	var semi_latus_rectum: float = (
		semi_major_axis
		* (1.0 - eccentricity * eccentricity)
	)

	var periapsis_direction: Vector2 = osculating_periapsis_direction

	if periapsis_direction.length_squared() < 0.5:
		periapsis_direction = Vector2.RIGHT

	var perpendicular := Vector2(
		-periapsis_direction.y,
		periapsis_direction.x
	)

	const TARGET_ORBIT_POINTS := 180

	for point_index in range(TARGET_ORBIT_POINTS + 1):
		var theta: float = (
			TAU * float(point_index) / float(TARGET_ORBIT_POINTS)
		)
		var orbit_radius: float = (
			semi_latus_rectum
			/ (1.0 + eccentricity * cos(theta))
		)
		target_orbit.add_point(
			autopilot_body.position
			+ periapsis_direction * cos(theta) * orbit_radius
			+ perpendicular * sin(theta) * orbit_radius
		)


func update_interplanetary_route_visual() -> void:
	var points: PackedVector2Array = route_plan.get("points", PackedVector2Array())
	var should_show: bool = (
		autopilot_active
		and is_route_phase(autopilot_phase)
		and autopilot_phase != AutopilotPhase.ARRIVAL_BURN
		and points.size() >= 2
	)

	interplanetary_route_line.visible = should_show
	departure_burn_marker.visible = false
	transfer_burn_marker.visible = false
	arrival_marker.visible = false

	if not should_show:
		interplanetary_route_line.clear_points()
		return

	interplanetary_route_line.points = points

	if autopilot_phase == AutopilotPhase.DEPARTURE_WAIT:
		place_route_marker(
			departure_burn_marker,
			route_plan.get("burn1_pos", Vector2.INF),
			"BURN 1  T-%s" % format_duration(route_plan.get("burn1_t", INF) - total_sim_time)
		)

	if (
		autopilot_phase == AutopilotPhase.DEPARTURE_WAIT
		or autopilot_phase == AutopilotPhase.DEPARTURE_BURN
		or autopilot_phase == AutopilotPhase.DEPARTURE_COAST
	):
		place_route_marker(
			transfer_burn_marker,
			route_plan.get("burn2_pos", Vector2.INF),
			"BURN 2  Δv %.3f  T-%s" % [
				route_plan.get("dv", Vector2.ZERO).length(),
				format_duration(route_plan.get("burn2_t", INF) - total_sim_time),
			]
		)

	place_route_marker(
		arrival_marker,
		route_plan.get("closest_pos", Vector2.INF),
		"PE %s %.0f  T-%s" % [
			get_body_name(autopilot_body),
			absf(route_plan.get("closest_signed", INF)) - autopilot_body.get("radius"),
			format_duration(route_plan.get("closest_t", INF) - total_sim_time),
		]
	)


func place_route_marker(marker: Node2D, marker_position: Vector2, text: String) -> void:
	if not marker_position.is_finite():
		return

	marker.position = marker_position
	marker.get_node("Label").text = text
	marker.visible = true


func format_duration(seconds: float) -> String:
	if not is_finite(seconds):
		return "--"

	seconds = maxf(seconds, 0.0)
	if seconds >= 3600.0:
		return "%dh%02dm" % [int(seconds / 3600.0), int(fmod(seconds, 3600.0) / 60.0)]
	if seconds >= 60.0:
		return "%dm%02ds" % [int(seconds / 60.0), int(fmod(seconds, 60.0))]
	return "%ds" % int(seconds)


const COLOR_MONO := Color(0.82, 0.85, 0.9)
const COLOR_DIM := Color(0.55, 0.55, 0.62)
const COLOR_GOOD := Color(0.4, 0.9, 0.5)
const COLOR_WARN := Color(0.92, 0.85, 0.35)
const COLOR_BAD := Color(0.95, 0.45, 0.3)
const COLOR_ORBIT_INFO := Color(0.4, 0.9, 1)
const COLOR_ETA_TRANSFER := Color(0.95, 0.4, 0.75)

const PLACEHOLDER_FUEL_PCT := 0.82
const PLACEHOLDER_ENERGY_PCT := 0.95
const PLACEHOLDER_SHIELD_PCT := 1.0


func update_hud() -> void:
	var speed: float = ship.velocity.length()
	var distance: float = ship.position.distance_to(sun.position)

	speed_gauge.speed = speed
	speed_gauge.zoom = camera_zoom
	distance_label.text = hud_row("Sun distance", "%.1f SU" % distance)
	distance_label.add_theme_color_override("font_color", COLOR_MONO)

	var rcs_command: Vector2 = ship.autopilot_rcs_local_command + ship.manual_rcs_local_command
	hud_status.set_state(autopilot_active, rcs_command.length() > 0.05, ship.throttle_locked, ship.throttle)
	time_warp_panel.set_state(time_scale)
	var main_engine_display: float = maxf(ship.throttle, ship.autopilot_main_engine_output)
	ship_blueprint_panel.set_state(main_engine_display, rcs_command)
	# Placeholder demo values - no fuel/energy/shield gameplay system exists yet.
	resource_bars_panel.set_state(PLACEHOLDER_FUEL_PCT, PLACEHOLDER_ENERGY_PCT, PLACEHOLDER_SHIELD_PCT)

	var lock_suffix: String = "  [LOCK]" if ship.throttle_locked else ""

	if time_scale == 0.0:
		thrust_label.text = hud_row("Thrust", "PAUSED" + lock_suffix)
		thrust_label.add_theme_color_override("font_color", COLOR_WARN)
	elif ship.throttle > 0.0 and time_scale > 1.0:
		thrust_label.text = hud_row("Thrust", "OFF (time warp)" + lock_suffix)
		thrust_label.add_theme_color_override("font_color", COLOR_DIM)
	elif ship.throttle > 0.0:
		thrust_label.text = hud_row(
			"Thrust", "%.1f/%.1f%s" % [ship.thrust_force * ship.throttle, ship.thrust_force, lock_suffix]
		)
		thrust_label.add_theme_color_override("font_color", COLOR_MONO)
	else:
		thrust_label.text = hud_row("Thrust", "OFF" + lock_suffix)
		thrust_label.add_theme_color_override("font_color", COLOR_DIM)

	var orbit_node: Node2D = get_current_orbit_body()
	var orbit_body: String = get_orbiting_body()

	if orbit_body == "None":
		orbit_label.text = hud_row("Orbit", "None")
		orbit_label.add_theme_color_override("font_color", COLOR_DIM)
	else:
		orbit_label.text = hud_row("Orbit", orbit_body)
		orbit_label.add_theme_color_override("font_color", COLOR_MONO)

	soi_label.text = hud_row("SOI", get_current_soi())
	soi_label.add_theme_color_override("font_color", COLOR_MONO)

	if ship.fov_devices.size() > 0:
		var fov_bits: PackedStringArray = []
		if not ship.radar_contacts.is_empty():
			fov_bits.append("RAD " + ", ".join(ship.radar_contacts))
		if not ship.weapon_locks.is_empty():
			fov_bits.append("LOCK " + ", ".join(ship.weapon_locks) + " [G]")
		if fov_bits.is_empty():
			fov_bits.append("scanning…")
		soi_label.text = hud_row("SOI", get_current_soi()) + "\n" + hud_row("Sensors", " | ".join(fov_bits))

	if trajectory_status == "IMPACT":
		trajectory_label.text = hud_row("Trajectory", "IMPACT - " + trajectory_target)
		trajectory_label.add_theme_color_override("font_color", COLOR_MONO)
	else:
		trajectory_label.text = hud_row("Trajectory", trajectory_status)
		trajectory_label.add_theme_color_override("font_color", COLOR_MONO)

	var show_apsis_targets: bool = can_edit_autopilot_apsis_targets()

	if has_bound_orbit:
		eccentricity_label.text = hud_row("Eccentricity", "%.3f" % current_eccentricity)
		eccentricity_label.add_theme_color_override("font_color", COLOR_MONO)
		pe_gauge.set_value(
			current_periapsis_altitude, true, autopilot_target_pe_altitude, show_apsis_targets
		)
		ap_gauge.set_value(
			current_apoapsis_altitude, true, autopilot_target_ap_altitude, show_apsis_targets
		)
	else:
		eccentricity_label.text = hud_row("Eccentricity", "--")
		eccentricity_label.add_theme_color_override("font_color", COLOR_DIM)
		pe_gauge.set_value(0.0, false)
		ap_gauge.set_value(0.0, false)

	update_autopilot_hud()


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


func get_phase_color(phase: AutopilotPhase) -> Color:
	match phase:
		AutopilotPhase.OFF:
			return COLOR_DIM
		AutopilotPhase.COMPLETE:
			return COLOR_GOOD
		AutopilotPhase.WAIT_FIRST_BURN, AutopilotPhase.COAST, \
		AutopilotPhase.STATION_KEEPING_WAIT, AutopilotPhase.DEPARTURE_WAIT, \
		AutopilotPhase.DEPARTURE_COAST, AutopilotPhase.TRANSFER_COAST, \
		AutopilotPhase.ARRIVAL_COAST, AutopilotPhase.INTERPLANETARY_CRUISE:
			return COLOR_ORBIT_INFO
		_:
			return COLOR_WARN


func update_autopilot_hud() -> void:
	if autopilot_selecting:
		autopilot_panel.set_state({
			"active": false,
			"selecting": true,
			"body_name": get_body_name(autopilot_body),
			"body_color": get_body_display_color(autopilot_body),
			"target_altitude": autopilot_target_altitude,
			"tolerance": AUTOPILOT_TOLERANCE,
		})
		return

	if not autopilot_active:
		autopilot_panel.set_state({"active": false, "selecting": false})
		return

	var burn_mode_text: String
	var burn_mode_color: Color
	if is_autopilot_using_main_engine():
		burn_mode_text = "MAIN ENGINE"
		burn_mode_color = Color(1.0, 0.6, 0.2)
	elif ship.autopilot_thrust != Vector2.ZERO:
		burn_mode_text = "RCS"
		burn_mode_color = Color(0.4, 0.75, 1.0)
	else:
		burn_mode_text = "COASTING"
		burn_mode_color = Color(0.55, 0.6, 0.68)

	var eta: Dictionary = get_autopilot_eta()
	var eta_text: String = ""
	var eta_color: Color = Color.WHITE
	if eta.get("valid", false):
		var eta_is_orbit: bool = eta.get("is_orbit", true)
		eta_text = (
			("ORBIT IN: " if eta_is_orbit else "ARRIVAL IN: ")
			+ format_duration(eta.get("time", 0.0))
		)
		eta_color = COLOR_GOOD if eta_is_orbit else COLOR_ETA_TRANSFER

	autopilot_panel.set_state({
		"active": true,
		"selecting": false,
		"body_name": get_body_name(autopilot_body),
		"body_color": get_body_display_color(autopilot_body),
		"target_altitude": autopilot_target_altitude,
		"target_pe_altitude": autopilot_target_pe_altitude,
		"target_ap_altitude": autopilot_target_ap_altitude,
		"show_apsis_targets": not is_interplanetary_autopilot_phase(autopilot_phase),
		"tolerance": AUTOPILOT_TOLERANCE,
		"burn1": autopilot_planned_delta_v1,
		"burn2": autopilot_planned_delta_v2,
		"remaining_delta_v": autopilot_remaining_delta_v,
		"remaining_color": get_delta_v_color(autopilot_remaining_delta_v),
		"eta_text": eta_text,
		"eta_color": eta_color,
		"rcs_lines": get_rcs_status(),
		"status_lines": get_autopilot_status().split("\n"),
		"status_color": get_phase_color(autopilot_phase),
		"burn_mode_text": burn_mode_text,
		"burn_mode_color": burn_mode_color,
	})


func get_autopilot_eta() -> Dictionary:
	match autopilot_phase:
		AutopilotPhase.DEPARTURE_WAIT, AutopilotPhase.DEPARTURE_BURN, AutopilotPhase.DEPARTURE_COAST, \
		AutopilotPhase.TRANSFER_BURN, AutopilotPhase.TRANSFER_COAST, AutopilotPhase.ESCAPE_BURN, \
		AutopilotPhase.INTERPLANETARY_CRUISE, AutopilotPhase.ARRIVAL_COAST:
			var arrival_time: float = route_plan.get("closest_t", -1.0)
			if arrival_time < 0.0:
				return {"valid": false}
			return {"valid": true, "is_orbit": false, "time": maxf(arrival_time - total_sim_time, 0.0)}

		AutopilotPhase.ARRIVAL_BURN, AutopilotPhase.CAPTURE_BURN, AutopilotPhase.SECOND_BURN, \
		AutopilotPhase.STATION_KEEPING_BURN:
			return {"valid": true, "is_orbit": true, "time": 0.0}

		AutopilotPhase.WAIT_FIRST_BURN, AutopilotPhase.FIRST_BURN, AutopilotPhase.COAST, \
		AutopilotPhase.STATION_KEEPING_WAIT:
			var eta: float = get_local_orbit_eta()
			if eta < 0.0:
				return {"valid": false}
			return {"valid": true, "is_orbit": true, "time": eta}

		_:
			return {"valid": false}


func get_local_orbit_eta() -> float:
	if autopilot_body == null or not is_inside_soi(ship.position, autopilot_body):
		return -1.0

	var body_velocity: Vector2 = Vector2.ZERO
	if autopilot_body != sun:
		body_velocity = autopilot_body.get("velocity")

	var relative_velocity: Vector2 = ship.velocity - body_velocity
	var relative_position: Vector2 = get_relative_position_precise(ship, autopilot_body)
	var mu: float = G * autopilot_body.get("mass")
	var orbit: Dictionary = OrbitMath.elements(relative_position, relative_velocity, mu)
	if orbit.e >= 1.0:
		return -1.0

	var period: float = OrbitMath.orbital_period(orbit.a, mu)

	match autopilot_phase:
		AutopilotPhase.WAIT_FIRST_BURN:
			return time_to_apsis(orbit, mu, autopilot_raising)
		AutopilotPhase.FIRST_BURN:
			return period * 0.5
		AutopilotPhase.COAST:
			return time_to_apsis(orbit, mu, not autopilot_raising)
		AutopilotPhase.STATION_KEEPING_WAIT:
			return time_to_apsis(orbit, mu, station_keeping_correcting_apoapsis)
		_:
			return -1.0


func time_to_apsis(orbit: Dictionary, mu: float, at_periapsis: bool) -> float:
	return OrbitMath.time_to_periapsis(orbit, mu) if at_periapsis else OrbitMath.time_to_apoapsis(orbit, mu)


func get_body_name(body: Node2D) -> String:
	if body == null:
		return "None"

	return body.get("body_name")


func get_rcs_status() -> PackedStringArray:
	var thrust: Vector2 = ship.autopilot_thrust
	var up_strength: float = maxf(-thrust.y, 0.0)
	var down_strength: float = maxf(thrust.y, 0.0)
	var left_strength: float = maxf(-thrust.x, 0.0)
	var right_strength: float = maxf(thrust.x, 0.0)

	return PackedStringArray([
		"↑ %.2f  ↓ %.2f" % [up_strength, down_strength],
		"← %.2f  → %.2f" % [left_strength, right_strength],
	])


func get_autopilot_status() -> String:
	match autopilot_phase:
		AutopilotPhase.DEPARTURE_WAIT:
			if not route_plan.get("ok", false):
				return "INTERPLANETARY: PLANNING ROUTE..."
			return (
				"INTERPLANETARY: WAITING FOR WINDOW\n"
				+ "BURN 1 IN: %s" % format_duration(route_plan.t_start - total_sim_time)
			)
		AutopilotPhase.DEPARTURE_BURN:
			return "INTERPLANETARY: BURN 1 (ESCAPE)"
		AutopilotPhase.DEPARTURE_COAST:
			return (
				"INTERPLANETARY: LEAVING SOI\n"
				+ "BURN 2 IN: %s" % format_duration(route_plan.get("burn2_t", INF) - total_sim_time)
			)
		AutopilotPhase.TRANSFER_BURN:
			return "INTERPLANETARY: TRANSFER BURN"
		AutopilotPhase.TRANSFER_COAST:
			return (
				"INTERPLANETARY: CRUISE\n"
				+ "ARRIVAL IN: %s" % format_duration(route_plan.get("closest_t", INF) - total_sim_time)
			)
		AutopilotPhase.ARRIVAL_COAST:
			return "INTERPLANETARY: COASTING TO PERIAPSIS"
		AutopilotPhase.ARRIVAL_BURN:
			return "INTERPLANETARY: CAPTURE BURN"
		AutopilotPhase.ESCAPE_BURN:
			return "INTERPLANETARY: ESCAPE BURN"
		AutopilotPhase.INTERPLANETARY_CRUISE:
			return "INTERPLANETARY: CRUISE"
		AutopilotPhase.CAPTURE_BURN:
			return "INTERPLANETARY: CAPTURE BURN"
		AutopilotPhase.WAIT_FIRST_BURN:
			return "WAITING FOR APSIS"
		AutopilotPhase.FIRST_BURN:
			return "BURN 1: MATCHING ALTITUDE"
		AutopilotPhase.COAST:
			return "COASTING TO OPPOSITE APSIS"
		AutopilotPhase.SECOND_BURN:
			return "BURN 2: CIRCULARIZING"
		AutopilotPhase.COMPLETE:
			return "MONITORING ORBIT"
		AutopilotPhase.STATION_KEEPING_WAIT:
			return "STATION KEEPING: WAITING FOR APSIS"
		AutopilotPhase.STATION_KEEPING_BURN:
			return "STATION KEEPING: CORRECTION BURN"
		_:
			return "OFF"


func update_trajectory_prediction_async(delta: float) -> void:
	if trajectory_task_id != -1:
		if not WorkerThreadPool.is_task_completed(trajectory_task_id):
			return
		WorkerThreadPool.wait_for_task_completion(trajectory_task_id)
		trajectory_task_id = -1
		apply_trajectory_result(trajectory_task_holder.get("result", {}))

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
	var count: int = planets.size()
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
		positions[i] = planets[i].position
		velocities[i] = planets[i].velocity
		radii[i] = planets[i].get("radius")
		masses[i] = planets[i].get("mass")
		soi_radii[i] = get_soi_radius(planets[i])
		names.append(get_body_name(planets[i]))

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
		"prediction_steps": 12000 if (settings_mgr != null and settings_mgr.trajectory_long_prediction) else PREDICTION_STEPS,
	}


func apply_trajectory_result(result: Dictionary) -> void:
	if result.is_empty():
		return

	trajectory_prediction.points = result.get("points", PackedVector2Array())
	update_trajectory_status(result.get("status", "ORBIT"), result.get("target", ""))

	match trajectory_status:
		"IMPACT":
			trajectory_prediction.default_color = Color.RED
		"ESCAPE":
			trajectory_prediction.default_color = Color.ORANGE
		"ORBIT":
			trajectory_prediction.default_color = Color.CYAN

	if autopilot_active and is_interplanetary_autopilot_phase(autopilot_phase):
		trajectory_prediction.default_color = Color.PINK


static func predict_trajectory(snap: Dictionary) -> Dictionary:
	var points := PackedVector2Array()
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

	points.append(ship_pos)

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
			predicted_status = "IMPACT"
			collision_detected = true
			break

		hit = _segment_circle_collision(
			previous_ship_pos, ship_pos, sun_pos, sun_radius + ship_radius
		)

		if hit != null:
			points.append(hit)
			predicted_status = "IMPACT"
			predicted_target = snap.sun_name
			collision_detected = true
			break

		if step % PREDICTION_DRAW_INTERVAL == 0:
			points.append(ship_pos)

	if not collision_detected:
		predicted_status = (
			"ESCAPE" if _is_escape_trajectory(ship_pos, ship_vel, sun_pos, sun_mass)
			else "ORBIT"
		)

	return {"points": points, "status": predicted_status, "target": predicted_target}


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
	sun_pos: Vector2,
	sun_mass: float
) -> bool:
	var distance: float = position.distance_to(sun_pos)

	if distance < 1.0:
		return false

	var escape_velocity: float = sqrt(2.0 * G * sun_mass / distance)
	var radial_direction: Vector2 = (position - sun_pos).normalized()
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


func _on_orbit_info_pressed() -> void:
	if planet_info_panel.visible:
		planet_info_panel.hide_panel()
		return

	var body: Node2D = get_current_orbit_body()
	var is_sun: bool = body == sun
	var body_radius: float = body.get("radius")

	planet_info_panel.show_body(
		get_body_name(body),
		body.get("color"),
		body_radius,
		body.get("mass"),
		0.0 if is_sun else get_soi_radius(body),
		body.get("atmosphere"),
		is_sun
	)


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
	get_tree().change_scene_to_file("res://scenes/menu/MainMenu.tscn")


func toggle_ship_builder() -> void:
	if ship_builder_panel.visible:
		close_ship_builder()
	else:
		open_ship_builder()


func open_ship_builder() -> void:
	autopilot_selecting = false
	ship_builder_panel.visible = true


func close_ship_builder() -> void:
	ship_builder_panel.visible = false
	_sync_ship_from_builder()


func toggle_enemy_menu() -> void:
	if enemy_menu_panel == null:
		return
	if enemy_menu_panel.visible:
		enemy_menu_panel.visible = false
	else:
		enemy_menu_panel.refresh()
		enemy_menu_panel.visible = true


## Spawns the chosen sandbox enemy at the player ship's position and hands
## WASD/Space control to it (see simulation_step's _test_enemy guard).
func _on_enemy_selected(enemy_id: String) -> void:
	var entry: Dictionary = {}
	for candidate: Dictionary in EnemyCatalog.all_enemies():
		if str(candidate.get("id", "")) == enemy_id:
			entry = candidate
			break
	if entry.is_empty():
		return

	if _test_enemy != null:
		_test_enemy.queue_free()
		_test_enemy = null

	var scene: PackedScene = entry.get("scene")
	if scene == null:
		return

	var enemy := scene.instantiate() as Enemy
	ship.get_parent().add_child(enemy)
	enemy.global_position = ship.global_position
	enemy.rotation = ship.rotation
	_test_enemy = enemy

	enemy_menu_panel.visible = false


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


func update_fov_gameplay() -> void:
	if ship == null:
		return
	if ship.fov_devices.is_empty():
		ship.clear_fov_contacts()
		for body in celestial_bodies:
			if body.get("fov_contact") != null:
				body.set("fov_contact", 0)
		return

	var has_radar := false
	for device in ship.fov_devices:
		if str(device.get("kind", "")) == "radar":
			has_radar = true
			break

	var radar: Array[String] = []
	var locks: Array[String] = []
	for body in celestial_bodies:
		var body_name: String = str(body.get("body_name"))
		var in_radar := false
		var in_weapon := false
		for device in ship.fov_devices:
			var kind := str(device.get("kind", ""))
			if not ship.is_body_in_device_fov(device, body.position):
				continue
			if kind == "radar":
				in_radar = true
			elif kind == "weapon":
				in_weapon = true

		var contact := 0
		if in_radar:
			radar.append(body_name)
			contact = 1
		# With radars fitted, weapons only lock bodies the sensors already see.
		# Without any radar, weapons lock on their own FOV.
		var can_lock := in_weapon and (in_radar or not has_radar)
		if can_lock:
			locks.append(body_name)
			contact = 2
		body.set("fov_contact", contact)

	ship.set_fov_contacts(radar, locks)


func _try_fire_fov_weapon() -> void:
	if ship == null or ship.weapon_locks.is_empty():
		return
	var best_body: Node2D = null
	var best_dist := INF
	for body in celestial_bodies:
		var body_name: String = str(body.get("body_name"))
		if not ship.weapon_locks.has(body_name):
			continue
		var dist: float = ship.position.distance_to(body.position)
		if dist < best_dist:
			best_dist = dist
			best_body = body
	if best_body != null:
		ship.try_fire_at(best_body.position)


func _on_setting_changed(key: String, value: Variant) -> void:
	match key:
		"show_orbit_lines":
			for line in orbit_lines:
				line.visible = value
		"show_soi_circles":
			for planet in planets:
				planet.show_soi = value
		"show_trajectory":
			trajectory_prediction.visible = value
		"starfield_brightness":
			if background_mask != null:
				background_mask.color.a = clampf(1.0 - float(value), 0.0, 1.0)
		"ship_rotation_speed":
			if ship != null:
				ship.rotation_speed = float(value)
		"autopilot_default_main_engine":
			autopilot_main_thruster_allowed = bool(value)
			if main_thruster_toggle != null:
				main_thruster_toggle.button_pressed = bool(value)
		"camera_smoothing":
			pass


func _apply_all_settings() -> void:
	if settings_mgr == null:
		return
	for line in orbit_lines:
		line.visible = settings_mgr.show_orbit_lines
	for planet in planets:
		planet.show_soi = settings_mgr.show_soi_circles
	trajectory_prediction.visible = settings_mgr.show_trajectory
	if background_mask != null:
		background_mask.color.a = clampf(1.0 - settings_mgr.starfield_brightness, 0.0, 1.0)
	if ship != null:
		ship.rotation_speed = settings_mgr.ship_rotation_speed
	autopilot_main_thruster_allowed = settings_mgr.autopilot_default_main_engine
	if main_thruster_toggle != null:
		main_thruster_toggle.button_pressed = settings_mgr.autopilot_default_main_engine


func _on_main_thruster_toggled(pressed: bool) -> void:
	autopilot_main_thruster_allowed = pressed


func _on_time_scale_selected(value: float) -> void:
	set_time_scale(value)


func set_time_scale(value: float) -> void:
	if value > 0.0:
		previous_time_scale = value
	time_scale = value
	if ship != null:
		ship.paused = (time_scale == 0.0)


func toggle_pause() -> void:
	if time_scale > 0.0:
		previous_time_scale = time_scale
		set_time_scale(0.0)
	else:
		set_time_scale(previous_time_scale if previous_time_scale > 0.0 else 1.0)


func step_simulation_once() -> void:
	if time_scale > 0.0:
		previous_time_scale = time_scale
		set_time_scale(0.0)

	if soi_radii_cache.size() != planets.size():
		soi_radii_cache.resize(planets.size())
	for i in range(planets.size()):
		soi_radii_cache[i] = get_soi_radius(planets[i])

	simulation_step(SIM_DT)
	total_sim_time += SIM_DT

	for i in range(planets.size()):
		update_orbit_line(planets[i], orbit_lines[i], i)


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
	var distance_to_sun: float = body.position.distance_to(sun.position)
	var body_mass: float = body.get("mass")
	var sun_mass: float = sun.get("mass")

	return distance_to_sun * pow(
		body_mass / sun_mass,
		0.4
	)


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


func _physics_process(delta: float) -> void:
	simulation_accumulator += delta * time_scale

	var steps := 0

	if soi_radii_cache.size() != planets.size():
		soi_radii_cache.resize(planets.size())
	for i in range(planets.size()):
		soi_radii_cache[i] = get_soi_radius(planets[i])

	while simulation_accumulator >= SIM_DT and steps < MAX_SIM_STEPS_PER_FRAME:
		simulation_step(SIM_DT)
		simulation_accumulator -= SIM_DT
		total_sim_time += SIM_DT
		steps += 1

	if steps > 0:
		for i in range(planets.size()):
			update_orbit_line(planets[i], orbit_lines[i], i)

	# Global so every planet shader lights itself from the sun without each
	# body needing to know where the sun is.
	RenderingServer.global_shader_parameter_set(
		"sun_position", Vector3(sun.global_position.x, 0.0, sun.global_position.y)
	)


func simulation_step(dt: float) -> void:
	update_orbit_autopilot(dt)

	if ship.poll_lock_toggle(time_scale <= 1.0) and autopilot_active:
		disengage_autopilot()

	var autopilot_on_main_engine: bool = is_autopilot_using_main_engine()
	var autopilot_thrusting: bool = ship.autopilot_thrust != Vector2.ZERO

	# While test-flying a sandbox enemy (E menu), the player ship stops reading
	# WASD/mouse-aim so both craft don't respond to the same keys at once.
	if _test_enemy == null:
		if Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
			ship.update_rotation(dt)
		elif autopilot_on_main_engine:
			ship.update_autopilot_rotation(dt)
		else:
			ship.update_rotation(dt)

		if autopilot_thrusting:
			ship.disengage_manual_main_engine()
		else:
			ship.update_throttle(dt, time_scale <= 1.0)

	var count: int = physics_planets.size()

	var a0 := PackedVector2Array()
	a0.resize(count)
	for i in range(count):
		a0[i] = get_planet_acceleration_precise(physics_planets[i])
	var ship_a0: Vector2 = get_ship_acceleration_precise()

	for i in range(count):
		physics_planets[i].advance_position(a0[i], dt)
	physics_ship.advance_position(ship_a0, dt)

	var a1 := PackedVector2Array()
	a1.resize(count)
	for i in range(count):
		a1[i] = get_planet_acceleration_precise(physics_planets[i])
	var ship_a1: Vector2 = get_ship_acceleration_precise()

	for i in range(count):
		physics_planets[i].advance_velocity(a0[i], a1[i], dt)
	physics_ship.advance_velocity(ship_a0, ship_a1, dt)

	for i in range(count):
		physics_planets[i].push_to_node()
	physics_ship.push_to_node()


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

	for i in range(planets.size()):
		if is_inside_soi_precise(physics_planets[i], soi_radii_cache[i]):
			acceleration = (
				get_gravity_precise(
					physics_ship,
					physics_planets[i].x,
					physics_planets[i].y,
					mu_planets[i]
				)
				+ get_planet_acceleration_precise(physics_planets[i])
			)
			break

	if time_scale <= 1.0:
		acceleration += ship.get_thrust_acceleration()
		acceleration += ship.get_manual_rcs_acceleration()
	elif ship.throttle_locked:
		acceleration += ship.get_thrust_acceleration()
	acceleration += ship.get_autopilot_acceleration(
		get_autopilot_thrust_force(), is_autopilot_using_main_engine()
	)

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

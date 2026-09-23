extends Control

signal closed
signal setting_changed(key: String, value: Variant)
signal track_skip_requested(direction: int)
signal track_play_pause_requested

var settings: SettingsManager
var music_manager: MusicManager

var current_tab: int = 0
const TABS: Array[String] = [
	"Gameplay",
	"Graphics & Display",
	"Keybindings",
	"Audio & Music",
]

# Centralized Design Tokens (High-Precision Telemetry)
const COLOR_CYAN := HudPanelStyle.COLOR_CYAN
const COLOR_CYAN_DIM := HudPanelStyle.COLOR_CYAN_DIM
const COLOR_AMBER := HudPanelStyle.COLOR_AMBER
const COLOR_EMERALD := HudPanelStyle.COLOR_EMERALD

const COLOR_TEXT_PRIMARY := HudPanelStyle.COLOR_TEXT_PRIMARY
const COLOR_TEXT_SECONDARY := HudPanelStyle.COLOR_TEXT_SECONDARY
const COLOR_TEXT_MUTED := HudPanelStyle.COLOR_TEXT_MUTED
const COLOR_TEXT_FAINT := HudPanelStyle.COLOR_TEXT_FAINT

const COLOR_CANVAS_BG := HudPanelStyle.COLOR_BG_CANVAS
const COLOR_CARD_BG := HudPanelStyle.COLOR_BG_SURFACE
const COLOR_CARD_BORDER := HudPanelStyle.COLOR_BORDER_DEFAULT

# Icons from Iconify / Lucide
var icon_settings: Texture2D
var icon_x: Texture2D
var icon_tab_gameplay: Texture2D
var icon_tab_graphics: Texture2D
var icon_tab_shortcuts: Texture2D
var icon_tab_audio: Texture2D
var icon_volume_2: Texture2D
var icon_volume_x: Texture2D
var icon_skip_back: Texture2D
var icon_skip_forward: Texture2D
var icon_play: Texture2D
var icon_pause: Texture2D

# Interaction state
var _dragging_slider: String = ""
var _hover_pos := Vector2(-1.0, -1.0)

# Click areas
var _close_rect := Rect2()
var _tab_rects: Array[Rect2] = []

# Tab 0: Gameplay rects
var _rot_slider_rect := Rect2()
var _zoom_slider_rect := Rect2()
var _pan_slider_rect := Rect2()
var _toggle_smoothing_rect := Rect2()
var _toggle_warp_drop_rect := Rect2()
var _toggle_auto_engine_rect := Rect2()

# Tab 1: Graphics rects
var _toggle_fullscreen_rect := Rect2()
var _toggle_vsync_rect := Rect2()
var _toggle_orbits_rect := Rect2()
var _toggle_soi_rect := Rect2()
var _toggle_trajectory_rect := Rect2()
var _toggle_horizon_rect := Rect2()
var _starfield_slider_rect := Rect2()

# Tab 3: Audio rects
var _master_slider_rect := Rect2()
var _master_mute_rect := Rect2()
var _music_slider_rect := Rect2()
var _music_mute_rect := Rect2()
var _sfx_slider_rect := Rect2()
var _sfx_mute_rect := Rect2()
var _toggle_music_toast_rect := Rect2()
var _toggle_autoplay_rect := Rect2()
var _music_prev_rect := Rect2()
var _music_toggle_rect := Rect2()
var _music_next_rect := Rect2()


func _ready() -> void:
	icon_settings = _load_icon("res://textures/icons/settings.svg")
	icon_x = _load_icon("res://textures/icons/x.svg")
	icon_tab_gameplay = _load_icon("res://textures/icons/rocket.svg")
	icon_tab_graphics = _load_icon("res://textures/icons/monitor.svg")
	icon_tab_shortcuts = _load_icon("res://textures/icons/keyboard.svg")
	icon_tab_audio = _load_icon("res://textures/icons/music.svg")
	icon_volume_2 = _load_icon("res://textures/icons/volume_2.svg")
	icon_volume_x = _load_icon("res://textures/icons/volume_x.svg")
	icon_skip_back = _load_icon("res://textures/icons/skip_back.svg")
	icon_skip_forward = _load_icon("res://textures/icons/skip_forward.svg")
	icon_play = _load_icon("res://textures/icons/play.svg")
	icon_pause = _load_icon("res://textures/icons/pause.svg")

	mouse_exited.connect(func() -> void:
		_hover_pos = Vector2(-1.0, -1.0)
		queue_redraw()
	)


func _process(_delta: float) -> void:
	# Keep audio visualizer smoothly animated only when Audio tab is open and music is playing
	if visible and current_tab == 3 and music_manager != null and music_manager.is_playing():
		queue_redraw()


static func _load_icon(path: String) -> Texture2D:
	if ResourceLoader.exists(path):
		var res = load(path)
		if res is Texture2D:
			return res
	if FileAccess.file_exists(path):
		var img := Image.load_from_file(path)
		if img != null:
			return ImageTexture.create_from_image(img)
	return null


func setup(p_settings: SettingsManager, p_music: MusicManager) -> void:
	settings = p_settings
	music_manager = p_music
	if music_manager != null:
		music_manager.track_changed.connect(func(_name: String) -> void: queue_redraw())
		music_manager.playback_state_changed.connect(func(_playing: bool) -> void: queue_redraw())
	queue_redraw()


func open_menu() -> void:
	visible = true
	_dragging_slider = ""
	_hover_pos = Vector2(-1.0, -1.0)
	current_tab = 0
	queue_redraw()


func close_menu() -> void:
	visible = false
	_dragging_slider = ""
	_hover_pos = Vector2(-1.0, -1.0)
	closed.emit()


func _gui_input(event: InputEvent) -> void:
	if not visible:
		return

	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				_handle_mouse_down(event.position)
			else:
				_dragging_slider = ""
		accept_event()

	elif event is InputEventMouseMotion:
		_hover_pos = event.position
		if _dragging_slider != "":
			_handle_slider_drag(event.position)
		queue_redraw()
		accept_event()


func _handle_mouse_down(pos: Vector2) -> void:
	if _close_rect.has_point(pos):
		close_menu()
		return

	for i in range(_tab_rects.size()):
		if _tab_rects[i].has_point(pos):
			current_tab = i
			queue_redraw()
			return

	if current_tab == 0:
		_handle_gameplay_clicks(pos)
	elif current_tab == 1:
		_handle_graphics_clicks(pos)
	elif current_tab == 3:
		_handle_audio_clicks(pos)


func _handle_gameplay_clicks(pos: Vector2) -> void:
	if _rot_slider_rect.has_point(pos):
		_dragging_slider = "rot_speed"
		_set_slider_range(_rot_slider_rect, pos.x, 1.0, 5.0, func(v: float) -> void:
			settings.ship_rotation_speed = v
			settings.save_settings()
			setting_changed.emit("ship_rotation_speed", v)
		)
	elif _zoom_slider_rect.has_point(pos):
		_dragging_slider = "zoom_speed"
		_set_slider_range(_zoom_slider_rect, pos.x, 1.05, 1.5, func(v: float) -> void:
			settings.camera_zoom_speed = v
			settings.save_settings()
			setting_changed.emit("camera_zoom_speed", v)
		)
	elif _pan_slider_rect.has_point(pos):
		_dragging_slider = "pan_speed"
		_set_slider_range(_pan_slider_rect, pos.x, 0.5, 2.5, func(v: float) -> void:
			settings.camera_pan_speed = v
			settings.save_settings()
			setting_changed.emit("camera_pan_speed", v)
		)
	elif _toggle_smoothing_rect.has_point(pos):
		settings.camera_smoothing = not settings.camera_smoothing
		settings.save_settings()
		setting_changed.emit("camera_smoothing", settings.camera_smoothing)
		queue_redraw()
	elif _toggle_warp_drop_rect.has_point(pos):
		settings.auto_drop_warp_on_thrust = not settings.auto_drop_warp_on_thrust
		settings.save_settings()
		setting_changed.emit("auto_drop_warp_on_thrust", settings.auto_drop_warp_on_thrust)
		queue_redraw()
	elif _toggle_auto_engine_rect.has_point(pos):
		settings.autopilot_default_main_engine = not settings.autopilot_default_main_engine
		settings.save_settings()
		setting_changed.emit("autopilot_default_main_engine", settings.autopilot_default_main_engine)
		queue_redraw()


func _handle_graphics_clicks(pos: Vector2) -> void:
	if _toggle_fullscreen_rect.has_point(pos):
		settings.set_fullscreen(not settings.fullscreen)
		setting_changed.emit("fullscreen", settings.fullscreen)
		queue_redraw()
	elif _toggle_vsync_rect.has_point(pos):
		settings.set_vsync(not settings.vsync)
		setting_changed.emit("vsync", settings.vsync)
		queue_redraw()
	elif _toggle_orbits_rect.has_point(pos):
		settings.show_orbit_lines = not settings.show_orbit_lines
		settings.save_settings()
		setting_changed.emit("show_orbit_lines", settings.show_orbit_lines)
		queue_redraw()
	elif _toggle_soi_rect.has_point(pos):
		settings.show_soi_circles = not settings.show_soi_circles
		settings.save_settings()
		setting_changed.emit("show_soi_circles", settings.show_soi_circles)
		queue_redraw()
	elif _toggle_trajectory_rect.has_point(pos):
		settings.show_trajectory = not settings.show_trajectory
		settings.save_settings()
		setting_changed.emit("show_trajectory", settings.show_trajectory)
		queue_redraw()
	elif _toggle_horizon_rect.has_point(pos):
		settings.trajectory_long_prediction = not settings.trajectory_long_prediction
		settings.save_settings()
		setting_changed.emit("trajectory_long_prediction", settings.trajectory_long_prediction)
		queue_redraw()
	elif _starfield_slider_rect.has_point(pos):
		_dragging_slider = "starfield"
		_set_slider_range(_starfield_slider_rect, pos.x, 0.0, 1.0, func(v: float) -> void:
			settings.starfield_brightness = v
			settings.save_settings()
			setting_changed.emit("starfield_brightness", v)
		)


func _handle_audio_clicks(pos: Vector2) -> void:
	if _master_slider_rect.has_point(pos):
		_dragging_slider = "master"
		_set_slider_range(_master_slider_rect, pos.x, 0.0, 1.0, func(v: float) -> void: settings.set_master_volume(v))
	elif _master_mute_rect.has_point(pos):
		settings.toggle_master_mute()
		queue_redraw()
	elif _music_slider_rect.has_point(pos):
		_dragging_slider = "music"
		_set_slider_range(_music_slider_rect, pos.x, 0.0, 1.0, func(v: float) -> void: settings.set_music_volume(v))
	elif _music_mute_rect.has_point(pos):
		settings.toggle_music_mute()
		queue_redraw()
	elif _sfx_slider_rect.has_point(pos):
		_dragging_slider = "sfx"
		_set_slider_range(_sfx_slider_rect, pos.x, 0.0, 1.0, func(v: float) -> void: settings.set_sfx_volume(v))
	elif _sfx_mute_rect.has_point(pos):
		settings.toggle_sfx_mute()
		queue_redraw()
	elif _toggle_music_toast_rect.has_point(pos):
		settings.show_music_notifications = not settings.show_music_notifications
		settings.save_settings()
		setting_changed.emit("show_music_notifications", settings.show_music_notifications)
		queue_redraw()
	elif _toggle_autoplay_rect.has_point(pos):
		settings.autoplay_music = not settings.autoplay_music
		settings.save_settings()
		setting_changed.emit("autoplay_music", settings.autoplay_music)
		queue_redraw()
	elif _music_prev_rect.has_point(pos):
		if music_manager != null:
			music_manager.prev_track()
		queue_redraw()
	elif _music_toggle_rect.has_point(pos):
		if music_manager != null:
			music_manager.toggle_playback()
		queue_redraw()
	elif _music_next_rect.has_point(pos):
		if music_manager != null:
			music_manager.next_track()
		queue_redraw()


func _handle_slider_drag(pos: Vector2) -> void:
	match _dragging_slider:
		"rot_speed":
			_set_slider_range(_rot_slider_rect, pos.x, 1.0, 5.0, func(v: float) -> void:
				settings.ship_rotation_speed = v
				settings.save_settings()
				setting_changed.emit("ship_rotation_speed", v)
			)
		"zoom_speed":
			_set_slider_range(_zoom_slider_rect, pos.x, 1.05, 1.5, func(v: float) -> void:
				settings.camera_zoom_speed = v
				settings.save_settings()
				setting_changed.emit("camera_zoom_speed", v)
			)
		"pan_speed":
			_set_slider_range(_pan_slider_rect, pos.x, 0.5, 2.5, func(v: float) -> void:
				settings.camera_pan_speed = v
				settings.save_settings()
				setting_changed.emit("camera_pan_speed", v)
			)
		"starfield":
			_set_slider_range(_starfield_slider_rect, pos.x, 0.0, 1.0, func(v: float) -> void:
				settings.starfield_brightness = v
				settings.save_settings()
				setting_changed.emit("starfield_brightness", v)
			)
		"master":
			_set_slider_range(_master_slider_rect, pos.x, 0.0, 1.0, func(v: float) -> void: settings.set_master_volume(v))
		"music":
			_set_slider_range(_music_slider_rect, pos.x, 0.0, 1.0, func(v: float) -> void: settings.set_music_volume(v))
		"sfx":
			_set_slider_range(_sfx_slider_rect, pos.x, 0.0, 1.0, func(v: float) -> void: settings.set_sfx_volume(v))


func _set_slider_range(rect: Rect2, x: float, min_val: float, max_val: float, apply_fn: Callable) -> void:
	var fraction: float = clampf((x - rect.position.x) / rect.size.x, 0.0, 1.0)
	var value: float = lerpf(min_val, max_val, fraction)
	apply_fn.call(value)
	queue_redraw()


# ==============================================================================
# MAIN DRAW ROUTINE
# ==============================================================================
func _draw() -> void:
	# 1. Outer Deep Obsidian Hull Container (96% opacity, calibrated hairline border)
	HudPanelStyle.draw_chamfered(self, size, COLOR_CARD_BORDER, 14.0, 0.96, 0.65)

	# Subtle Corner Precision Brackets (Avionics Telemetry Alignment)
	_draw_corner_brackets()

	var font: Font = HudPanelStyle.get_font()

	# 2. Header Bar
	var title_x: float = 24.0
	if icon_settings != null:
		draw_texture_rect(icon_settings, Rect2(title_x, 15.0, 15.0, 15.0), false, COLOR_CYAN)
		title_x += 24.0

	draw_string(font, Vector2(title_x, 27.0), "Flight Deck Settings", HORIZONTAL_ALIGNMENT_LEFT, 240.0, 13, COLOR_TEXT_PRIMARY)
	draw_string(font, Vector2(title_x + 190.0, 27.0), "Simulation & Navigation Avionics", HORIZONTAL_ALIGNMENT_LEFT, 320.0, 10, COLOR_TEXT_MUTED)

	# Minimalist Close [X] Button (top right)
	_close_rect = Rect2(size.x - 38.0, 12.0, 24.0, 24.0)
	_draw_minimal_close(_close_rect)

	# 3. Integrated Flight Deck Tabs Bar
	var tab_y: float = 46.0
	var tab_h: float = 32.0
	var tab_gap: float = 4.0
	var start_x: float = 24.0
	var avail_w: float = size.x - 48.0
	var tab_w: float = (avail_w - tab_gap * float(TABS.size() - 1)) / float(TABS.size())

	var tab_icons := [icon_tab_gameplay, icon_tab_graphics, icon_tab_shortcuts, icon_tab_audio]
	_tab_rects.resize(TABS.size())
	for i in range(TABS.size()):
		var r := Rect2(start_x + float(i) * (tab_w + tab_gap), tab_y, tab_w, tab_h)
		_tab_rects[i] = r
		var active: bool = (i == current_tab)
		_draw_tab_header(r, TABS[i], tab_icons[i] if i < tab_icons.size() else null, active)

	# Hairline baseline rule under tabs
	draw_line(
		Vector2(24.0, tab_y + tab_h),
		Vector2(size.x - 24.0, tab_y + tab_h),
		Color(COLOR_CARD_BORDER, 0.4), 1.0
	)

	# 4. Active Tab Content
	var content_top: float = tab_y + tab_h + 12.0
	if current_tab == 0:
		_draw_tab_gameplay(content_top)
	elif current_tab == 1:
		_draw_tab_graphics(content_top)
	elif current_tab == 2:
		_draw_tab_shortcuts(content_top)
	elif current_tab == 3:
		_draw_tab_audio(content_top)


func _draw_corner_brackets() -> void:
	var b_col := Color(COLOR_CYAN, 0.35)
	var b_len := 10.0
	# Top-left
	draw_line(Vector2(14.0, 6.0), Vector2(14.0 + b_len, 6.0), b_col, 1.0)
	draw_line(Vector2(6.0, 14.0), Vector2(6.0, 14.0 + b_len), b_col, 1.0)
	# Top-right
	draw_line(Vector2(size.x - 14.0 - b_len, 6.0), Vector2(size.x - 14.0, 6.0), b_col, 1.0)
	draw_line(Vector2(size.x - 6.0, 14.0), Vector2(size.x - 6.0, 14.0 + b_len), b_col, 1.0)
	# Bottom-left
	draw_line(Vector2(14.0, size.y - 6.0), Vector2(14.0 + b_len, size.y - 6.0), b_col, 1.0)
	draw_line(Vector2(6.0, size.y - 14.0 - b_len), Vector2(6.0, size.y - 14.0), b_col, 1.0)
	# Bottom-right
	draw_line(Vector2(size.x - 14.0 - b_len, size.y - 6.0), Vector2(size.x - 14.0, size.y - 6.0), b_col, 1.0)
	draw_line(Vector2(size.x - 6.0, size.y - 14.0 - b_len), Vector2(size.x - 6.0, size.y - 14.0), b_col, 1.0)


# ==============================================================================
# TAB 0: GAMEPLAY (2 Symmetrical Flight Columns)
# ==============================================================================
func _draw_tab_gameplay(top_y: float) -> void:
	if settings == null:
		return

	var col_w: float = 368.0
	var col1_x: float = 24.0
	var col2_x: float = 408.0

	# --- Column 1: Flight Controls ---
	_draw_section_header(Vector2(col1_x, top_y), "Flight Controls", col_w)
	var card1 := Rect2(col1_x, top_y + 20.0, col_w, 330.0)
	_draw_card_background(card1)

	var y: float = card1.position.y + 18.0
	var inner_x: float = col1_x + 16.0
	var ctrl_x: float = col1_x + 175.0
	var ctrl_w: float = 177.0

	# 1. RCS Turn Rate
	_draw_setting_label(Vector2(inner_x, y), "RCS Turn Rate", "Maximum angular speed (RMB hold)")
	_rot_slider_rect = Rect2(ctrl_x, y + 4.0, ctrl_w - 56.0, 16.0)
	var rot_frac: float = (settings.ship_rotation_speed - 1.0) / (5.0 - 1.0)
	_draw_slider(_rot_slider_rect, rot_frac, false)
	_draw_badge_value(Vector2(ctrl_x + ctrl_w - 50.0, y + 2.0), "%.1f r/s" % settings.ship_rotation_speed)

	# 2. Autopilot Main Engine
	y += 74.0
	_draw_setting_label(Vector2(inner_x, y), "Autopilot Main Engine", "Allow main thruster in burns")
	_toggle_auto_engine_rect = Rect2(ctrl_x + ctrl_w - 76.0, y + 4.0, 76.0, 22.0)
	_draw_switch(_toggle_auto_engine_rect, settings.autopilot_default_main_engine, "ON", "OFF")

	# 3. Drop Warp on Thrust
	y += 74.0
	_draw_setting_label(Vector2(inner_x, y), "Drop Warp on Thrust", "Reset to 1x when pressing W")
	_toggle_warp_drop_rect = Rect2(ctrl_x + ctrl_w - 76.0, y + 4.0, 76.0, 22.0)
	_draw_switch(_toggle_warp_drop_rect, settings.auto_drop_warp_on_thrust, "ON", "OFF")


	# --- Column 2: Camera & Viewport ---
	_draw_section_header(Vector2(col2_x, top_y), "Camera Dynamics", col_w)
	var card2 := Rect2(col2_x, top_y + 20.0, col_w, 330.0)
	_draw_card_background(card2)

	y = card2.position.y + 18.0
	inner_x = col2_x + 16.0
	ctrl_x = col2_x + 175.0
	ctrl_w = 177.0

	# 1. Zoom Sensitivity
	_draw_setting_label(Vector2(inner_x, y), "Zoom Sensitivity", "Scale step per scroll notch")
	_zoom_slider_rect = Rect2(ctrl_x, y + 4.0, ctrl_w - 56.0, 16.0)
	var zoom_frac: float = (settings.camera_zoom_speed - 1.05) / (1.5 - 1.05)
	_draw_slider(_zoom_slider_rect, zoom_frac, false)
	_draw_badge_value(Vector2(ctrl_x + ctrl_w - 50.0, y + 2.0), "%.2fx" % settings.camera_zoom_speed)

	# 2. Pan Sensitivity
	y += 74.0
	_draw_setting_label(Vector2(inner_x, y), "Pan Sensitivity", "Camera speed (MMB drag)")
	_pan_slider_rect = Rect2(ctrl_x, y + 4.0, ctrl_w - 56.0, 16.0)
	var pan_frac: float = (settings.camera_pan_speed - 0.5) / (2.5 - 0.5)
	_draw_slider(_pan_slider_rect, pan_frac, false)
	_draw_badge_value(Vector2(ctrl_x + ctrl_w - 50.0, y + 2.0), "%.1fx" % settings.camera_pan_speed)

	# 3. Camera Smoothing
	y += 74.0
	_draw_setting_label(Vector2(inner_x, y), "Camera Smoothing", "Inertial damping following ship")
	_toggle_smoothing_rect = Rect2(ctrl_x + ctrl_w - 76.0, y + 4.0, 76.0, 22.0)
	_draw_switch(_toggle_smoothing_rect, settings.camera_smoothing, "ON", "OFF")


# ==============================================================================
# TAB 1: GRAPHICS & DISPLAY (2 Symmetrical Columns)
# ==============================================================================
func _draw_tab_graphics(top_y: float) -> void:
	if settings == null:
		return

	var col_w: float = 368.0
	var col1_x: float = 24.0
	var col2_x: float = 408.0

	# --- Column 1: Display & Environment ---
	_draw_section_header(Vector2(col1_x, top_y), "Display & Environment", col_w)
	var card1 := Rect2(col1_x, top_y + 20.0, col_w, 330.0)
	_draw_card_background(card1)

	var y: float = card1.position.y + 18.0
	var inner_x: float = col1_x + 16.0
	var ctrl_x: float = col1_x + 175.0
	var ctrl_w: float = 177.0

	# 1. Fullscreen
	_draw_setting_label(Vector2(inner_x, y), "Window Mode", "Exclusive borderless fullscreen")
	_toggle_fullscreen_rect = Rect2(ctrl_x + ctrl_w - 104.0, y + 4.0, 104.0, 22.0)
	_draw_switch(_toggle_fullscreen_rect, settings.fullscreen, "Fullscreen", "Windowed")

	# 2. V-Sync
	y += 66.0
	_draw_setting_label(Vector2(inner_x, y), "Vertical Sync", "Synchronize frame rate (V-Sync)")
	_toggle_vsync_rect = Rect2(ctrl_x + ctrl_w - 76.0, y + 4.0, 76.0, 22.0)
	_draw_switch(_toggle_vsync_rect, settings.vsync, "ON", "OFF")

	# 3. Starfield Brightness
	y += 66.0
	_draw_setting_label(Vector2(inner_x, y), "Starfield Brightness", "Deep space background stars")
	_starfield_slider_rect = Rect2(ctrl_x, y + 4.0, ctrl_w - 56.0, 16.0)
	_draw_slider(_starfield_slider_rect, settings.starfield_brightness, false)
	_draw_badge_value(Vector2(ctrl_x + ctrl_w - 50.0, y + 2.0), "%d%%" % roundi(settings.starfield_brightness * 100.0))


	# --- Column 2: Telemetry Overlays ---
	_draw_section_header(Vector2(col2_x, top_y), "Telemetry Overlays", col_w)
	var card2 := Rect2(col2_x, top_y + 20.0, col_w, 330.0)
	_draw_card_background(card2)

	y = card2.position.y + 18.0
	inner_x = col2_x + 16.0
	ctrl_x = col2_x + 175.0
	ctrl_w = 177.0

	# 1. Orbit Trails
	_draw_setting_label(Vector2(inner_x, y), "Planet Orbit Lines", "Keplerian orbital trajectory trails")
	_toggle_orbits_rect = Rect2(ctrl_x + ctrl_w - 76.0, y + 4.0, 76.0, 22.0)
	_draw_switch(_toggle_orbits_rect, settings.show_orbit_lines, "ON", "OFF")

	# 2. Spheres of Influence (SOI)
	y += 66.0
	_draw_setting_label(Vector2(inner_x, y), "Spheres of Influence", "Gravitational boundary markers")
	_toggle_soi_rect = Rect2(ctrl_x + ctrl_w - 76.0, y + 4.0, 76.0, 22.0)
	_draw_switch(_toggle_soi_rect, settings.show_soi_circles, "ON", "OFF")

	# 3. Trajectory Prediction
	y += 66.0
	_draw_setting_label(Vector2(inner_x, y), "Flight Trajectory", "Numerical orbital trajectory projection")
	_toggle_trajectory_rect = Rect2(ctrl_x + ctrl_w - 76.0, y + 4.0, 76.0, 22.0)
	_draw_switch(_toggle_trajectory_rect, settings.show_trajectory, "ON", "OFF")

	# 4. Prediction Horizon
	y += 66.0
	_draw_setting_label(Vector2(inner_x, y), "Prediction Horizon", "Calculation steps (6k vs 12k)")
	_toggle_horizon_rect = Rect2(ctrl_x + ctrl_w - 80.0, y + 4.0, 80.0, 22.0)
	_draw_switch(_toggle_horizon_rect, settings.trajectory_long_prediction, "12k", "6k")


# ==============================================================================
# TAB 2: KEYBINDINGS (Physical Avionics Keycaps)
# ==============================================================================
func _draw_tab_shortcuts(top_y: float) -> void:
	var col_w: float = 368.0
	var col1_x: float = 24.0
	var col2_x: float = 408.0

	# --- Column 1 ---
	_draw_section_header(Vector2(col1_x, top_y), "Propulsion & Maneuvers", col_w)
	var card1 := Rect2(col1_x, top_y + 20.0, col_w, 150.0)
	_draw_card_background(card1)

	var y: float = card1.position.y + 14.0
	y = _draw_clean_shortcut(col1_x + 14.0, y, "W / S", "Main Thruster (Forward / Reverse)")
	y = _draw_clean_shortcut(col1_x + 14.0, y, "X", "Throttle Lock Toggle")
	y = _draw_clean_shortcut(col1_x + 14.0, y, "A / D", "Lateral RCS Thrusters")
	y = _draw_clean_shortcut(col1_x + 14.0, y, "RMB (Hold)", "Orient ship towards cursor")

	var y_time: float = top_y + 192.0
	_draw_section_header(Vector2(col1_x, y_time), "Time Warp & Simulation", col_w)
	var card_time := Rect2(col1_x, y_time + 20.0, col_w, 138.0)
	_draw_card_background(card_time)

	y = card_time.position.y + 14.0
	y = _draw_clean_shortcut(col1_x + 14.0, y, "Space / P", "Pause / Resume simulation")
	y = _draw_clean_shortcut(col1_x + 14.0, y, "1 .. 7", "Time multipliers: 1x, 2x .. 200x")
	y = _draw_clean_shortcut(col1_x + 14.0, y, "Step (▶|)", "Single simulation step (paused)")

	# --- Column 2 ---
	_draw_section_header(Vector2(col2_x, top_y), "Orbital Autopilot", col_w)
	var card2 := Rect2(col2_x, top_y + 20.0, col_w, 176.0)
	_draw_card_background(card2)

	y = card2.position.y + 14.0
	y = _draw_clean_shortcut(col2_x + 14.0, y, "F", "Engage / Disengage Autopilot")
	y = _draw_clean_shortcut(col2_x + 14.0, y, "Tab", "Cycle target celestial body")
	y = _draw_clean_shortcut(col2_x + 14.0, y, "Scroll (Target)", "Adjust target orbit altitude")
	y = _draw_clean_shortcut(col2_x + 14.0, y, "G", "Fire weapon at FOV lock")

	var y_cam: float = top_y + 218.0
	_draw_section_header(Vector2(col2_x, y_cam), "Camera & Tracking", col_w)
	var card_cam := Rect2(col2_x, y_cam + 20.0, col_w, 138.0)
	_draw_card_background(card_cam)

	y = card_cam.position.y + 14.0
	y = _draw_clean_shortcut(col2_x + 14.0, y, "Scroll Wheel", "Zoom camera view in / out")
	y = _draw_clean_shortcut(col2_x + 14.0, y, "MMB (Drag)", "Pan camera freely")
	y = _draw_clean_shortcut(col2_x + 14.0, y, "LMB on Ship", "Focus and track ship")


# ==============================================================================
# TAB 3: AUDIO & MUSIC (Instrument Deck)
# ==============================================================================
func _draw_tab_audio(top_y: float) -> void:
	if settings == null:
		return

	var full_w: float = size.x - 48.0
	var card_x: float = 24.0

	# 1. Audio Channels & Buses
	_draw_section_header(Vector2(card_x, top_y), "Audio Channels & Buses", full_w)
	var card_audio := Rect2(card_x, top_y + 20.0, full_w, 194.0)
	_draw_card_background(card_audio)

	var y: float = card_audio.position.y + 16.0
	var label_x: float = card_x + 16.0
	var slider_x: float = card_x + 280.0
	var slider_w: float = 270.0
	var mute_x: float = card_x + full_w - 106.0

	# Master
	_draw_audio_row_header(Vector2(label_x, y), icon_volume_2, "Master Volume")
	_master_slider_rect = Rect2(slider_x, y + 4.0, slider_w, 16.0)
	_draw_slider(_master_slider_rect, settings.master_volume, settings.master_muted)
	_draw_badge_value(Vector2(slider_x + slider_w + 10.0, y + 2.0), "%d%%" % roundi(settings.master_volume * 100.0))
	_master_mute_rect = Rect2(mute_x, y, 92.0, 24.0)
	_draw_mute_button(_master_mute_rect, settings.master_muted)

	# Music
	y += 42.0
	_draw_audio_row_header(Vector2(label_x, y), icon_tab_audio, "Soundtrack (Music)")
	_music_slider_rect = Rect2(slider_x, y + 4.0, slider_w, 16.0)
	_draw_slider(_music_slider_rect, settings.music_volume, settings.music_muted)
	_draw_badge_value(Vector2(slider_x + slider_w + 10.0, y + 2.0), "%d%%" % roundi(settings.music_volume * 100.0))
	_music_mute_rect = Rect2(mute_x, y, 92.0, 24.0)
	_draw_mute_button(_music_mute_rect, settings.music_muted)

	# SFX
	y += 42.0
	_draw_audio_row_header(Vector2(label_x, y), icon_volume_2, "RCS & Engine SFX")
	_sfx_slider_rect = Rect2(slider_x, y + 4.0, slider_w, 16.0)
	_draw_slider(_sfx_slider_rect, settings.sfx_volume, settings.sfx_muted)
	_draw_badge_value(Vector2(slider_x + slider_w + 10.0, y + 2.0), "%d%%" % roundi(settings.sfx_volume * 100.0))
	_sfx_mute_rect = Rect2(mute_x, y, 92.0, 24.0)
	_draw_mute_button(_sfx_mute_rect, settings.sfx_muted)

	# Additional audio toggles
	y += 42.0
	var font: Font = HudPanelStyle.get_font()
	draw_string(font, Vector2(label_x, y + 14.0), "HUD Music Toast Notifications", HORIZONTAL_ALIGNMENT_LEFT, 240.0, 11, COLOR_TEXT_SECONDARY)
	_toggle_music_toast_rect = Rect2(label_x + 225.0, y + 2.0, 72.0, 22.0)
	_draw_switch(_toggle_music_toast_rect, settings.show_music_notifications, "ON", "OFF")

	draw_string(font, Vector2(slider_x, y + 14.0), "Autoplay on Launch", HORIZONTAL_ALIGNMENT_LEFT, 240.0, 11, COLOR_TEXT_SECONDARY)
	_toggle_autoplay_rect = Rect2(mute_x + 20.0, y + 2.0, 72.0, 22.0)
	_draw_switch(_toggle_autoplay_rect, settings.autoplay_music, "ON", "OFF")


	# 2. Soundtrack Deck
	var player_top: float = top_y + 230.0
	_draw_section_header(Vector2(card_x, player_top), "Soundtrack Player", full_w)
	var card_player := Rect2(card_x, player_top + 20.0, full_w, 100.0)
	_draw_card_background(card_player)

	var track_title: String = music_manager.get_current_track_title() if music_manager != null else "No track"
	var is_playing: bool = music_manager.is_playing() if music_manager != null else false

	var py: float = card_player.position.y + 16.0

	# Status dot + Status label (No green or yellow - Telemetry Cyan and Cool Slate)
	var status_col: Color = COLOR_CYAN if is_playing else COLOR_TEXT_MUTED
	draw_circle(Vector2(label_x + 4.0, py + 8.0), 3.5, status_col)
	if is_playing:
		draw_circle(Vector2(label_x + 4.0, py + 8.0), 6.5, Color(COLOR_CYAN, 0.25))

	var status_text: String = "PLAYING" if is_playing else "PAUSED"
	draw_string(font, Vector2(label_x + 16.0, py + 12.0), status_text, HORIZONTAL_ALIGNMENT_LEFT, 90.0, 10, status_col)

	# Now Playing Track Title
	draw_string(font, Vector2(label_x + 100.0, py + 12.0), track_title, HORIZONTAL_ALIGNMENT_LEFT, 380.0, 12, COLOR_TEXT_PRIMARY)

	# Animated VU Meter / Audio Visualizer Bars (14 bars)
	_draw_audio_visualizer(Vector2(card_x + full_w - 180.0, py + 1.0), is_playing)

	# Transport Deck Buttons
	py += 32.0
	var btn_w: float = 125.0
	var btn_gap: float = 10.0
	var start_bx: float = label_x

	_music_prev_rect = Rect2(start_bx, py, btn_w, 26.0)
	_draw_quiet_button(_music_prev_rect, icon_skip_back, "Previous")

	_music_toggle_rect = Rect2(start_bx + btn_w + btn_gap, py, btn_w, 26.0)
	_draw_quiet_button(_music_toggle_rect, icon_pause if is_playing else icon_play, "Pause" if is_playing else "Play", is_playing)

	_music_next_rect = Rect2(start_bx + (btn_w + btn_gap) * 2.0, py, btn_w, 26.0)
	_draw_quiet_button(_music_next_rect, icon_skip_forward, "Next")


func _draw_audio_visualizer(pos: Vector2, is_playing: bool) -> void:
	var bar_count: int = 14
	var bar_w: float = 4.0
	var bar_gap: float = 3.0
	var max_h: float = 14.0
	var time_ms: float = float(Time.get_ticks_msec()) * 0.005

	for i in range(bar_count):
		var h: float
		if is_playing:
			var wave := sin(time_ms * 1.8 + float(i) * 0.75) * 0.5 + 0.5
			var wave2 := cos(time_ms * 2.6 + float(i) * 1.2) * 0.5 + 0.5
			h = 3.0 + (wave * 0.6 + wave2 * 0.4) * (max_h - 3.0)
		else:
			h = 2.0

		var bx: float = pos.x + float(i) * (bar_w + bar_gap)
		var by: float = pos.y + (max_h - h)
		var bar_col: Color = Color(COLOR_CYAN, 0.75 if is_playing else 0.25)
		draw_rect(Rect2(bx, by, bar_w, h), bar_col)


# ==============================================================================
# ATOMIC DESIGN SYSTEM COMPONENTS (UNSLOP & CALIBRATED)
# ==============================================================================

func _draw_section_header(pos: Vector2, title: String, width: float) -> void:
	var font: Font = HudPanelStyle.get_font()
	# Clean title case label with quiet telemetry hierarchy
	draw_string(font, Vector2(pos.x, pos.y + 11.0), title, HORIZONTAL_ALIGNMENT_LEFT, 240.0, 11, COLOR_TEXT_SECONDARY)
	# Quiet structural rule line continuing to the end
	var str_w: float = font.get_string_size(title, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x
	var line_start_x: float = pos.x + 12.0 + str_w
	if line_start_x < pos.x + width:
		draw_line(
			Vector2(line_start_x, pos.y + 7.0),
			Vector2(pos.x + width, pos.y + 7.0),
			Color(COLOR_CARD_BORDER, 0.45), 1.0
		)


func _draw_card_background(rect: Rect2) -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(COLOR_CARD_BG, 0.92)
	style.border_color = Color(COLOR_CARD_BORDER, 0.55)
	style.set_border_width_all(1)
	style.set_corner_radius_all(6)
	draw_style_box(style, rect)


func _draw_setting_label(pos: Vector2, title: String, subline: String) -> void:
	var font: Font = HudPanelStyle.get_font()
	draw_string(font, Vector2(pos.x, pos.y + 12.0), title, HORIZONTAL_ALIGNMENT_LEFT, 190.0, 11, COLOR_TEXT_PRIMARY)
	draw_string(font, Vector2(pos.x, pos.y + 26.0), subline, HORIZONTAL_ALIGNMENT_LEFT, 190.0, 9, COLOR_TEXT_MUTED)


func _draw_badge_value(pos: Vector2, text: String) -> void:
	var font: Font = HudPanelStyle.get_font()
	var badge_rect := Rect2(pos.x, pos.y, 48.0, 18.0)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.04, 0.07, 0.11, 0.85)
	style.border_color = Color(COLOR_CARD_BORDER, 0.5)
	style.set_border_width_all(1)
	style.set_corner_radius_all(3)
	draw_style_box(style, badge_rect)

	draw_string(
		font, Vector2(badge_rect.position.x, badge_rect.position.y + 13.0),
		text, HORIZONTAL_ALIGNMENT_CENTER, badge_rect.size.x, 9, COLOR_CYAN
	)


func _draw_tab_header(rect: Rect2, label: String, icon: Texture2D, active: bool) -> void:
	var is_hovered: bool = rect.has_point(_hover_pos)
	var font: Font = HudPanelStyle.get_font()

	if active:
		# Elevated tab plate
		var style := StyleBoxFlat.new()
		style.bg_color = Color(0.08, 0.14, 0.22, 0.70)
		style.border_color = Color(COLOR_CYAN, 0.40)
		style.set_border_width_all(1)
		style.set_corner_radius_all(4)
		draw_style_box(style, rect)

		# Glowing baseline indicator
		draw_line(
			Vector2(rect.position.x + 6.0, rect.end.y),
			Vector2(rect.end.x - 6.0, rect.end.y),
			COLOR_CYAN, 2.0
		)
	elif is_hovered:
		var style := StyleBoxFlat.new()
		style.bg_color = Color(0.07, 0.11, 0.17, 0.45)
		style.border_color = Color(COLOR_CARD_BORDER, 0.35)
		style.set_border_width_all(1)
		style.set_corner_radius_all(4)
		draw_style_box(style, rect)

	var text_col: Color = COLOR_CYAN if active else (COLOR_TEXT_PRIMARY if is_hovered else COLOR_TEXT_MUTED)

	if icon != null:
		var sz := 13.0
		var str_w: float = font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x
		var content_w: float = sz + 6.0 + str_w
		var start_x: float = rect.position.x + maxf((rect.size.x - content_w) * 0.5, 4.0)
		var iy: float = rect.position.y + (rect.size.y - sz) * 0.5
		draw_texture_rect(icon, Rect2(start_x, iy, sz, sz), false, text_col)
		draw_string(font, Vector2(start_x + sz + 6.0, rect.position.y + rect.size.y * 0.5 + 4.0), label, HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - (start_x - rect.position.x + sz + 6.0), 10, text_col)
	else:
		draw_string(font, Vector2(rect.position.x, rect.position.y + rect.size.y * 0.5 + 4.0), label, HORIZONTAL_ALIGNMENT_CENTER, rect.size.x, 10, text_col)


# Modern Aerospace Toggle Switch (36x18px)
func _draw_switch(rect: Rect2, active: bool, label_on: String, label_off: String) -> void:
	var is_hovered: bool = rect.has_point(_hover_pos)
	var track_w: float = 36.0
	var track_h: float = 18.0
	var track_rect := Rect2(rect.position.x, rect.position.y + (rect.size.y - track_h) * 0.5, track_w, track_h)

	var style := StyleBoxFlat.new()
	if active:
		style.bg_color = Color(0.08, 0.22, 0.30, 0.95) if is_hovered else Color(0.06, 0.18, 0.25, 0.85)
		style.border_color = COLOR_CYAN if is_hovered else Color(COLOR_CYAN, 0.75)
	else:
		style.bg_color = Color(0.07, 0.10, 0.15, 0.85) if is_hovered else Color(0.05, 0.07, 0.11, 0.75)
		style.border_color = Color(COLOR_CARD_BORDER, 0.6) if is_hovered else Color(COLOR_CARD_BORDER, 0.4)
	style.set_border_width_all(1)
	style.set_corner_radius_all(9)
	draw_style_box(style, track_rect)

	# Sliding Thumb Indicator
	var thumb_r: float = 5.5
	var thumb_x: float = track_rect.end.x - thumb_r - 3.5 if active else track_rect.position.x + thumb_r + 3.5
	var thumb_y: float = track_rect.position.y + track_rect.size.y * 0.5

	if active:
		draw_circle(Vector2(thumb_x, thumb_y), thumb_r + 2.0, Color(COLOR_CYAN, 0.25))
		draw_circle(Vector2(thumb_x, thumb_y), thumb_r, Color.WHITE)
	else:
		draw_circle(Vector2(thumb_x, thumb_y), thumb_r, Color(0.44, 0.50, 0.60))

	# Text Label alongside the switch
	var font: Font = HudPanelStyle.get_font()
	var state_label: String = label_on if active else label_off
	var label_col: Color = COLOR_CYAN if active else COLOR_TEXT_MUTED
	draw_string(font, Vector2(track_rect.end.x + 8.0, rect.position.y + rect.size.y * 0.5 + 4.0), state_label, HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - track_w - 8.0, 10, label_col)


# Precision Instrument Slider with Calibration Ticks
func _draw_slider(rect: Rect2, fraction: float, is_muted: bool) -> void:
	var is_hovered: bool = rect.has_point(_hover_pos)
	var cy: float = rect.position.y + rect.size.y * 0.5
	var track_h: float = 3.0
	var track_rect := Rect2(rect.position.x, cy - track_h * 0.5, rect.size.x, track_h)

	# Background track
	var bg_style := StyleBoxFlat.new()
	bg_style.bg_color = Color(0.10, 0.15, 0.22, 0.85)
	bg_style.set_corner_radius_all(2)
	draw_style_box(bg_style, track_rect)

	# Calibration ticks (0%, 25%, 50%, 75%, 100%)
	var tick_col := Color(COLOR_TEXT_FAINT, 0.6)
	for t in [0.0, 0.25, 0.5, 0.75, 1.0]:
		var tx: float = rect.position.x + rect.size.x * t
		draw_line(Vector2(tx, cy - 3.0), Vector2(tx, cy + 3.0), tick_col, 1.0)

	# Active glowing fill line
	var clamped_frac: float = clampf(fraction, 0.0, 1.0)
	if clamped_frac > 0.002 and not is_muted:
		var fill_w: float = rect.size.x * clamped_frac
		var fill_style := StyleBoxFlat.new()
		fill_style.bg_color = COLOR_CYAN if is_hovered else Color(COLOR_CYAN, 0.8)
		fill_style.set_corner_radius_all(2)
		draw_style_box(fill_style, Rect2(rect.position.x, cy - track_h * 0.5, fill_w, track_h))

	# Precision Grabber Needle
	var grabber_x: float = rect.position.x + rect.size.x * clamped_frac
	var grabber_w: float = 5.0
	var grabber_h: float = 14.0
	var grabber_rect := Rect2(grabber_x - grabber_w * 0.5, cy - grabber_h * 0.5, grabber_w, grabber_h)

	if not is_muted:
		draw_circle(Vector2(grabber_x, cy), 7.0, Color(COLOR_CYAN, 0.20 if is_hovered else 0.08))

	var grabber_style := StyleBoxFlat.new()
	if is_muted:
		grabber_style.bg_color = Color(0.22, 0.28, 0.36, 0.90)
		grabber_style.border_color = Color(0.38, 0.48, 0.60, 0.70)
	else:
		grabber_style.bg_color = Color.WHITE if is_hovered else Color(0.90, 0.96, 1.0)
		grabber_style.border_color = COLOR_CYAN if is_hovered else Color(COLOR_CYAN, 0.7)
	grabber_style.set_border_width_all(1)
	grabber_style.set_corner_radius_all(2)
	draw_style_box(grabber_style, grabber_rect)


func _draw_audio_row_header(pos: Vector2, icon: Texture2D, label: String) -> void:
	if icon != null:
		draw_texture_rect(icon, Rect2(pos.x, pos.y + 1.0, 14.0, 14.0), false, COLOR_CYAN)
	var font: Font = HudPanelStyle.get_font()
	draw_string(font, Vector2(pos.x + 22.0, pos.y + 13.0), label, HORIZONTAL_ALIGNMENT_LEFT, 230.0, 11, COLOR_TEXT_PRIMARY)


func _draw_keycap_rect(rect: Rect2, text: String, font_size: int = 9) -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.07, 0.10, 0.15, 0.90)
	style.border_color = Color(COLOR_CARD_BORDER, 0.7)
	style.set_border_width_all(1)
	style.set_corner_radius_all(3)
	draw_style_box(style, rect)

	# Top highlight bevel
	draw_line(
		Vector2(rect.position.x + 2.0, rect.position.y + 1.0),
		Vector2(rect.end.x - 2.0, rect.position.y + 1.0),
		Color(0.35, 0.48, 0.65, 0.4), 1.0
	)

	var font: Font = HudPanelStyle.get_font()
	draw_string(
		font, Vector2(rect.position.x, rect.position.y + rect.size.y * 0.5 + 4.0),
		text, HORIZONTAL_ALIGNMENT_CENTER, rect.size.x, font_size, COLOR_CYAN
	)


func _draw_clean_shortcut(x: float, y: float, key: String, desc: String) -> float:
	var key_box := Rect2(x, y, 100.0, 20.0)
	_draw_keycap_rect(key_box, key, 9)

	var font: Font = HudPanelStyle.get_font()
	draw_string(font, Vector2(x + 112.0, y + 14.0), desc, HORIZONTAL_ALIGNMENT_LEFT, 236.0, 10, COLOR_TEXT_PRIMARY)
	return y + 26.0


func _draw_quiet_button(rect: Rect2, icon: Texture2D, label: String, active: bool = false) -> void:
	var is_hovered: bool = rect.has_point(_hover_pos)
	var style := StyleBoxFlat.new()
	if active:
		# Active transport state (Telemetry Cyan plate, no yellow)
		style.bg_color = Color(0.08, 0.20, 0.28, 0.95) if is_hovered else Color(0.06, 0.16, 0.23, 0.88)
		style.border_color = COLOR_CYAN if is_hovered else Color(COLOR_CYAN, 0.75)
	else:
		style.bg_color = Color(0.08, 0.13, 0.19, 0.90) if is_hovered else Color(0.05, 0.08, 0.12, 0.75)
		style.border_color = COLOR_CYAN if is_hovered else Color(COLOR_CARD_BORDER, 0.50)
	style.set_border_width_all(1)
	style.set_corner_radius_all(4)
	draw_style_box(style, rect)

	var font: Font = HudPanelStyle.get_font()
	var text_col: Color = COLOR_CYAN if active or is_hovered else COLOR_TEXT_PRIMARY

	if icon != null:
		var sz := 12.0
		var str_w: float = font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x
		var content_w: float = sz + 5.0 + str_w
		var start_x: float = rect.position.x + maxf((rect.size.x - content_w) * 0.5, 4.0)
		var iy: float = rect.position.y + (rect.size.y - sz) * 0.5
		draw_texture_rect(icon, Rect2(start_x, iy, sz, sz), false, text_col)
		draw_string(font, Vector2(start_x + sz + 5.0, rect.position.y + rect.size.y * 0.5 + 4.0), label, HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - (start_x - rect.position.x + sz + 5.0), 10, text_col)
	else:
		draw_string(font, Vector2(rect.position.x, rect.position.y + rect.size.y * 0.5 + 4.0), label, HORIZONTAL_ALIGNMENT_CENTER, rect.size.x, 10, text_col)


func _draw_mute_button(rect: Rect2, muted: bool) -> void:
	var is_hovered: bool = rect.has_point(_hover_pos)
	var style := StyleBoxFlat.new()
	if muted:
		# Quiet, subtle deactivated state in cool charcoal slate (No yellow)
		style.bg_color = Color(0.10, 0.14, 0.19, 0.92) if is_hovered else Color(0.07, 0.10, 0.14, 0.85)
		style.border_color = Color(0.42, 0.52, 0.65, 0.70) if is_hovered else Color(0.30, 0.38, 0.48, 0.50)
	else:
		style.bg_color = Color(0.08, 0.13, 0.19, 0.90) if is_hovered else Color(0.05, 0.08, 0.12, 0.75)
		style.border_color = COLOR_CYAN if is_hovered else Color(COLOR_CARD_BORDER, 0.50)
	style.set_border_width_all(1)
	style.set_corner_radius_all(4)
	draw_style_box(style, rect)

	var font: Font = HudPanelStyle.get_font()
	var label: String = "Muted" if muted else "Mute"
	var icon: Texture2D = icon_volume_x if muted else icon_volume_2
	var text_col: Color
	if muted:
		text_col = Color(0.70, 0.78, 0.88) if is_hovered else Color(0.52, 0.60, 0.70)
	else:
		text_col = COLOR_CYAN if is_hovered else COLOR_TEXT_PRIMARY

	var sz := 12.0
	var str_w: float = font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x
	var content_w: float = sz + 5.0 + str_w
	var start_x: float = rect.position.x + maxf((rect.size.x - content_w) * 0.5, 4.0)
	var iy: float = rect.position.y + (rect.size.y - sz) * 0.5
	if icon != null:
		draw_texture_rect(icon, Rect2(start_x, iy, sz, sz), false, text_col)
	draw_string(
		font, Vector2(start_x + sz + 5.0, rect.position.y + rect.size.y * 0.5 + 4.0),
		label, HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - (start_x - rect.position.x + sz + 5.0), 10, text_col
	)


func _draw_minimal_close(rect: Rect2) -> void:
	var is_hovered: bool = rect.has_point(_hover_pos)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.12, 0.18, 0.26, 0.7) if is_hovered else Color(0.05, 0.07, 0.11, 0.3)
	style.border_color = COLOR_CYAN if is_hovered else Color(COLOR_CARD_BORDER, 0.4)
	style.set_border_width_all(1)
	style.set_corner_radius_all(4)
	draw_style_box(style, rect)

	if icon_x != null:
		var sz := 12.0
		var pos := rect.position + (rect.size - Vector2(sz, sz)) * 0.5
		draw_texture_rect(icon_x, Rect2(pos, Vector2(sz, sz)), false, COLOR_CYAN if is_hovered else COLOR_TEXT_MUTED)

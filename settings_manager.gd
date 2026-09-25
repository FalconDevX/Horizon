class_name SettingsManager
extends RefCounted

const SAVE_PATH := "user://settings.cfg"

# Audio settings
var master_volume: float = 1.0
var master_muted: bool = false
var music_volume: float = 0.35
var music_muted: bool = false
var sfx_volume: float = 0.8
var sfx_muted: bool = false
var show_music_notifications: bool = true
var autoplay_music: bool = true

# Display & Visual settings
var fullscreen: bool = false
var vsync: bool = true
var show_orbit_lines: bool = true
var show_soi_circles: bool = true
var show_trajectory: bool = true
var trajectory_long_prediction: bool = false
var starfield_brightness: float = 0.5

# Gameplay & Flight settings
var camera_smoothing: bool = true
var camera_zoom_speed: float = 1.2
var camera_pan_speed: float = 1.0
var auto_drop_warp_on_thrust: bool = true
var autopilot_default_main_engine: bool = true


func _init() -> void:
	ensure_buses()
	load_settings()


static func ensure_buses() -> void:
	if AudioServer.get_bus_index("Music") == -1:
		var idx := AudioServer.bus_count
		AudioServer.add_bus(idx)
		AudioServer.set_bus_name(idx, "Music")
		AudioServer.set_bus_send(idx, "Master")
	if AudioServer.get_bus_index("SFX") == -1:
		var idx := AudioServer.bus_count
		AudioServer.add_bus(idx)
		AudioServer.set_bus_name(idx, "SFX")
		AudioServer.set_bus_send(idx, "Master")


func apply_audio_settings() -> void:
	ensure_buses()
	_apply_bus("Master", master_volume, master_muted)
	_apply_bus("Music", music_volume, music_muted)
	_apply_bus("SFX", sfx_volume, sfx_muted)


func _apply_bus(bus_name: String, volume_linear: float, muted: bool) -> void:
	var idx := AudioServer.get_bus_index(bus_name)
	if idx == -1:
		return
	var is_effectively_muted: bool = muted or volume_linear <= 0.001
	AudioServer.set_bus_mute(idx, is_effectively_muted)
	if is_effectively_muted:
		AudioServer.set_bus_volume_db(idx, -80.0)
	else:
		AudioServer.set_bus_volume_db(idx, linear_to_db(clampf(volume_linear, 0.001, 1.0)))


func apply_display_settings() -> void:
	var mode := DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN if fullscreen else DisplayServer.WINDOW_MODE_WINDOWED
	if DisplayServer.window_get_mode() != mode:
		DisplayServer.window_set_mode(mode)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if vsync else DisplayServer.VSYNC_DISABLED)


func set_master_volume(value: float) -> void:
	master_volume = clampf(value, 0.0, 1.0)
	apply_audio_settings()
	save_settings()


func toggle_master_mute() -> void:
	master_muted = not master_muted
	apply_audio_settings()
	save_settings()


func set_music_volume(value: float) -> void:
	music_volume = clampf(value, 0.0, 1.0)
	apply_audio_settings()
	save_settings()


func toggle_music_mute() -> void:
	music_muted = not music_muted
	apply_audio_settings()
	save_settings()


func set_sfx_volume(value: float) -> void:
	sfx_volume = clampf(value, 0.0, 1.0)
	apply_audio_settings()
	save_settings()


func toggle_sfx_mute() -> void:
	sfx_muted = not sfx_muted
	apply_audio_settings()
	save_settings()


func set_fullscreen(enabled: bool) -> void:
	fullscreen = enabled
	apply_display_settings()
	save_settings()


func set_vsync(enabled: bool) -> void:
	vsync = enabled
	apply_display_settings()
	save_settings()


func save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("audio", "master_volume", master_volume)
	cfg.set_value("audio", "master_muted", master_muted)
	cfg.set_value("audio", "music_volume", music_volume)
	cfg.set_value("audio", "music_muted", music_muted)
	cfg.set_value("audio", "sfx_volume", sfx_volume)
	cfg.set_value("audio", "sfx_muted", sfx_muted)
	cfg.set_value("audio", "show_music_notifications", show_music_notifications)
	cfg.set_value("audio", "autoplay_music", autoplay_music)

	cfg.set_value("display", "fullscreen", fullscreen)
	cfg.set_value("display", "vsync", vsync)
	cfg.set_value("display", "show_orbit_lines", show_orbit_lines)
	cfg.set_value("display", "show_soi_circles", show_soi_circles)
	cfg.set_value("display", "show_trajectory", show_trajectory)
	cfg.set_value("display", "trajectory_long_prediction", trajectory_long_prediction)
	cfg.set_value("display", "starfield_brightness", starfield_brightness)

	cfg.set_value("gameplay", "camera_smoothing", camera_smoothing)
	cfg.set_value("gameplay", "camera_zoom_speed", camera_zoom_speed)
	cfg.set_value("gameplay", "camera_pan_speed", camera_pan_speed)
	cfg.set_value("gameplay", "auto_drop_warp_on_thrust", auto_drop_warp_on_thrust)
	cfg.set_value("gameplay", "autopilot_default_main_engine", autopilot_default_main_engine)

	cfg.save(SAVE_PATH)


func load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) == OK:
		master_volume = cfg.get_value("audio", "master_volume", 1.0)
		master_muted = cfg.get_value("audio", "master_muted", false)
		music_volume = cfg.get_value("audio", "music_volume", 0.7)
		music_muted = cfg.get_value("audio", "music_muted", false)
		sfx_volume = cfg.get_value("audio", "sfx_volume", 0.8)
		sfx_muted = cfg.get_value("audio", "sfx_muted", false)
		show_music_notifications = cfg.get_value("audio", "show_music_notifications", true)
		autoplay_music = cfg.get_value("audio", "autoplay_music", true)

		fullscreen = cfg.get_value("display", "fullscreen", false)
		vsync = cfg.get_value("display", "vsync", true)
		show_orbit_lines = cfg.get_value("display", "show_orbit_lines", true)
		show_soi_circles = cfg.get_value("display", "show_soi_circles", true)
		show_trajectory = cfg.get_value("display", "show_trajectory", true)
		trajectory_long_prediction = cfg.get_value("display", "trajectory_long_prediction", false)
		starfield_brightness = cfg.get_value("display", "starfield_brightness", 0.5)

		camera_smoothing = cfg.get_value("gameplay", "camera_smoothing", true)
		camera_zoom_speed = cfg.get_value("gameplay", "camera_zoom_speed", 1.2)
		camera_pan_speed = cfg.get_value("gameplay", "camera_pan_speed", 1.0)
		auto_drop_warp_on_thrust = cfg.get_value("gameplay", "auto_drop_warp_on_thrust", true)
		autopilot_default_main_engine = cfg.get_value("gameplay", "autopilot_default_main_engine", true)

	apply_audio_settings()
	if fullscreen or not vsync:
		apply_display_settings()

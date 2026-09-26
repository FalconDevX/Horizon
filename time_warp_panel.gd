extends Control
## Bottom-left HUD panel: pause / play / single step, and the warp - its
## state, the locked target and what the jump would cost. The warp fuel bar
## itself is on the resource bars panel. (Time acceleration is gone: long
## trips are made in warp.)

signal pause_toggled()
signal step_requested()

var time_scale := 1.0
## "", "ALIGNING" or "WARPING".
var warp_state := ""
var warp_target := ""
var warp_cost := 0.0
var warp_fuel_share := 1.0
var warp_notice := ""

const PILL_HEIGHT := 26.0
const PILL_GAP := 4.0
const LABEL_HEIGHT := 16.0

const COLOR_ON := HudPanelStyle.COLOR_CYAN
const COLOR_OFF := HudPanelStyle.COLOR_BORDER_DEFAULT
const COLOR_PAUSE_ON := HudPanelStyle.COLOR_AMBER
const COLOR_STEP := Color(0.70, 0.80, 0.92)
const COLOR_WARP := Color(0.62, 0.55, 1.0)
const COLOR_FUEL_LOW := Color(0.95, 0.45, 0.3)

var icon_pause: Texture2D
var icon_play: Texture2D
var icon_step: Texture2D

var _start_rect := Rect2()
var _stop_rect := Rect2()
var _step_rect := Rect2()
var _help_rect := Rect2()
var _hover_pos := Vector2(-1.0, -1.0)
var _help: HelpPopup


func _ready() -> void:
	icon_pause = _load_icon("res://textures/icons/pause.svg")
	icon_play = _load_icon("res://textures/icons/play.svg")
	icon_step = _load_icon("res://textures/icons/step_forward.svg")
	_help = HelpPopup.new(PackedStringArray([
		"Ctrl+LMB on a planet: lock it as the warp target",
		"Ctrl+LMB on it again: let go",
		"WARP button or Q: jump there",
		"The path must be clear and the planet not too close",
		"Land on a planet to refuel",
		"P, 0 or Space: pause",
	]))
	add_child(_help)

	mouse_exited.connect(func() -> void:
		_hover_pos = Vector2(-1.0, -1.0)
		queue_redraw()
	)


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


func set_state(
	p_time_scale: float, p_state: String, p_target: String, p_cost: float, p_fuel_share: float, p_notice: String
) -> void:
	time_scale = p_time_scale
	warp_state = p_state
	warp_target = p_target
	warp_cost = p_cost
	warp_fuel_share = clampf(p_fuel_share, 0.0, 1.0)
	warp_notice = p_notice
	queue_redraw()


func _status() -> Array:
	if is_equal_approx(time_scale, 0.0):
		return ["PAUSED", COLOR_PAUSE_ON]
	if warp_notice != "":
		return [warp_notice.to_upper(), HudPanelStyle.COLOR_AMBER]
	if warp_state != "":
		return [warp_state, COLOR_WARP]
	if warp_fuel_share <= 0.0:
		return ["NO FUEL", COLOR_FUEL_LOW]
	return ["READY" if warp_target != "" else "NO TARGET", COLOR_WARP if warp_target != "" else HudPanelStyle.COLOR_TEXT_MUTED]


func _draw() -> void:
	HudPanelStyle.draw_chamfered(self, size, COLOR_WARP if warp_state != "" else HudPanelStyle.COLOR_BORDER_DEFAULT, 14.0, 0.88, 0.55)

	var font: Font = HudPanelStyle.get_font()
	var is_paused: bool = is_equal_approx(time_scale, 0.0)

	draw_string(
		font, Vector2(12.0, 17.0), "Warp Drive",
		HORIZONTAL_ALIGNMENT_LEFT, 120.0, 11, HudPanelStyle.COLOR_TEXT_SECONDARY
	)
	_help_rect = Rect2(size.x - 30.0, 4.0, 18.0, 18.0)
	HelpPopup.draw_button(self, _help_rect, _help_rect.has_point(_hover_pos), _help.visible)
	var status: Array = _status()
	draw_string(
		font, Vector2(110.0, 17.0), String(status[0]),
		HORIZONTAL_ALIGNMENT_RIGHT, _help_rect.position.x - 118.0, 11, status[1]
	)

	var y: float = LABEL_HEIGHT + 10.0
	var btn_size: float = 30.0

	_start_rect = Rect2(12.0, y, btn_size, PILL_HEIGHT)
	_draw_control_pill(_start_rect, icon_play, not is_paused, COLOR_ON, "START")
	_stop_rect = Rect2(_start_rect.end.x + PILL_GAP, y, btn_size, PILL_HEIGHT)
	_draw_control_pill(_stop_rect, icon_pause, is_paused, COLOR_PAUSE_ON, "STOP")
	_step_rect = Rect2(_stop_rect.end.x + PILL_GAP, y, btn_size, PILL_HEIGHT)
	_draw_control_pill(_step_rect, icon_step, is_paused, COLOR_STEP, "STEP")

	var sep_x: float = _step_rect.end.x + 4.0
	draw_line(
		Vector2(sep_x, y + 4.0), Vector2(sep_x, y + PILL_HEIGHT - 4.0),
		Color(HudPanelStyle.COLOR_BORDER_DEFAULT, 0.6), 1.0
	)

	# The locked target and what jumping there would cost.
	var info_x: float = sep_x + 10.0
	var info_w: float = size.x - 12.0 - info_x
	if warp_target == "":
		draw_string(
			font, Vector2(info_x, y + 17.0), "Ctrl+click a planet to lock a target",
			HORIZONTAL_ALIGNMENT_LEFT, info_w, 10, HudPanelStyle.COLOR_TEXT_MUTED
		)
		return
	draw_string(
		font, Vector2(info_x, y + 10.0), warp_target.to_upper(),
		HORIZONTAL_ALIGNMENT_LEFT, info_w, 11, COLOR_WARP
	)
	var left: float = warp_fuel_share - warp_cost
	var cost_text: String = "Fuel -%d%%   %d%% left after" % [maxi(roundi(warp_cost * 100.0), 1), roundi(left * 100.0)]
	draw_string(
		font, Vector2(info_x, y + 24.0), cost_text, HORIZONTAL_ALIGNMENT_LEFT, info_w, 10,
		COLOR_FUEL_LOW if left < 0.0 else HudPanelStyle.COLOR_TEXT_PRIMARY
	)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		_hover_pos = event.position
		queue_redraw()
		return

	if not (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT):
		return

	if _help_rect.has_point(event.position):
		_help.toggle_at(Vector2(size.x, 0.0))
		if _help.visible:
			# Opens upward: the panel sits at the bottom of the screen.
			_help.position.y = -_help.size.y - 6.0
		accept_event()
		return
	_help.close()

	if _start_rect.has_point(event.position):
		if is_equal_approx(time_scale, 0.0):
			pause_toggled.emit()
		accept_event()
		return

	if _stop_rect.has_point(event.position):
		if not is_equal_approx(time_scale, 0.0):
			pause_toggled.emit()
		accept_event()
		return

	if _step_rect.has_point(event.position):
		step_requested.emit()
		accept_event()
		return


func _draw_control_pill(rect: Rect2, icon: Texture2D, active: bool, active_color: Color, pill_type: String) -> void:
	var is_hovered: bool = rect.has_point(_hover_pos)
	var style := StyleBoxFlat.new()
	if active:
		if active_color == COLOR_PAUSE_ON:
			style.bg_color = Color(0.18, 0.12, 0.05, 0.92) if is_hovered else Color(0.14, 0.09, 0.04, 0.85)
		else:
			style.bg_color = Color(0.08, 0.18, 0.26, 0.92) if is_hovered else Color(0.06, 0.14, 0.20, 0.85)
		style.border_color = active_color
	else:
		style.bg_color = Color(0.08, 0.12, 0.17, 0.8) if is_hovered else Color(0.05, 0.07, 0.11, 0.75)
		style.border_color = Color(COLOR_OFF, 0.8) if is_hovered else Color(COLOR_OFF, 0.45)
	style.set_border_width_all(1)
	style.set_corner_radius_all(4)
	draw_style_box(style, rect)

	var icon_color: Color = active_color if active else (HudPanelStyle.COLOR_TEXT_PRIMARY if is_hovered else HudPanelStyle.COLOR_TEXT_MUTED)
	var center := rect.position + rect.size * 0.5
	var icon_size := Vector2(13.0, 13.0)

	if icon != null:
		draw_texture_rect(icon, Rect2(center - icon_size * 0.5, icon_size), false, icon_color)
	else:
		match pill_type:
			"START":
				_draw_play_vector(center, 11.0, icon_color)
			"STOP":
				_draw_pause_vector(center, 11.0, icon_color)
			"STEP":
				_draw_step_vector(center, 11.0, icon_color)


func _draw_pause_vector(center: Vector2, bar_h: float, color: Color) -> void:
	var bar_w: float = 3.0
	var gap: float = 4.0
	draw_rect(Rect2(center.x - gap * 0.5 - bar_w, center.y - bar_h * 0.5, bar_w, bar_h), color)
	draw_rect(Rect2(center.x + gap * 0.5, center.y - bar_h * 0.5, bar_w, bar_h), color)


func _draw_play_vector(center: Vector2, icon_h: float, color: Color) -> void:
	var half_h: float = icon_h * 0.5
	var half_w: float = icon_h * 0.45
	var pts := PackedVector2Array([
		Vector2(center.x - half_w * 0.7, center.y - half_h),
		Vector2(center.x + half_w, center.y),
		Vector2(center.x - half_w * 0.7, center.y + half_h)
	])
	draw_colored_polygon(pts, color)


func _draw_step_vector(center: Vector2, icon_h: float, color: Color) -> void:
	_draw_play_vector(center - Vector2(2.5, 0.0), icon_h, color)
	draw_rect(Rect2(center.x + 3.5, center.y - icon_h * 0.5, 2.0, icon_h), color)

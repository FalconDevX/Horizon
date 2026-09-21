extends Control

signal time_scale_selected(value: float)
signal pause_toggled()
signal step_requested()

var time_scale := 1.0

const STEPS := [1.0, 2.0, 5.0, 10.0, 50.0, 100.0, 200.0]
const PILL_HEIGHT := 26.0
const PILL_GAP := 4.0
const LABEL_HEIGHT := 16.0

const COLOR_ON := HudPanelStyle.COLOR_CYAN
const COLOR_OFF := HudPanelStyle.COLOR_BORDER_DEFAULT
const COLOR_PAUSE_ON := HudPanelStyle.COLOR_AMBER
const COLOR_STEP := Color(0.70, 0.80, 0.92)

var icon_pause: Texture2D
var icon_play: Texture2D
var icon_step: Texture2D
var icon_clock: Texture2D

var _start_rect := Rect2()
var _stop_rect := Rect2()
var _step_rect := Rect2()
var _pill_rects: Array[Rect2] = []
var _hover_pos := Vector2(-1.0, -1.0)


func _ready() -> void:
	icon_pause = _load_icon("res://textures/icons/pause.svg")
	icon_play = _load_icon("res://textures/icons/play.svg")
	icon_step = _load_icon("res://textures/icons/step_forward.svg")
	icon_clock = _load_icon("res://textures/icons/clock.svg")

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


func set_state(p_time_scale: float) -> void:
	if is_equal_approx(time_scale, p_time_scale):
		return
	time_scale = p_time_scale
	queue_redraw()


func _draw() -> void:
	# Subtle obsidian panel with hairline border
	HudPanelStyle.draw_chamfered(self, size, HudPanelStyle.COLOR_BORDER_DEFAULT, 14.0, 0.88, 0.55)

	var font: Font = HudPanelStyle.get_font()
	var is_paused: bool = is_equal_approx(time_scale, 0.0)

	# Clock icon & Header
	if icon_clock != null:
		draw_texture_rect(icon_clock, Rect2(12.0, 6.0, 13.0, 13.0), false, HudPanelStyle.COLOR_TEXT_SECONDARY)
		draw_string(
			font, Vector2(29.0, 17.0), "Time Warp",
			HORIZONTAL_ALIGNMENT_LEFT, 110.0, 11, HudPanelStyle.COLOR_TEXT_SECONDARY
		)
	else:
		draw_string(
			font, Vector2(12.0, 17.0), "Time Warp",
			HORIZONTAL_ALIGNMENT_LEFT, 120.0, 11, HudPanelStyle.COLOR_TEXT_SECONDARY
		)

	if is_paused:
		draw_string(
			font, Vector2(130.0, 17.0), "PAUSED",
			HORIZONTAL_ALIGNMENT_RIGHT, size.x - 142.0, 11, COLOR_PAUSE_ON
		)
	else:
		var status_text: String = "%dx" % int(time_scale)
		draw_string(
			font, Vector2(130.0, 17.0), status_text,
			HORIZONTAL_ALIGNMENT_RIGHT, size.x - 142.0, 11, COLOR_ON
		)

	var total_width: float = size.x - 24.0
	var y: float = LABEL_HEIGHT + 10.0

	var btn_size: float = 30.0
	var sep_gap: float = 8.0

	# 1. START (Play icon)
	_start_rect = Rect2(12.0, y, btn_size, PILL_HEIGHT)
	_draw_control_pill(_start_rect, icon_play, not is_paused, COLOR_ON, "START")

	# 2. STOP (Pause icon)
	_stop_rect = Rect2(_start_rect.end.x + PILL_GAP, y, btn_size, PILL_HEIGHT)
	_draw_control_pill(_stop_rect, icon_pause, is_paused, COLOR_PAUSE_ON, "STOP")

	# 3. STEP FORWARD (Step icon)
	_step_rect = Rect2(_stop_rect.end.x + PILL_GAP, y, btn_size, PILL_HEIGHT)
	_draw_control_pill(_step_rect, icon_step, is_paused, COLOR_STEP, "STEP")

	# Hairline separator
	var sep_x: float = _step_rect.end.x + sep_gap * 0.5
	draw_line(
		Vector2(sep_x, y + 4.0),
		Vector2(sep_x, y + PILL_HEIGHT - 4.0),
		Color(HudPanelStyle.COLOR_BORDER_DEFAULT, 0.6),
		1.0
	)

	var speeds_start_x: float = _step_rect.end.x + sep_gap
	var count: int = STEPS.size()
	var remaining_width: float = (12.0 + total_width) - speeds_start_x
	var speed_pill_width: float = (remaining_width - PILL_GAP * float(count - 1)) / float(count)

	_pill_rects.resize(count)
	for i in range(count):
		var value: float = STEPS[i]
		var active: bool = (not is_paused) and is_equal_approx(time_scale, value)
		var rect := Rect2(speeds_start_x + float(i) * (speed_pill_width + PILL_GAP), y, speed_pill_width, PILL_HEIGHT)
		_pill_rects[i] = rect
		_draw_pill(rect, "%dx" % int(value), active)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		_hover_pos = event.position
		queue_redraw()
		return

	if not (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT):
		return

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

	for i in range(_pill_rects.size()):
		if _pill_rects[i].has_point(event.position):
			time_scale_selected.emit(STEPS[i])
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


func _draw_pill(rect: Rect2, label: String, active: bool) -> void:
	var is_hovered: bool = rect.has_point(_hover_pos)
	var style := StyleBoxFlat.new()
	if active:
		style.bg_color = Color(0.08, 0.18, 0.26, 0.92) if is_hovered else Color(0.06, 0.14, 0.20, 0.85)
		style.border_color = COLOR_ON
	else:
		style.bg_color = Color(0.08, 0.12, 0.17, 0.75) if is_hovered else Color(0.05, 0.07, 0.11, 0.7)
		style.border_color = Color(COLOR_OFF, 0.7) if is_hovered else Color(COLOR_OFF, 0.4)
	style.set_border_width_all(1)
	style.set_corner_radius_all(4)
	draw_style_box(style, rect)

	var font: Font = HudPanelStyle.get_font()
	var text_col: Color = COLOR_ON if active else (HudPanelStyle.COLOR_TEXT_PRIMARY if is_hovered else HudPanelStyle.COLOR_TEXT_MUTED)
	draw_string(
		font, rect.position + Vector2(0.0, rect.size.y * 0.5 + 4.0), label,
		HORIZONTAL_ALIGNMENT_CENTER, rect.size.x, 10, text_col
	)

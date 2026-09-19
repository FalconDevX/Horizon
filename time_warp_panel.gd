extends Control

signal time_scale_selected(value: float)

var time_scale := 1.0

const STEPS := [1.0, 2.0, 5.0, 10.0, 50.0, 100.0, 200.0]
const PILL_HEIGHT := 26.0
const PILL_GAP := 4.0
const LABEL_HEIGHT := 16.0

const COLOR_ON := Color(0.35, 0.85, 1.0)
const COLOR_OFF := Color(0.4, 0.45, 0.52, 0.5)

var _pill_rects: Array[Rect2] = []


func set_state(p_time_scale: float) -> void:
	if is_equal_approx(time_scale, p_time_scale):
		return
	time_scale = p_time_scale
	queue_redraw()


func _draw() -> void:
	HudPanelStyle.draw_chamfered(self, size, COLOR_ON, 14.0, 0.55)

	var font: Font = HudPanelStyle.get_font()
	draw_string(
		font, Vector2(12.0, 18.0), "TIME WARP",
		HORIZONTAL_ALIGNMENT_LEFT, size.x - 24.0, 12, Color(0.55, 0.7, 0.95, 0.85)
	)

	var count: int = STEPS.size()
	var total_width: float = size.x - 24.0
	var pill_width: float = (total_width - PILL_GAP * float(count - 1)) / float(count)
	var y: float = LABEL_HEIGHT + 10.0

	_pill_rects.resize(count)
	for i in range(count):
		var value: float = STEPS[i]
		var active: bool = is_equal_approx(time_scale, value)
		var rect := Rect2(12.0 + float(i) * (pill_width + PILL_GAP), y, pill_width, PILL_HEIGHT)
		_pill_rects[i] = rect
		_draw_pill(rect, "%dx" % int(value), active)


func _gui_input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT):
		return

	for i in range(_pill_rects.size()):
		if _pill_rects[i].has_point(event.position):
			time_scale_selected.emit(STEPS[i])
			return


func _draw_pill(rect: Rect2, label: String, active: bool) -> void:
	var color: Color = COLOR_ON if active else COLOR_OFF

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.09, 0.14, 0.2, 0.9) if active else Color(0.05, 0.07, 0.11, 0.85)
	style.border_color = color
	style.set_border_width_all(1)
	style.set_corner_radius_all(4)
	draw_style_box(style, rect)

	var font: Font = HudPanelStyle.get_font()
	draw_string(
		font, rect.position + Vector2(0.0, rect.size.y * 0.5 + 4.0), label,
		HORIZONTAL_ALIGNMENT_CENTER, rect.size.x, 11,
		color if active else Color(0.6, 0.65, 0.72, 0.7)
	)

class_name WarpButton
extends Control
## The hyperdrive's HUD button. Grey until a course is set on the galaxy map
## and the ship is out past the last asteroid belt; then it lights up and a
## click sends `warp_pressed`. solar_system.gd feeds it every frame with
## set_state(): whether it can jump, the headline and the line under it
## (where to, or what is still missing).

signal warp_pressed

## Colour of the lit button (cyan for the hyperdrive, violet for the warp).
var lit_color: Color = HudPanelStyle.COLOR_CYAN
var _ready_to_jump: bool = false
var _title: String = "WARP"
var _detail: String = ""
var _hovered: bool = false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	mouse_entered.connect(func() -> void: _hovered = true)
	mouse_exited.connect(func() -> void: _hovered = false)


func set_state(ready_to_jump: bool, title: String, detail: String) -> void:
	if ready_to_jump == _ready_to_jump and title == _title and detail == _detail:
		if _ready_to_jump:
			queue_redraw()
		return
	_ready_to_jump = ready_to_jump
	_title = title
	_detail = detail
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if ready_to_jump else Control.CURSOR_ARROW
	queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		accept_event()
		warp_pressed.emit()


func _draw() -> void:
	var rect := Rect2(Vector2.ZERO, size)
	var font: Font = HudPanelStyle.get_font()
	var pulse: float = 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.005)
	var accent: Color
	if _ready_to_jump:
		accent = lit_color
		draw_rect(rect, Color(accent, (0.22 if _hovered else 0.12) + 0.08 * pulse))
		draw_rect(rect.grow(2.0), Color(accent, 0.25 * pulse), false, 2.0)
		draw_rect(rect, accent, false, 1.0)
	else:
		accent = HudPanelStyle.COLOR_TEXT_MUTED
		draw_rect(rect, Color(HudPanelStyle.COLOR_BG_SURFACE, 0.85))
		draw_rect(rect, HudPanelStyle.COLOR_BORDER_DEFAULT, false, 1.0)
	draw_rect(Rect2(rect.position, Vector2(3.0, rect.size.y)), accent)

	# Chevrons: the jump glyph.
	var cx: float = 22.0
	var cy: float = rect.size.y * 0.5
	for i in 2:
		var x: float = cx + float(i) * 7.0
		draw_polyline(
			PackedVector2Array([Vector2(x - 4.0, cy - 7.0), Vector2(x + 3.0, cy), Vector2(x - 4.0, cy + 7.0)]),
			accent, 2.0, true
		)

	var text_x: float = 44.0
	var title_color: Color = HudPanelStyle.COLOR_TEXT_PRIMARY if _ready_to_jump else HudPanelStyle.COLOR_TEXT_MUTED
	draw_string(
		font, Vector2(text_x, 19.0), _title, HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - text_x - 8.0, 13, title_color
	)
	draw_string(
		font, Vector2(text_x, 35.0), _detail, HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - text_x - 8.0, 10,
		Color(accent, 0.9) if _ready_to_jump else HudPanelStyle.COLOR_TEXT_FAINT.lerp(HudPanelStyle.COLOR_TEXT_MUTED, 0.6)
	)

extends Control


@export var label_text := "PE"
@export var accent_color := Color(0.5, 0.85, 0.95)
@export var warn_below_zero := false

signal scrolled(direction: float)

const DANGER_COLOR := Color(1.0, 0.25, 0.25)
const TARGET_COLOR := Color(0.85, 0.8, 0.5)

var value: float = 0.0
var has_value: bool = false
var target_value: float = 0.0
var show_target: bool = false


func set_value(
	p_value: float, p_has_value: bool, p_target_value: float = 0.0, p_show_target: bool = false
) -> void:
	if (
		has_value == p_has_value
		and is_equal_approx(value, p_value)
		and show_target == p_show_target
		and is_equal_approx(target_value, p_target_value)
	):
		return
	value = p_value
	has_value = p_has_value
	target_value = p_target_value
	show_target = p_show_target
	queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton and event.pressed and event.ctrl_pressed):
		return
	if event.button_index == MOUSE_BUTTON_WHEEL_UP:
		scrolled.emit(1.0)
		accept_event()
	elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
		scrolled.emit(-1.0)
		accept_event()


func _process(_delta: float) -> void:
	if warn_below_zero and has_value and value < 0.0:
		queue_redraw()


func _draw() -> void:
	var danger: bool = warn_below_zero and has_value and value < 0.0
	var color: Color = accent_color if has_value else Color(0.4, 0.45, 0.52, 0.55)

	if danger:
		var flash: float = 0.6 + 0.4 * sin(Time.get_ticks_msec() / 1000.0 * 6.0)
		color = DANGER_COLOR.lerp(Color.WHITE, 0.15) if flash > 0.8 else DANGER_COLOR

	_draw_panel(color)

	var font: Font = HudPanelStyle.get_font()
	var text_width: float = size.x - 16.0
	var label_color: Color = Color(0.8, 0.83, 0.88, 0.85) if has_value else Color(0.5, 0.53, 0.58, 0.5)

	draw_string(
		font, Vector2(8.0, size.y * 0.32), label_text,
		HORIZONTAL_ALIGNMENT_CENTER, text_width, 12, label_color
	)

	draw_line(
		Vector2(size.x * 0.28, size.y * 0.42), Vector2(size.x * 0.72, size.y * 0.42),
		Color(color, 0.9), 2.0
	)

	var value_text: String = ("%.0f" % value) if has_value else "--"
	draw_string(
		font, Vector2(8.0, size.y * 0.72), value_text,
		HORIZONTAL_ALIGNMENT_CENTER, text_width, 24, Color(0.95, 0.96, 0.98) if has_value else color
	)

	var unit_text: String = "SU"
	var unit_color: Color = Color(0.55, 0.58, 0.63, 0.7)
	if show_target:
		unit_text = "SU  ->%.0f" % target_value
		unit_color = Color(TARGET_COLOR, 0.9)

	draw_string(
		font, Vector2(8.0, size.y * 0.9), unit_text,
		HORIZONTAL_ALIGNMENT_CENTER, text_width, 10, unit_color
	)


func _draw_panel(color: Color) -> void:
	HudPanelStyle.draw_chamfered(self, size, color, 12.0, 0.75)

extends Control


@export var label_text := "PE"
@export var accent_color := Color(0.5, 0.85, 0.95)
@export var warn_below_zero := false

const DANGER_COLOR := Color(1.0, 0.25, 0.25)

var value: float = 0.0
var has_value: bool = false


func set_value(p_value: float, p_has_value: bool) -> void:
	if has_value == p_has_value and is_equal_approx(value, p_value):
		return
	value = p_value
	has_value = p_has_value
	queue_redraw()


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

	draw_string(
		font, Vector2(8.0, size.y * 0.34), label_text,
		HORIZONTAL_ALIGNMENT_CENTER, text_width, 12, Color(color, 0.85)
	)

	var value_text: String = ("%.0f" % value) if has_value else "--"
	draw_string(
		font, Vector2(8.0, size.y * 0.65), value_text,
		HORIZONTAL_ALIGNMENT_CENTER, text_width, 22, color
	)

	draw_string(
		font, Vector2(8.0, size.y * 0.88), "SU",
		HORIZONTAL_ALIGNMENT_CENTER, text_width, 10, Color(color, 0.7)
	)


func _draw_panel(color: Color) -> void:
	HudPanelStyle.draw_chamfered(self, size, color, 12.0, 0.75)

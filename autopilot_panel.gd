extends Control


var data: Dictionary = {}

const COLOR_OFF := Color(0.45, 0.48, 0.55, 0.6)
const COLOR_ACTIVE := Color(0.35, 0.85, 1.0)
const COLOR_SELECTING := Color(0.9, 0.75, 0.25)
const PAD := 12.0
const LINE_HEIGHT := 17.0
const SMALL_LINE_HEIGHT := 15.0


func set_state(p_data: Dictionary) -> void:
	data = p_data
	queue_redraw()


func _draw() -> void:
	var active: bool = data.get("active", false)
	var selecting: bool = data.get("selecting", false)

	var accent: Color = COLOR_OFF
	if selecting:
		accent = COLOR_SELECTING
	elif active:
		accent = COLOR_ACTIVE

	_draw_panel(accent)

	var font: Font = HudPanelStyle.get_font()
	var content_width: float = size.x - PAD * 2.0
	var y: float = 22.0

	draw_string(font, Vector2(PAD, y), "AUTOPILOT", HORIZONTAL_ALIGNMENT_LEFT, content_width, 13, accent)
	draw_circle(Vector2(size.x - PAD - 4.0, y - 5.0), 4.0, accent if (active or selecting) else Color(accent, 0.4))
	y += LINE_HEIGHT * 1.4

	if not selecting and not active:
		draw_string(
			font, Vector2(PAD, y), "STANDBY",
			HORIZONTAL_ALIGNMENT_LEFT, content_width, 12, Color(0.55, 0.6, 0.68, 0.7)
		)
		return

	var body_name: String = data.get("body_name", "")
	var body_color: Color = data.get("body_color", Color.WHITE)
	var label: String = "SELECTING: " if selecting else "TARGET: "
	draw_string(font, Vector2(PAD, y), label + body_name, HORIZONTAL_ALIGNMENT_LEFT, content_width, 12, body_color)
	y += LINE_HEIGHT

	y = _line(font, y, content_width, "TARGET ALT: %.0f SU" % data.get("target_altitude", 0.0), Color(0.75, 0.78, 0.85))
	y = _line(font, y, content_width, "TOLERANCE: ±%.0f SU" % data.get("tolerance", 0.0), Color(0.75, 0.78, 0.85))

	if selecting:
		y += SMALL_LINE_HEIGHT * 0.5
		y = _line(font, y, content_width, "Scroll: change orbit", Color(0.6, 0.63, 0.7))
		y = _line(font, y, content_width, "Tab: change target body", Color(0.6, 0.63, 0.7))
		y = _line(font, y, content_width, "Release F: engage", Color(0.6, 0.63, 0.7))
		return

	y = _line(font, y, content_width, "BURN 1 Δv: %+.3f" % data.get("burn1", 0.0), Color(0.75, 0.78, 0.85))
	y = _line(font, y, content_width, "BURN 2 Δv: %+.3f" % data.get("burn2", 0.0), Color(0.75, 0.78, 0.85))
	y = _line(
		font, y, content_width, "REMAINING Δv: %.3f" % data.get("remaining_delta_v", 0.0),
		data.get("remaining_color", Color.WHITE)
	)

	y += SMALL_LINE_HEIGHT * 0.3
	var rcs_lines: PackedStringArray = data.get("rcs_lines", PackedStringArray())
	for line in rcs_lines:
		y = _line(font, y, content_width, line, Color(0.55, 0.75, 0.95))

	y += SMALL_LINE_HEIGHT * 0.3
	var status_color: Color = data.get("status_color", Color.WHITE)
	var status_lines: PackedStringArray = data.get("status_lines", PackedStringArray())
	for line in status_lines:
		y = _line(font, y, content_width, line, status_color)

	y += SMALL_LINE_HEIGHT * 0.3
	_line(
		font, y, content_width, "BURN: " + String(data.get("burn_mode_text", "")),
		data.get("burn_mode_color", Color.WHITE)
	)


func _line(font: Font, y: float, content_width: float, text: String, color: Color) -> float:
	draw_string(font, Vector2(PAD, y), text, HORIZONTAL_ALIGNMENT_LEFT, content_width, 11, color)
	return y + SMALL_LINE_HEIGHT


# Ucięte po skosie narożniki (góra-lewo, dół-prawo) zamiast zaokrąglonego
# boksu - kanciasty, sci-fi look z referencyjnego wzoru HUD-u zamiast
# zaokrąglonych kart.
func _draw_panel(accent: Color) -> void:
	var chamfer := 16.0
	var w: float = size.x
	var h: float = size.y

	var points := PackedVector2Array([
		Vector2(chamfer, 0.0),
		Vector2(w, 0.0),
		Vector2(w, h - chamfer),
		Vector2(w - chamfer, h),
		Vector2(0.0, h),
		Vector2(0.0, chamfer),
	])

	draw_colored_polygon(points, Color(0.05, 0.07, 0.12, 0.55))

	var outline: PackedVector2Array = points.duplicate()
	outline.append(points[0])
	draw_polyline(outline, Color(accent, 0.8), 1.5, true)

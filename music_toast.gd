extends Control

var current_text: String = ""
var display_timer: float = 0.0
const DISPLAY_DURATION := 4.5
const FADE_DURATION := 0.8


func show_track(title: String) -> void:
	current_text = "♪  NOW PLAYING: " + title
	display_timer = DISPLAY_DURATION
	visible = true
	queue_redraw()


func _process(delta: float) -> void:
	if display_timer > 0.0:
		display_timer -= delta
		if display_timer <= 0.0:
			visible = false
		queue_redraw()


func _draw() -> void:
	if display_timer <= 0.0:
		return

	var alpha: float = 1.0
	if display_timer < FADE_DURATION:
		alpha = clampf(display_timer / FADE_DURATION, 0.0, 1.0)
	elif display_timer > DISPLAY_DURATION - FADE_DURATION:
		alpha = clampf((DISPLAY_DURATION - display_timer) / FADE_DURATION, 0.0, 1.0)

	var panel_color := Color(HudPanelStyle.COLOR_CYAN, 0.75 * alpha)
	var bg_color := Color(HudPanelStyle.COLOR_BG_CANVAS, 0.94 * alpha)

	var style := StyleBoxFlat.new()
	style.bg_color = bg_color
	style.border_color = panel_color
	style.set_border_width_all(1)
	style.set_corner_radius_all(6)
	draw_style_box(style, Rect2(Vector2.ZERO, size))

	# Subtle glowing halo under the toast
	draw_line(
		Vector2(12.0, size.y),
		Vector2(size.x - 12.0, size.y),
		Color(HudPanelStyle.COLOR_CYAN, 0.4 * alpha), 1.0
	)

	var font: Font = HudPanelStyle.get_font()
	var text_shift_right := 14.0
	draw_string(
		font, Vector2(10.0 + text_shift_right, size.y * 0.5 + 4.0), current_text,
		HORIZONTAL_ALIGNMENT_CENTER, size.x - 20.0 - text_shift_right, 11,
		Color(HudPanelStyle.COLOR_TEXT_PRIMARY, alpha)
	)

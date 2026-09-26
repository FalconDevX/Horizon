extends Control


var flight_assist := false
var throttle_locked := false
var throttle := 0.0

const CHIP_WIDTH := 92.0
const CHIP_HEIGHT := 18.0
const CHIP_GAP := 6.0
const BAR_GAP_ABOVE := 14.0
const BAR_HEIGHT := 10.0
const BAR_SEGMENTS := 18
const BAR_SEGMENT_GAP := 2.0
const BAR_LABEL_GAP := 4.0
const PAD_LEFT := 22.0
const PAD_TOP := 10.0

const COLOR_ON := HudPanelStyle.COLOR_CYAN
const COLOR_OFF := Color(0.35, 0.42, 0.52, 0.5)
const COLOR_WARN := HudPanelStyle.COLOR_AMBER
const COLOR_ASSIST := HudPanelStyle.COLOR_EMERALD


func set_state(p_assist: bool, p_lock: bool, p_throttle: float) -> void:
	if (
		flight_assist == p_assist
		and throttle_locked == p_lock
		and is_equal_approx(throttle, p_throttle)
	):
		return

	flight_assist = p_assist
	throttle_locked = p_lock
	throttle = p_throttle
	queue_redraw()


func _draw() -> void:
	HudPanelStyle.draw_chamfered(self, size, HudPanelStyle.COLOR_BORDER_DEFAULT, 14.0, 0.85, 0.55)

	var chips := [
		{"label": "ASSIST (V)", "on": flight_assist, "warn": false, "color": COLOR_ASSIST},
		{"label": "LOCK (X)", "on": throttle_locked, "warn": throttle_locked, "color": COLOR_WARN},
	]

	var total_width: float = CHIP_WIDTH * chips.size() + CHIP_GAP * (chips.size() - 1)
	var start_x: float = maxf((size.x - total_width) * 0.5, PAD_LEFT)

	for i in range(chips.size()):
		var chip: Dictionary = chips[i]
		var rect := Rect2(start_x + float(i) * (CHIP_WIDTH + CHIP_GAP), PAD_TOP, CHIP_WIDTH, CHIP_HEIGHT)
		_draw_chip(rect, chip.label, chip.on, chip.warn, chip.color)

	var font: Font = HudPanelStyle.get_font()
	var bar_y: float = PAD_TOP + CHIP_HEIGHT + BAR_GAP_ABOVE
	draw_string(
		font, Vector2(start_x, bar_y - BAR_LABEL_GAP), "THRUST",
		HORIZONTAL_ALIGNMENT_LEFT, total_width, 9, HudPanelStyle.COLOR_TEXT_MUTED
	)

	var percent_text: String = "%d%%" % roundi(throttle * 100.0)
	var percent_width: float = 36.0
	var bar_rect := Rect2(start_x, bar_y, total_width - percent_width, BAR_HEIGHT)
	_draw_throttle_bar(bar_rect)

	draw_string(
		font, Vector2(bar_rect.end.x + 6.0, bar_y + BAR_HEIGHT - 1.0), percent_text,
		HORIZONTAL_ALIGNMENT_LEFT, percent_width, 11, HudPanelStyle.COLOR_TEXT_PRIMARY
	)


# A chip is just a dot + text, no border/background - matches the
# reference HUD look (elements "float" on the background instead of sitting in boxes).
func _draw_chip(rect: Rect2, label: String, on: bool, warn: bool, on_color: Color) -> void:
	var color: Color = COLOR_OFF
	if on:
		color = COLOR_WARN if warn else on_color

	draw_circle(
		rect.position + Vector2(4.0, rect.size.y * 0.5), 3.0,
		color if on else Color(color, 0.4)
	)

	var font: Font = HudPanelStyle.get_font()
	draw_string(
		font, rect.position + Vector2(12.0, rect.size.y * 0.5 + 4.0),
		label, HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - 12.0, 11,
		color if on else HudPanelStyle.COLOR_TEXT_MUTED
	)


func _draw_throttle_bar(rect: Rect2) -> void:
	var seg_width: float = (rect.size.x - BAR_SEGMENT_GAP * float(BAR_SEGMENTS - 1)) / float(BAR_SEGMENTS)
	var filled_segments: int = roundi(throttle * BAR_SEGMENTS)

	for i in range(BAR_SEGMENTS):
		var seg_rect := Rect2(
			rect.position.x + float(i) * (seg_width + BAR_SEGMENT_GAP),
			rect.position.y, seg_width, rect.size.y
		)
		var active: bool = i < filled_segments
		var t: float = float(i) / float(BAR_SEGMENTS - 1)
		var color: Color = (
			COLOR_ON.lerp(COLOR_WARN, t)
			if active else Color(HudPanelStyle.COLOR_BORDER_DEFAULT, 0.35)
		)
		draw_rect(seg_rect, color, true)

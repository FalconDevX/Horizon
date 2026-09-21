extends Control

@export var max_speed: float = 1000.0
@export var gauge_color := HudPanelStyle.COLOR_CYAN
@export var track_color := Color(1.0, 1.0, 1.0, 0.08)

var speed: float = 0.0:
	set(value):
		if is_equal_approx(speed, value):
			return
		speed = value
		queue_redraw()

var zoom: float = 1.0:
	set(value):
		if is_equal_approx(zoom, value):
			return
		zoom = value
		queue_redraw()

const START_ANGLE := PI * 0.75
const SWEEP := PI * 1.5
const ARC_POINTS := 64
const TICK_COUNT := 10


func _draw() -> void:
	var short_side: float = minf(size.x, size.y)
	var center: Vector2 = size * 0.5
	var radius: float = short_side * 0.5 - 16.0

	_draw_panel()
	draw_arc(center, radius, START_ANGLE, START_ANGLE + SWEEP, ARC_POINTS, track_color, 6.0, true)

	var fraction: float = clampf(speed / max_speed, 0.0, 1.0)
	if fraction > 0.0:
		var end_angle: float = START_ANGLE + SWEEP * fraction
		draw_arc(center, radius, START_ANGLE, end_angle, ARC_POINTS, Color(gauge_color, 0.25), 12.0, true)
		draw_arc(center, radius, START_ANGLE, end_angle, ARC_POINTS, gauge_color, 5.0, true)

	_draw_ticks(center, radius)
	_draw_text(center, radius)


func _draw_panel() -> void:
	HudPanelStyle.draw_chamfered(self, size, HudPanelStyle.COLOR_BORDER_DEFAULT, 20.0, 0.85, 0.55)


func _draw_ticks(center: Vector2, radius: float) -> void:
	for i in range(TICK_COUNT + 1):
		var angle: float = START_ANGLE + SWEEP * float(i) / float(TICK_COUNT)
		var dir := Vector2(cos(angle), sin(angle))
		draw_line(
			center + dir * (radius - 7.0),
			center + dir * (radius + 2.0),
			Color(1.0, 1.0, 1.0, 0.35),
			1.5
		)

	draw_circle(center + Vector2.UP * (radius + 9.0), 2.0, Color(1.0, 1.0, 1.0, 0.9))

	var font: Font = HudPanelStyle.get_font()
	var start_dir := Vector2(cos(START_ANGLE), sin(START_ANGLE))
	var end_dir := Vector2(cos(START_ANGLE + SWEEP), sin(START_ANGLE + SWEEP))
	draw_string(
		font, center + start_dir * (radius + 14.0) - Vector2(10.0, -4.0), "0",
		HORIZONTAL_ALIGNMENT_CENTER, 20.0, 10, Color(1.0, 1.0, 1.0, 0.45)
	)
	draw_string(
		font, center + end_dir * (radius + 14.0) - Vector2(10.0, -4.0), "%d" % int(max_speed),
		HORIZONTAL_ALIGNMENT_CENTER, 20.0, 10, Color(1.0, 1.0, 1.0, 0.45)
	)


func _draw_text(center: Vector2, radius: float) -> void:
	var font: Font = HudPanelStyle.get_font()
	var text_width: float = radius * 1.6

	draw_string(
		font, center + Vector2(-text_width * 0.5, -radius * 0.42),
		"SPEED", HORIZONTAL_ALIGNMENT_CENTER, text_width,
		maxi(11, roundi(radius * 0.15)), Color(0.55, 0.7, 0.95, 0.85)
	)
	draw_string(
		font, center + Vector2(-text_width * 0.5, radius * 0.18),
		"%.1f" % speed, HORIZONTAL_ALIGNMENT_CENTER, text_width,
		maxi(20, roundi(radius * 0.5)), Color(0.9, 0.95, 1.0)
	)
	draw_string(
		font, center + Vector2(-text_width * 0.5, radius * 0.56),
		"SU/s", HORIZONTAL_ALIGNMENT_CENTER, text_width,
		maxi(10, roundi(radius * 0.13)), Color(0.55, 0.6, 0.7, 0.8)
	)

	var zoom_text: String = "ZOOM %.2fx" % zoom if zoom >= 0.1 else "ZOOM %.4fx" % zoom
	draw_string(
		font, center + Vector2(-text_width * 0.5, radius * 0.78),
		zoom_text, HORIZONTAL_ALIGNMENT_CENTER, text_width,
		maxi(9, roundi(radius * 0.1)), Color(0.5, 0.55, 0.62, 0.65)
	)

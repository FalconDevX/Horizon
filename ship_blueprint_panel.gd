extends Control

signal clicked

const SHIP_TEXTURE := preload("res://textures/ship_blueprint.png")

const FRONT_POS := Vector2(0.50, 0.10)
const BACK_POS := Vector2(0.50, 0.72)
const LEFT_POS := Vector2(0.03, 0.47)
const RIGHT_POS := Vector2(0.96, 0.475)
const ENGINE_EXIT_POS := Vector2(0.58, 0.97)

const RCS_COLOR := HudPanelStyle.COLOR_CYAN
const RCS_CORE_COLOR := Color(0.8, 0.95, 1.0)
const MAIN_OUTER_COLOR := Color(1.0, 0.45, 0.1)
const MAIN_CORE_COLOR := Color(1.0, 0.85, 0.5)
const LINE_COLOR := Color(0.6, 0.65, 0.72, 0.9)
const RCS_ACTIVE_THRESHOLD := 0.05

var throttle := 0.0
var rcs_command := Vector2.ZERO


func _process(_delta: float) -> void:
	if throttle > 0.0 or rcs_command.length() > RCS_ACTIVE_THRESHOLD:
		queue_redraw()


func set_state(p_throttle: float, p_rcs_command: Vector2) -> void:
	if is_equal_approx(throttle, p_throttle) and rcs_command.is_equal_approx(p_rcs_command):
		return
	throttle = p_throttle
	rcs_command = p_rcs_command
	queue_redraw()


# Klik na podgląd statku = to samo co klik na statek w świecie gry
# (kamera zaczyna go śledzić) - łatwiej trafić w duży model w rogu niż
# w malutki znacznik statku po oddaleniu kamery.
func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		clicked.emit()


func _draw() -> void:
	HudPanelStyle.draw_chamfered(self, size, HudPanelStyle.COLOR_BORDER_DEFAULT, 16.0, 0.85, 0.55)

	var image_rect: Rect2 = _fit_rect()
	draw_texture_rect(SHIP_TEXTURE, image_rect, false)

	var scale_ref: float = minf(image_rect.size.x, image_rect.size.y)

	_draw_engine_flame(image_rect, scale_ref)
	_draw_rcs_flame(
		image_rect.position + FRONT_POS * image_rect.size, Vector2.UP,
		rcs_command.x < -RCS_ACTIVE_THRESHOLD, scale_ref, 0.0, "FWD"
	)
	_draw_rcs_flame(
		image_rect.position + BACK_POS * image_rect.size, Vector2.DOWN,
		rcs_command.x > RCS_ACTIVE_THRESHOLD, scale_ref, 1.7, "AFT"
	)
	_draw_rcs_flame(
		image_rect.position + LEFT_POS * image_rect.size, Vector2.LEFT,
		rcs_command.y < -RCS_ACTIVE_THRESHOLD, scale_ref, 3.4, "L"
	)
	_draw_rcs_flame(
		image_rect.position + RIGHT_POS * image_rect.size, Vector2.RIGHT,
		rcs_command.y > RCS_ACTIVE_THRESHOLD, scale_ref, 5.1, "R"
	)

	var engine_label_pos: Vector2 = image_rect.position + ENGINE_EXIT_POS * image_rect.size + Vector2(-15.0, 10.0)
	draw_string(
		HudPanelStyle.get_font(), engine_label_pos, "MAIN", HORIZONTAL_ALIGNMENT_CENTER, 30.0, 8,
		Color(MAIN_OUTER_COLOR, 0.9) if throttle > 0.0 else Color(LINE_COLOR, 0.5)
	)


const FLAME_RESERVE_FRACTION := 0.22
const TOP_PADDING := 16.0
const SIDE_PADDING := 16.0

func _fit_rect() -> Rect2:
	var texture_size: Vector2 = SHIP_TEXTURE.get_size()
	var available_width: float = size.x - SIDE_PADDING * 2.0
	var available_height: float = (size.y - TOP_PADDING) * (1.0 - FLAME_RESERVE_FRACTION)
	var fit_scale: float = minf(available_width / texture_size.x, available_height / texture_size.y)
	var fitted_size: Vector2 = texture_size * fit_scale
	var origin_x: float = (size.x - fitted_size.x) * 0.5
	return Rect2(Vector2(origin_x, TOP_PADDING), fitted_size)


# Burst z falującą krawędzią (kilka punktów z drgającym przesunięciem
# zamiast prostego trójkąta) + iskry lecące wzdłuż strumienia - więcej
# "życia" niż płaski kształt, ale nadal tanie (bez cząsteczek/shaderów).
func _draw_engine_flame(image_rect: Rect2, scale_ref: float) -> void:
	if throttle <= 0.0:
		return

	var tip: Vector2 = image_rect.position + ENGINE_EXIT_POS * image_rect.size
	var direction: Vector2 = Vector2.DOWN
	var side: Vector2 = direction.orthogonal()

	var t: float = Time.get_ticks_msec() / 1000.0
	var flicker: float = 0.85 + 0.15 * sin(t * 24.0) + 0.08 * sin(t * 61.0 + 1.3)
	var length: float = 0.3 * scale_ref * throttle * flicker

	var outer_half_width: float = 0.11 * image_rect.size.x
	_draw_wavy_flame(tip, direction, side, outer_half_width, length, t, Color(MAIN_OUTER_COLOR, 0.55 * flicker))

	var mid_half_width: float = outer_half_width * 0.75
	_draw_wavy_flame(tip, direction, side, mid_half_width, length * 0.8, t + 3.1, Color(1.0, 0.65, 0.2, 0.7 * flicker))

	var inner_half_width: float = outer_half_width * 0.4
	draw_colored_polygon(
		PackedVector2Array([
			tip + side * inner_half_width, tip - side * inner_half_width,
			tip + direction * (length * 0.6)
		]),
		Color(MAIN_CORE_COLOR, 0.95 * flicker)
	)

	_draw_sparks(tip, direction, side, outer_half_width, length, t, Color(1.0, 0.8, 0.4))


# Trójkąt zamieniony na kilka segmentów z bocznym driftem (sinusoidalnie
# w czasie i wzdłuż długości) - krawędź faluje jak prawdziwy strumień
# spalin zamiast być idealnie prosta.
func _draw_wavy_flame(
	tip: Vector2, direction: Vector2, side: Vector2, half_width: float, length: float, t: float, color: Color
) -> void:
	var segments := 5
	var left_points := PackedVector2Array()
	var right_points := PackedVector2Array()

	for i in range(segments + 1):
		var f: float = float(i) / float(segments)
		var pos: Vector2 = tip + direction * (length * f)
		var taper: float = 1.0 - f
		var wobble: float = sin(t * 14.0 + f * 6.0) * half_width * 0.18 * f
		var width: float = half_width * taper + wobble
		left_points.append(pos + side * width)
		right_points.append(pos - side * width)

	var points := PackedVector2Array()
	points.append_array(left_points)
	right_points.reverse()
	points.append_array(right_points)
	draw_colored_polygon(points, color)


# Kilka drobnych iskier odrywających się od strumienia, migających
# niezależnie od głównego płomienia (inna faza/częstotliwość).
func _draw_sparks(
	tip: Vector2, direction: Vector2, side: Vector2, half_width: float, length: float, t: float, spark_color: Color
) -> void:
	var spark_count := 3
	for i in range(spark_count):
		var phase_seed: float = float(i) * 17.3
		var f: float = fmod(t * 0.7 + phase_seed, 1.0)
		var pos: Vector2 = tip + direction * (length * (0.35 + f * 0.9))
		var drift: float = sin(t * 9.0 + phase_seed) * half_width * 0.5 * f
		pos += side * drift
		var alpha: float = (1.0 - f) * 0.8
		var radius: float = maxf(0.6, 1.4 * (1.0 - f * 0.6) * (half_width / 6.0))
		draw_circle(pos, radius, Color(spark_color, alpha))


func _draw_rcs_flame(
	pos: Vector2, outward_dir: Vector2, active: bool, scale_ref: float, phase: float, label: String
) -> void:
	draw_circle(pos, 3.0, RCS_COLOR if active else Color(LINE_COLOR, 0.35))

	var font: Font = HudPanelStyle.get_font()
	var label_pos: Vector2 = pos - outward_dir * 14.0 - Vector2(15.0, 0.0)
	draw_string(
		font, label_pos, label, HORIZONTAL_ALIGNMENT_CENTER, 30.0, 8,
		Color(RCS_COLOR, 0.9) if active else Color(LINE_COLOR, 0.5)
	)

	if not active:
		return

	var t: float = Time.get_ticks_msec() / 1000.0
	var flicker: float = 0.75 + 0.25 * sin(t * 19.0 + phase) + 0.15 * sin(t * 53.0 + phase * 2.0)
	var length: float = 0.13 * scale_ref * flicker
	var half_width: float = 0.045 * scale_ref
	var base: Vector2 = pos + outward_dir * 3.0

	_draw_wavy_flame(base, outward_dir, outward_dir.orthogonal(), half_width, length, t + phase, Color(RCS_COLOR, 0.7 * flicker))
	_draw_sparks(base, outward_dir, outward_dir.orthogonal(), half_width, length, t + phase, RCS_CORE_COLOR)

	draw_colored_polygon(
		PackedVector2Array([
			base + outward_dir.orthogonal() * half_width * 0.4,
			base - outward_dir.orthogonal() * half_width * 0.4,
			base + outward_dir * length * 0.55
		]),
		Color(RCS_CORE_COLOR, 0.9 * flicker)
	)



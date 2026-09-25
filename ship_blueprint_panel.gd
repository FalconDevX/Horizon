extends Control

signal clicked

const SHIP_TEXTURE := preload("res://textures/ship_blueprint.png")

const ENGINE_EXIT_POS := Vector2(0.58, 0.97)

const MAIN_OUTER_COLOR := Color(1.0, 0.45, 0.1)
const MAIN_CORE_COLOR := Color(1.0, 0.85, 0.5)
const LINE_COLOR := Color(0.6, 0.65, 0.72, 0.9)

var throttle := 0.0
## The ship built in the yard (ShipRender), nose to the right; null shows the
## stock ship's blueprint.
var built_texture: Texture2D = null


func set_built_texture(texture: Texture2D) -> void:
	built_texture = texture
	queue_redraw()


func _process(_delta: float) -> void:
	if throttle > 0.0:
		queue_redraw()


func set_state(p_throttle: float) -> void:
	if is_equal_approx(throttle, p_throttle):
		return
	throttle = p_throttle
	queue_redraw()


# Clicking the ship preview = same as clicking the ship in the game world
# (camera starts following it) - easier to hit the large model in the corner
# than the tiny ship marker once the camera has zoomed out.
func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		clicked.emit()


func _draw() -> void:
	HudPanelStyle.draw_chamfered(self, size, HudPanelStyle.COLOR_BORDER_DEFAULT, 16.0, 0.85, 0.55)
	if built_texture != null:
		_draw_built()
		return

	var image_rect: Rect2 = _fit_rect()
	draw_texture_rect(SHIP_TEXTURE, image_rect, false)

	var scale_ref: float = minf(image_rect.size.x, image_rect.size.y)

	_draw_engine_flame(image_rect, scale_ref)

	var engine_label_pos: Vector2 = image_rect.position + ENGINE_EXIT_POS * image_rect.size + Vector2(-15.0, 10.0)
	draw_string(
		HudPanelStyle.get_font(), engine_label_pos, "MAIN", HORIZONTAL_ALIGNMENT_CENTER, 30.0, 8,
		Color(MAIN_OUTER_COLOR, 0.9) if throttle > 0.0 else Color(LINE_COLOR, 0.5)
	)


## The built ship, turned nose up like the blueprint, fitted to the panel.
func _draw_built() -> void:
	var picture: Vector2 = built_texture.get_size()
	var turned := Vector2(picture.y, picture.x)
	var room := size - Vector2(SIDE_PADDING, TOP_PADDING) * 2.0
	var fit: float = minf(room.x / turned.x, room.y / turned.y)
	var drawn: Vector2 = picture * fit
	draw_set_transform(size * 0.5, -PI * 0.5, Vector2.ONE)
	draw_texture_rect(built_texture, Rect2(-drawn * 0.5, drawn), false)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	if throttle > 0.0:
		draw_string(
			HudPanelStyle.get_font(), Vector2(0.0, size.y - 10.0), "ENGINES", HORIZONTAL_ALIGNMENT_CENTER, size.x, 8,
			Color(MAIN_OUTER_COLOR, 0.9)
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


# A burst with a wavy edge (a few points with a jittering offset instead
# of a plain triangle) + sparks flying along the stream - more "life"
# than a flat shape, but still cheap (no particles/shaders).
func _draw_engine_flame(image_rect: Rect2, scale_ref: float) -> void:
	# A near-zero flame folds into degenerate polygons Godot cannot triangulate.
	if throttle <= 0.02:
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


# The triangle is replaced by a few segments with sideways drift (sinusoidal
# over time and along the length) - the edge waves like a real exhaust
# stream instead of being perfectly straight.
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


# A few tiny sparks breaking off the stream, flickering independently
# of the main flame (different phase/frequency).
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



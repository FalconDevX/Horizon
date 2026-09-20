extends Control

const GLOW_TEXTURE := preload("res://textures/glow.png")
const PREVIEW_RADIUS := 40.0
const GRAVITY_CONSTANT := 3000.0

var body_name: String = ""
var body_color: Color = Color.WHITE
var diameter: float = 0.0
var mass: float = 0.0
var surface_gravity: float = 0.0
var soi_radius: float = 0.0
var atmosphere: String = "None"
var is_sun: bool = false


func show_body(
	p_body_name: String,
	p_color: Color,
	p_radius: float,
	p_mass: float,
	p_soi_radius: float,
	p_atmosphere: String,
	p_is_sun: bool
) -> void:
	body_name = p_body_name
	body_color = p_color
	diameter = p_radius * 2.0
	mass = p_mass
	surface_gravity = GRAVITY_CONSTANT * p_mass / maxf(p_radius * p_radius, 1.0)
	soi_radius = p_soi_radius
	atmosphere = p_atmosphere
	is_sun = p_is_sun
	visible = true
	queue_redraw()


func hide_panel() -> void:
	visible = false


func _get_close_rect() -> Rect2:
	return Rect2(size.x - 28.0, 8.0, 20.0, 20.0)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if _get_close_rect().has_point(event.position):
			hide_panel()
		accept_event()


func _draw() -> void:
	HudPanelStyle.draw_chamfered(self, size, body_color, 16.0, 0.85)

	var font: Font = HudPanelStyle.get_font()
	var pad := 14.0

	draw_string(
		font, Vector2(pad, 24.0), body_name.to_upper(),
		HORIZONTAL_ALIGNMENT_LEFT, size.x - pad * 2.0 - 20.0, 15, Color(0.92, 0.94, 0.98)
	)

	var close_rect: Rect2 = _get_close_rect()
	draw_string(
		font, close_rect.position + Vector2(3.0, 15.0), "X",
		HORIZONTAL_ALIGNMENT_LEFT, 20.0, 13, Color(0.7, 0.73, 0.8)
	)

	var preview_center := Vector2(size.x * 0.5, 90.0)
	var glow_diameter: float = PREVIEW_RADIUS * 4.0
	var glow_rect := Rect2(
		preview_center - Vector2.ONE * glow_diameter * 0.5,
		Vector2.ONE * glow_diameter
	)
	draw_texture_rect(GLOW_TEXTURE, glow_rect, false, Color(body_color, 0.6))
	draw_circle(preview_center, PREVIEW_RADIUS, body_color)

	var lines: PackedStringArray = [
		"DIAMETER: %.0f SU" % diameter,
		"MASS: %.0f" % mass,
		"SURFACE GRAVITY: %.2f" % surface_gravity,
		"SOI RADIUS: %.0f SU" % soi_radius if not is_sun else "SOI RADIUS: -- (star)",
		"ATMOSPHERE: " + atmosphere,
	]

	var y := 150.0
	for line in lines:
		draw_string(
			font, Vector2(pad, y), line,
			HORIZONTAL_ALIGNMENT_LEFT, size.x - pad * 2.0, 12, Color(0.8, 0.83, 0.88)
		)
		y += 22.0

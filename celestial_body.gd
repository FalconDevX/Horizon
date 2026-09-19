@tool
extends Node2D

const GLOW_TEXTURE := preload("res://textures/glow.png")

@export var radius: float = 20.0:
	set(value):
		radius = value
		queue_redraw()

@export var visual_radius := 0.0:
	set(value):
		visual_radius = value
		queue_redraw()

@export var color: Color = Color.GREEN:
	set(value):
		color = value
		queue_redraw()

@export var mass: float = 1.0

@export var body_name: String = "Unnamed"

@export var show_soi := false:
	set(value):
		show_soi = value
		queue_redraw()

@export var soi_radius := 0.0:
	set(value):
		soi_radius = value
		queue_redraw()

@export var soi_line_width := 1.0:
	set(value):
		soi_line_width = value
		queue_redraw()

var velocity: Vector2 = Vector2.ZERO


func _draw() -> void:
	var draw_radius: float = radius

	if visual_radius > 0.0:
		draw_radius = visual_radius

	_draw_glow(draw_radius)
	draw_circle(Vector2.ZERO, draw_radius, color)

	if show_soi and soi_radius > 0.0:
		draw_arc(
			Vector2.ZERO,
			soi_radius,
			0.0,
			TAU,
			128,
			Color(1, 1, 1, 0.15),
			soi_line_width
		)


func _draw_glow(draw_radius: float) -> void:
	var diameter: float = draw_radius * 4.0
	var rect := Rect2(Vector2(-diameter, -diameter) * 0.5, Vector2(diameter, diameter))
	draw_texture_rect(GLOW_TEXTURE, rect, false, Color(color, 0.6))

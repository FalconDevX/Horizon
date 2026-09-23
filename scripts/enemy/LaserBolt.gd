class_name LaserBolt
extends Node2D
## Glowing laser bolt fired by enemies - travels forward and fades out.
## Purely visual for now; no damage/hit detection yet.

@export var velocity: Vector2 = Vector2.ZERO
@export var lifetime: float = 2.0
@export var length: float = 14.0
@export var width: float = 2.2
@export var color: Color = Color(1.0, 0.15, 0.1, 0.95)

const FADE_START_FRACTION := 0.55 ## Alpha starts easing to 0 once this much of lifetime has passed.

var _age := 0.0


func _process(delta: float) -> void:
	_age += delta
	if _age >= lifetime:
		queue_free()
		return
	position += velocity * delta
	queue_redraw()


func _draw() -> void:
	var dir := velocity.normalized() if velocity.length() > 0.001 else Vector2.RIGHT
	var tail := -dir * length
	var fade_start := lifetime * FADE_START_FRACTION
	var alpha_mul := 1.0
	if _age > fade_start:
		alpha_mul = 1.0 - clampf((_age - fade_start) / (lifetime - fade_start), 0.0, 1.0)
	var c := Color(color, color.a * alpha_mul)
	draw_line(Vector2.ZERO, tail, Color(c, c.a * 0.35), width * 2.5)
	draw_line(Vector2.ZERO, tail, c, width)
	draw_circle(Vector2.ZERO, width * 0.9, c)

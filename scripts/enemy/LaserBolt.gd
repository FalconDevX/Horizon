class_name LaserBolt
extends Node2D
## Glowing laser bolt fired by enemies - travels forward and fades out.
## Hits enemies that explode_on_hit (kamikaze), and the player's ship.

@export var velocity: Vector2 = Vector2.ZERO
@export var lifetime: float = 2.0
@export var length: float = 14.0
@export var width: float = 2.2
@export var color: Color = Color(1.0, 0.15, 0.1, 0.95)
## What a hit would take off, set by the firing enemy.
@export var damage: float = 10.0

const FADE_START_FRACTION := 0.55 ## Alpha starts easing to 0 once this much of lifetime has passed.

var _age := 0.0
## Skip self-hits for the ship that just fired (set by Enemy.fire_laser).
var ignore_enemy: Enemy = null


func _process(delta: float) -> void:
	_age += delta
	if _age >= lifetime:
		queue_free()
		return
	var previous: Vector2 = position
	position += velocity * delta
	if _try_hit_segment(previous, position):
		return
	queue_redraw()


func _try_hit_segment(from: Vector2, to: Vector2) -> bool:
	var parent := get_parent()
	if parent == null:
		return false
	for child in parent.get_children():
		if child == ignore_enemy:
			continue
		if child is Enemy:
			var enemy := child as Enemy
			if not enemy.is_hittable():
				continue
			if _segment_hits_circle(from, to, enemy.position, enemy.collision_radius):
				enemy.take_hit(damage)
				queue_free()
				return true
		elif child.name == "Ship" and child is Node2D and child.has_method("take_damage"):
			var ship := child as Node2D
			if _segment_hits_circle(from, to, ship.position, float(ship.get("collision_radius"))):
				ship.call("take_damage", damage)
				queue_free()
				return true
	return false


static func _segment_hits_circle(a: Vector2, b: Vector2, center: Vector2, radius: float) -> bool:
	var ab: Vector2 = b - a
	var ac: Vector2 = center - a
	var ab_len_sq: float = ab.length_squared()
	var t: float = 0.0 if ab_len_sq < 0.0001 else clampf(ac.dot(ab) / ab_len_sq, 0.0, 1.0)
	var closest: Vector2 = a + ab * t
	return closest.distance_squared_to(center) <= radius * radius


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

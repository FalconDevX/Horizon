class_name DamageZone
extends Node2D
## Persistent damage field (minelayer). Ticks DPS on the player ship and on
## hittable sandbox enemies inside its radius.

@export var radius: float = 140.0
@export var damage_per_second: float = 28.0
@export var lifetime: float = 14.0
@export var color: Color = Color(0.95, 0.35, 0.12, 0.35)

var ignore_enemy: Enemy = null
var _age := 0.0


func _init() -> void:
	# Moved by hand in _process, not in physics ticks.
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF


func _process(delta: float) -> void:
	_age += delta
	if _age >= lifetime:
		queue_free()
		return
	_tick_damage(delta)
	queue_redraw()


func _tick_damage(delta: float) -> void:
	var amount: float = damage_per_second * delta
	var parent := get_parent()
	if parent == null:
		return
	for child in parent.get_children():
		if child == ignore_enemy or child == self:
			continue
		if child is Enemy:
			var enemy := child as Enemy
			if enemy.is_hittable() and _in_radius(enemy.global_position):
				enemy.take_hit(amount)
		elif child.name == "Ship" and child is Node2D:
			var ship := child as Node2D
			if _in_radius(ship.global_position):
				_damage_ship(ship, amount)


func _in_radius(world_pos: Vector2) -> bool:
	return global_position.distance_squared_to(world_pos) <= radius * radius


func _damage_ship(ship: Node2D, amount: float) -> void:
	if ship.has_method("take_damage"):
		ship.call("take_damage", amount)


func _draw() -> void:
	var t: float = Time.get_ticks_msec() / 1000.0
	var pulse: float = 0.85 + 0.15 * sin(t * 6.0)
	var fade: float = 1.0
	if _age > lifetime - 1.5:
		fade = clampf((lifetime - _age) / 1.5, 0.0, 1.0)
	var fill := Color(color, color.a * 0.45 * pulse * fade)
	var edge := Color(color.r, color.g, color.b, 0.75 * pulse * fade)
	draw_circle(Vector2.ZERO, radius, fill)
	draw_arc(Vector2.ZERO, radius, 0.0, TAU, 48, edge, 2.0)
	draw_arc(Vector2.ZERO, radius * (0.55 + 0.08 * sin(t * 4.0)), 0.0, TAU, 32, Color(edge, edge.a * 0.5), 1.2)

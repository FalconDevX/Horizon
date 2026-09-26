class_name SniperBeam
extends Node2D
## Long straight laser fired by the sniper enemy: it shoots out to its full
## range in a blink, then thins and fades where it was fired. Hits kamikaze
## enemies along the beam on the first frame. Widths are screen pixels, so
## it reads the same at any zoom.

## Beam direction (unit) and reach in world units.
var direction: Vector2 = Vector2.RIGHT
var reach: float = 12000.0
var lifetime: float = 0.9
var damage: float = 60.0
var glow_color: Color = Color(1.0, 0.78, 0.12)
var core_color: Color = Color(1.0, 0.97, 0.75)
## Share of the lifetime the beam takes to reach full length.
var grow_fraction: float = 0.08
## Skip the sniper that fired this beam.
var ignore_enemy: Enemy = null
## False for the player's own beams: they never hurt the player's ship.
var hits_player: bool = true
## When set, the beam's root rides along with this node (the player's ship),
## `carrier_offset` off its position in its unrotated frame.
var carrier: Node2D = null
var carrier_offset: Vector2 = Vector2.ZERO

var _age := 0.0
var _did_hit_check := false


func _init() -> void:
	# Moved by hand in _process, not in physics ticks.
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF


func _process(delta: float) -> void:
	_age += delta
	if carrier != null and is_instance_valid(carrier):
		global_position = carrier.global_position + carrier_offset.rotated(carrier.rotation)
	if not _did_hit_check:
		_did_hit_check = true
		_hit_along_beam()
	if _age >= lifetime:
		queue_free()
		return
	queue_redraw()


func _hit_along_beam() -> void:
	var parent := get_parent()
	if parent == null:
		return
	var tip: Vector2 = global_position + direction * reach
	for child in parent.get_children():
		if child == ignore_enemy:
			continue
		if child is Enemy:
			var enemy := child as Enemy
			if not enemy.is_hittable():
				continue
			if LaserBolt._segment_hits_circle(
				global_position, tip, enemy.global_position, enemy.collision_radius
			):
				enemy.take_hit(damage)
		elif hits_player and child.name == "Ship" and child is Node2D and child.has_method("take_damage"):
			var ship := child as Node2D
			if LaserBolt._segment_hits_circle(
				global_position, tip, ship.global_position, float(ship.get("collision_radius"))
			):
				ship.call("take_damage", damage)


func _draw() -> void:
	var t: float = _age / lifetime
	var grow: float = clampf(t / grow_fraction, 0.0, 1.0)
	var fade: float = 1.0 - smoothstep(grow_fraction, 1.0, t)
	var px: float = 1.0 / maxf(get_global_transform_with_canvas().get_scale().x, 0.0001)
	var tip: Vector2 = direction * reach * grow
	# Wide soft glow, a bright band, then a white-hot core.
	draw_line(Vector2.ZERO, tip, Color(glow_color, 0.1 * fade), 18.0 * px * (0.5 + 0.5 * fade))
	draw_line(Vector2.ZERO, tip, Color(glow_color, 0.25 * fade), 9.0 * px * (0.5 + 0.5 * fade))
	draw_line(Vector2.ZERO, tip, Color(glow_color, 0.8 * fade), 4.0 * px * (0.4 + 0.6 * fade))
	draw_line(Vector2.ZERO, tip, Color(core_color, fade), 1.8 * px)
	# Muzzle flash.
	var flash: float = 1.0 - smoothstep(0.0, 0.35, t)
	if flash > 0.0:
		draw_circle(Vector2.ZERO, 12.0 * px * flash, Color(glow_color, 0.45 * flash))
		draw_circle(Vector2.ZERO, 5.0 * px * flash, Color(core_color, 0.9 * flash))

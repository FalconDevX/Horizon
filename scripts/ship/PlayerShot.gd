class_name PlayerShot
extends Node2D
## One projectile fired by the player's ship: it flies straight on (with the
## ship's own velocity added), hits the first enemy it crosses, and a `ball`
## blows up - on a hit or at the end of its reach - hurting every enemy in
## its blast. Spawned by solar_system.gd from the weapons' FX table below.
## A bolt fades out over the last FADE_FROM share of its reach.
## Sizes are in screen pixels, so shots read at any zoom.

## How each weapon fires. speed in SU/s; length / width / radius in screen
## px; pellets and spread (degrees) for a shotgun; burst = shots per trigger
## pull, burst_gap seconds apart; barrels = how many muzzles take turns.
const FX := {
	&"weapon_laser": {"kind": "bolt", "speed": 3200.0, "color": Color(1.0, 0.12, 0.1), "length": 16.0, "width": 1.6, "spread": 6.0},
	&"weapon_gauss": {"kind": "bolt", "speed": 2400.0, "color": Color(1.0, 0.6, 0.25), "length": 20.0, "width": 2.4},
	&"weapon_railgun": {"kind": "bolt", "speed": 5200.0, "color": Color(0.35, 0.7, 1.0), "length": 44.0, "width": 4.5, "barrels": 2},
	&"weapon_coilgun": {"kind": "bolt", "speed": 1900.0, "color": Color(0.45, 0.8, 1.0), "length": 7.0, "width": 2.0, "pellets": 9, "spread": 30.0},
	&"weapon_particle": {"kind": "ball", "speed": 900.0, "color": Color(0.35, 0.65, 1.0), "radius": 6.0, "blast": 90.0},
	&"weapon_revolver": {"kind": "bolt", "speed": 2600.0, "color": Color(1.0, 0.8, 0.35), "length": 14.0, "width": 3.0, "burst": 5, "burst_gap": 0.09},
	&"weapon_rockets": {"kind": "ball", "speed": 1300.0, "color": Color(1.0, 0.5, 0.2), "radius": 3.5, "blast": 60.0},
	&"weapon_drones": {"kind": "bolt", "speed": 1500.0, "color": Color(0.6, 1.0, 0.6), "length": 8.0, "width": 2.0},
}
## Every shot flies this much faster than its FX speed says - the reaches
## went up 3x (ModuleCatalog.WEAPON_RANGE_SCALE) and ships fly faster.
const SPEED_SCALE := 2.0
const DEFAULT_FX := {"kind": "bolt", "speed": 2200.0, "color": Color(1.0, 0.55, 0.2), "length": 14.0, "width": 2.0}

var velocity := Vector2.ZERO
var damage: float = 10.0
## How far it may fly before it fades (a bolt) or blows up (a ball).
var max_distance: float = 1000.0
var fx: Dictionary = DEFAULT_FX
## The enemy the player is flying (never hit by their own ship's shots).
var ignore: Node = null

var _travelled: float = 0.0
## A ball after it went off: seconds into its blast, or -1 while flying.
var _blast_age: float = -1.0
const BLAST_TIME := 0.35
const FADE_FROM := 0.6


func _init() -> void:
	# Moved by hand every frame: physics interpolation would draw the first
	# frame somewhere between the world origin and the muzzle.
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF


static func fx_for(weapon_id: StringName) -> Dictionary:
	return FX.get(weapon_id, DEFAULT_FX)


func _process(delta: float) -> void:
	# Game time: shots stop on pause.
	var scale: float = float(get_parent().get("time_scale")) if get_parent() != null else 1.0
	var dt: float = delta * minf(scale, 1.0)
	if _blast_age >= 0.0:
		_blast_age += delta
		if _blast_age >= BLAST_TIME:
			queue_free()
		queue_redraw()
		return
	if dt <= 0.0:
		return
	var previous: Vector2 = position
	position += velocity * dt
	_travelled += (velocity * dt).length()
	var hit: Enemy = _first_enemy_on(previous, position)
	if hit != null:
		if fx["kind"] == "ball":
			position = hit.position
			_explode()
		else:
			hit.take_hit(damage)
			queue_free()
		return
	if _travelled >= max_distance:
		if fx["kind"] == "ball":
			_explode()
		else:
			queue_free()
		return
	queue_redraw()


func _first_enemy_on(from: Vector2, to: Vector2) -> Enemy:
	var best: Enemy = null
	var best_d := INF
	for child in get_parent().get_children():
		if not (child is Enemy) or child == ignore or not (child as Enemy).is_alive():
			continue
		var enemy := child as Enemy
		var reach: float = enemy.hit_radius() + (float(fx.get("radius", 0.0)) * _px())
		if LaserBolt._segment_hits_circle(from, to, enemy.position, reach):
			var d: float = from.distance_squared_to(enemy.position)
			if d < best_d:
				best_d = d
				best = enemy
	return best


func _explode() -> void:
	var blast: float = float(fx.get("blast", 60.0))
	for child in get_parent().get_children():
		if child is Enemy and child != ignore and (child as Enemy).is_alive():
			var enemy := child as Enemy
			if enemy.position.distance_to(position) <= blast + enemy.hit_radius():
				enemy.take_hit(damage)
	_blast_age = 0.0
	queue_redraw()


## World units per screen pixel right now.
func _px() -> float:
	return 1.0 / maxf(get_global_transform_with_canvas().get_scale().x, 0.0001)


func _draw() -> void:
	var px: float = _px()
	var color: Color = fx["color"]
	if _blast_age >= 0.0:
		var t: float = _blast_age / BLAST_TIME
		var blast: float = float(fx.get("blast", 60.0))
		draw_circle(Vector2.ZERO, blast * (0.4 + 0.6 * t), Color(color, 0.35 * (1.0 - t)))
		draw_arc(Vector2.ZERO, blast * (0.4 + 0.6 * t), 0.0, TAU, 40, Color(1.0, 1.0, 1.0, 0.8 * (1.0 - t)), 2.0 * px)
		return
	if fx["kind"] == "ball":
		var r: float = float(fx.get("radius", 5.0)) * px
		draw_circle(Vector2.ZERO, r * 2.2, Color(color, 0.25))
		draw_circle(Vector2.ZERO, r, color)
		draw_circle(Vector2.ZERO, r * 0.45, Color(1.0, 1.0, 1.0, 0.9))
		return
	var dir: Vector2 = velocity.normalized() if velocity.length_squared() > 0.0 else Vector2.RIGHT
	var tail: Vector2 = -dir * float(fx.get("length", 14.0)) * px
	var width: float = float(fx.get("width", 2.0)) * px
	var fade: float = 1.0 - smoothstep(FADE_FROM, 1.0, _travelled / maxf(max_distance, 1.0))
	draw_line(tail, Vector2.ZERO, Color(color, 0.35 * fade), width * 2.2)
	draw_line(tail, Vector2.ZERO, Color(color, fade), width)
	draw_line(tail * 0.5, Vector2.ZERO, Color(1.0, 1.0, 1.0, 0.85 * fade), width * 0.45)

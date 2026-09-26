class_name ExplosionFX
extends RefCounted
## A blast drawn by hand onto any CanvasItem, one frame at a time from `t`
## (0 at the bang .. 1 gone): a white flash, a glow, a fireball of puffs that
## cool from white through yellow and the tint to dark red and smoke, sparks
## streaking out, tumbling debris, a shockwave ring and smoke that lingers.
## Every particle's direction and speed come from `seed`, so a blast draws
## the same each frame. Enemy.gd (a ship going up) and PlayerShot.gd (a
## ball's blast, a bolt's hit) draw with it.

const WHITE := Color(1.0, 0.98, 0.92)
const YELLOW := Color(1.0, 0.85, 0.35)
const EMBER := Color(0.55, 0.1, 0.04)
const SMOKE := Color(0.16, 0.15, 0.15)
const DEBRIS := Color(0.12, 0.11, 0.11)


## Draws the blast at `centre` on `canvas`. `radius` is how far the fireball
## reaches (canvas units), `px` one screen pixel in canvas units (line
## widths), `tint` the fire's own colour (orange for fuel, blue for plasma),
## `detail` 0..1 how many particles (a bolt's hit is small), `debris` whether
## pieces of hull fly out.
static func draw(
	canvas: CanvasItem, centre: Vector2, t: float, radius: float, seed: int, px: float,
	tint: Color = Color(1.0, 0.45, 0.12), detail: float = 1.0, debris: bool = true
) -> void:
	t = clampf(t, 0.0, 1.0)
	if t >= 1.0:
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var out: float = 1.0 - pow(1.0 - t, 3.0)
	var fade: float = 1.0 - t

	# The glow lighting up space around it: soft, rings of falling alpha.
	var glow: float = radius * (1.1 + 0.7 * out)
	for k in 6:
		var share: float = 1.0 - k / 6.0
		canvas.draw_circle(centre, glow * share, Color(tint, 0.05 * fade * fade * (0.4 + k * 0.25)))

	# Smoke, late and slow, behind the fire.
	var smoke_count: int = roundi(8 * detail)
	for i in smoke_count:
		var dir := Vector2.from_angle(rng.randf() * TAU)
		var reach: float = rng.randf_range(0.2, 0.7)
		var start: float = rng.randf_range(0.15, 0.35)
		var life: float = clampf((t - start) / (1.0 - start), 0.0, 1.0)
		if life <= 0.0:
			continue
		var r: float = radius * rng.randf_range(0.3, 0.5) * (0.6 + 0.8 * life)
		var a: float = 0.35 * sin(life * PI)
		canvas.draw_circle(centre + dir * radius * reach * (0.5 + out), r, Color(SMOKE, a))

	# The fireball: puffs blown outward, cooling as they go.
	var puffs: int = maxi(roundi(11 * detail), 3)
	for i in puffs:
		var dir := Vector2.from_angle(rng.randf() * TAU)
		var reach: float = rng.randf_range(0.1, 0.85)
		var size: float = rng.randf_range(0.3, 0.55)
		var lag: float = rng.randf_range(0.0, 0.15)
		var life: float = clampf((t - lag) / (0.8 - lag), 0.0, 1.0)
		if life <= 0.0 or life >= 1.0:
			continue
		var grow: float = 1.0 - pow(1.0 - life, 2.0)
		var pos: Vector2 = centre + dir * radius * reach * grow
		var r: float = radius * size * (0.35 + 0.9 * grow)
		var colour: Color = _heat_colour(1.0 - life, tint)
		var a: float = pow(1.0 - life, 1.1)
		canvas.draw_circle(pos, r * 1.25, Color(colour, 0.25 * a))
		canvas.draw_circle(pos, r, Color(colour, 0.6 * a))
		canvas.draw_circle(pos, r * 0.55, Color(colour.lerp(WHITE, 0.45 * (1.0 - life)), 0.8 * a))

	# The flash, gone in a moment.
	if t < 0.22:
		var f: float = 1.0 - t / 0.22
		canvas.draw_circle(centre, radius * (0.35 + 0.5 * (1.0 - f)), Color(WHITE, 0.95 * f))
		canvas.draw_circle(centre, radius * 0.9, Color(YELLOW, 0.35 * f))

	# Sparks: streaks flying out, slowing, the tail shrinking.
	var sparks: int = maxi(roundi(20 * detail), 4)
	for i in sparks:
		var dir := Vector2.from_angle(rng.randf() * TAU)
		var speed: float = rng.randf_range(0.7, 1.6)
		var life: float = clampf(t / rng.randf_range(0.45, 0.8), 0.0, 1.0)
		if life >= 1.0:
			continue
		var travel: float = 1.0 - pow(1.0 - life, 2.5)
		var head: Vector2 = centre + dir * radius * 1.5 * speed * travel
		var tail: Vector2 = head - dir * radius * 0.35 * speed * (1.0 - life)
		var colour: Color = YELLOW.lerp(tint, life)
		canvas.draw_line(tail, head, Color(colour, 0.35 * (1.0 - life)), 3.5 * px, true)
		canvas.draw_line(tail, head, Color(colour.lerp(WHITE, 0.4), 0.95 * (1.0 - life)), 1.4 * px, true)

	# Debris: dark shards tumbling out, glowing hot at first.
	if debris:
		for i in roundi(7 * detail):
			var dir := Vector2.from_angle(rng.randf() * TAU)
			var speed: float = rng.randf_range(0.5, 1.1)
			var spin: float = rng.randf_range(-12.0, 12.0)
			var size: float = radius * rng.randf_range(0.07, 0.14)
			var pos: Vector2 = centre + dir * radius * 1.3 * speed * out
			var turn: float = rng.randf() * TAU + spin * t
			var shard := PackedVector2Array([
				pos + Vector2.from_angle(turn) * size,
				pos + Vector2.from_angle(turn + 2.3) * size * 0.7,
				pos + Vector2.from_angle(turn + 4.0) * size * 0.9,
			])
			var a: float = clampf(1.5 * fade, 0.0, 1.0)
			canvas.draw_colored_polygon(shard, Color(DEBRIS.lerp(tint, 0.6 * fade * fade), a))
			if t < 0.6:
				canvas.draw_circle(pos, size * 0.4, Color(YELLOW, 0.8 * (1.0 - t / 0.6)))

	# The shockwave: a thin ring racing ahead of the fire.
	var wave: float = 1.0 - pow(1.0 - t, 4.0)
	var ring: float = radius * (0.3 + 1.9 * wave)
	canvas.draw_arc(centre, ring, 0.0, TAU, 64, Color(tint, 0.25 * fade * fade), 5.0 * px, true)
	canvas.draw_arc(centre, ring, 0.0, TAU, 64, Color(WHITE.lerp(tint, t), 0.65 * fade * fade), 1.5 * px, true)
	if detail >= 0.5:
		canvas.draw_arc(centre, ring * 0.8, 0.0, TAU, 40, Color(tint, 0.3 * fade * fade), 1.0 * px, true)


## White hot (1) through yellow and the tint to dark red embers and smoke (0).
static func _heat_colour(heat: float, tint: Color) -> Color:
	if heat > 0.8:
		return YELLOW.lerp(WHITE, (heat - 0.8) / 0.2)
	if heat > 0.55:
		return tint.lerp(YELLOW, (heat - 0.55) / 0.25)
	# Embers keep a trace of the tint (plasma dies blue, fuel red).
	var ember: Color = EMBER.lerp(tint.darkened(0.6), 0.5)
	if heat > 0.25:
		return ember.lerp(tint, (heat - 0.25) / 0.3)
	return SMOKE.lerp(ember, heat / 0.25)

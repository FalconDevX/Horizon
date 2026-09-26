class_name MissileCatalog
extends RefCounted
## The Rocket Launcher's missiles, from the Horizon Miro board ("Moduły
## statku": Standard missile, AOE, Interceptor, EMP, Hunter). Missiles are
## cargo: they sit in the hold (PlayerProgress.inventory) under these ids and
## a launcher loads them from there (ship.gd, MAGAZINE at a time); in god mode
## every type is there without end.
##
## Missiles reach far - much further than any gun - each type its own way.
## Per type: range (SU it flies, and the furthest a launcher fires it at),
## speed (SU/s, the ship's own speed is added at launch), tracking (1-5, how
## hard it can turn onto its target - `turn` in rad/s follows from it),
## damage (times the launcher's) and damage_kind (words for the hold),
## blast (world units hurt round the burst), fuse (goes off this close to its
## target, 0 = only on contact), emp (seconds a hit enemy stays dead in space,
## guns off). Every missile flies only at the locked target it was fired at.
## `look` shapes its picture (draw_icon).

const TYPES := {
	&"missile_standard": {
		"name": "Standard missile", "short": "STD", "color": Color(1.0, 0.55, 0.22),
		"range": 45000.0, "speed": 2600.0, "tracking": 3, "turn": 2.4,
		"damage": 1.0, "damage_kind": "Explosive", "blast": 60.0, "fuse": 0.0,
		"note": "A plain long-range missile homing on the locked target. Heavy hit.",
		"look": {"body": 0.13, "nose": 0.24, "fins": "rear", "bands": 1},
	},
	&"missile_aoe": {
		"name": "AOE missile", "short": "AOE", "color": Color(1.0, 0.82, 0.25),
		"range": 36000.0, "speed": 2400.0, "tracking": 2, "turn": 1.8,
		"damage": 0.75, "damage_kind": "Explosive, area", "blast": 320.0, "fuse": 240.0,
		"note": "Bursts once it is close to its target and hurts everything round it. A little less damage than a standard missile.",
		"look": {"body": 0.14, "nose": 0.2, "warhead": 0.2, "fins": "rear", "hazard": true},
	},
	&"missile_interceptor": {
		"name": "Interceptor", "short": "INT", "color": Color(0.4, 0.85, 1.0),
		"range": 28000.0, "speed": 4200.0, "tracking": 4, "turn": 5.0,
		"damage": 0.45, "damage_kind": "Kinetic", "blast": 40.0, "fuse": 0.0,
		"note": "Fast and nimble, it turns hard after a locked target. Light damage, the shortest reach of the missiles.",
		"look": {"body": 0.09, "nose": 0.3, "fins": "long", "canards": true, "bands": 2},
	},
	&"missile_emp": {
		"name": "EMP missile", "short": "EMP", "color": Color(0.55, 0.6, 1.0),
		"range": 38000.0, "speed": 2600.0, "tracking": 3, "turn": 2.4,
		"damage": 0.0, "damage_kind": "EMP, no damage", "blast": 90.0, "fuse": 0.0,
		"emp": 30.0,
		"note": "No damage. The target it hits drifts dead, guns off, for 30 seconds.",
		"look": {"body": 0.14, "nose": 0.18, "fins": "rear", "coils": 3, "antenna": true},
	},
	&"missile_hunter": {
		"name": "Hunter", "short": "HNT", "color": Color(1.0, 0.3, 0.35),
		"range": 75000.0, "speed": 1700.0, "tracking": 5, "turn": 6.5,
		"damage": 1.6, "damage_kind": "Heavy explosive", "blast": 70.0, "fuse": 0.0,
		"note": "Slow, but it tracks its prey relentlessly and reaches the furthest. Big damage.",
		"look": {"body": 0.16, "nose": 0.22, "fins": "big", "canards": true, "eye": true, "bands": 1},
	},
}
## In the picker and when nothing else is known.
const DEFAULT := &"missile_standard"
## A new game starts with this many standard missiles in the hold.
const STARTER_STOCK := 6

const METAL := Color(0.78, 0.82, 0.87)
const METAL_DARK := Color(0.42, 0.46, 0.53)
const METAL_LIGHT := Color(0.95, 0.97, 1.0)
const NOZZLE := Color(0.22, 0.24, 0.28)


static func has(id: StringName) -> bool:
	return TYPES.has(id)


static func info(id: StringName) -> Dictionary:
	return TYPES.get(id, TYPES[DEFAULT])


static func ids() -> Array:
	return TYPES.keys()


## The longest reach of any missile: how far a Rocket Launcher can fire.
static func max_range() -> float:
	var reach := 0.0
	for id: StringName in TYPES:
		reach = maxf(reach, float(TYPES[id]["range"]))
	return reach


## How many of `id` a launcher can draw on: the hold's count, or -1 (no end)
## in god mode.
static func stock(id: StringName) -> int:
	if PlayerProgress.god_mode:
		return -1
	return PlayerProgress.amount(id)


## A side-on missile, nose to +x, `length` long, centred on `at`: exhaust,
## nozzle, a shaded body with panel seams and coloured bands, fins, and the
## type's own parts (hazard-striped warhead, EMP coils and aerial, canards,
## a seeker eye). For the module rack's list, the cargo hold and in flight.
static func draw_icon(canvas: CanvasItem, at: Vector2, length: float, id: StringName, flame: bool = true) -> void:
	var data: Dictionary = info(id)
	var look: Dictionary = data["look"]
	var colour: Color = data["color"]
	var l: float = length
	var r: float = l * float(look.get("body", 0.13)) * 0.5
	var tail_x: float = at.x - l * 0.5
	var nose_len: float = l * float(look.get("nose", 0.24))
	var nose_x: float = at.x + l * 0.5
	var shoulder_x: float = nose_x - nose_len
	var y: float = at.y

	# Exhaust plume.
	if flame:
		canvas.draw_colored_polygon(PackedVector2Array([
			Vector2(tail_x, y - r * 0.8), Vector2(tail_x - l * 0.34, y), Vector2(tail_x, y + r * 0.8),
		]), Color(1.0, 0.45, 0.15, 0.55))
		canvas.draw_colored_polygon(PackedVector2Array([
			Vector2(tail_x, y - r * 0.5), Vector2(tail_x - l * 0.2, y), Vector2(tail_x, y + r * 0.5),
		]), Color(1.0, 0.85, 0.45, 0.9))

	# Rear fins (under the body), by kind.
	var fin_colour: Color = METAL_DARK
	match str(look.get("fins", "rear")):
		"big":
			_fin(canvas, tail_x + l * 0.02, l * 0.22, r, r * 3.2, y, fin_colour)
		"long":
			_fin(canvas, tail_x + l * 0.02, l * 0.3, r, r * 2.2, y, fin_colour)
		_:
			_fin(canvas, tail_x + l * 0.02, l * 0.16, r, r * 2.5, y, fin_colour)

	# Nozzle.
	canvas.draw_colored_polygon(PackedVector2Array([
		Vector2(tail_x + l * 0.04, y - r), Vector2(tail_x, y - r * 0.75),
		Vector2(tail_x, y + r * 0.75), Vector2(tail_x + l * 0.04, y + r),
	]), NOZZLE)

	# Body: a cylinder shaded top to bottom.
	var body_from: float = tail_x + l * 0.04
	var body := Rect2(Vector2(body_from, y - r), Vector2(shoulder_x - body_from, r * 2.0))
	canvas.draw_rect(body, METAL)
	canvas.draw_rect(Rect2(body.position, Vector2(body.size.x, r * 0.45)), METAL_LIGHT)
	canvas.draw_rect(Rect2(Vector2(body.position.x, y + r * 0.45), Vector2(body.size.x, r * 0.55)), METAL_DARK)
	# Panel seams.
	for k in 3:
		var sx: float = body.position.x + body.size.x * (0.28 + 0.24 * k)
		canvas.draw_line(Vector2(sx, y - r), Vector2(sx, y + r), Color(METAL_DARK, 0.8), maxf(l * 0.008, 0.6))

	# AOE: a fat, hazard-striped warhead behind the nose.
	var warhead: float = l * float(look.get("warhead", 0.0))
	if warhead > 0.0:
		var wr: float = r * 1.45
		var wx: float = shoulder_x - warhead
		canvas.draw_colored_polygon(PackedVector2Array([
			Vector2(wx - l * 0.03, y - r), Vector2(wx, y - wr), Vector2(shoulder_x, y - wr),
			Vector2(shoulder_x, y + wr), Vector2(wx, y + wr), Vector2(wx - l * 0.03, y + r),
		]), colour)
		if look.get("hazard", false):
			var stripe: float = warhead / 5.0
			for k in 5:
				if k % 2 == 1:
					var x0: float = wx + stripe * k
					canvas.draw_colored_polygon(PackedVector2Array([
						Vector2(x0, y - wr), Vector2(x0 + stripe, y - wr),
						Vector2(x0 + stripe * 0.4, y + wr), Vector2(x0 - stripe * 0.6, y + wr),
					]), Color(0.12, 0.1, 0.08))
		canvas.draw_rect(Rect2(Vector2(wx, y - wr), Vector2(warhead, wr * 0.4)), Color(1.0, 1.0, 1.0, 0.22))
		r = wr

	# Type-colour bands round the body.
	for k in int(look.get("bands", 0)):
		var bx: float = body.position.x + body.size.x * (0.12 + 0.1 * k)
		canvas.draw_rect(Rect2(Vector2(bx, y - r), Vector2(l * 0.035, r * 2.0)), colour)

	# EMP: copper coils round the body and an aerial.
	for k in int(look.get("coils", 0)):
		var cx: float = body.position.x + body.size.x * (0.5 + 0.12 * k)
		canvas.draw_rect(Rect2(Vector2(cx, y - r * 1.2), Vector2(l * 0.04, r * 2.4)), Color(0.85, 0.55, 0.25))
		canvas.draw_rect(Rect2(Vector2(cx, y - r * 1.2), Vector2(l * 0.04, r * 0.5)), Color(1.0, 0.8, 0.5))
	if look.get("antenna", false):
		var ax: float = body.position.x + body.size.x * 0.35
		canvas.draw_line(Vector2(ax, y - r), Vector2(ax - l * 0.06, y - r * 3.0), METAL_DARK, maxf(l * 0.012, 0.8))
		canvas.draw_circle(Vector2(ax - l * 0.06, y - r * 3.0), maxf(l * 0.018, 0.8), colour)

	# Canards near the nose.
	if look.get("canards", false):
		var kx: float = shoulder_x - l * 0.1
		canvas.draw_colored_polygon(PackedVector2Array([
			Vector2(kx, y - r), Vector2(kx + l * 0.06, y - r), Vector2(kx + l * 0.01, y - r * 2.0),
		]), fin_colour)
		canvas.draw_colored_polygon(PackedVector2Array([
			Vector2(kx, y + r), Vector2(kx + l * 0.06, y + r), Vector2(kx + l * 0.01, y + r * 2.0),
		]), fin_colour)

	# Ogive nose in the type's colour, lit along its top.
	var nose := PackedVector2Array()
	var steps := 8
	for k in steps + 1:
		var t: float = float(k) / steps
		nose.append(Vector2(shoulder_x + nose_len * t, y - r * sqrt(maxf(1.0 - t * t, 0.0))))
	for k in range(steps, -1, -1):
		var t: float = float(k) / steps
		nose.append(Vector2(shoulder_x + nose_len * t, y + r * sqrt(maxf(1.0 - t * t, 0.0))))
	canvas.draw_colored_polygon(nose, colour)
	canvas.draw_colored_polygon(PackedVector2Array([
		Vector2(shoulder_x, y - r), Vector2(shoulder_x + nose_len * 0.7, y - r * 0.55),
		Vector2(shoulder_x + nose_len * 0.5, y - r * 0.25), Vector2(shoulder_x, y - r * 0.4),
	]), Color(1.0, 1.0, 1.0, 0.35))
	canvas.draw_line(Vector2(shoulder_x, y - r), Vector2(shoulder_x, y + r), Color(0.0, 0.0, 0.0, 0.35), maxf(l * 0.01, 0.6))

	# Hunter: a seeker eye at the tip.
	if look.get("eye", false):
		var eye := Vector2(nose_x - nose_len * 0.25, y)
		canvas.draw_circle(eye, r * 0.42, Color(0.1, 0.02, 0.03))
		canvas.draw_circle(eye, r * 0.26, Color(1.0, 0.25, 0.2))
		canvas.draw_circle(eye + Vector2(-r * 0.08, -r * 0.1), r * 0.09, Color(1.0, 0.9, 0.85))

	# Upper fin, seen edge-on over the body.
	canvas.draw_colored_polygon(PackedVector2Array([
		Vector2(tail_x + l * 0.03, y - r * 0.15), Vector2(tail_x + l * 0.14, y - r * 0.15),
		Vector2(tail_x + l * 0.1, y + r * 0.15), Vector2(tail_x + l * 0.03, y + r * 0.15),
	]), Color(METAL_DARK, 0.9))


## A pair of swept fins, top and bottom, from `x0` over `chord`.
static func _fin(canvas: CanvasItem, x0: float, chord: float, r: float, span: float, y: float, colour: Color) -> void:
	for side: float in [-1.0, 1.0]:
		canvas.draw_colored_polygon(PackedVector2Array([
			Vector2(x0, y + side * r * 0.9), Vector2(x0 + chord, y + side * r * 0.9),
			Vector2(x0 + chord * 0.35, y + side * span), Vector2(x0 - chord * 0.1, y + side * span),
		]), colour)
		canvas.draw_line(Vector2(x0 - chord * 0.1, y + side * span), Vector2(x0 + chord * 0.35, y + side * span),
			Color(1.0, 1.0, 1.0, 0.3), maxf(chord * 0.04, 0.5))

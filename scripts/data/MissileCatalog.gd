class_name MissileCatalog
extends RefCounted
## The Rocket Launcher's missiles, from the Horizon Miro board ("Moduły
## statku": Standard missile, AOE, Interceptor, EMP, Hunter). Missiles are
## cargo: they sit in the hold (PlayerProgress.inventory) under these ids and
## a launcher loads them from there (ship.gd, MAGAZINE at a time); in god mode
## every type is there without end.
##
## Per type: speed (SU/s, the ship's own speed is added at launch), turn
## (rad/s it can swing toward its target), damage (times the launcher's),
## blast (world units hurt round the burst), fuse (goes off this close to its
## target, 0 = only on contact), emp (seconds a hit enemy stays dead in space,
## guns off), seek (finds a target of its own when fired without one), life
## (share of the launcher's reach it flies before it bursts).

const TYPES := {
	&"missile_standard": {
		"name": "Standard missile", "short": "STD", "color": Color(1.0, 0.55, 0.22),
		"speed": 2600.0, "turn": 2.4, "damage": 1.0, "blast": 60.0, "fuse": 0.0,
		"life": 1.2,
		"note": "A plain homing missile. Heavy hit, small blast.",
	},
	&"missile_aoe": {
		"name": "AOE missile", "short": "AOE", "color": Color(1.0, 0.82, 0.25),
		"speed": 2400.0, "turn": 2.0, "damage": 0.75, "blast": 320.0, "fuse": 240.0,
		"life": 1.2,
		"note": "Bursts once it is close to its target and hurts everything round it. A little less damage than a standard missile.",
	},
	&"missile_interceptor": {
		"name": "Interceptor", "short": "INT", "color": Color(0.4, 0.85, 1.0),
		"speed": 4200.0, "turn": 5.5, "damage": 0.45, "blast": 40.0, "fuse": 0.0,
		"seek": true, "life": 0.9,
		"note": "Fast and nimble; finds the nearest enemy by itself. Light damage.",
	},
	&"missile_emp": {
		"name": "EMP missile", "short": "EMP", "color": Color(0.55, 0.6, 1.0),
		"speed": 2600.0, "turn": 2.4, "damage": 0.0, "blast": 90.0, "fuse": 0.0,
		"emp": 30.0, "life": 1.2,
		"note": "No damage. The target it hits drifts dead, guns off, for 30 seconds.",
	},
	&"missile_hunter": {
		"name": "Hunter", "short": "HNT", "color": Color(1.0, 0.3, 0.35),
		"speed": 1600.0, "turn": 6.5, "damage": 1.6, "blast": 70.0, "fuse": 0.0,
		"seek": true, "life": 2.5,
		"note": "Slow, but it tracks its prey relentlessly. Big damage.",
	},
}
## In the picker and when nothing else is known.
const DEFAULT := &"missile_standard"
## A new game starts with this many standard missiles in the hold.
const STARTER_STOCK := 6


static func has(id: StringName) -> bool:
	return TYPES.has(id)


static func info(id: StringName) -> Dictionary:
	return TYPES.get(id, TYPES[DEFAULT])


static func ids() -> Array:
	return TYPES.keys()


## How many of `id` a launcher can draw on: the hold's count, or -1 (no end)
## in god mode.
static func stock(id: StringName) -> int:
	if PlayerProgress.god_mode:
		return -1
	return PlayerProgress.amount(id)


## A small side-on missile, nose to +x, `length` long, centred on `at` - for
## the module rack's picker and the cargo hold's icons.
static func draw_icon(canvas: CanvasItem, at: Vector2, length: float, id: StringName) -> void:
	var colour: Color = info(id)["color"]
	var half: float = length * 0.5
	var body: float = length * 0.11
	var nose := at + Vector2(half, 0.0)
	var tail := at - Vector2(half * 0.7, 0.0)
	# Fins, then the body, then the coloured warhead.
	canvas.draw_colored_polygon(PackedVector2Array([
		tail + Vector2(length * 0.12, 0.0), tail - Vector2(length * 0.16, body * 2.6), tail - Vector2(length * 0.02, 0.0),
	]), Color(0.55, 0.6, 0.68))
	canvas.draw_colored_polygon(PackedVector2Array([
		tail + Vector2(length * 0.12, 0.0), tail - Vector2(length * 0.16, -body * 2.6), tail - Vector2(length * 0.02, 0.0),
	]), Color(0.55, 0.6, 0.68))
	canvas.draw_rect(Rect2(tail - Vector2(0.0, body), Vector2(nose.x - tail.x - length * 0.2, body * 2.0)), Color(0.82, 0.86, 0.9))
	var head := Vector2(nose.x - length * 0.2, at.y)
	canvas.draw_colored_polygon(PackedVector2Array([
		head + Vector2(0.0, -body), nose, head + Vector2(0.0, body),
	]), colour)
	canvas.draw_rect(Rect2(head - Vector2(length * 0.06, body), Vector2(length * 0.06, body * 2.0)), colour)
	# Exhaust.
	canvas.draw_colored_polygon(PackedVector2Array([
		tail + Vector2(0.0, -body * 0.7), tail - Vector2(length * 0.22, 0.0), tail + Vector2(0.0, body * 0.7),
	]), Color(1.0, 0.7, 0.3, 0.85))

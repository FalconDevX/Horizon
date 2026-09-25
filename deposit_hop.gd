class_name DepositHop
extends DepositMotion

## Hopping like a slime jelly: it sits wobbling, squashes down, springs up
## and forward in a little arc, lands with a splat, and after a pause picks a
## slightly new way and goes again. A hop that would land on forbidden ground
## is cut short and the next one sets off somewhere else.

## Seconds between the start of one hop and the next.
const PERIOD := Vector2(1.4, 2.4)
## Share of each period spent in the air.
const AIRTIME := 0.35
## Radians of planet covered per hop.
const HOP := Vector2(0.004, 0.008)
## Peak height of a hop, in cluster units.
const HEIGHT := 0.8

var period: float
var hop: float
var clock: float


func start() -> void:
	period = rng.randf_range(PERIOD.x, PERIOD.y)
	hop = rng.randf_range(HOP.x, HOP.y)
	clock = rng.randf_range(0.0, period)


func update(ground: ResourceDeposits.Ground, delta: float, _time: float) -> void:
	clock += delta
	if clock >= period:
		clock = fmod(clock, period)
		# A new hop: set off a little to one side of the last.
		turn(rng.randf_range(-0.8, 0.8))
	if clock / period < AIRTIME and not walk(ground, hop * delta / (period * AIRTIME)):
		turn(rng.randf_range(PI * 0.6, PI * 1.4))


func pose(_time: float) -> Transform3D:
	var t: float = clock / period
	var lift := 0.0
	var squash := 1.0
	if t < AIRTIME:
		var arc: float = t / AIRTIME
		lift = HEIGHT * sin(arc * PI)
		# Stretched tall on the way up and down, round at the top.
		squash = 1.0 + 0.25 * cos(arc * TAU)
	else:
		# Settling: a splat on landing that wobbles out.
		var rest: float = (t - AIRTIME) / (1.0 - AIRTIME)
		squash = 1.0 - 0.3 * exp(-rest * 8.0) * cos(rest * 30.0)
	var wide: float = 1.0 / sqrt(maxf(squash, 0.3))
	return Transform3D(Basis.from_scale(Vector3(wide, squash, wide)), Vector3(0.0, lift, 0.0))


func animates() -> bool:
	return true

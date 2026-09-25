class_name DepositRoll
extends DepositMotion

## Rolling before the wind, like a tumbleweed: quick and mostly one way, the
## course wavering a little, bouncing as it goes and tumbling over and over.
## Blocked by liquid or a cliff, it swings round and rolls off another way.

## Radians of planet per second of game time.
const SPEED := Vector2(0.04, 0.08)
## How far the course wavers, radians of turn per second.
const WAVER := 0.25
## Bounce height, in cluster units.
const BOUNCE := 0.12

var speed: float
var phase: float
## Radians of planet rolled so far - what turns the ball over.
var rolled := 0.0


func start() -> void:
	speed = rng.randf_range(SPEED.x, SPEED.y)
	phase = rng.randf_range(0.0, TAU)


func update(ground: ResourceDeposits.Ground, delta: float, time: float) -> void:
	turn(sin(time * 0.3 + phase) * WAVER * delta)
	if walk(ground, speed * delta):
		rolled += speed * delta
	else:
		turn(rng.randf_range(PI * 0.6, PI * 1.4))


func pose(_time: float) -> Transform3D:
	# Over and over about its own left-right axis: a ball ~0.4 cluster units
	# across, a cluster ~0.045 planet radii, turns ~50 radians per radian rolled.
	var tumble: float = -rolled * 50.0
	var bounce: float = BOUNCE * absf(sin(rolled * 120.0 + phase))
	var centre := Vector3(0.0, 0.42, 0.0)
	return Transform3D(Basis(Vector3.RIGHT, tumble), Vector3(0.0, bounce, 0.0) + centre - Basis(Vector3.RIGHT, tumble) * centre)


func animates() -> bool:
	return true

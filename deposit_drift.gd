class_name DepositDrift
extends DepositMotion

## A slow, aimless slide: the cluster wanders over the ground on a meandering
## course, turning slowly on itself and bobbing a little, and swings round to
## a new course when it runs up against liquid or a cliff.

## Radians of planet per second of game time.
const SPEED := Vector2(0.012, 0.025)
## How hard the course meanders, radians of turn per second.
const MEANDER := 0.35
## Turning on itself, radians per second (either way).
const SPIN := Vector2(0.15, 0.4)
## Bob height, in cluster units.
const BOB := 0.06

var speed: float
var spin: float
var phase: float


func start() -> void:
	speed = rng.randf_range(SPEED.x, SPEED.y)
	spin = rng.randf_range(SPIN.x, SPIN.y) * (1.0 if rng.randf() < 0.5 else -1.0)
	phase = rng.randf_range(0.0, TAU)


func update(ground: ResourceDeposits.Ground, delta: float, time: float) -> void:
	# Two slow sines out of step make a course that wanders without looping.
	var meander: float = sin(time * 0.37 + phase) + 0.5 * sin(time * 0.91 + phase * 2.3)
	turn(meander * MEANDER * delta)
	if not walk(ground, speed * delta):
		turn(rng.randf_range(PI * 0.5, PI * 1.5))


func pose(time: float) -> Transform3D:
	return Transform3D(
		Basis(Vector3.UP, time * spin + phase),
		Vector3(0.0, BOB * sin(time * 1.3 + phase), 0.0)
	)


func animates() -> bool:
	return true

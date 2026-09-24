class_name DepositMotion
extends RefCounted

## How a resource deposit moves over its planet, and how it looks doing it.
## This base class stands still; every walk is a subclass. One instance per
## deposit, so a motion keeps whatever state it needs in its own vars.
##
## To add a walk: extend this, override what you need, register it in
## ResourceDeposits.MOTIONS and name it as a spawn's `motion` in SPAWNS.
##
## - start(): once, when the deposit is placed. Use `rng` (seeded from the
##   deposit) for anything random, so a world always sets off the same way.
## - update(): every frame of game time (stops on pause, speeds up under warp).
##   Move with walk() and turn() only - they keep the deposit on the sphere and
##   on ground its spawn rule allows (no liquid, cliffs, or wrong heights).
## - pose(): the body's offset from standing still, in the deposit's own frame
##   (+Y out of the ground, -Z the way it is heading) and in cluster units
##   (1 = its footprint). Bobs, waddles, hops, squashes and spins go here.
## - animates(): true if update() or pose() ever do anything, so still
##   deposits cost nothing per frame.

## Longest single step, in radians. Longer moves are split, so a deposit
## cannot hop over a lava channel under time warp.
const MAX_STEP := 0.004

## Where it stands, planet space, unit length.
var direction := Vector3.UP
## Which way it faces, tangent to the sphere at `direction`, unit length.
var heading := Vector3.FORWARD
var rng := RandomNumberGenerator.new()
## The deposit's entry in ResourceDeposits.SPAWNS: where it may go.
var rule: Dictionary = {}


## Called by ResourceDeposits when the deposit is placed.
func setup(at: Vector3, spawn_rule: Dictionary, motion_seed: int) -> void:
	rule = spawn_rule
	rng.seed = motion_seed
	direction = at.normalized()
	var helper := Vector3.UP if absf(direction.y) < 0.9 else Vector3.RIGHT
	heading = helper.cross(direction).normalized()
	turn(rng.randf_range(0.0, TAU))
	start()


func start() -> void:
	pass


func update(_ground: ResourceDeposits.Ground, _delta: float, _time: float) -> void:
	pass


func pose(_time: float) -> Transform3D:
	return Transform3D.IDENTITY


func animates() -> bool:
	return false


## Moves `distance` radians along the heading (backwards if negative),
## following the sphere. Stops short and returns false at the first step onto
## ground its rule does not allow; the deposit stays where it got to.
func walk(ground: ResourceDeposits.Ground, distance: float) -> bool:
	var left: float = absf(distance)
	var way: float = signf(distance)
	while left > 0.0:
		var angle: float = minf(left, MAX_STEP) * way
		var next: Vector3 = (direction * cos(angle) + heading * sin(angle)).normalized()
		if not ground.allows(rule, next):
			return false
		# Carry the heading along the great circle so it stays tangent.
		heading = (heading * cos(angle) - direction * sin(angle)).normalized()
		direction = next
		left -= MAX_STEP
	return true


## Turns the heading by `angle` radians (positive = anticlockwise seen from
## above the ground).
func turn(angle: float) -> void:
	heading = heading.rotated(direction, angle).normalized()

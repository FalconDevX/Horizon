class_name Maneuver
extends RefCounted

# A maneuver describes a physical velocity change, never a position change.
enum Direction { PROGRADE, RETROGRADE, RADIAL_OUT, RADIAL_IN }
enum Trigger { IMMEDIATE, PERIAPSIS, APOAPSIS }

var direction: Direction = Direction.PROGRADE
var trigger: Trigger = Trigger.IMMEDIATE
var delta_v: float = 0.0
var remaining_delta_v: float = 0.0
var tolerance: float = 0.8
var label: String = ""


func _init(
	p_direction: Direction = Direction.PROGRADE,
	p_delta_v: float = 0.0,
	p_trigger: Trigger = Trigger.IMMEDIATE,
	p_label: String = ""
) -> void:
	direction = p_direction
	delta_v = maxf(p_delta_v, 0.0)
	remaining_delta_v = delta_v
	trigger = p_trigger
	label = p_label


func is_complete() -> bool:
	return remaining_delta_v <= tolerance

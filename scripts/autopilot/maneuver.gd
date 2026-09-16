class_name Maneuver
extends RefCounted

enum TriggerType {
	IMMEDIATE,
	TIME,
	RADIUS,
	ANOMALY,
	PERIAPSIS,
	APOAPSIS
}

# Legacy compatibility enums for existing callsites
enum Trigger { IMMEDIATE, PERIAPSIS, APOAPSIS }
enum Direction { PROGRADE, RETROGRADE, RADIAL_OUT, RADIAL_IN }

var reference_body: ProcPlanet = null
var label: String = ""

var trigger_type: TriggerType = TriggerType.IMMEDIATE
var trigger: Trigger = Trigger.IMMEDIATE # Legacy alias
var direction: Direction = Direction.PROGRADE # Legacy alias

var trigger_time: float = 0.0
var trigger_radius: float = 0.0
var trigger_anomaly: float = 0.0

var planned_delta_v: Vector2 = Vector2.ZERO
var delta_v: float = 0.0
var remaining_delta_v: float = 0.0

var expected_periapsis_radius: float = 0.0
var expected_apoapsis_radius: float = 0.0

var tolerance_delta_v: float = 0.5 # m/s
var tolerance: float = 0.5 # Legacy alias
var tolerance_orbit: float = 500.0 # meters


func _init(
	p_direction = Direction.PROGRADE,
	p_delta_v: float = 0.0,
	p_trigger = Trigger.IMMEDIATE,
	p_label: String = ""
) -> void:
	if p_direction is Direction:
		direction = p_direction
	elif p_direction is int:
		direction = p_direction as Direction
		
	if p_trigger is Trigger:
		trigger = p_trigger
		match p_trigger:
			Trigger.IMMEDIATE:
				trigger_type = TriggerType.IMMEDIATE
			Trigger.PERIAPSIS:
				trigger_type = TriggerType.PERIAPSIS
			Trigger.APOAPSIS:
				trigger_type = TriggerType.APOAPSIS
	elif p_trigger is TriggerType:
		trigger_type = p_trigger
		match p_trigger:
			TriggerType.IMMEDIATE:
				trigger = Trigger.IMMEDIATE
			TriggerType.PERIAPSIS:
				trigger = Trigger.PERIAPSIS
			TriggerType.APOAPSIS:
				trigger = Trigger.APOAPSIS

	delta_v = maxf(p_delta_v, 0.0)
	remaining_delta_v = delta_v
	label = p_label
	tolerance = tolerance_delta_v


func is_complete() -> bool:
	return remaining_delta_v <= tolerance_delta_v

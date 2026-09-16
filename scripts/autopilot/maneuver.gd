class_name Maneuver
extends RefCounted

# Zaktualizowany model Maneuver
# Przestaje opierac sie na 'PROGRADE' itp., a przechowuje konkretne parametry do precyzyjnej egzekucji.

var reference_body: ProcPlanet

enum TriggerType { IMMEDIATE, TIME, ANOMALY, ALTITUDE, PERIAPSIS, APOAPSIS }
var trigger_type: TriggerType = TriggerType.IMMEDIATE
var trigger_radius: float = 0.0
var trigger_anomaly: float = 0.0

var delta_v_vector: Vector2 = Vector2.ZERO
var remaining_delta_v: Vector2 = Vector2.ZERO

var planned_position: Vector2 = Vector2.ZERO
var planned_time: float = 0.0

var expected_periapsis: float = 0.0
var expected_apoapsis: float = 0.0

var tolerance_dv: float = 0.5
var tolerance_time: float = 1.0

var label: String = "Maneuver"

func _init(l: String = "Maneuver") -> void:
    label = l

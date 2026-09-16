class_name AutopilotPlan
extends RefCounted

var maneuvers: Array[Maneuver] = []
var current_index: int = 0
var status: String = "IDLE"
var failure_reason: String = ""

var target_planet: ProcPlanet = null
var target_orbit_altitude: float = 0.0
var expected_final_periapsis: float = 0.0
var expected_final_apoapsis: float = 0.0


func _init(p_target: ProcPlanet = null, p_target_alt: float = 0.0) -> void:
	target_planet = p_target
	target_orbit_altitude = p_target_alt


func add_maneuver(m: Maneuver) -> void:
	if m != null:
		maneuvers.append(m)


func clear() -> void:
	maneuvers.clear()
	current_index = 0
	status = "IDLE"
	failure_reason = ""


func current_maneuver() -> Maneuver:
	if current_index >= 0 and current_index < maneuvers.size():
		return maneuvers[current_index]
	return null


func advance_maneuver() -> bool:
	current_index += 1
	return current_index < maneuvers.size()


func is_complete() -> bool:
	return current_index >= maneuvers.size() and not maneuvers.is_empty()


func is_empty() -> bool:
	return maneuvers.is_empty()


func total_delta_v() -> float:
	var total := 0.0
	for m in maneuvers:
		total += m.delta_v
	return total


func remaining_delta_v() -> float:
	var rem := 0.0
	for i in range(maxi(current_index, 0), maneuvers.size()):
		rem += maneuvers[i].remaining_delta_v
	return rem


func to_debug_string() -> String:
	var lines := PackedStringArray()
	lines.append("PLAN (Status: %s, Current: %d/%d)" % [status, current_index + 1, maneuvers.size()])
	if not failure_reason.is_empty():
		lines.append("  Failure: %s" % failure_reason)
	for i in maneuvers.size():
		var m := maneuvers[i]
		var prefix := "  -> " if i == current_index else "     "
		lines.append("%s[%d] %s: planned=%.1f m/s, rem=%.1f m/s, trig=%s" % [
			prefix, i, m.label, m.delta_v, m.remaining_delta_v, m.trigger_type
		])
	return "\n".join(lines)

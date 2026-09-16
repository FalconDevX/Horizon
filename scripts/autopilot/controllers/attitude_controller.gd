class_name AttitudeController
extends RefCounted

const DEFAULT_ALIGNMENT_TOLERANCE := 0.05 # ~2.8 degrees
const DEFAULT_SPIN_TOLERANCE := 0.03 # rad/s
const MAX_SPIN := 1.15 # Matches ship.gd MAX_SPIN


# Computes the next angular velocity for the ship to smoothly reach desired_heading
# without overshoot or oscillation across varying time steps / time warps.
static func calculate_angular_velocity(
	current_rotation: float,
	current_spin: float,
	desired_heading: float,
	available_accel: float,
	dt: float
) -> float:
	if dt <= 0.0:
		return current_spin

	var error := angle_difference(current_rotation, desired_heading)
	var accel := maxf(available_accel, 0.01)

	# Calculate maximum safe speed to arrive at target with zero velocity
	# v^2 = 2 * a * d
	var stopping_factor := 0.75
	var abs_error := absf(error)
	var target_spin := 0.0

	if abs_error > 0.001:
		var max_braking_speed := sqrt(2.0 * accel * abs_error * stopping_factor)
		var desired_spin := signf(error) * minf(max_braking_speed, MAX_SPIN)
		# Proportional blend in the small error regime to prevent limit cycles
		if abs_error < 0.08:
			desired_spin = error * 6.0
		target_spin = clampf(desired_spin, -MAX_SPIN, MAX_SPIN)

	# Steer current spin towards target spin with available acceleration
	var max_delta_spin := accel * 2.5 * dt
	var next_spin := move_toward(current_spin, target_spin, max_delta_spin)
	return clampf(next_spin, -MAX_SPIN, MAX_SPIN)


static func is_aligned(
	current_rotation: float,
	current_spin: float,
	desired_heading: float,
	tolerance_angle: float = DEFAULT_ALIGNMENT_TOLERANCE,
	tolerance_spin: float = DEFAULT_SPIN_TOLERANCE
) -> bool:
	var error := absf(angle_difference(current_rotation, desired_heading))
	return error <= tolerance_angle and absf(current_spin) <= tolerance_spin

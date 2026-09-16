class_name OrbitState
extends RefCounted

var radius: float = 0.0
var altitude: float = 0.0

var radial_velocity: float = 0.0
var tangential_velocity: float = 0.0
var total_velocity: float = 0.0

var specific_energy: float = 0.0
var angular_momentum: float = 0.0

var semi_major_axis: float = 0.0
var eccentricity: float = 0.0
var eccentricity_vector: Vector2 = Vector2.ZERO

var periapsis_radius: float = 0.0
var apoapsis_radius: float = 0.0

var periapsis_altitude: float = 0.0
var apoapsis_altitude: float = 0.0

var orbital_period: float = 0.0
var time_to_pe: float = 0.0
var time_to_ap: float = 0.0

var is_bound: bool = false
var is_near_circular: bool = false

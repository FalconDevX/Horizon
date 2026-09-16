class_name ShipStats
extends RefCounted

var mass: float = 1.0
var com: Vector2 = Vector2.ZERO
var fuel: float = 0.0
var fuel_max: float = 0.0
var thrust: float = 0.0
var thrust_force: Vector2 = Vector2.ZERO
var thrust_torque: float = 0.0
var rcs_thrust: float = 0.0
var inertia: float = 1.0
var hull: float = 0.0
var hull_max: float = 0.0
var radius: float = 4.0
var cockpit_count: int = 0
var engine_count: int = 0
var component_count: int = 1

class_name SurfaceCoordinate
extends RefCounted

var latitude: float = 0.0
var longitude: float = 0.0


func _init(p_latitude: float = 0.0, p_longitude: float = 0.0) -> void:
	latitude = clampf(p_latitude, -PI * 0.5, PI * 0.5)
	longitude = wrapf(p_longitude, -PI, PI)


func to_unit_vector() -> Vector3:
	var latitude_cos := cos(latitude)
	return Vector3(
		latitude_cos * cos(longitude),
		sin(latitude),
		latitude_cos * sin(longitude)
	)


static func from_unit_vector(value: Vector3) -> SurfaceCoordinate:
	var unit := value.normalized()
	return SurfaceCoordinate.new(
		asin(clampf(unit.y, -1.0, 1.0)),
		atan2(unit.z, unit.x)
	)


func shifted(latitude_delta: float, longitude_delta: float) -> SurfaceCoordinate:
	return SurfaceCoordinate.new(latitude + latitude_delta, longitude + longitude_delta)


func angular_distance_to(other: SurfaceCoordinate) -> float:
	return acos(clampf(to_unit_vector().dot(other.to_unit_vector()), -1.0, 1.0))


func is_above_horizon_for(observer: SurfaceCoordinate) -> bool:
	return to_unit_vector().dot(observer.to_unit_vector()) > 0.0


func copy() -> SurfaceCoordinate:
	return SurfaceCoordinate.new(latitude, longitude)

class_name Units
extends RefCounted

# Symulacja zawsze w SI: metry, sekundy, kilogramy.
# HUD pokazuje kilometry jako metry / 1000 — bez sztucznego mnożenia.
const METERS_PER_KILOMETER := 1_000.0
const STANDARD_GRAVITY := 9.80665
const WARP_LOCK_ALTITUDE := 12_000.0
const HANGAR_REST_SPEED := 12.0
const SPEED_GAUGE_MAX := 1_200.0
const RADAR_RANGES := [50_000.0, 500_000.0, 5_000_000.0, 50_000_000.0]


static func km(value_meters: float) -> float:
	return value_meters / METERS_PER_KILOMETER


static func m(value_kilometers: float) -> float:
	return value_kilometers * METERS_PER_KILOMETER


static func radar_range(nearest_distance_m: float) -> float:
	var distance := maxf(nearest_distance_m, 0.0)
	for band in RADAR_RANGES:
		if distance < float(band) * 0.85:
			return float(band)
	return float(RADAR_RANGES[RADAR_RANGES.size() - 1])

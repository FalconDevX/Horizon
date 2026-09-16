class_name Universe
extends Node2D

const PREFIX: Array[String] = ["Ke", "Sel", "Vor", "Nyx", "Tal", "Iri", "Myr", "Zha", "Orr", "Lun", "Ash", "Vel"]
const MID: Array[String] = ["ra", "lun", "the", "vos", "kai", "dra", "si", "ae", "or"]
const SUFFIX: Array[String] = ["ne", "os", "ix", "ara", "um", "eth", "is", "or", "yn"]
const KINDS: Array[String] = ["arid", "ocean", "ice", "lava", "gas", "toxic", "carbon"]

var rng := RandomNumberGenerator.new()
var planets: Array[ProcPlanet] = []
var stations: Array[Station] = []
# The system is compact enough for a game, but every number is still meters.
const SUN_SURFACE_GRAVITY := 90.0
const SUN_RADIUS_M := 24_000.0
const INNER_ORBIT_M := 95_000.0
const ORBIT_GAP_MIN_M := 75_000.0
var sun_radius: float = SUN_RADIUS_M
var _asteroids: Array[Dictionary] = []


func generate(system_seed: int = 0) -> void:
	if system_seed == 0:
		rng.randomize()
	else:
		rng.seed = system_seed
	sun_radius = rng.randf_range(20_000.0, 28_000.0)
	_make_sun_body()
	var count := rng.randi_range(6, 8)
	var orbit := rng.randf_range(INNER_ORBIT_M, INNER_ORBIT_M * 1.25)
	for i in count:
		var kind: String = KINDS[i % KINDS.size()]
		if i == 0:
			kind = ["arid", "lava", "carbon"][rng.randi_range(0, 2)]
		elif i == count - 1:
			kind = ["ice", "gas", "carbon"][rng.randi_range(0, 2)]
		elif rng.randf() < 0.35:
			kind = KINDS[rng.randi_range(0, KINDS.size() - 1)]
		var radius := rng.randf_range(5_200.0, 12_500.0)
		if kind == "gas":
			radius = rng.randf_range(18_000.0, 32_000.0)
		var planet := ProcPlanet.new()
		# Planets cover orbit/trajectory overlays where the far side is occluded.
		planet.z_index = 8
		planet.configure(rng, _make_name(), kind, radius, orbit)
		planet.orbit_speed = OrbitalPhysics.circular_speed(sun_mu(), orbit) / orbit
		if rng.randf() < 0.18:
			planet.orbit_speed *= -1.0
		planet.name = planet.planet_name
		add_child(planet)
		planet.tick(0.0)
		planets.append(planet)
		if kind != "gas" and rng.randf() > 0.55:
			_add_moon(planet)
		elif kind == "gas" and rng.randf() > 0.4:
			_add_moon(planet)
			if rng.randf() > 0.5:
				_add_moon(planet)
		orbit += rng.randf_range(ORBIT_GAP_MIN_M, ORBIT_GAP_MIN_M * 2.0) + radius * 3.0
	_make_stations()
	_make_asteroids()
	queue_redraw()


func _make_name() -> String:
	return PREFIX[rng.randi_range(0, PREFIX.size() - 1)] + MID[rng.randi_range(0, MID.size() - 1)] + SUFFIX[rng.randi_range(0, SUFFIX.size() - 1)]


func _make_sun_body() -> void:
	var body := StaticBody2D.new()
	body.name = "SunBody"
	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = sun_radius * 0.9
	shape.shape = circle
	body.add_child(shape)
	add_child(body)


func _add_moon(parent: ProcPlanet) -> void:
	var moon := ProcPlanet.new()
	moon.z_index = 8
	var mk: String = ["ice", "carbon", "arid"][rng.randi_range(0, 2)]
	var r := parent.radius * rng.randf_range(0.12, 0.24)
	var orbit := parent.radius * rng.randf_range(1.9, 3.1)
	moon.configure(rng, parent.planet_name + " " + ["I", "II", "III"][rng.randi_range(0, 2)], mk, r, orbit)
	moon.parent_body = parent
	moon.orbit_speed = OrbitalPhysics.circular_speed(parent.mu, orbit) / orbit
	if rng.randf() < 0.12:
		moon.orbit_speed *= -1.0
	moon.name = moon.planet_name
	add_child(moon)
	moon.tick(0.0)
	planets.append(moon)


func _make_stations() -> void:
	stations.clear()
	var mains: Array[ProcPlanet] = []
	for p in planets:
		if p.parent_body == null:
			mains.append(p)
	if mains.is_empty():
		return
	var first := Station.new()
	first.configure(mains[0], "Stacja", rng)
	add_child(first)
	stations.append(first)
	if mains.size() > 2 and rng.randf() > 0.4:
		var extra := Station.new()
		extra.configure(mains[mini(2, mains.size() - 1)], "Posterunek", rng)
		add_child(extra)
		stations.append(extra)


func _make_asteroids() -> void:
	_asteroids.clear()
	var mains: Array[ProcPlanet] = []
	for p in planets:
		if p.parent_body == null:
			mains.append(p)
	var belt_r := 280_000.0
	if mains.size() >= 4:
		belt_r = (mains[2].orbit_radius + mains[3].orbit_radius) * 0.5
	for i in 140:
		var ang := rng.randf() * TAU
		var rad := belt_r + rng.randf_range(-15_000.0, 15_000.0)
		_asteroids.append({
			"pos": Vector2(cos(ang), sin(ang)) * rad,
			"r": rng.randf_range(40.0, 220.0),
			"rot": rng.randf() * TAU,
		})


func first_landable_planet() -> ProcPlanet:
	for planet in planets:
		if planet.allows_surface_landing() and not planet.is_moon():
			return planet
	for planet in planets:
		if planet.allows_surface_landing():
			return planet
	return planets[0] if not planets.is_empty() else null


func should_lock_warp(world: Vector2) -> bool:
	var body := nearest(world)
	if body == null:
		return false
	var altitude := world.distance_to(body.global_position) - body.radius
	return altitude < (body.radius * 0.15 + 400.0)


func nearest(from: Vector2) -> ProcPlanet:
	if planets.is_empty():
		return null
	var best := planets[0]
	var best_d := from.distance_to(best.global_position) - best.radius
	for p in planets:
		var d := from.distance_to(p.global_position) - p.radius
		if d < best_d:
			best = p
			best_d = d
	return best


func nearest_at_time(from: Vector2, seconds_ahead: float) -> ProcPlanet:
	var best: ProcPlanet = null
	var best_d := INF
	for planet in planets:
		if not is_instance_valid(planet):
			continue
		var pose := planet.predicted_state(seconds_ahead)
		var position: Vector2 = pose["position"]
		var d := from.distance_to(position) - planet.radius
		if d < best_d:
			best_d = d
			best = planet
	return best


func gravity_at(world: Vector2) -> Vector2:
	var primary := dominant_body(world)
	if primary == null:
		return OrbitalPhysics.gravity_at(world, Vector2.ZERO, sun_mu(), sun_radius * 1.05)
	return primary.gravity_at(world)


func gravity_at_time(world: Vector2, seconds_ahead: float) -> Vector2:
	# Predictive counterpart of gravity_at().  The route planner must use the
	# future positions of planets; using their current positions made long routes
	# visually miss moving targets.
	var selected: ProcPlanet = null
	var selected_position := Vector2.ZERO
	var best_score := INF
	for planet in planets:
		if not is_instance_valid(planet):
			continue
		var pose := planet.predicted_state(seconds_ahead)
		var position: Vector2 = pose["position"]
		var score := world.distance_to(position) / maxf(soi_radius(planet), 1.0)
		if score < 1.0 and score < best_score:
			best_score = score
			selected = planet
			selected_position = position
	if selected == null:
		return OrbitalPhysics.gravity_at(world, Vector2.ZERO, sun_mu(), sun_radius * 1.05)
	return OrbitalPhysics.gravity_at(world, selected_position, selected.mu, selected.radius * 0.55)


func collision_at_time(world: Vector2, seconds_ahead: float, clearance: float = 0.0) -> Dictionary:
	var sun_distance := world.length()
	if sun_distance <= sun_radius + clearance:
		return {"hit": true, "body": null, "position": Vector2.ZERO, "radius": sun_radius}
	for planet in planets:
		if not is_instance_valid(planet):
			continue
		var pose := planet.predicted_state(seconds_ahead)
		var position: Vector2 = pose["position"]
		if world.distance_to(position) <= planet.radius + clearance:
			return {"hit": true, "body": planet, "position": position, "radius": planet.radius}
	return {"hit": false, "body": null, "position": Vector2.ZERO, "radius": 0.0}


func collision_along_time(
	from: Vector2, to: Vector2, start_seconds: float, end_seconds: float, clearance: float = 0.0
) -> Dictionary:
	# A point-only collision check can skip a small moon during a long planning
	# step.  Sample the full segment against the bodies at their matching future
	# time; the cap keeps this safety check inexpensive.
	var steps := clampi(int(ceil(from.distance_to(to) / 100.0)), 1, 24)
	for i in range(1, steps + 1):
		var t := float(i) / float(steps)
		var hit := collision_at_time(from.lerp(to, t), lerpf(start_seconds, end_seconds, t), clearance)
		if bool(hit.get("hit", false)):
			return hit
	return {"hit": false, "body": null, "position": Vector2.ZERO, "radius": 0.0}


func dominant_body(world: Vector2) -> ProcPlanet:
	var selected: ProcPlanet = null
	var best_score := INF
	for p in planets:
		var score := world.distance_to(p.global_position) / maxf(soi_radius(p), 1.0)
		if score < 1.0 and score < best_score:
			selected = p
			best_score = score
	return selected


func sun_mu() -> float:
	return OrbitalPhysics.mu_from_surface_gravity(SUN_SURFACE_GRAVITY, sun_radius)


func parent_mu(planet: ProcPlanet) -> float:
	if planet != null and planet.parent_body is ProcPlanet:
		return (planet.parent_body as ProcPlanet).mu
	return sun_mu()


func parent_center(planet: ProcPlanet) -> Vector2:
	if planet != null and planet.parent_body is ProcPlanet:
		return (planet.parent_body as ProcPlanet).global_position
	return Vector2.ZERO


func circular_orbit_speed(planet: ProcPlanet, radius: float = -1.0) -> float:
	var orbit := planet.orbit_radius if radius < 0.0 else radius
	return OrbitalPhysics.circular_speed(parent_mu(planet), orbit) / maxf(orbit, 1.0)


func siblings(planet: ProcPlanet) -> Array[ProcPlanet]:
	var result: Array[ProcPlanet] = []
	if planet == null:
		return result
	for other in planets:
		if other == planet:
			continue
		if other.parent_body == planet.parent_body:
			result.append(other)
	return result


func minimum_orbit_gap(a: ProcPlanet, b: ProcPlanet) -> float:
	return (a.radius + b.radius) * 2.0 + 35_000.0


func validate_orbit_radius(planet: ProcPlanet, radius: float) -> Dictionary:
	if planet == null:
		return {"ok": false, "reason": "Brak planety"}
	var min_radius := planet.radius * 2.0
	if planet.parent_body is ProcPlanet:
		var parent := planet.parent_body as ProcPlanet
		min_radius = parent.radius * 1.6 + planet.radius * 2.5
	if radius < min_radius:
		return {"ok": false, "reason": "Orbita zbyt blisko ciała nadrzędnego"}
	for other in siblings(planet):
		var gap := absf(radius - other.orbit_radius)
		if gap < minimum_orbit_gap(planet, other):
			return {"ok": false, "reason": "Orbita zbyt blisko sąsiedniej planety"}
	return {"ok": true, "reason": ""}


func pick_body(world: Vector2, meters_per_pixel: float, pixel_slop: float = 10.0) -> ProcPlanet:
	var best: ProcPlanet = null
	var best_pixels := pixel_slop
	for planet in planets:
		var to_body := world.distance_to(planet.global_position)
		var body_pixels := maxf(to_body - planet.radius, 0.0) / maxf(meters_per_pixel, 0.000001)
		if to_body <= planet.radius:
			body_pixels = 0.0
		if body_pixels <= best_pixels:
			best_pixels = body_pixels
			best = planet
		var center := parent_center(planet)
		var orbit_pixels := absf(world.distance_to(center) - planet.orbit_radius) / maxf(meters_per_pixel, 0.000001)
		if orbit_pixels <= best_pixels:
			best_pixels = orbit_pixels
			best = planet
	return best


func soi_radius(planet: ProcPlanet) -> float:
	var parent_mu := sun_mu()
	var a := planet.orbit_radius
	if planet.parent_body is ProcPlanet:
		parent_mu = (planet.parent_body as ProcPlanet).mu
	var ratio := planet.mu / maxf(parent_mu, 1.0)
	var soi := a * pow(ratio, 0.4)
	return maxf(soi, planet.radius * 6.0)


func orbit_status(world: Vector2, vel: Vector2) -> Dictionary:
	var body_name := "słońce"
	var body_pos := Vector2.ZERO
	var body_vel := Vector2.ZERO
	var body_mu := sun_mu()
	var body_radius := sun_radius
	var focus: ProcPlanet = null
	var best_score := 1.0
	for p in planets:
		var r := world.distance_to(p.global_position)
		var soi := soi_radius(p)
		var score := r / soi
		if score < 1.0 and score < best_score:
			best_score = score
			focus = p
	if focus:
		body_name = focus.planet_name
		body_pos = focus.global_position
		body_vel = focus.inertial_velocity()
		body_mu = focus.mu
		body_radius = focus.radius
	var rel_p := world - body_pos
	var rel_v := vel - body_vel
	var r := maxf(rel_p.length(), 1.0)
	var elements := OrbitalPhysics.elements(rel_p, rel_v, body_mu)
	var bound: bool = elements["bound"]
	var pe: float = elements["pe"]
	var ap: float = elements["ap"]
	var band := _solar_band(world.length())
	return {
		"body": body_name,
		"is_sun": focus == null,
		"focus": focus,
		"bound": bound,
		"pe": pe - body_radius,
		"ap": ap - body_radius,
		"alt": r - body_radius,
		"center": body_pos,
		"velocity": body_vel,
		"mu": body_mu,
		"radius": body_radius,
		"relative_position": rel_p,
		"relative_velocity": rel_v,
		"circular_speed": OrbitalPhysics.circular_speed(body_mu, r),
		"escape_speed": OrbitalPhysics.escape_speed(body_mu, r),
		"band": band["text"],
		"inner": band["inner"],
		"outer": band["outer"],
		"time_to_pe": elements["time_to_pe"],
		"time_to_ap": elements["time_to_ap"],
		"period": elements["period"],
	}


func solar_orbit_status(world: Vector2, vel: Vector2) -> Dictionary:
	var body_mu := sun_mu()
	var body_radius := sun_radius
	var rel_p := world
	var rel_v := vel
	var r := maxf(rel_p.length(), 1.0)
	var elements := OrbitalPhysics.elements(rel_p, rel_v, body_mu)
	return {
		"center": Vector2.ZERO,
		"mu": body_mu,
		"radius": body_radius,
		"relative_position": rel_p,
		"relative_velocity": rel_v,
		"bound": elements["bound"],
		"pe": elements["pe"] - body_radius,
		"ap": elements["ap"] - body_radius,
		"alt": r - body_radius,
		"time_to_pe": elements["time_to_pe"],
		"time_to_ap": elements["time_to_ap"],
		"period": elements["period"],
	}


func _solar_band(sun_dist: float) -> Dictionary:
	var mains: Array[ProcPlanet] = []
	for p in planets:
		if p.parent_body == null:
			mains.append(p)
	mains.sort_custom(func(a: ProcPlanet, b: ProcPlanet) -> bool:
		return a.orbit_radius < b.orbit_radius
	)
	if mains.is_empty():
		return {"text": "pas słońca", "inner": null, "outer": null}
	if sun_dist < mains[0].orbit_radius:
		return {"text": "wewnątrz orbity %s" % mains[0].planet_name, "inner": null, "outer": mains[0]}
	if sun_dist > mains[mains.size() - 1].orbit_radius:
		return {"text": "za orbitą %s" % mains[mains.size() - 1].planet_name, "inner": mains[mains.size() - 1], "outer": null}
	for i in mains.size() - 1:
		if sun_dist >= mains[i].orbit_radius and sun_dist <= mains[i + 1].orbit_radius:
			return {
				"text": "między %s a %s" % [mains[i].planet_name, mains[i + 1].planet_name],
				"inner": mains[i],
				"outer": mains[i + 1],
			}
	return {"text": "pas słońca", "inner": null, "outer": null}


func tick(delta: float) -> void:
	for p in planets:
		p.tick(delta)
	for s in stations:
		s.tick(delta)


func spawn_near_first() -> Vector2:
	if planets.is_empty():
		return Vector2(280, 0)
	var p := planets[0]
	var away := p.global_position.normalized()
	if away.length() < 0.01:
		away = Vector2.RIGHT
	return p.global_position + away * (p.radius + maxf(140.0, p.radius * 0.018))


func _draw() -> void:
	_draw_asteroids()
	_draw_sun()


func _draw_asteroids() -> void:
	# A distant belt is background detail.  Drawing every pebble was needlessly
	# expensive while it is only a few pixels wide on screen.
	for i in range(0, _asteroids.size(), 2):
		var a: Dictionary = _asteroids[i]
		var pos: Vector2 = a["pos"]
		var r: float = a["r"]
		draw_circle(pos, r, Color("#6a5a4a"))
		draw_circle(pos, r * 0.45, Color("#8a7a68"))


func _draw_sun() -> void:
	for i in 8:
		var t := float(i) / 8.0
		var c := Color(1.0, 0.55 + t * 0.2, 0.22, 0.045 * (1.0 - t))
		draw_circle(Vector2.ZERO, sun_radius * lerpf(1.0, 2.35, t), c)
	draw_circle(Vector2.ZERO, sun_radius * 1.08, Color(1.0, 0.78, 0.38, 0.2))
	draw_circle(Vector2.ZERO, sun_radius * 0.92, Color("#ffe08a"))
	draw_circle(Vector2.ZERO, sun_radius * 0.58, Color("#fff6d0"))
	draw_circle(Vector2.ZERO, sun_radius * 0.22, Color("#fffaf0"))

class_name OrbitRenderer
extends Node2D

const INACTIVE := Color(0.82, 0.84, 0.88, 0.62)
const PLANET_ORBIT := Color(0.25, 0.28, 0.35, 0.35)
const SELECTED := Color(0.35, 0.95, 1.0, 0.92)
const SELECTED_GLOW := Color(0.35, 0.95, 1.0, 0.22)
const EDITED := Color(1.0, 0.72, 0.22, 0.95)
const PREVIOUS := Color(1.0, 0.72, 0.22, 0.35)
const STABLE := Color(0.32, 0.62, 1.0, 0.88)
const ESCAPE := Color(1.0, 0.58, 0.16, 0.86)
const COLLISION := Color(1.0, 0.28, 0.22, 0.92)
const PLANNED := Color(0.32, 0.92, 0.48, 0.78)
const CURRENT_ORBIT := Color(1.0, 0.78, 0.18, 0.86)
const VELOCITY_PREVIEW := Color(1.0, 0.82, 0.2, 0.92)

var universe: Universe
var ship: SurveyShip
var selected_target: ProcPlanet
var show_all: bool = false
var edit_active: bool = false
var edit_original_radius: float = 0.0
var colorblind: bool = false

# Cache green AP preview.  A projected interplanetary route is intentionally
# refreshed slowly: it remains readable while the ship moves and avoids a
# costly full reconstruction every rendered frame.
var _planned_cache: Dictionary = {}
const _PLANNED_CACHE_FRAMES := 30
const REDRAW_INTERVAL := 0.066
var _redraw_elapsed := REDRAW_INTERVAL


func _ready() -> void:
	z_index = 7


func _process(delta: float) -> void:
	_redraw_elapsed += delta
	if _redraw_elapsed >= REDRAW_INTERVAL:
		_redraw_elapsed = 0.0
		queue_redraw()


func _draw() -> void:
	if universe == null or ship == null:
		return
	var cam := get_viewport().get_camera_2d()
	var zoom := cam.zoom.x if cam else 1.0
	var px := 1.8 / maxf(zoom, 0.000001)
	# Planet orbital paths stay visible in normal flight as light-gray rings.
	for planet in universe.planets:
		if edit_active and planet == selected_target:
			continue
		_draw_body_orbit(planet, PLANET_ORBIT, px * 0.5, false)
	if selected_target:
		if edit_active:
			_draw_orbit_circle(
				universe.parent_center(selected_target),
				edit_original_radius,
				PREVIOUS,
				px * 0.8,
				true
			)
			_draw_body_orbit(selected_target, EDITED, px * 1.35, false)
		else:
			var active_plan := {}
			if ship.autopilot_target == selected_target and not ship.surface_mode_active:
				active_plan = _cached_autopilot_plan(selected_target)
			var orbit_center: Vector2 = active_plan.get("orbit_center", selected_target.global_position)
			_draw_target_orbit_ring(selected_target, px, ship.autopilot_target == selected_target, orbit_center)
			# Computing a route is useful only for an active mission.  Removing it
			# while merely browsing targets eliminates the remaining map stutter.
			if not ship.surface_mode_active and ship.autopilot_target == selected_target:
				_draw_full_planned_trajectory(selected_target, px, true, active_plan)
	if edit_active and selected_target:
		_draw_target_orbit_ring(selected_target, px, true)
	if not ship.surface_mode_active and ship.landed_on == null:
		_draw_current_ship_orbit(px)


func _draw_current_ship_orbit(width: float) -> void:
	# One yellow line is the ship's osculating orbit at this exact moment.  It is
	# deliberately separate from the green autopilot route and target ring.
	var state := universe.orbit_status(ship.global_position, ship.velocity)
	if state.get("focus", null) != null and not bool(state.get("bound", false)):
		state = universe.solar_orbit_status(ship.global_position, ship.velocity)
	var points := OrbitalPhysics.sample_conic(
		state["relative_position"], state["relative_velocity"], state["mu"], 220
	)
	if points.size() < 2:
		return
	var center: Vector2 = state["center"]
	var world_points := PackedVector2Array()
	for point in points:
		world_points.append(center + point)
	draw_polyline(world_points, CURRENT_ORBIT, width * 0.9, true)


func _draw_velocity_projection(width: float) -> void:
	if ship.surface_mode_active or ship.landed_on != null or ship.velocity.length() < 0.1:
		return
	var points := ship.get_coast_trajectory()
	if points.size() < 2:
		return
	var glow := VELOCITY_PREVIEW
	glow.a = 0.2
	draw_polyline(points, glow, width * 3.2, true)
	draw_polyline(points, VELOCITY_PREVIEW, width * 1.15, true)
	# Compact chevrons make the direction readable without pretending this is an
	# autopilot route.  This is simply the currently held velocity vector.
	for i in range(8, points.size() - 2, 12):
		var forward := (points[i + 1] - points[i - 1]).normalized()
		if forward.is_zero_approx():
			continue
		var size := width * 4.0
		var side := forward.orthogonal() * size * 0.65
		var tip := points[i] + forward * size
		draw_line(points[i] - forward * size * 0.45 + side, tip, VELOCITY_PREVIEW, width, true)
		draw_line(points[i] - forward * size * 0.45 - side, tip, VELOCITY_PREVIEW, width, true)


func _draw_body_orbit(planet: ProcPlanet, color: Color, width: float, dashed: bool) -> void:
	_draw_orbit_circle(universe.parent_center(planet), planet.orbit_radius, color, width, dashed)


func _draw_orbit_circle(center: Vector2, radius: float, color: Color, width: float, dashed: bool) -> void:
	if radius <= 1.0:
		return
	var cam := get_viewport().get_camera_2d()
	var zoom := cam.zoom.x if cam else 1.0
	var points := clampi(int(radius * zoom * 1.35), 512, 2048)
	if dashed:
		var previous := center + Vector2(radius, 0.0)
		for i in range(1, points + 1):
			var t := TAU * float(i) / float(points)
			var point := center + Vector2(cos(t), sin(t)) * radius
			if i % 6 < 3:
				draw_line(previous, point, color, width, true)
			previous = point
		return
	draw_arc(center, radius, 0.0, TAU, points, color, width, true)


func _draw_ship_orbit(width: float) -> void:
	var state := universe.orbit_status(ship.global_position, ship.velocity)
	# If escaping a local planet or in interplanetary space, draw single unified solar orbit
	if state["focus"] != null and not state["bound"]:
		state = universe.solar_orbit_status(ship.global_position, ship.velocity)
	var center: Vector2 = state["center"]
	var body_radius := float(state["radius"])
	var points := OrbitalPhysics.sample_conic(
		state["relative_position"],
		state["relative_velocity"],
		state["mu"],
		720
	)
	var kind := OrbitalPhysics.orbit_kind(state["bound"], state["pe"] + state["radius"], state["radius"])
	var color := STABLE
	if kind == "ucieczkowa":
		color = ESCAPE
	elif kind == "kolizyjna":
		color = COLLISION

	if points.size() < 2:
		return

	# Collision course: draw only the future branch from the ship to its FIRST
	# impact.  The old implementation drew both halves of the mathematical conic,
	# including the impossible part after passing through a planet or the sun.
	if kind == "kolizyjna":
		_draw_future_collision_path(center, body_radius, points, state, width)
		return

	var stable_pts := PackedVector2Array()
	for i in points.size():
		var world_point := center + points[i]
		if colorblind and kind != "stabilna" and i % 3 == 0:
			if stable_pts.size() > 1:
				draw_polyline(stable_pts, color, width, true)
			stable_pts = PackedVector2Array()
			continue
		stable_pts.append(world_point)
	if stable_pts.size() > 1:
		draw_polyline(stable_pts, color, width, true)


func _surface_clip_point(center: Vector2, body_radius: float, from_rel: Vector2, to_rel: Vector2) -> Vector2:
	var r0 := from_rel.length()
	var r1 := to_rel.length()
	if absf(r1 - r0) < 0.0001:
		return center + from_rel.normalized() * body_radius
	var t := (body_radius - r0) / (r1 - r0)
	var clipped := from_rel.lerp(to_rel, clampf(t, 0.0, 1.0))
	if clipped.length_squared() < 0.0001:
		return center + from_rel.normalized() * body_radius
	return center + clipped.normalized() * body_radius


func _draw_future_collision_path(
	center: Vector2,
	body_radius: float,
	points: PackedVector2Array,
	state: Dictionary,
	width: float
) -> void:
	var current_rel: Vector2 = state["relative_position"]
	var current_vel: Vector2 = state["relative_velocity"]
	var closest := 0
	var closest_distance := INF
	for i in points.size():
		var distance := points[i].distance_squared_to(current_rel)
		if distance < closest_distance:
			closest_distance = distance
			closest = i
	var forward_step := 1 if current_rel.cross(current_vel) >= 0.0 else -1
	var segment := PackedVector2Array([center + current_rel])
	var previous := current_rel
	var index := closest
	while index + forward_step >= 0 and index + forward_step < points.size():
		index += forward_step
		var rel: Vector2 = points[index]
		if rel.length() <= body_radius:
			segment.append(_surface_clip_point(center, body_radius, previous, rel))
			break
		segment.append(center + rel)
		previous = rel
	_draw_dashed_polyline(segment, COLLISION, width)


func _draw_dashed_polyline(points: PackedVector2Array, color: Color, width: float, dash_world: float = -1.0) -> void:
	if points.size() < 2:
		return
	var cam := get_viewport().get_camera_2d()
	var zoom := cam.zoom.x if cam else 1.0
	var dash := dash_world if dash_world > 0.0 else (10.0 / maxf(zoom, 0.000001))
	var gap := dash * 0.85
	var drawing := true
	var budget := dash
	var prev: Vector2 = points[0]
	for i in range(1, points.size()):
		var cur: Vector2 = points[i]
		var remaining := cur - prev
		var seg_len := remaining.length()
		if seg_len <= 0.0001:
			continue
		var dir := remaining / seg_len
		var consumed := 0.0
		while consumed < seg_len:
			var step := minf(budget, seg_len - consumed)
			var a := prev + dir * consumed
			var b := prev + dir * (consumed + step)
			if drawing:
				draw_line(a, b, color, width, true)
			consumed += step
			budget -= step
			if budget <= 0.0001:
				drawing = not drawing
				budget = dash if drawing else gap
		prev = cur


func _draw_target_orbit_ring(
	target: ProcPlanet, width: float, is_active_ap: bool, orbit_center: Vector2 = Vector2.ZERO
) -> void:
	if target == null:
		return
	if orbit_center == Vector2.ZERO:
		orbit_center = target.global_position
	var cam := get_viewport().get_camera_2d()
	var zoom := cam.zoom.x if cam else 1.0
	var target_orbit_r := target.radius + (ship.get_target_orbit_altitude(target) if ship else target.lowest_orbit_altitude() * 1.35)
	var arc_points := clampi(int(target_orbit_r * zoom * 1.5), 96, 512)
	var is_f_held := Input.is_key_pressed(KEY_F) and target == selected_target

	if is_active_ap:
		var glow_col := PLANNED
		glow_col.a = 0.25
		draw_arc(orbit_center, target_orbit_r, 0.0, TAU, arc_points, glow_col, width * 2.5, true)
		var main_col := PLANNED
		main_col.a = 0.95
		draw_arc(orbit_center, target_orbit_r, 0.0, TAU, arc_points, main_col, width * 1.25, true)
	elif is_f_held:
		# Highlighted orbit ring while adjusting with scroll wheel
		var glow_col := PLANNED
		glow_col.a = 0.35
		draw_arc(orbit_center, target_orbit_r, 0.0, TAU, arc_points, glow_col, width * 3.2, true)
		var main_col := PLANNED
		main_col.a = 0.95
		draw_arc(orbit_center, target_orbit_r, 0.0, TAU, arc_points, main_col, width * 1.35, true)
	else:
		var col := PLANNED
		col.a = 0.68
		draw_arc(orbit_center, target_orbit_r, 0.0, TAU, arc_points, col, width * 1.0, true)


func _draw_full_planned_trajectory(
	target: ProcPlanet, width: float, is_active: bool, supplied_plan: Dictionary = {}
) -> void:
	if target == null or ship == null:
		return
	var plan := supplied_plan if not supplied_plan.is_empty() else _cached_autopilot_plan(target)
	var pts: PackedVector2Array = plan.get("points", PackedVector2Array())
	if pts.size() < 2:
		return
	# A cached simulation may be up to half a second old.  Its first vertex must
	# always be the live ship position, otherwise the route visibly starts behind
	# the ship whenever time acceleration is enabled.
	pts = pts.duplicate()
	pts[0] = ship.global_position
	var status := str(plan.get("status", "horizon"))
	# Green always means the planned autopilot course.  Only a real collision is
	# red; an incomplete forecast must not look like a different, yellow route.
	var route_col := COLLISION if status == "collision" else PLANNED

	# 1. Soft glowing underlay for visibility against dark space
	var glow_col := route_col
	glow_col.a = 0.25 if is_active else 0.16
	draw_polyline(pts, glow_col, width * 2.8, true)

	# 2. Crisp, antialiased core trajectory line
	var core_col := route_col
	core_col.a = 0.95 if is_active else 0.75
	draw_polyline(pts, core_col, width * 1.15, true)

	# The end marker is the result of the actual simulation: green means target
	# orbit reached, orange means the bounded forecast horizon, red means a body
	# would be hit and the autopilot must re-plan rather than fly through it.
	var marker := pts[pts.size() - 1]
	var marker_glow := route_col
	marker_glow.a = 0.25
	draw_circle(marker, width * 6.0, marker_glow, true, -1.0, true)
	draw_circle(marker, width * 2.2, route_col, true, -1.0, true)

func _cached_autopilot_plan(target: ProcPlanet) -> Dictionary:
	if target == null or ship == null:
		return {}
	var key := target.get_instance_id()
	var frame := Engine.get_process_frames()
	var alt := ship.get_target_orbit_altitude(target)
	var entry: Dictionary = _planned_cache.get(key, {})
	var fresh := true
	if entry.has("plan") and int(entry.get("frame", -999)) + _PLANNED_CACHE_FRAMES >= frame:
		# Rebuild only on the timed cadence (four seconds at 60 FPS) or a genuine
		# mission change. Rebuilding from every position/velocity twitch was the
		# source of the severe map stutter during time warp.
		if is_equal_approx(float(entry.get("alt", -1.0)), alt):
			if int(entry.get("dir", 0)) == int(ship._autopilot_direction) and entry.get("landed", null) == ship.landed_on:
				fresh = false
	if fresh:
		entry = {
			"plan": ship.get_autopilot_plan(target, 72),
			"frame": frame,
			"pos": ship.global_position,
			"vel": ship.velocity,
			"alt": alt,
			"dir": ship._autopilot_direction,
			"landed": ship.landed_on,
		}
		_planned_cache[key] = entry
	return entry["plan"]


func _cached_planned_trajectory(target: ProcPlanet) -> PackedVector2Array:
	var plan := _cached_autopilot_plan(target)
	return plan.get("points", PackedVector2Array())

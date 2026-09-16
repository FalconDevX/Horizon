class_name ProcPlanet
extends Node2D

const SPHERE_SHADER := preload("res://shaders/planet_surface.gdshader")
const SCREEN_WIDTH_RATIO := 0.37
const SCREEN_HEIGHT_RATIO := 0.42

var planet_name: String = ""
var kind: String = "arid"
var radius: float = 80.0
var orbit_radius: float = 900.0
var orbit_speed: float = 0.04
var orbit_angle: float = 0.0
var spin_speed: float = 0.08
var seed_value: float = 1.0
var parent_body: Node2D = null
var mu: float = 1.0
var has_rings: bool = false
var ring_inner: float = 1.4
var ring_outer: float = 2.2
var ring_tilt: float = 0.28
var atmo_color: Color = Color(0.45, 0.7, 0.9, 0.18)
var atmo_scale: float = 1.22

var _noise := FastNoiseLite.new()
var _low: Color
var _mid: Color
var _high: Color
var _ocean: Color
var _ice: Color
var _glow: Color = Color(0, 0, 0, 0)
var _style: int = 0
var _ocean_level: float = 0.42
var _cloud_spin: float = 0.0
var _has_clouds: bool = false
var _sphere_visual: Sprite2D
var visual_quality: int = 2
var _next_visual_refresh_frame := 0


static func target_screen_radius(viewport: Vector2) -> float:
	return minf(
		viewport.x * SCREEN_WIDTH_RATIO,
		viewport.y * SCREEN_HEIGHT_RATIO
	)


func configure(rng: RandomNumberGenerator, p_name: String, p_kind: String, p_radius: float, p_orbit: float) -> void:
	planet_name = p_name
	kind = p_kind
	radius = p_radius
	orbit_radius = p_orbit
	orbit_angle = rng.randf() * TAU
	# Rotation is expressed in radians per second. A day lasts 10Ă„â€šĂ˘â‚¬ĹľÄ‚ËĂ˘â€šÂ¬ÄąË‡Ă„â€šĂ˘â‚¬Ä…Ä‚â€šĂ‚ÂÄ‚â€žĂ˘â‚¬ĹˇÄ‚â€ąĂ‚ÂĂ„â€šĂ‹ÂÄ‚ËĂ˘â‚¬ĹˇĂ‚Â¬Ă„Ä…Ă‹â€ˇĂ„â€šĂ˘â‚¬ĹˇÄ‚â€šĂ‚Â¬Ä‚â€žĂ˘â‚¬ĹˇÄ‚â€ąĂ‚ÂĂ„â€šĂ‹ÂÄ‚ËĂ˘â€šÂ¬ÄąË‡Ä‚â€šĂ‚Â¬Ä‚â€žĂ„â€¦Ä‚ËĂ˘â€šÂ¬ÄąĹş40 hours.
	spin_speed = TAU / rng.randf_range(10.0 * 3600.0, 40.0 * 3600.0)
	if rng.randf() <= 0.2:
		spin_speed = -spin_speed
	seed_value = rng.randf_range(1.0, 90.0)
	_noise.seed = int(seed_value * 17.0)
	_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	_noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	_noise.fractal_octaves = 4
	_noise.frequency = 1.0
	_apply_kind(rng)
	_build_sphere_visual()
	var g := 9.0
	if kind == "gas":
		g = 18.0
	elif kind == "ice" or radius < 3500.0:
		g = 5.5
	mu = OrbitalPhysics.mu_from_surface_gravity(g, radius)
	rotation = rng.randf() * TAU
	_build_collision()
	# Keep the rendered and predicted orbital pose identical from the first
	# frame.  Without this, newly configured standalone bodies lived at (0, 0)
	# until the next physics tick while the autopilot predicted their true orbit.
	global_position = Vector2(cos(orbit_angle), sin(orbit_angle)) * orbit_radius
	queue_redraw()


func _build_collision() -> void:
	var body := StaticBody2D.new()
	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = radius
	shape.shape = circle
	body.add_child(shape)
	add_child(body)


func _build_sphere_visual() -> void:
	# Sprite2D provides one stable, rectangular UV domain.  Polygon2D could be
	# triangulated inconsistently on very large rotating planets, leaving only a
	# triangular slice of the procedural disk visible.
	_sphere_visual = Sprite2D.new()
	_sphere_visual.name = "Sphere3D"
	_sphere_visual.z_index = 1
	var img := Image.create(4, 4, false, Image.FORMAT_RGBA8)
	img.fill(Color.WHITE)
	_sphere_visual.texture = ImageTexture.create_from_image(img)
	_sphere_visual.scale = Vector2.ONE * (radius * 0.5)
	var material := ShaderMaterial.new()
	material.shader = SPHERE_SHADER
	material.set_shader_parameter("deep_color", _ocean)
	material.set_shader_parameter("low_color", _low)
	material.set_shader_parameter("mid_color", _mid)
	material.set_shader_parameter("high_color", _high)
	material.set_shader_parameter("ice_color", _ice)
	material.set_shader_parameter("glow_color", _glow)
	material.set_shader_parameter("atmosphere_color", atmo_color)
	material.set_shader_parameter("ocean_level", _ocean_level)
	material.set_shader_parameter("seed", seed_value)
	material.set_shader_parameter("planet_kind", kind_index())
	material.set_shader_parameter("has_clouds", 1 if _has_clouds else 0)
	material.set_shader_parameter("quality", visual_quality)
	material.set_shader_parameter("lod", 1.0)
	material.set_shader_parameter("surface_detail_scale", 1.0)
	material.set_shader_parameter("disk_center_uv", Vector2(0.5, 0.5))
	material.set_shader_parameter("disk_radius_uv", Vector2(0.5, 0.5))
	material.set_shader_parameter("inverse_view_rotation", Basis().inverse())
	_sphere_visual.material = material
	add_child(_sphere_visual)


func _apply_kind(rng: RandomNumberGenerator) -> void:
	_style = 0
	_has_clouds = false
	has_rings = false
	atmo_scale = 1.22
	match kind:
		"ocean":
			_low = Color("#2a4a34")
			_mid = Color("#6a8c48")
			_high = Color("#d4c8a0")
			_ocean = Color("#1a4a5c")
			_ice = Color("#dce8ee")
			atmo_color = Color(0.48, 0.74, 0.9, 0.22)
			_ocean_level = rng.randf_range(0.46, 0.58)
			_has_clouds = true
		"arid":
			_low = Color("#5a2e1c")
			_mid = Color("#c47a4a")
			_high = Color("#e8d2a8")
			_ocean = Color("#3a4a38")
			_ice = Color("#ece4d4")
			atmo_color = Color(0.82, 0.58, 0.38, 0.14)
			_ocean_level = rng.randf_range(0.2, 0.32)
			atmo_scale = 1.14
		"ice":
			_style = 2
			_low = Color("#4a6580")
			_mid = Color("#9bb8c8")
			_high = Color("#eef4f8")
			_ocean = Color("#3a6080")
			_ice = Color("#f4f8fc")
			atmo_color = Color(0.72, 0.84, 0.94, 0.18)
			_ocean_level = 0.2
		"lava":
			_style = 3
			_low = Color("#1a1210")
			_mid = Color("#4a2218")
			_high = Color("#e07030")
			_ocean = Color("#801808")
			_ice = Color("#3a2018")
			_glow = Color(1.0, 0.32, 0.06, 0.9)
			atmo_color = Color(0.9, 0.35, 0.12, 0.2)
			_ocean_level = 0.38
		"gas":
			_style = 1
			_low = Color("#6a3a28")
			_mid = Color("#d4a05a")
			_high = Color("#f0d8a8")
			_ocean = _mid
			_ice = _high
			atmo_color = Color(0.88, 0.7, 0.42, 0.2)
			atmo_scale = 1.28
			has_rings = rng.randf() > 0.32
			if rng.randf() > 0.5:
				_low = Color("#3a4a78")
				_mid = Color("#8aa0d0")
				_high = Color("#d8e4f0")
				atmo_color = Color(0.55, 0.68, 0.88, 0.22)
		"toxic":
			_low = Color("#2a3a18")
			_mid = Color("#7a9a32")
			_high = Color("#c8d86a")
			_ocean = Color("#3a5818")
			_ice = Color("#dce8a8")
			atmo_color = Color(0.62, 0.84, 0.28, 0.2)
			_has_clouds = true
			_glow = Color(0.2, 0.35, 0.05, 0.4)
			_ocean_level = 0.4
		"carbon":
			_low = Color("#121018")
			_mid = Color("#3a2a48")
			_high = Color("#8a6aa0")
			_ocean = Color("#1a1028")
			_ice = Color("#c8b8d8")
			atmo_color = Color(0.42, 0.28, 0.55, 0.16)
			_ocean_level = 0.3
		_:
			_low = Color("#3a2a22")
			_mid = Color("#c47a4a")
			_high = Color("#e6c99a")
			_ocean = Color("#1c3a42")
			_ice = Color("#dce8ee")
	if has_rings:
		ring_inner = rng.randf_range(1.35, 1.55)
		ring_outer = rng.randf_range(2.0, 2.55)
		ring_tilt = rng.randf_range(0.18, 0.38)


func atmosphere_height() -> float:
	return maxf(radius * (atmo_scale - 1.0), 0.0)


func lowest_orbit_altitude() -> float:
	return maxf(atmosphere_height(), radius * 0.08)


func approach_altitude() -> float:
	return lowest_orbit_altitude()


func allows_surface_landing() -> bool:
	return kind != "gas"


func map_color() -> Color:
	return _mid


func kind_index() -> int:
	match kind:
		"ocean":
			return 1
		"ice":
			return 2
		"lava":
			return 3
		"gas":
			return 4
		"toxic":
			return 5
		"carbon":
			return 6
		_:
			return 0


func apply_surface_quality(quality: int) -> void:
	visual_quality = quality
	if _sphere_visual and _sphere_visual.material is ShaderMaterial:
		(_sphere_visual.material as ShaderMaterial).set_shader_parameter("quality", quality)


var _view_basis: Basis = Basis()
var _has_synced_view: bool = false


func set_surface_view(view_quat: Quaternion) -> void:
	_view_basis = Basis(view_quat)
	_has_synced_view = true
	# Do not show a low-detail frame while switching back from the close surface.
	if _sphere_visual and _sphere_visual.material is ShaderMaterial:
		var material := _sphere_visual.material as ShaderMaterial
		material.set_shader_parameter("quality", 2)
		material.set_shader_parameter("lod", 1.0)
		material.set_shader_parameter("surface_detail_scale", 2.2)


func sphere_view_basis() -> Basis:
	if _has_synced_view:
		return _view_basis
	return Basis(Vector3.UP, rotation)


func surface_palette() -> Dictionary:
	return {
		"deep": _ocean,
		"low": _low,
		"mid": _mid,
		"high": _high,
		"ice": _ice,
		"ocean_level": _ocean_level,
	}


func is_moon() -> bool:
	return parent_body != null


func surface_from_world(world: Vector2) -> SurfaceCoordinate:
	var local := to_local(world) / maxf(radius, 1.0)
	if local.length() > 1.0:
		local = local.normalized()
	var depth := sqrt(maxf(0.0, 1.0 - local.length_squared()))
	return SurfaceCoordinate.from_unit_vector(Vector3(local.x, -local.y, depth))


func n_at(ang: float, scale: float = 3.2) -> float:
	var c := Vector2(cos(ang), sin(ang)) * scale
	return _noise.get_noise_2d(c.x + seed_value, c.y - seed_value * 0.3) * 0.5 + 0.5


func tick(delta: float) -> void:
	orbit_angle += orbit_speed * delta
	rotate(spin_speed * delta)
	_cloud_spin += spin_speed * 0.35 * delta
	if _has_synced_view:
		_view_basis = Basis(Vector3.UP, spin_speed * delta) * _view_basis
	var center := parent_body.global_position if parent_body else Vector2.ZERO
	global_position = center + Vector2(cos(orbit_angle), sin(orbit_angle)) * orbit_radius
	if _sphere_visual and _sphere_visual.material is ShaderMaterial:
		_sphere_visual.rotation = -rotation
		var cam := get_viewport().get_camera_2d()
		var screen_radius := radius * (cam.zoom.x if cam else 1.0)
		# Tiny worlds are not readable individually.  Do not update their shader,
		# atmosphere and rings every frame when they occupy less than a pixel.
		visible = screen_radius >= 0.75
		if not visible:
			return
		var frame := Engine.get_process_frames()
		var refresh_interval := 1 if screen_radius > 90.0 else (3 if screen_radius > 24.0 else 12)
		if frame < _next_visual_refresh_frame:
			return
		_next_visual_refresh_frame = frame + refresh_interval
		var sun_world := -global_position
		var light_direction := sun_world.normalized() if sun_world.length_squared() > 1.0 else Vector2(-0.7, -0.45)
		var material := _sphere_visual.material as ShaderMaterial
		material.set_shader_parameter("light_direction", light_direction)
		material.set_shader_parameter("inverse_view_rotation", sphere_view_basis().inverse())
		material.set_shader_parameter("cloud_time", _cloud_spin)
		# Same richness as surface mode: full quality/lod whenever the disk is on screen.
		var lod := 1.0
		var quality := 1
		if screen_radius < 10.0:
			lod = 0.65
			quality = 0
		elif screen_radius > 240.0:
			# Reserve the expensive six-octave shader for a truly close inspection.
			quality = 2
		material.set_shader_parameter("lod", lod)
		material.set_shader_parameter("quality", quality)
		# Mirror surface_mode: denser ground texture as the disk grows on screen.
		var equiv_zoom := clampf(screen_radius / 110.0, 1.0, 120.0)
		material.set_shader_parameter(
			"surface_detail_scale",
			clampf(1.0 + log(equiv_zoom) * 0.45, 1.0, 3.0)
		)
		queue_redraw()
	else:
		queue_redraw()


func inertial_velocity() -> Vector2:
	var center_vel := Vector2.ZERO
	if parent_body is ProcPlanet:
		center_vel = (parent_body as ProcPlanet).inertial_velocity()
	var tangent := Vector2(-sin(orbit_angle), cos(orbit_angle))
	return center_vel + tangent * (orbit_speed * orbit_radius)


# Pose/velocity at a future time, matching tick() orbital motion (not linear drift).
func predicted_state(dt_ahead: float) -> Dictionary:
	var angle := orbit_angle + orbit_speed * dt_ahead
	var center := Vector2.ZERO
	var center_vel := Vector2.ZERO
	if parent_body is ProcPlanet:
		var parent_state: Dictionary = (parent_body as ProcPlanet).predicted_state(dt_ahead)
		center = parent_state["position"]
		center_vel = parent_state["velocity"]
	elif parent_body != null:
		center = parent_body.global_position
	var pos := center + Vector2(cos(angle), sin(angle)) * orbit_radius
	var tangent := Vector2(-sin(angle), cos(angle))
	var vel := center_vel + tangent * (orbit_speed * orbit_radius)
	return {"position": pos, "velocity": vel, "angle": angle}


func gravity_at(world: Vector2) -> Vector2:
	return OrbitalPhysics.gravity_at(world, global_position, mu, radius * 0.55)


func _draw() -> void:
	_draw_atmosphere()
	if has_rings:
		_draw_rings(0.55)


func _draw_atmosphere() -> void:
	var cam := get_viewport().get_camera_2d()
	var screen_r := radius * (cam.zoom.x if cam else 1.0)
	if screen_r < 10.0:
		return
	var layers := 14 if screen_r > 100.0 else (9 if screen_r > 36.0 else 5)
	var shell := maxf((atmo_scale - 1.0) * radius, radius * 0.08)
	var width := maxf(shell / float(layers) * 1.75, 1.25)
	for i in layers:
		var t := float(i) / float(layers - 1)
		var r := radius * lerpf(1.0, atmo_scale, t)
		var c := atmo_color
		# Dense near the limb, falling off outward. Arc rings only â€” never
		# fill the planet disk (filled circles hid a failed sphere completely).
		c.a = atmo_color.a * pow(1.0 - t, 1.4) * 0.65
		draw_arc(Vector2.ZERO, r, 0.0, TAU, 96, c, width, true)


func _draw_rings(alpha: float) -> void:
	var cam := get_viewport().get_camera_2d()
	if radius * (cam.zoom.x if cam else 1.0) < 12.0:
		return
	var xf := Transform2D(0.45, Vector2.ZERO)
	xf.y *= ring_tilt
	draw_set_transform(Vector2.ZERO, 0.45, Vector2(1.0, ring_tilt))
	var inner := radius * ring_inner
	var outer := radius * ring_outer
	var col := Color(0.82, 0.7, 0.5, alpha)
	if kind == "gas" and _low.b > 0.4:
		col = Color(0.7, 0.78, 0.88, alpha)
	var pts_o := PackedVector2Array()
	var pts_i := PackedVector2Array()
	var n := 48
	for i in n + 1:
		var a := TAU * float(i) / float(n)
		pts_o.append(Vector2(cos(a), sin(a)) * outer)
		pts_i.append(Vector2(cos(a), sin(a)) * inner)
	for i in n:
		var poly := PackedVector2Array([pts_i[i], pts_o[i], pts_o[i + 1], pts_i[i + 1]])
		var gap := absf(sin(float(i) * 0.55))
		var c := col
		c.a *= 0.45 + gap * 0.55
		if absf(float(i) / n - 0.62) < 0.04:
			c.a *= 0.15
		draw_colored_polygon(poly, c)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	xf = xf


func _draw_body() -> void:
	draw_circle(Vector2.ZERO, radius, _mid)
	draw_arc(Vector2.ZERO, radius, 0.0, TAU, 96, Color(0.75, 0.9, 1.0, 0.28), 2.0, true)


func _rim(ang: float) -> Vector2:
	var bump := 0.0 if _style == 1 else (n_at(ang, 4.0) - 0.5) * 0.07
	return Vector2(cos(ang), sin(ang)) * radius * (1.0 + bump)


func _color_at(ang: float) -> Color:
	var n := n_at(ang, 3.4)
	if _style == 1:
		var bands := sin(sin(ang) * 14.0 + n * 4.0)
		var col := _low.lerp(_mid, n)
		return col.lerp(_high, clampf(bands * 0.5 + 0.5, 0.0, 1.0))
	if _style == 2:
		return _low.lerp(_ice, clampf(n * 1.15, 0.0, 1.0)).lerp(_high, smoothstep(0.55, 0.85, n_at(ang, 8.0)))
	var ocean := 1.0 - smoothstep(_ocean_level - 0.04, _ocean_level + 0.03, n)
	var land := _low.lerp(_mid, clampf((n - _ocean_level) * 3.0, 0.0, 1.0))
	land = land.lerp(_high, smoothstep(0.62, 0.88, n))
	var col := land.lerp(_ocean, ocean)
	var ice := smoothstep(0.72, 0.95, absf(sin(ang)))
	col = col.lerp(_ice, ice * (0.85 if kind == "ocean" or kind == "ice" else 0.35))
	return col


func _draw_clouds(sun_local: Vector2) -> void:
	var segs := 72
	for i in segs:
		var ang := TAU * float(i) / float(segs) + _cloud_spin
		var cover := n_at(ang, 5.5)
		if cover < 0.55:
			continue
		var a0 := ang
		var a1 := ang + TAU / float(segs)
		var r := radius * 1.02
		var p0 := Vector2(cos(a0), sin(a0)) * r
		var p1 := Vector2(cos(a1), sin(a1)) * r
		var lit := clampf(Vector2(cos(ang), sin(ang)).dot(sun_local) * 0.4 + 0.6, 0.25, 1.0)
		var c := Color(0.93, 0.9, 0.86, (cover - 0.55) * 1.3 * 0.55)
		c = Color(c.r * lit, c.g * lit, c.b * lit, c.a)
		draw_colored_polygon(PackedVector2Array([Vector2.ZERO, p0, p1]), c)

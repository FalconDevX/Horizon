extends SceneTree

## Renders every terrain kind, plus close-ups, to PNGs.
## Usage: godot --path . -s res://.bench/shots.gd -- <out_dir> [close]

var out_dir := ""
var frames := 0
var mode := "grid"
var root3d: Node3D
var camera: Camera3D
var planets: Array[MeshInstance3D] = []

func material_for(kind: int, seed_value: int) -> ShaderMaterial:
	var p := PlanetTerrain.resolve(kind, seed_value)
	var m := ShaderMaterial.new()
	m.shader = load("res://planet_terrain.gdshader")
	for key in ["relief", "bump"]:
		m.set_shader_parameter(key, p[key])
	m.set_shader_parameter("is_gas", PlanetTerrain.is_gas(kind))
	var cols := PackedVector4Array()
	for c: Color in p["land"]:
		var l := c.srgb_to_linear(); cols.append(Vector4(l.r, l.g, l.b, 1))
	m.set_shader_parameter("land_colors", cols)
	m.set_shader_parameter("land_stops", PackedFloat32Array(p["stops"]))
	m.set_shader_parameter("liquid_shallow", p["shallow"])
	m.set_shader_parameter("liquid_deep", p["deep"])
	m.set_shader_parameter("liquid_emission", p["emission"])
	m.set_shader_parameter("liquid_gloss", p["gloss"])
	m.set_shader_parameter("rock_color", p["rock"])
	m.set_shader_parameter("slope_rock", p["slope_rock"])
	m.set_shader_parameter("dry_color", p["dry"])
	m.set_shader_parameter("dry_amount", p["dry_amount"])
	m.set_shader_parameter("strata", p["strata"])
	m.set_shader_parameter("cap_color", p["cap"])
	m.set_shader_parameter("cap_latitude", p["cap_latitude"])
	m.set_shader_parameter("atmo_color", p["atmo"])
	m.set_shader_parameter("atmo_strength", p["atmo_strength"])
	m.set_shader_parameter("atmo_haze", p["haze"])
	m.set_shader_parameter("cloud_color", p["cloud_color"])
	m.set_shader_parameter("cloud_coverage", p["clouds"])
	m.set_shader_parameter("seed_offset", float(seed_value % 997) * 1.37)
	var d := PlanetTerrain.bake(kind, seed_value, 1024, Vector3.UP, p)
	m.set_shader_parameter("height_faces", PlanetTerrain.make_texture(d))
	m.set_shader_parameter("face_size", float(d["size"]))
	m.set_shader_parameter("has_liquid", d["sea_level"] >= 0.0)
	m.set_shader_parameter("sea_level", maxf(d["sea_level"], 0.0))
	return m

func _init() -> void:
	var args := OS.get_cmdline_user_args()
	out_dir = args[0]
	if args.size() > 1: mode = args[1]
	root3d = Node3D.new()
	root.add_child(root3d)
	var body := load("res://celestial_body.gd")
	var mesh: ArrayMesh = body._make_sphere(160)
	RenderingServer.global_shader_parameter_set("sun_position", Vector3(-400, 0, 0))
	camera = Camera3D.new()
	root3d.add_child(camera)
	var env := WorldEnvironment.new(); env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.01, 0.01, 0.015)
	root3d.add_child(env)
	root.size = Vector2i(1600, 800)
	for kind in range(1, 9):
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		mi.material_override = material_for(kind, 1000 + kind * 17)
		root3d.add_child(mi)
		planets.append(mi)
	layout(mode)

func layout(which: String) -> void:
	if which == "grid":
		camera.position = Vector3(0, 0, 10)
		camera.fov = 40
		for i in planets.size():
			planets[i].visible = true
			planets[i].position = Vector3((i % 4 - 1.5) * 2.3, (0.5 - i / 4) * 2.3, 0)
			planets[i].rotation = Vector3(0.3, 0.5, 0)
	else:
		var k := int(which.substr(5))  # "close1".."close8"
		for i in planets.size():
			planets[i].visible = i == k - 1
			planets[i].position = Vector3.ZERO
			planets[i].rotation = Vector3(0.2, 0.9, 0.1)
		camera.fov = 45
		camera.look_at_from_position(Vector3(-0.55, 0.3, 1.35), Vector3(-0.3, 0.05, 0.85))

func _process(_delta: float) -> bool:
	frames += 1
	if frames == 8:
		var img := root.get_texture().get_image()
		img.save_png(out_dir + "/" + mode + ".png")
		print("saved ", mode)
		return true
	return false

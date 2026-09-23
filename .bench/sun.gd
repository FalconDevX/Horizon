extends SceneTree

var frames := 0
var out_dir := ""
var tag := ""

func _init() -> void:
	var args := OS.get_cmdline_user_args()
	out_dir = args[0]
	tag = args[1]
	var zoom := float(args[2])
	var root3d := Node3D.new()
	root.add_child(root3d)
	root.size = Vector2i(1600, 900)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.0, 0.0, 0.01)
	env.environment.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	env.environment.glow_enabled = true
	env.environment.glow_intensity = 0.7
	env.environment.glow_bloom = 0.0
	env.environment.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE
	env.environment.glow_hdr_threshold = 1.0
	root3d.add_child(env)
	var body := load("res://celestial_body.gd")
	var sphere := MeshInstance3D.new()
	sphere.mesh = body._make_sphere(160)
	var m := ShaderMaterial.new(); m.shader = load("res://planet_star.gdshader")
	m.set_shader_parameter("star_color", Color(1, 0.85, 0.3))
	sphere.material_override = m
	root3d.add_child(sphere)
	var plane := MeshInstance3D.new()
	plane.mesh = PlaneMesh.new(); (plane.mesh as PlaneMesh).size = Vector2.ONE
	var c := ShaderMaterial.new(); c.shader = load("res://planet_corona.gdshader")
	c.set_shader_parameter("star_color", Color(1, 0.85, 0.3))
	c.set_shader_parameter("extent", 5.0)
	plane.material_override = c
	plane.scale = Vector3(10, 1, 10)
	plane.position = Vector3(0, -1.2, 0)
	root3d.add_child(plane)
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = zoom
	root3d.add_child(cam)
	cam.look_at_from_position(Vector3(0, 50, 0), Vector3.ZERO, Vector3(0, 0, -1))

func _process(_d: float) -> bool:
	frames += 1
	if frames == 30:
		root.get_texture().get_image().save_png(out_dir + "/sun_" + tag + ".png")
		print("saved")
		return true
	return false

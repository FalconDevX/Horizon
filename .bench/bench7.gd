extends SceneTree

func attempt(passes: int, barrier: bool, push_bytes: int) -> void:
	var rd := RenderingServer.create_local_rendering_device()
	var shader := rd.shader_create_from_spirv(PlanetTerrain.BAKE_SHADER.get_spirv())
	var hb := rd.storage_buffer_create(6 * 64 * 64 * 4)
	var st := PackedInt32Array(); st.resize(4 + 1024)
	var sb := rd.storage_buffer_create(st.size() * 4, st.to_byte_array())
	var pa := PackedFloat32Array(); pa.resize(20); pa[1] = 64; pa[2] = 1.4; pa[0] = 1
	var pb := rd.storage_buffer_create(80, pa.to_byte_array())
	var us: Array[RDUniform] = []
	for i in 3:
		var u := RDUniform.new(); u.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER; u.binding = i
		u.add_id([hb, sb, pb][i]); us.append(u)
	var set_ := rd.uniform_set_create(us, shader, 0)
	var pipe := rd.compute_pipeline_create(shader)
	var l := rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(l, pipe)
	rd.compute_list_bind_uniform_set(l, set_, 0)
	for p in passes:
		var push := PackedInt32Array([p, 7, 0, 0]).to_byte_array()
		rd.compute_list_set_push_constant(l, push, push_bytes)
		rd.compute_list_dispatch(l, 8, 8, 6)
		if barrier: rd.compute_list_add_barrier(l)
	rd.compute_list_end()
	rd.submit(); rd.sync()
	var d := rd.buffer_get_data(hb)
	print("passes ", passes, " barrier ", barrier, " -> ", d.to_float32_array()[100])
	rd.free()

func _init() -> void:
	attempt(1, false, 16)
	attempt(2, false, 16)
	attempt(2, true, 16)
	quit()

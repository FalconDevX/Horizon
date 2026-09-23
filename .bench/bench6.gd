extends SceneTree

func _init() -> void:
	var rd := RenderingServer.create_local_rendering_device()
	var b := rd.storage_buffer_create(64)
	print("A")
	var data := rd.buffer_get_data(b)
	print("plain get ok: ", data.size())
	var shader := rd.shader_create_from_spirv(PlanetTerrain.BAKE_SHADER.get_spirv())
	print("shader valid ", shader.is_valid())
	var pipeline := rd.compute_pipeline_create(shader)
	print("pipeline valid ", pipeline.is_valid())
	quit()

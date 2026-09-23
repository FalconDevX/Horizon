extends SceneTree

func _init() -> void:
	var spirv: RDShaderSPIRV = PlanetTerrain.BAKE_SHADER.get_spirv()
	print("compile error: '", spirv.compile_error_compute, "'")
	var t := Time.get_ticks_msec()
	var holders := []
	var tasks := []
	for kind in range(1, 9):
		var h := {}
		holders.append(h)
		var p := PlanetTerrain.resolve(kind, 12345 + kind)
		tasks.append(WorkerThreadPool.add_task(func(): h["d"] = PlanetTerrain.bake(kind, 12345 + kind, 1024, Vector3.UP, p), true))
	for task in tasks:
		WorkerThreadPool.wait_for_task_completion(task)
	print("8 kinds @1024: ", Time.get_ticks_msec() - t, " ms")
	for h in holders:
		var d: Dictionary = h["d"]
		if d.is_empty():
			print("EMPTY"); continue
		var f: PackedFloat32Array = d["faces"][0]
		print(d["size"], " sea ", d["sea_level"], " sample ", f[0], " ", f[500000], " ", f[1000000])
	quit()

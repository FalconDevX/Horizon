extends SceneTree

func _init() -> void:
	for kind in [1, 5]:
		var p := PlanetTerrain.resolve(kind, 7)
		var t := Time.get_ticks_msec()
		var d := PlanetTerrain.bake(kind, 7, 512, Vector3.UP, p)
		print("kind ", kind, " @512 total: ", Time.get_ticks_msec() - t, " ms")
		t = Time.get_ticks_msec()
		var n := 0
		var g := WorkerThreadPool.add_group_task(func(i): PlanetTerrain._bake_band(kind, 7, p["frequency"], Vector3.UP, 0, 512, i / 32, (i % 32) * 16), 192, -1, true)
		WorkerThreadPool.wait_for_group_task_completion(g)
		print("  bands only: ", Time.get_ticks_msec() - t, " ms")
	quit()

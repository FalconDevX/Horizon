extends SceneTree

func _init() -> void:
	print("threads ", OS.get_processor_count())
	for kind in [1, 5]:
		var p := PlanetTerrain.resolve(kind, 7)
		var t := Time.get_ticks_msec()
		PlanetTerrain.bake(kind, 7, 256, Vector3.UP, p)
		print("kind ", kind, " @256 main thread: ", Time.get_ticks_msec() - t, " ms")
		var noises := PlanetTerrain._make_noises(7, p["frequency"])
		var storm := PlanetTerrain._roll_storm(7, Vector3.UP)
		t = Time.get_ticks_usec()
		for i in 20000:
			PlanetTerrain._raw_height(kind, Vector3(sin(i), cos(i), 0.3).normalized(), noises, Vector3.UP, 0, storm)
		print("  per sample us: ", (Time.get_ticks_usec() - t) / 20000.0)
	quit()

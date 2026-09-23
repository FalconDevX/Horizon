extends SceneTree

func _init() -> void:
	for res in [192, 512]:
		var p := PlanetTerrain.resolve(PlanetTerrain.Kind.TERRAN, 12345)
		var t := Time.get_ticks_msec()
		var d := PlanetTerrain.bake(PlanetTerrain.Kind.TERRAN, 12345, res, Vector3.UP, p)
		print("res ", res, ": ", Time.get_ticks_msec() - t, " ms, sea ", d["sea_level"])
	quit()

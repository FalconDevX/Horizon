extends SceneTree

func _init() -> void:
	var p := PlanetTerrain.resolve(1, 5)
	var d := PlanetTerrain.bake(1, 5, 64, Vector3.UP, p)
	print("main 64: ", d.get("sea_level"))
	quit()

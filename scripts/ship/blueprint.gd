class_name ShipBlueprint
extends RefCounted

const USER_PATH := "user://current_blueprint.json"
const STARTER_PATH := "res://data/blueprints/starter.json"


static func load_current() -> Dictionary:
	if FileAccess.file_exists(USER_PATH):
		var user_data := load_path(USER_PATH)
		if not user_data.is_empty():
			return user_data
	return load_path(STARTER_PATH)


static func load_path(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		return {}
	return parsed


static func save_path(data: Dictionary, path: String) -> bool:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify(data, "\t"))
	return true


static func save_current(data: Dictionary) -> bool:
	return save_path(data, USER_PATH)


static func starter_graph() -> ModuleGraph:
	var graph := ModuleGraph.new()
	graph.load_blueprint(load_path(STARTER_PATH))
	if graph.modules.is_empty():
		_fallback_starter(graph)
	return graph


static func _fallback_starter(graph: ModuleGraph) -> void:
	graph.clear()
	graph.modules.append(ShipModule.new(ModuleCatalog.get_def("cockpit_mk1"), Vector2i(1, 0), 0))
	graph.modules.append(ShipModule.new(ModuleCatalog.get_def("fuel_tank_s"), Vector2i(-1, 0), 0))
	graph.modules.append(ShipModule.new(ModuleCatalog.get_def("engine_chemical_s"), Vector2i(-3, 0), 0))
	graph.modules.append(ShipModule.new(ModuleCatalog.get_def("rcs"), Vector2i(0, 2), 0))
	graph.modules.append(ShipModule.new(ModuleCatalog.get_def("rcs"), Vector2i(0, -1), 0))
	graph.mark_dirty()

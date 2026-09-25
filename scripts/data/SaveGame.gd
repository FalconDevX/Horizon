class_name SaveGame
extends RefCounted
## Saved games on disk: one file per slot in `SAVE_DIR`, written with
## var_to_str so Vector2s, StringNames and int dictionary keys come back as
## they went in. A save is a Dictionary:
##   "meta"     - what the load list shows: name, system, day, saved_unix
##   "galaxy"   - GalaxyMap.to_dict() (visits, course, systems left behind)
##   "progress" - PlayerProgress.to_dict() (cargo hold, unlocked tech)
##   "journal"  - Journal.to_dict() (worlds seen, finds, known resources)
##   everything else is the flight scene's own (solar_system.gd
##   build_save_data() / _apply_pending_save()).
##
## Loading is two steps: begin_load() restores the static state (galaxy,
## progress) and parks the rest in `pending`; the flight scene reads its world
## seed from there in _enter_tree (before the planets generate) and applies
## the rest at the end of _ready.

const SAVE_DIR := "user://saves"
const EXTENSION := ".save"
const VERSION := 1

## The save the flight scene should restore when it next loads, or {}.
static var pending: Dictionary = {}
## The slot this session saves into; empty until the first save of a new game.
static var current_slot: String = ""


## Every save, newest first: {slot, name, system, day, saved_unix}.
static func list_saves() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var dir := DirAccess.open(SAVE_DIR)
	if dir == null:
		return result
	for file: String in dir.get_files():
		if not file.ends_with(EXTENSION):
			continue
		var slot: String = file.trim_suffix(EXTENSION)
		var data: Dictionary = read(slot)
		if data.is_empty():
			continue
		var meta: Dictionary = data.get("meta", {})
		result.append({
			"slot": slot,
			"name": String(meta.get("name", slot)),
			"system": String(meta.get("system", "")),
			"day": int(meta.get("day", 1)),
			"saved_unix": int(meta.get("saved_unix", 0)),
		})
	result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["saved_unix"] > b["saved_unix"])
	return result


static func has_saves() -> bool:
	return not list_saves().is_empty()


static func _path(slot: String) -> String:
	return "%s/%s%s" % [SAVE_DIR, slot, EXTENSION]


static func write(slot: String, data: Dictionary) -> bool:
	DirAccess.make_dir_recursive_absolute(SAVE_DIR)
	var file := FileAccess.open(_path(slot), FileAccess.WRITE)
	if file == null:
		push_error("Could not write save %s: %s" % [slot, FileAccess.get_open_error()])
		return false
	data["version"] = VERSION
	file.store_string(var_to_str(data))
	return true


static func read(slot: String) -> Dictionary:
	if not FileAccess.file_exists(_path(slot)):
		return {}
	var text: String = FileAccess.get_file_as_string(_path(slot))
	var value: Variant = str_to_var(text)
	return value if value is Dictionary else {}


static func delete(slot: String) -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(_path(slot)))
	if current_slot == slot:
		current_slot = ""


## A fresh slot name, unique to the second.
static func new_slot() -> String:
	var slot: String = "save_%d" % Time.get_unix_time_from_system()
	var n: int = 1
	while FileAccess.file_exists(_path(slot)):
		n += 1
		slot = "save_%d_%d" % [Time.get_unix_time_from_system(), n]
	return slot


## New Game: forget the galaxy and progress of any game played before in this
## run, and save into a new slot later.
static func start_new_game() -> void:
	pending = {}
	current_slot = ""
	GalaxyMap.reset()
	PlayerProgress.reset()
	Journal.clear()


## Load: restores the static state now and leaves the rest for the flight
## scene. False if the slot can't be read.
static func begin_load(slot: String) -> bool:
	var data: Dictionary = read(slot)
	if data.is_empty():
		return false
	GalaxyMap.reset()
	PlayerProgress.reset()
	GalaxyMap.from_dict(data.get("galaxy", {}))
	PlayerProgress.from_dict(data.get("progress", {}))
	Journal.clear()
	Journal.from_dict(data.get("journal", {}))
	pending = data
	current_slot = slot
	return true


## Writes the flight scene's state (plus the static parts) to the session's
## slot, making one on the first save. Returns the slot, or "" on failure.
static func save_session(scene_data: Dictionary) -> String:
	if current_slot.is_empty():
		current_slot = new_slot()
	scene_data["galaxy"] = GalaxyMap.to_dict()
	scene_data["progress"] = PlayerProgress.to_dict()
	scene_data["journal"] = Journal.to_dict()
	return current_slot if write(current_slot, scene_data) else ""

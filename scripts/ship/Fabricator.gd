class_name Fabricator
extends RefCounted
## The ship's fabricator (F): refines hel from the cargo hold into fuel, one
## batch after another, in the background - the window only queues batches
## and shows them. Two recipes: engine fuel (cheap, 1 hel a batch) and warp
## fuel (3 hel a batch, for the warp, the boost and the hyperdrive). A
## batch's hel leaves the hold when it is queued (cancelling gives it back)
## and its fuel goes into the tank when it is done. A batch is only queued
## while the tank has room for it and everything already queued for it.
## Needs a Fabricator module on the ship (god mode: none needed, no hel).
## solar_system.gd owns one and calls update() every running frame.

signal batch_done(recipe: StringName, amount: float)

const HEL := &"hel"
const MAX_QUEUE := 8
## Per recipe: name, hel a batch takes, fuel it gives (engine fuel units,
## warp tank points out of ship.WARP_FUEL_CAPACITY), seconds a batch takes.
const RECIPES := {
	&"fuel": {
		"name": "Engine fuel", "hel": 1, "yield": 30.0, "time": 6.0,
		"note": "Light refining. Burned by the main engine.",
	},
	&"warp_fuel": {
		"name": "Warp fuel", "hel": 3, "yield": 10.0, "time": 12.0,
		"note": "Dense, slow to make. Warp, boost and hyperdrive.",
	},
}
const ORDER: Array[StringName] = [&"fuel", &"warp_fuel"]

## Recipe ids, the first one being refined.
var queue: Array[StringName] = []
## Seconds into the first batch.
var progress: float = 0.0


func time_of(recipe: StringName) -> float:
	return float(RECIPES[recipe]["time"])


## 0..1 through the batch being refined (0 with nothing queued).
func share_done() -> float:
	return 0.0 if queue.is_empty() else clampf(progress / time_of(queue[0]), 0.0, 1.0)


func queued(recipe: StringName) -> int:
	return queue.count(recipe)


## Why a batch of `recipe` cannot be queued now, or "" if it can.
func problem(recipe: StringName, ship: Node, inventory: Inventory, fitted: bool) -> String:
	if not fitted:
		return "No fabricator on the ship"
	if queue.size() >= MAX_QUEUE:
		return "Queue full"
	var info: Dictionary = RECIPES[recipe]
	if not PlayerProgress.god_mode and inventory.count(HEL) < int(info["hel"]):
		return "Needs %d hel" % int(info["hel"])
	var room: float = _room(recipe, ship)
	if room < 0.0:
		return "No fuel tank"
	if room < float(info["yield"]) * float(queued(recipe) + 1) - 0.01:
		return "Tank full"
	return ""


## Space left in the tank a recipe fills (-1 with no such tank).
func _room(recipe: StringName, ship: Node) -> float:
	if recipe == &"warp_fuel":
		return float(ship.WARP_FUEL_CAPACITY) - float(ship.warp_fuel)
	if not bool(ship.resources_enabled) or float(ship.fuel_capacity) <= 0.0:
		return -1.0
	return float(ship.fuel_capacity) - float(ship.fuel)


func add(recipe: StringName, ship: Node, inventory: Inventory, fitted: bool) -> bool:
	if problem(recipe, ship, inventory, fitted) != "":
		return false
	if not PlayerProgress.god_mode:
		inventory.remove(HEL, int(RECIPES[recipe]["hel"]))
	queue.append(recipe)
	return true


## Drops batch `index` and gives its hel back.
func cancel(index: int, inventory: Inventory) -> void:
	if index < 0 or index >= queue.size():
		return
	if not PlayerProgress.god_mode:
		inventory.add(HEL, int(RECIPES[queue[index]]["hel"]))
	queue.remove_at(index)
	if index == 0:
		progress = 0.0


## Refines for `delta` seconds of game time (only with a fabricator fitted).
func update(delta: float, ship: Node, fitted: bool) -> void:
	if queue.is_empty() or not fitted:
		return
	progress += delta
	while not queue.is_empty() and progress >= time_of(queue[0]):
		progress -= time_of(queue[0])
		var recipe: StringName = queue.pop_front()
		var amount: float = maxf(minf(float(RECIPES[recipe]["yield"]), _room(recipe, ship)), 0.0)
		if recipe == &"warp_fuel":
			ship.warp_fuel = float(ship.warp_fuel) + amount
		else:
			ship.fuel = float(ship.fuel) + amount
		batch_done.emit(recipe, amount)
	if queue.is_empty():
		progress = 0.0


func to_dict() -> Dictionary:
	var ids: Array = []
	for recipe in queue:
		ids.append(String(recipe))
	return {"queue": ids, "progress": progress}


func from_dict(data: Dictionary) -> void:
	queue.clear()
	for id: Variant in data.get("queue", []):
		if RECIPES.has(StringName(str(id))):
			queue.append(StringName(str(id)))
	progress = float(data.get("progress", 0.0)) if not queue.is_empty() else 0.0

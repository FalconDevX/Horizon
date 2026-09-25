class_name PlayerProgress
extends RefCounted
## What the player owns across the session: resource stock and unlocked
## tech-tree nodes (TechTree). Static, so the shipyard and the flight scene
## share it. There is no save system yet, so it resets when the game restarts.
##
## Nothing collects resources in flight yet - the player starts with a stock
## of common and uncommon ones (enough for a few tier-2 unlocks); rare ones
## (tier 3) have to come from gathering once that exists.

## Starting stock by resource tier.
const START_STOCK := {1: 50, 2: 20, 3: 0}

static var _resources: Dictionary = {}
static var _unlocked: Dictionary = {}
static var _initialized := false


static func ensure_initialized() -> void:
	if _initialized:
		return
	_initialized = true
	for r: Dictionary in ResourceCatalog.RESOURCES:
		_resources[r["id"]] = START_STOCK.get(int(r["tier"]), 0)
	for node: Dictionary in TechTree.NODES:
		if int(node["tier"]) <= 1:
			_unlocked[node["id"]] = true


static func amount(id: StringName) -> int:
	ensure_initialized()
	return int(_resources.get(id, 0))


static func add(id: StringName, count: int) -> void:
	ensure_initialized()
	_resources[id] = maxi(amount(id) + count, 0)


static func is_unlocked(node_id: StringName) -> bool:
	ensure_initialized()
	return _unlocked.has(node_id)


## Modules no node covers are always available.
static func is_module_unlocked(module_id: StringName) -> bool:
	var node: Dictionary = TechTree.node_for_module(module_id)
	return node.is_empty() or is_unlocked(node["id"])


## Titles of the prerequisite nodes still locked.
static func missing_requirements(node: Dictionary) -> Array[String]:
	var missing: Array[String] = []
	for req: StringName in node["requires"]:
		if not is_unlocked(req):
			missing.append(String(TechTree.get_node(req).get("title", req)))
	return missing


static func can_afford(node: Dictionary) -> bool:
	var cost: Dictionary = TechTree.unlock_cost(node)
	for id: StringName in cost:
		if amount(id) < int(cost[id]):
			return false
	return true


static func can_unlock(node: Dictionary) -> bool:
	return not is_unlocked(node["id"]) and missing_requirements(node).is_empty() and can_afford(node)


## Spends the cost and unlocks; false (and nothing spent) if not allowed.
static func unlock(node: Dictionary) -> bool:
	if not can_unlock(node):
		return false
	var cost: Dictionary = TechTree.unlock_cost(node)
	for id: StringName in cost:
		_resources[id] = amount(id) - int(cost[id])
	_unlocked[node["id"]] = true
	return true

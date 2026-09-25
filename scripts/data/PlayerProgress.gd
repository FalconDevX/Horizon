class_name PlayerProgress
extends RefCounted
## What the player owns across the session: the cargo hold (an Inventory of
## resources gathered on planets - ResourceDeposits types - which the flight
## scene fills and shows) and unlocked tech-tree nodes (TechTree). Static, so
## the shipyard and the flight scene share it and it survives scene reloads
## (galaxy-map travel). There is no save system yet, so it resets when the
## game restarts. The hold starts empty: tier-1 nodes are free, the rest are
## paid for with what the player collects.

static var inventory := Inventory.new()
static var _unlocked: Dictionary = {}
static var _initialized := false


static func ensure_initialized() -> void:
	if _initialized:
		return
	_initialized = true
	for node: Dictionary in TechTree.NODES:
		if int(node["tier"]) <= 1:
			_unlocked[node["id"]] = true


static func amount(id: StringName) -> int:
	return inventory.count(id)


static func add(id: StringName, count: int) -> void:
	if count > 0:
		inventory.add(id, count)
	elif count < 0:
		inventory.remove(id, mini(-count, amount(id)))


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
		inventory.remove(id, int(cost[id]))
	_unlocked[node["id"]] = true
	return true

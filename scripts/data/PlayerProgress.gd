class_name PlayerProgress
extends RefCounted
## What the player owns across the session: the cargo hold (an Inventory of
## resources gathered on planets - ResourceDeposits types - which the flight
## scene fills and shows) and unlocked tech-tree nodes (TechTree). Static, so
## the shipyard and the flight scene share it and it survives scene reloads
## (galaxy-map travel). There is no save system yet, so it resets when the
## game restarts. The hold starts empty: tier-1 nodes are free, the rest are
## paid for with what the player collects.

## Debug "god mode" (Settings > Gameplay, SettingsManager.god_mode): every
## tech-tree node and module counts as unlocked while it is on. Nothing is
## written into `_unlocked`, so switching it off puts the real progress back.
static var god_mode := false

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


## A new game: empty hold, only the free tier unlocked.
static func reset() -> void:
	inventory.clear()
	_unlocked.clear()
	_initialized = false


## The hold and the unlocked tech, for SaveGame.
static func to_dict() -> Dictionary:
	ensure_initialized()
	return {"inventory": inventory.to_dict(), "unlocked": _unlocked.keys()}


static func from_dict(data: Dictionary) -> void:
	ensure_initialized()
	inventory.load_dict(data.get("inventory", {}))
	for node_id: StringName in data.get("unlocked", []):
		_unlocked[node_id] = true


static func amount(id: StringName) -> int:
	return inventory.count(id)


static func add(id: StringName, count: int) -> void:
	if count > 0:
		inventory.add(id, count)
	elif count < 0:
		inventory.remove(id, mini(-count, amount(id)))


static func is_unlocked(node_id: StringName) -> bool:
	ensure_initialized()
	return god_mode or _unlocked.has(node_id)


## Modules no node covers are always available.
static func is_module_unlocked(module_id: StringName) -> bool:
	if god_mode:
		return true
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
	return not payment(node).is_empty() or TechTree.unlock_cost(node).is_empty()


## What unlocking `node` would take from the hold: the recipe's resources,
## with any shortfall made up from their substitutes (TechTree.substitutes_for).
## {} if the hold cannot cover it.
static func payment(node: Dictionary) -> Dictionary:
	var cost: Dictionary = TechTree.unlock_cost(node)
	var spend: Dictionary = {}
	var left := func(id: StringName) -> int: return amount(id) - int(spend.get(id, 0))
	for id: StringName in cost:
		var need: int = int(cost[id])
		var take: int = mini(left.call(id), need)
		if take > 0:
			spend[id] = int(spend.get(id, 0)) + take
		need -= take
		for sub: StringName in TechTree.substitutes_for(node, id):
			if need <= 0:
				break
			var from_sub: int = mini(left.call(sub), need)
			if from_sub > 0:
				spend[sub] = int(spend.get(sub, 0)) + from_sub
				need -= from_sub
		if need > 0:
			return {}
	return spend


static func can_unlock(node: Dictionary) -> bool:
	return not is_unlocked(node["id"]) and missing_requirements(node).is_empty() and can_afford(node)


## Spends the cost and unlocks; false (and nothing spent) if not allowed.
static func unlock(node: Dictionary) -> bool:
	if not can_unlock(node):
		return false
	var spend: Dictionary = payment(node)
	for id: StringName in spend:
		inventory.remove(id, int(spend[id]))
	_unlocked[node["id"]] = true
	return true

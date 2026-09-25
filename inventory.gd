class_name Inventory
extends RefCounted

## What the ship carries: item id -> count, in the order things were first
## picked up, plus where each came from. Items are resource types
## (ResourceDeposits.TYPES keys) for now. Plain data - anything that shows it
## (InventoryView) binds to it and redraws on `changed`.

signal changed

var _counts: Dictionary = {}
## id -> {source name: count} - where the ship picked each item up.
var _sources: Dictionary = {}


func add(id: StringName, amount: int = 1, source: String = "") -> void:
	_counts[id] = _counts.get(id, 0) + amount
	if not source.is_empty():
		var sources: Dictionary = _sources.get_or_add(id, {})
		sources[source] = sources.get(source, 0) + amount
	changed.emit()


## Takes `amount` away; false (and nothing taken) if there are not that many.
func remove(id: StringName, amount: int = 1) -> bool:
	if count(id) < amount:
		return false
	_counts[id] -= amount
	if _counts[id] == 0:
		_counts.erase(id)
		_sources.erase(id)
	changed.emit()
	return true


func count(id: StringName) -> int:
	return _counts.get(id, 0)


## Every item held, in pickup order.
func ids() -> Array:
	return _counts.keys()


## source name -> count, for one item.
func sources(id: StringName) -> Dictionary:
	return _sources.get(id, {})


func total() -> int:
	var sum: int = 0
	for amount: int in _counts.values():
		sum += amount
	return sum


func is_empty() -> bool:
	return _counts.is_empty()

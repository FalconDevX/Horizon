class_name Journal
extends RefCounted

## What the player has learned, across every system they visit: for each
## planet (by name - galaxy-map travel re-rolls the same planets), which of its
## variants and traits they have seen and what they found on each variant, and
## which resource types they know. Static, like PlayerProgress, so it survives
## travel and scene reloads; there is no save system yet.
##
## A "variant" is terrain_params.variant ("" for kinds without one); a "trait"
## is a flag a roll can set beside it (PlanetLore.FLAG_LABELS: blind, julia,
## rings).

## body name -> {variant: true}
static var _variants: Dictionary = {}
## body name -> {trait: true}
static var _traits: Dictionary = {}
## body name -> {variant: {resource type: true}}; a trait's finds are kept
## under "#<trait>" as well, so its card can tell them apart.
static var _finds: Dictionary = {}
## resource type -> true
static var _known: Dictionary = {}


## Notes the world `body_name` is now: its variant and every trait it has.
static func record_world(body_name: String, params: Dictionary) -> void:
	_variants.get_or_add(body_name, {})[params.get("variant", "")] = true
	for flag: String in PlanetLore.FLAG_LABELS:
		if params.get(flag, false) == true:
			_traits.get_or_add(body_name, {})[flag] = true


## Notes a resource found on `body_name` while it was the world `params`.
static func record_find(body_name: String, params: Dictionary, type_name: StringName) -> void:
	record_world(body_name, params)
	var by_variant: Dictionary = _finds.get_or_add(body_name, {})
	by_variant.get_or_add(params.get("variant", ""), {})[type_name] = true
	for flag: String in PlanetLore.FLAG_LABELS:
		if params.get(flag, false) == true:
			by_variant.get_or_add("#" + flag, {})[type_name] = true
	_known[type_name] = true


static func has_seen(body_name: String, variant: String) -> bool:
	return _variants.get(body_name, {}).has(variant)


static func has_seen_trait(body_name: String, flag: String) -> bool:
	return _traits.get(body_name, {}).has(flag)


## How many of `body_name`'s variants have been seen.
static func seen_count(body_name: String) -> int:
	return _variants.get(body_name, {}).size()


static func is_found(body_name: String, variant: String, type_name: StringName) -> bool:
	return _finds.get(body_name, {}).get(variant, {}).has(type_name)


## Whether this type was found on `body_name` while it had the trait `flag`.
static func is_found_with_trait(body_name: String, flag: String, type_name: StringName) -> bool:
	return is_found(body_name, "#" + flag, type_name)


## Every variant of `body_name` this type was found on.
static func variants_found_on(body_name: String, type_name: StringName) -> Array:
	var variants: Array = []
	var by_variant: Dictionary = _finds.get(body_name, {})
	for variant: String in by_variant:
		if not variant.begins_with("#") and by_variant[variant].has(type_name):
			variants.append(variant)
	return variants


static func is_known(type_name: StringName) -> bool:
	return _known.has(type_name)


## Forgets everything - a new game.
static func clear() -> void:
	_variants.clear()
	_traits.clear()
	_finds.clear()
	_known.clear()

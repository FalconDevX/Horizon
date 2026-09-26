class_name TechTree
extends RefCounted
## The ship-module tech tree, built from the Horizon Miro board: the branches
## and modules of the "Moduły statku" frame, tiers and recipes from the
## "Receptury modułów (surowce × tier)" table. A node is one module from the
## board; it unlocks one or more catalog modules (its sizes / variants).
##
## Each node's `cost` is what unlocking it takes (resource id → amount), from
## the board's "Przedmioty × surowce (ilości do odblokowania)" table;
## PlayerProgress spends it from the cargo hold. A node with no cost (the
## cockpit) is open from the start; every other node, tier 1 included, is
## bought. Costs name ResourceDeposits types - what the player gathers on
## planets (the board's "Snow wurm" is ice_wurm, "Moonbloom" is beanstalk).
## Drones and the fabricator have no amounts on the board yet and keep
## placeholder costs. Branches follow the board's "Receptury modułów" table
## (fuel tanks under propulsion, shields under structure). The `requires`
## links are not on the board - they follow each branch's natural
## progression.
##
## Substitutes (PlayerProgress pays with them when the named resource runs
## short, in this order): frozen moonbloom for moonbloom (SUBSTITUTES - the
## same flower recoloured, as the bones are); then the wildcards, which are
## in no cost themselves - slime jelly for anything in a weapon or structure
## cost, silver spheres for anything in a propulsion, power or support cost,
## and egg for anything at all.

enum Branch { STRUCTURE, WEAPONS, PROPULSION, POWER, SUPPORT }

const BRANCH_NAMES := {
	Branch.STRUCTURE: "Structure",
	Branch.WEAPONS: "Weapons",
	Branch.PROPULSION: "Propulsion",
	Branch.POWER: "Power & Storage",
	Branch.SUPPORT: "Support",
}

const BRANCH_ORDER: Array[Branch] = [
	Branch.STRUCTURE, Branch.WEAPONS, Branch.PROPULSION, Branch.POWER, Branch.SUPPORT,
]

## Resources that stand in for one short in a cost, in the order they are
## spent (see the header).
const SUBSTITUTES := {&"beanstalk": [&"frozen_beanstalk"]}
## Wildcard → the branches whose costs it can make up; &"egg" covers all.
const WILDCARDS := {
	&"slime_jelly": [Branch.WEAPONS, Branch.STRUCTURE],
	&"silver_spheres": [Branch.PROPULSION, Branch.POWER, Branch.SUPPORT],
	&"egg": [Branch.STRUCTURE, Branch.WEAPONS, Branch.PROPULSION, Branch.POWER, Branch.SUPPORT],
}

const TIER_NAMES := {1: "Basic", 2: "Advanced", 3: "Elite"}
## The tree's tier colours: grey, blue, violet.
const TIER_COLORS := {
	1: Color(0.87, 0.87, 0.85),
	2: Color(0.61, 0.9, 1.0),
	3: Color(0.72, 0.67, 0.98),
}

const NODES := [
	# --- Structure ---
	{"id": &"hull_light", "title": "Light Hull", "branch": Branch.STRUCTURE, "tier": 1,
		"cost": {&"scrap": 1}, "requires": [], "modules": [&"hull_light"]},
	{"id": &"truss", "title": "Truss", "branch": Branch.STRUCTURE, "tier": 1,
		"cost": {&"silver_ore": 2, &"gold_ore": 2}, "requires": [], "modules": [&"truss_1", &"truss_2", &"truss_3"],
		"note": "Mounting frame for guns, reaching further out from the hull."},
	{"id": &"connectors", "title": "Connectors", "branch": Branch.STRUCTURE, "tier": 1,
		"cost": {&"ice_crystal": 6, &"pink_crystal": 3}, "requires": [],
		"modules": [&"connector_straight", &"connector_elbow", &"connector_t", &"connector_cross"]},
	{"id": &"cockpit", "title": "Cockpit", "branch": Branch.STRUCTURE, "tier": 1,
		"cost": {}, "requires": [], "modules": [&"cockpit"]},
	{"id": &"hull_standard", "title": "Standard Hull", "branch": Branch.STRUCTURE, "tier": 2,
		"cost": {&"scrap": 2, &"gold_ore": 1, &"pink_crystal": 1}, "requires": [&"hull_light"], "modules": [&"hull_standard"]},
	{"id": &"hull_heavy", "title": "Heavy Hull", "branch": Branch.STRUCTURE, "tier": 3,
		"cost": {&"gold_ore": 1, &"pink_crystal": 1, &"gold_pillar": 1}, "requires": [&"hull_standard"], "modules": [&"hull_heavy"]},

	{"id": &"shields", "title": "Shields", "branch": Branch.STRUCTURE, "tier": 2,
		"cost": {&"silver_ore": 6, &"ice_crystal": 2, &"beanstalk": 4}, "requires": [&"hull_light"],
		"modules": [&"shield_deflector", &"shield_barrier", &"shield_aegis"],
		"note": "An extra shield bar on top of HP; switchable, costs power."},

	# --- Weapons ---
	{"id": &"revolver", "title": "Revolver Cannon", "branch": Branch.WEAPONS, "tier": 1,
		"cost": {&"silver_ore": 4, &"gold_ore": 2}, "requires": [], "modules": [&"weapon_revolver"]},
	{"id": &"laser", "title": "High-Power Laser (DEW)", "branch": Branch.WEAPONS, "tier": 2,
		"cost": {&"silver_ore": 3, &"pink_crystal": 1, &"sky_stone": 1, &"bone": 3}, "requires": [&"revolver"], "modules": [&"weapon_laser"]},
	{"id": &"coilgun", "title": "Coilgun: Shotgun", "branch": Branch.WEAPONS, "tier": 2,
		"cost": {&"ice_crystal": 2, &"bone": 3}, "requires": [&"revolver"], "modules": [&"weapon_coilgun"]},
	{"id": &"rockets", "title": "Rocket Launcher", "branch": Branch.WEAPONS, "tier": 2,
		"cost": {&"scrap": 2, &"beanstalk": 5, &"gold_pillar": 1}, "requires": [&"revolver"], "modules": [&"weapon_rockets"]},
	{"id": &"sniper_laser", "title": "Sniper Laser", "branch": Branch.WEAPONS, "tier": 2,
		"cost": {&"gold_ore": 2, &"ice_crystal": 1, &"pink_crystal": 1, &"sky_stone": 6}, "requires": [&"laser"], "modules": [&"weapon_sniper"],
		"note": "A long yellow beam that hits at very long range, in a narrow cone."},
	{"id": &"drones", "title": "Drones (?)", "branch": Branch.WEAPONS, "tier": 2,
		"cost": {&"silver_ore": 10, &"pink_crystal": 10, &"beanstalk": 10}, "requires": [&"laser"], "modules": [&"weapon_drones"],
		"note": "An idea still to be confirmed on the board."},
	{"id": &"gauss", "title": "Gauss Cannon / Railgun", "branch": Branch.WEAPONS, "tier": 3,
		"cost": {&"gold_ore": 4, &"toxic_ore": 2, &"gold_pillar": 5}, "requires": [&"coilgun"],
		"modules": [&"weapon_gauss", &"weapon_railgun"]},
	{"id": &"sniper", "title": "Particle Cannon: Sniper", "branch": Branch.WEAPONS, "tier": 3,
		"cost": {&"silver_ore": 4, &"ice_wurm": 7}, "requires": [&"laser"], "modules": [&"weapon_particle"]},

	# --- Propulsion ---
	{"id": &"engine_chemical", "title": "Chemical Engine", "branch": Branch.PROPULSION, "tier": 1,
		"cost": {&"scrap": 4}, "requires": [],
		"modules": [&"engine_chemical_s", &"engine_chemical_m", &"engine_chemical_l"]},
	{"id": &"engine_ion", "title": "Ion Engine", "branch": Branch.PROPULSION, "tier": 2,
		"cost": {&"scrap": 2, &"silver_ore": 2, &"gold_ore": 2, &"sky_stone": 3}, "requires": [&"engine_chemical"],
		"modules": [&"engine_ion_s", &"engine_ion_m", &"engine_ion_l"]},
	{"id": &"engine_plasma", "title": "Plasma Engine", "branch": Branch.PROPULSION, "tier": 2,
		"cost": {&"scrap": 2, &"silver_ore": 2, &"gold_ore": 2, &"ice_wurm": 2}, "requires": [&"engine_chemical"],
		"modules": [&"engine_plasma_s", &"engine_plasma_m", &"engine_plasma_l"]},
	{"id": &"engine_nuclear", "title": "Nuclear Thermal Engine", "branch": Branch.PROPULSION, "tier": 3,
		"cost": {&"scrap": 2, &"bone": 6, &"beanstalk": 4, &"toxic_ore": 6}, "requires": [&"engine_plasma"],
		"modules": [&"engine_nuclear_s", &"engine_nuclear_m", &"engine_nuclear_l"]},
	{"id": &"engine_fusion", "title": "Fusion Engine", "branch": Branch.PROPULSION, "tier": 3,
		"cost": {&"scrap": 4, &"ice_crystal": 4, &"pink_crystal": 4, &"sky_stone": 4, &"gold_pillar": 2, &"ice_wurm": 2}, "requires": [&"engine_plasma"],
		"modules": [&"engine_fusion_s", &"engine_fusion_m", &"engine_fusion_l"]},

	{"id": &"fuel_tank", "title": "Fuel Tank", "branch": Branch.PROPULSION, "tier": 1,
		"cost": {&"scrap": 4}, "requires": [],
		"modules": [&"fuel_s", &"fuel_s_armored", &"fuel_m", &"fuel_m_armored", &"fuel_l", &"fuel_l_armored"]},

	# --- Power & storage ---
	{"id": &"generator", "title": "Generator (fuel)", "branch": Branch.POWER, "tier": 1,
		"cost": {&"scrap": 3, &"silver_ore": 3, &"gold_ore": 3}, "requires": [], "modules": [&"util_generator"]},
	{"id": &"solar", "title": "Solar Panels", "branch": Branch.POWER, "tier": 1,
		"cost": {&"ice_crystal": 2, &"beanstalk": 3, &"toxic_ore": 1}, "requires": [], "modules": [&"util_solar"]},
	{"id": &"batteries", "title": "Batteries", "branch": Branch.POWER, "tier": 1,
		"cost": {&"scrap": 2}, "requires": [],
		"modules": [&"battery_s", &"battery_s_armored", &"battery_m", &"battery_m_armored",
			&"battery_l", &"battery_l_armored"]},

	# --- Support ---
	{"id": &"sonar", "title": "Sonar / Radar", "branch": Branch.SUPPORT, "tier": 1,
		"cost": {&"pink_crystal": 2}, "requires": [],
		"modules": [&"radar_proximity", &"radar_survey", &"radar_deep"],
		"note": "Detects nearby enemies."},
	{"id": &"repair", "title": "Repair Module", "branch": Branch.SUPPORT, "tier": 2,
		"cost": {&"gold_ore": 6, &"sky_stone": 2}, "requires": [&"sonar"], "modules": [&"util_repair"],
		"note": "Repairs neighbouring modules; power hungry, can be switched off."},
	{"id": &"fabricator", "title": "Fabricator", "branch": Branch.SUPPORT, "tier": 2,
		"cost": {&"scrap": 10, &"gold_ore": 10, &"pink_crystal": 10}, "requires": [&"repair"], "modules": [&"util_fabricator"],
		"note": "No recipe on the board yet - this one is a placeholder."},
]


static func get_node(id: StringName) -> Dictionary:
	for node: Dictionary in NODES:
		if node["id"] == id:
			return node
	return {}


static func nodes_in(branch: Branch) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for node: Dictionary in NODES:
		if node["branch"] == branch:
			result.append(node)
	return result


## The node that unlocks a catalog module, or {} if none does.
static func node_for_module(module_id: StringName) -> Dictionary:
	for node: Dictionary in NODES:
		if (node["modules"] as Array).has(module_id):
			return node
	return {}


## Resource id → amount needed to unlock `node` (empty = free).
static func unlock_cost(node: Dictionary) -> Dictionary:
	return node.get("cost", {})


## The resources `node` costs, in the order its cost lists them.
static func recipe(node: Dictionary) -> Array[StringName]:
	var ids: Array[StringName] = []
	ids.assign(unlock_cost(node).keys())
	return ids


## `id` and what pays like it in any cost (frozen moonbloom for moonbloom) -
## the wildcards not included.
static func payable_with(id: StringName) -> Array[StringName]:
	var ids: Array[StringName] = [id]
	for sub: StringName in SUBSTITUTES.get(id, []):
		ids.append(sub)
	return ids


## What can make up a shortfall of `resource` in `node`'s cost, in the order
## it is spent: SUBSTITUTES, then the wildcards whose branches include the
## node's (egg last).
static func substitutes_for(node: Dictionary, resource: StringName) -> Array[StringName]:
	var list: Array[StringName] = []
	for sub: StringName in SUBSTITUTES.get(resource, []):
		list.append(sub)
	for wildcard: StringName in WILDCARDS:
		if wildcard != resource and (WILDCARDS[wildcard] as Array).has(node["branch"]):
			list.append(wildcard)
	return list

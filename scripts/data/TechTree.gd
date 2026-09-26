class_name TechTree
extends RefCounted
## The ship-module tech tree, from the Horizon Miro board: branches and tiers
## from the "Przedmioty × surowce (ilości do odblokowania)" table, which also
## gives every item's price in the resources gathered on planets
## (ResourceDeposits types; the board's Moonbloom is `beanstalk`, Snow wurm
## `ice_wurm`, Silver balls `silver_spheres`). A node is one item from the
## board; it unlocks one or more catalog modules (its sizes / variants).
##
## Tier 1 nodes are open from the start (the board's sum for them is 0; their
## amounts show as the recipe). Higher tiers need the nodes in `requires`
## unlocked first and cost their `cost` from the cargo hold. Items the board
## prices only as a total (Drones, Fabricator) split it evenly over their
## recipe. The `requires` links are not on the board - they follow each
## branch's natural progression. The board's Floor (removed from the game)
## and Surface Scanner (no module yet) have no node.
##
## Substitutes, from the board's "Surowce → moduły" table (PlayerProgress
## pays with them when the named resource runs short): frozen beanstalk for
## beanstalk; slime jelly for anything in a weapon or structure recipe; egg
## for anything at all.

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
		"cost": {&"scrap": 2, &"gold_ore": 1, &"pink_crystal": 1}, "requires": [&"hull_light"],
		"modules": [&"hull_standard"]},
	{"id": &"hull_heavy", "title": "Heavy Hull", "branch": Branch.STRUCTURE, "tier": 3,
		"cost": {&"gold_ore": 1, &"pink_crystal": 1, &"gold_pillar": 1}, "requires": [&"hull_standard"],
		"modules": [&"hull_heavy"]},

	# --- Weapons ---
	{"id": &"revolver", "title": "Revolver Cannon", "branch": Branch.WEAPONS, "tier": 1,
		"cost": {&"silver_ore": 4, &"gold_ore": 2}, "requires": [], "modules": [&"weapon_revolver"]},
	{"id": &"laser", "title": "High-Power Laser (DEW)", "branch": Branch.WEAPONS, "tier": 2,
		"cost": {&"bone": 3, &"silver_ore": 3, &"sky_stone": 1, &"pink_crystal": 1}, "requires": [&"revolver"],
		"modules": [&"weapon_laser"]},
	{"id": &"coilgun", "title": "Coilgun: Shotgun", "branch": Branch.WEAPONS, "tier": 2,
		"cost": {&"bone": 3, &"ice_crystal": 2}, "requires": [&"revolver"], "modules": [&"weapon_coilgun"]},
	{"id": &"rockets", "title": "Rocket Launcher", "branch": Branch.WEAPONS, "tier": 2,
		"cost": {&"beanstalk": 5, &"scrap": 2, &"gold_pillar": 1}, "requires": [&"revolver"],
		"modules": [&"weapon_rockets"]},
	{"id": &"sniper_laser", "title": "Sniper Laser", "branch": Branch.WEAPONS, "tier": 2,
		"cost": {&"sky_stone": 6, &"ice_crystal": 1, &"gold_ore": 2, &"pink_crystal": 1}, "requires": [&"laser"],
		"modules": [&"weapon_sniper"],
		"note": "A long yellow beam that hits at very long range, in a narrow cone."},
	{"id": &"drones", "title": "Drones (?)", "branch": Branch.WEAPONS, "tier": 2,
		"cost": {&"silver_ore": 10, &"pink_crystal": 10, &"beanstalk": 10}, "requires": [&"laser"],
		"modules": [&"weapon_drones"],
		"note": "An idea still to be confirmed on the board (priced 30 in all)."},
	{"id": &"gauss", "title": "Gauss Cannon / Railgun", "branch": Branch.WEAPONS, "tier": 3,
		"cost": {&"toxic_ore": 2, &"gold_ore": 4, &"gold_pillar": 5}, "requires": [&"coilgun"],
		"modules": [&"weapon_gauss", &"weapon_railgun"]},
	{"id": &"sniper", "title": "Particle Cannon", "branch": Branch.WEAPONS, "tier": 3,
		"cost": {&"silver_ore": 4, &"ice_wurm": 7}, "requires": [&"laser"], "modules": [&"weapon_particle"]},

	# --- Propulsion ---
	{"id": &"engine_chemical", "title": "Chemical Engine", "branch": Branch.PROPULSION, "tier": 1,
		"cost": {&"scrap": 4}, "requires": [],
		"modules": [&"engine_chemical_s", &"engine_chemical_m", &"engine_chemical_l"]},
	{"id": &"engine_ion", "title": "Ion Engine", "branch": Branch.PROPULSION, "tier": 2,
		"cost": {&"silver_ore": 2, &"sky_stone": 3, &"scrap": 2, &"gold_ore": 2}, "requires": [&"engine_chemical"],
		"modules": [&"engine_ion_s", &"engine_ion_m", &"engine_ion_l"]},
	{"id": &"engine_plasma", "title": "Plasma Engine", "branch": Branch.PROPULSION, "tier": 2,
		"cost": {&"silver_ore": 2, &"scrap": 2, &"ice_wurm": 2, &"gold_ore": 2}, "requires": [&"engine_chemical"],
		"modules": [&"engine_plasma_s", &"engine_plasma_m", &"engine_plasma_l"]},
	{"id": &"engine_nuclear", "title": "Nuclear Thermal Engine", "branch": Branch.PROPULSION, "tier": 3,
		"cost": {&"toxic_ore": 6, &"beanstalk": 4, &"bone": 6, &"scrap": 2}, "requires": [&"engine_plasma"],
		"modules": [&"engine_nuclear_s", &"engine_nuclear_m", &"engine_nuclear_l"]},
	{"id": &"engine_fusion", "title": "Fusion Engine", "branch": Branch.PROPULSION, "tier": 3,
		"cost": {&"sky_stone": 4, &"ice_crystal": 4, &"ice_wurm": 2, &"scrap": 4, &"pink_crystal": 4,
			&"gold_pillar": 2},
		"requires": [&"engine_plasma"],
		"modules": [&"engine_fusion_s", &"engine_fusion_m", &"engine_fusion_l"]},

	# --- Power & storage ---
	{"id": &"fuel_tank", "title": "Fuel Tank", "branch": Branch.POWER, "tier": 1,
		"cost": {&"scrap": 4}, "requires": [],
		"modules": [&"fuel_s", &"fuel_s_armored", &"fuel_m", &"fuel_m_armored", &"fuel_l", &"fuel_l_armored"]},
	{"id": &"generator", "title": "Generator (fuel)", "branch": Branch.POWER, "tier": 1,
		"cost": {&"silver_ore": 3, &"scrap": 3, &"gold_ore": 3}, "requires": [], "modules": [&"util_generator"]},
	{"id": &"solar", "title": "Solar Panels", "branch": Branch.POWER, "tier": 1,
		"cost": {&"toxic_ore": 1, &"beanstalk": 3, &"ice_crystal": 2}, "requires": [], "modules": [&"util_solar"]},
	{"id": &"batteries", "title": "Batteries", "branch": Branch.POWER, "tier": 1,
		"cost": {&"scrap": 2}, "requires": [],
		"modules": [&"battery_s", &"battery_s_armored", &"battery_m", &"battery_m_armored",
			&"battery_l", &"battery_l_armored"]},

	# --- Support ---
	{"id": &"sonar", "title": "Sonar / Radar", "branch": Branch.SUPPORT, "tier": 1,
		"cost": {&"pink_crystal": 2}, "requires": [],
		"modules": [&"radar_proximity", &"radar_survey", &"radar_deep"],
		"note": "Radar scans find enemies far off; planets hide them."},
	{"id": &"shields", "title": "Shields", "branch": Branch.SUPPORT, "tier": 2,
		"cost": {&"beanstalk": 4, &"silver_ore": 6, &"ice_crystal": 2}, "requires": [&"sonar"],
		"modules": [&"shield_deflector", &"shield_barrier", &"shield_aegis"],
		"note": "An extra shield bar on top of HP; switchable, costs power."},
	{"id": &"repair", "title": "Repair Module", "branch": Branch.SUPPORT, "tier": 2,
		"cost": {&"sky_stone": 2, &"gold_ore": 6}, "requires": [&"sonar"], "modules": [&"util_repair"],
		"note": "Repairs neighbouring modules; power hungry, can be switched off."},
	{"id": &"fabricator", "title": "Fabricator", "branch": Branch.SUPPORT, "tier": 2,
		"cost": {&"scrap": 10, &"gold_ore": 10, &"pink_crystal": 10}, "requires": [&"repair"],
		"modules": [&"util_fabricator"],
		"note": "Priced 30 in all on the board, with no breakdown yet."},
]


## A node's resources, in its cost's order.
static func recipe(node: Dictionary) -> Array[StringName]:
	var ids: Array[StringName] = []
	for id: StringName in node.get("cost", {}):
		ids.append(id)
	return ids


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


## Resources that can stand in for one short in a recipe, in the order they
## are spent (see the header).
const SUBSTITUTES := {&"beanstalk": [&"frozen_beanstalk"]}
const SLIME_BRANCHES: Array[Branch] = [Branch.WEAPONS, Branch.STRUCTURE]


static func substitutes_for(node: Dictionary, resource: StringName) -> Array[StringName]:
	var list: Array[StringName] = []
	for sub: StringName in SUBSTITUTES.get(resource, []):
		list.append(sub)
	if resource != &"slime_jelly" and SLIME_BRANCHES.has(node["branch"]):
		list.append(&"slime_jelly")
	if resource != &"egg":
		list.append(&"egg")
	return list


## Resource id → amount needed to unlock `node` (empty for tier 1).
static func unlock_cost(node: Dictionary) -> Dictionary:
	# Tier 1 is open from the start: its amounts are only the recipe.
	if int(node["tier"]) <= 1:
		return {}
	return (node.get("cost", {}) as Dictionary).duplicate()

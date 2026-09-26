class_name TechTree
extends RefCounted
## The ship-module tech tree, built from the Horizon Miro board: the branches
## and modules of the "Moduły statku" frame, tiers and recipes from the
## "Receptury modułów (surowce × tier)" table. A node is one module from the
## board; it unlocks one or more catalog modules (its sizes / variants).
##
## Tier 1 nodes are open from the start. Higher tiers need the nodes in
## `requires` unlocked first and cost UNLOCK_COST[tier] of every resource in
## the node's recipe (PlayerProgress spends it from the cargo hold). Recipes
## name ResourceDeposits types - what the player gathers on planets; the
## board's raw materials were mapped onto them (iron → scrap, aluminium →
## silver ore, copper → gold ore, silicon → pink crystal, nickel → sky stone,
## titanium → bone, lithium → beanstalk, xenon → slime jelly, uranium → toxic
## ore, tungsten → gold pillar, neodymium → egg). The `requires` links are not
## on the board - they follow each branch's natural progression. Branches
## follow the board's "Receptury modułów" table (fuel tanks under propulsion,
## shields under structure).
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

## Resource units of each recipe ingredient to unlock a node, by tier.
const UNLOCK_COST := {1: 0, 2: 10, 3: 20}

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
		"recipe": [&"silver_ore"], "requires": [], "modules": [&"hull_light"]},
	{"id": &"truss", "title": "Truss", "branch": Branch.STRUCTURE, "tier": 1,
		"recipe": [&"silver_ore"], "requires": [], "modules": [&"truss_1", &"truss_2", &"truss_3"],
		"note": "Mounting frame for guns, reaching further out from the hull."},
	{"id": &"connectors", "title": "Connectors", "branch": Branch.STRUCTURE, "tier": 1,
		"recipe": [&"scrap"], "requires": [],
		"modules": [&"connector_straight", &"connector_elbow", &"connector_t", &"connector_cross"]},
	{"id": &"cockpit", "title": "Cockpit", "branch": Branch.STRUCTURE, "tier": 1,
		"recipe": [&"silver_ore", &"gold_ore", &"pink_crystal"], "requires": [], "modules": [&"cockpit"]},
	{"id": &"hull_standard", "title": "Standard Hull", "branch": Branch.STRUCTURE, "tier": 2,
		"recipe": [&"scrap", &"sky_stone"], "requires": [&"hull_light"], "modules": [&"hull_standard"]},
	{"id": &"hull_heavy", "title": "Heavy Hull", "branch": Branch.STRUCTURE, "tier": 3,
		"recipe": [&"bone", &"gold_pillar"], "requires": [&"hull_standard"], "modules": [&"hull_heavy"]},

	{"id": &"shields", "title": "Shields", "branch": Branch.STRUCTURE, "tier": 2,
		"recipe": [&"gold_ore", &"beanstalk"], "requires": [&"hull_light"],
		"modules": [&"shield_deflector", &"shield_barrier", &"shield_aegis"],
		"note": "An extra shield bar on top of HP; switchable, costs power."},

	# --- Weapons ---
	{"id": &"revolver", "title": "Revolver Cannon", "branch": Branch.WEAPONS, "tier": 1,
		"recipe": [&"scrap", &"gold_ore", &"slime_jelly"], "requires": [], "modules": [&"weapon_revolver"]},
	{"id": &"laser", "title": "High-Power Laser (DEW)", "branch": Branch.WEAPONS, "tier": 2,
		"recipe": [&"gold_ore", &"pink_crystal"], "requires": [&"revolver"], "modules": [&"weapon_laser"]},
	{"id": &"coilgun", "title": "Coilgun: Shotgun", "branch": Branch.WEAPONS, "tier": 2,
		"recipe": [&"gold_ore"], "requires": [&"revolver"], "modules": [&"weapon_coilgun"]},
	{"id": &"rockets", "title": "Rocket Launcher", "branch": Branch.WEAPONS, "tier": 2,
		"recipe": [&"silver_ore", &"bone", &"scrap"], "requires": [&"revolver"], "modules": [&"weapon_rockets"]},
	{"id": &"sniper_laser", "title": "Sniper Laser", "branch": Branch.WEAPONS, "tier": 2,
		"recipe": [&"gold_ore", &"pink_crystal", &"beanstalk"], "requires": [&"laser"], "modules": [&"weapon_sniper"],
		"note": "A long yellow beam that hits at very long range, in a narrow cone."},
	{"id": &"drones", "title": "Drones (?)", "branch": Branch.WEAPONS, "tier": 2,
		"recipe": [&"silver_ore", &"pink_crystal", &"beanstalk"], "requires": [&"laser"], "modules": [&"weapon_drones"],
		"note": "An idea still to be confirmed on the board."},
	{"id": &"gauss", "title": "Gauss Cannon / Railgun", "branch": Branch.WEAPONS, "tier": 3,
		"recipe": [&"gold_ore", &"gold_pillar", &"egg"], "requires": [&"coilgun"],
		"modules": [&"weapon_gauss", &"weapon_railgun"]},
	{"id": &"sniper", "title": "Particle Cannon: Sniper", "branch": Branch.WEAPONS, "tier": 3,
		"recipe": [&"bone", &"egg", &"toxic_ore"], "requires": [&"laser"], "modules": [&"weapon_particle"]},

	# --- Propulsion ---
	{"id": &"engine_chemical", "title": "Chemical Engine", "branch": Branch.PROPULSION, "tier": 1,
		"recipe": [&"scrap", &"gold_ore"], "requires": [],
		"modules": [&"engine_chemical_s", &"engine_chemical_m", &"engine_chemical_l"]},
	{"id": &"engine_ion", "title": "Ion Engine", "branch": Branch.PROPULSION, "tier": 2,
		"recipe": [&"pink_crystal", &"silver_ore"], "requires": [&"engine_chemical"],
		"modules": [&"engine_ion_s", &"engine_ion_m", &"engine_ion_l"]},
	{"id": &"engine_plasma", "title": "Plasma Engine", "branch": Branch.PROPULSION, "tier": 2,
		"recipe": [&"bone", &"gold_ore"], "requires": [&"engine_chemical"],
		"modules": [&"engine_plasma_s", &"engine_plasma_m", &"engine_plasma_l"]},
	{"id": &"engine_nuclear", "title": "Nuclear Thermal Engine", "branch": Branch.PROPULSION, "tier": 3,
		"recipe": [&"scrap", &"slime_jelly", &"toxic_ore"], "requires": [&"engine_plasma"],
		"modules": [&"engine_nuclear_s", &"engine_nuclear_m", &"engine_nuclear_l"]},
	{"id": &"engine_fusion", "title": "Fusion Engine", "branch": Branch.PROPULSION, "tier": 3,
		"recipe": [&"gold_pillar", &"egg", &"beanstalk"], "requires": [&"engine_plasma"],
		"modules": [&"engine_fusion_s", &"engine_fusion_m", &"engine_fusion_l"]},

	{"id": &"fuel_tank", "title": "Fuel Tank", "branch": Branch.PROPULSION, "tier": 1,
		"recipe": [&"scrap", &"silver_ore"], "requires": [],
		"modules": [&"fuel_s", &"fuel_s_armored", &"fuel_m", &"fuel_m_armored", &"fuel_l", &"fuel_l_armored"]},

	# --- Power & storage ---
	{"id": &"generator", "title": "Generator (fuel)", "branch": Branch.POWER, "tier": 1,
		"recipe": [&"scrap", &"gold_ore"], "requires": [], "modules": [&"util_generator"]},
	{"id": &"solar", "title": "Solar Panels", "branch": Branch.POWER, "tier": 1,
		"recipe": [&"silver_ore", &"pink_crystal", &"sky_stone"], "requires": [], "modules": [&"util_solar"]},
	{"id": &"batteries", "title": "Batteries", "branch": Branch.POWER, "tier": 1,
		"recipe": [&"silver_ore", &"gold_ore", &"bone", &"beanstalk"], "requires": [],
		"modules": [&"battery_s", &"battery_s_armored", &"battery_m", &"battery_m_armored",
			&"battery_l", &"battery_l_armored"]},

	# --- Support ---
	{"id": &"sonar", "title": "Sonar / Radar", "branch": Branch.SUPPORT, "tier": 1,
		"recipe": [&"gold_ore", &"pink_crystal", &"slime_jelly"], "requires": [],
		"modules": [&"radar_proximity", &"radar_survey", &"radar_deep"],
		"note": "Detects nearby enemies."},
	{"id": &"repair", "title": "Repair Module", "branch": Branch.SUPPORT, "tier": 2,
		"recipe": [&"gold_ore", &"sky_stone", &"bone"], "requires": [&"sonar"], "modules": [&"util_repair"],
		"note": "Repairs neighbouring modules; power hungry, can be switched off."},
	{"id": &"fabricator", "title": "Fabricator", "branch": Branch.SUPPORT, "tier": 2,
		"recipe": [&"scrap", &"gold_ore", &"pink_crystal"], "requires": [&"repair"], "modules": [&"util_fabricator"],
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


## Resource id → amount needed to unlock `node` (empty for tier 1).
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


static func unlock_cost(node: Dictionary) -> Dictionary:
	var amount: int = UNLOCK_COST.get(int(node["tier"]), 0)
	var cost: Dictionary = {}
	if amount <= 0:
		return cost
	for id: StringName in node["recipe"]:
		cost[id] = amount
	return cost

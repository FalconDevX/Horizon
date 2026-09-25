class_name ResourceCatalog
extends RefCounted
## Raw resources, and which planet yields which. Source: the "Surowce,
## wytwarzanie" frame of the Horizon Miro board (tables "Surowce → moduły" and
## "Planety → surowce"). Icons live in textures/resources/<id>.png.

## Tier 1 common, 2 uncommon, 3 rare - also the colour the UI tints them with.
const RESOURCES := [
	{"id": &"iron", "name": "Iron", "tier": 1},
	{"id": &"aluminium", "name": "Aluminium", "tier": 1},
	{"id": &"copper", "name": "Copper", "tier": 1},
	{"id": &"water_ice", "name": "Water Ice", "tier": 1},
	{"id": &"silicon", "name": "Silicon", "tier": 1},
	{"id": &"nickel", "name": "Nickel", "tier": 2},
	{"id": &"titanium", "name": "Titanium", "tier": 2},
	{"id": &"lithium", "name": "Lithium", "tier": 2},
	{"id": &"xenon", "name": "Xenon", "tier": 2},
	{"id": &"uranium", "name": "Uranium", "tier": 3},
	{"id": &"tungsten", "name": "Tungsten", "tier": 3},
	{"id": &"neodymium", "name": "Neodymium", "tier": 3},
	{"id": &"platinum", "name": "Platinum", "tier": 3},
	{"id": &"helium_3", "name": "Helium-3", "tier": 3},
]

const TIER_NAMES := {1: "Common", 2: "Uncommon", 3: "Rare"}
## Same colours as the Miro tables (T1 grey, T2 blue, T3 violet).
const TIER_COLORS := {
	1: Color(0.87, 0.87, 0.85),
	2: Color(0.61, 0.9, 1.0),
	3: Color(0.72, 0.67, 0.98),
}

## What each planet yields and how far out it is (1 start, 2 middle, 3 far,
## 0 anomaly), keyed by body_name.
const PLANETS := {
	"Anthea": {"resources": [&"aluminium", &"silicon", &"water_ice"], "zone": 1,
		"why": "Lush and rainy: water, and bauxite (aluminium) weathered out of the rock."},
	"Ashkar": {"resources": [&"iron", &"copper", &"silicon"], "zone": 1,
		"why": "Desert: the sand is silicon, the rusty dunes iron, copper as in the Atacama. No water."},
	"Aurumbra": {"resources": [&"copper", &"nickel", &"platinum"], "zone": 3,
		"why": "Golden veins: nickel-copper-platinum ores. The only source of platinum."},
	"Cinderhal": {"resources": [&"water_ice", &"xenon"], "zone": 2,
		"why": "Cryovolcanoes throw out ice and trapped noble gases."},
	"Cindral": {"resources": [&"iron", &"aluminium", &"silicon"], "zone": 1,
		"why": "Dead rock like the Moon: basalt (iron) and anorthosite (aluminium). Dry."},
	"Coralyss": {"resources": [&"iron", &"aluminium", &"copper", &"water_ice"], "zone": 1,
		"why": "Earth-like: every basic resource - the starting planet."},
	"Dunmere": {"resources": [&"copper", &"silicon"], "zone": 1,
		"why": "Sandy with oases: silicon and copper. No ice."},
	"Duskveil": {"resources": [&"water_ice", &"aluminium", &"nickel"], "zone": 2,
		"why": "Constant rain builds laterite deposits of nickel and bauxite."},
	"Emberrock": {"resources": [&"iron", &"copper", &"titanium"], "zone": 2,
		"why": "Hot and volcanic: titanium-rich basalts and copper veins. No ice."},
	"Glacenna": {"resources": [&"water_ice", &"silicon"], "zone": 1,
		"why": "Oceanic: water everywhere, sand on the islands."},
	"Hoarveil": {"resources": [&"water_ice", &"iron"], "zone": 1,
		"why": "Icy: the main source of fuel early on."},
	"Marrow": {"resources": [&"silicon", &"lithium"], "zone": 2,
		"why": "Fractal crystals: pegmatites with quartz and spodumene (lithium)."},
	"Mireth": {"resources": [&"iron", &"copper", &"water_ice"], "zone": 1,
		"why": "Wet and swampy: bog iron and copper in the sediments."},
	"Nyxholm": {"resources": [&"iron", &"titanium", &"nickel"], "zone": 2,
		"why": "Quakes expose deep mantle rock (nickel, titanium)."},
	"Oruvel": {"resources": [&"water_ice", &"xenon"], "zone": 2,
		"why": "Ice giant: harvested from orbit only."},
	"Rimebeck": {"resources": [&"water_ice", &"iron", &"aluminium"], "zone": 1,
		"why": "Frozen moon: ice in the craters, regolith with iron and aluminium."},
	"Taurvane": {"resources": [&"xenon", &"helium_3"], "zone": 3,
		"why": "Gas giant: the only source of helium-3, the fusion fuel."},
	"Thornix": {"resources": [&"neodymium", &"tungsten"], "zone": 3,
		"why": "Granite intrusions: rare-earth elements and tungsten."},
	"Vantauri": {"resources": [&"iron", &"copper", &"silicon"], "zone": 1,
		"why": "Metallic bands on the surface: easy ores."},
	"Vesk": {"resources": [&"uranium", &"lithium"], "zone": 3,
		"why": "Toxic, with a green glow: the only source of uranium."},
	"Erebus": {"resources": [], "zone": 0,
		"why": "No landing - a hazard and a story point."},
}

const ZONE_NAMES := {0: "Anomaly", 1: "Start", 2: "Middle", 3: "Far"}

static var _icons: Dictionary = {}


static func get_resource(id: StringName) -> Dictionary:
	for r: Dictionary in RESOURCES:
		if r["id"] == id:
			return r
	return {}


static func display_name(id: StringName) -> String:
	return String(get_resource(id).get("name", String(id)))


static func tier_of(id: StringName) -> int:
	return int(get_resource(id).get("tier", 1))


static func tier_color(id: StringName) -> Color:
	return TIER_COLORS.get(tier_of(id), Color.WHITE)


static func icon(id: StringName) -> Texture2D:
	if not _icons.has(id):
		var path := "res://textures/resources/%s.png" % String(id)
		_icons[id] = load(path) if ResourceLoader.exists(path) else null
	return _icons[id]


## Resources, zone and reason for a planet, or {} if the board has nothing.
static func planet_info(body_name: String) -> Dictionary:
	return PLANETS.get(body_name, {})

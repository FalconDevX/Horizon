class_name PlanetLore
extends RefCounted

## Catalog text for a body, written from what it actually is: its terrain
## kind (PlanetTerrain.Kind) and what that kind rolled for this world seed
## (PlanetTerrain.resolve() - liquid share, lava or cryo, clouds, aurora, a
## storm...). Nothing is keyed by planet name, because a world reroll (N) or a
## kind change in the scene gives the same name a different planet. Keep each
## entry in step with its kind's _roll_*() in planet_terrain.gd.

const STAR := {
	"class": "Yellow dwarf star",
	"description": "The heart of the system. Its photosphere is a boiling carpet of convection granules, freckled with sunspot groups and scattered pores, and its limb is fringed with red prominences - loops of plasma held up by magnetic fields. A pale corona streams out for several stellar radii.",
	"facts": [
		"Every granule is a column of hot plasma rising from below; each one lives only a few minutes before sinking back.",
		"Sunspots look dark only by contrast - they are cooler than the surface around them, but still hotter than molten iron.",
		"Prominences can stand for days, then snap and hurl their plasma into space.",
	],
}

const KINDS := {
	# Filled in by describe(): lava or cryo, depending on the roll.
	PlanetTerrain.Kind.VOLCANIC: {"class": "Volcanic world", "description": "", "facts": []},
	PlanetTerrain.Kind.TERRAN: {
		"class": "Ocean world",
		"description": "A temperate, water-rich planet. Oceans run from shallow turquoise shelves to deep abyss; green lowlands climb into eroded, snow-capped ranges, dry belts cross the subtropics and ice caps cover the poles.",
		"facts": [
			"Its cyclones spin opposite ways in the two hemispheres, as the planet's rotation dictates.",
			"The deserts sit where they do on Earth: in the subtropics, under descending dry air.",
			"Open water and an oxygen-rich sky make it the most habitable kind of world there is.",
		],
	},
	PlanetTerrain.Kind.DESERT: {
		"class": "Desert world",
		"description": "A dry planet with no seas at all. Wind has carved its highlands into stepped mesas whose cliffs show banded sediment, and old impact craters pock the plains.",
		"facts": [
			"The stripes on its cliffs are rock layers laid down over ages - read top to bottom, they are the planet's history.",
			"Without rain to wear them down, its craters survive for aeons.",
			"A mesa is what is left of a plateau after the wind strips away the softer rock around it.",
		],
	},
	PlanetTerrain.Kind.ICE: {
		"class": "Ice world",
		"description": "A frozen planet sheathed in ice sheets split by long fracture lines with raised flanks. Dark meltwater pools in the lowlands and broad caps crown the poles.",
		"facts": [
			"The fractures open as the ice shell flexes with the planet's tides and freeze shut again.",
			"Under the ice, tidal heating may keep a whole ocean liquid.",
			"Clean ice is so reflective that such worlds shine among the brightest objects in the sky.",
		],
	},
	PlanetTerrain.Kind.BARREN: {
		"class": "Barren world",
		"description": "An airless ball of rock saturated with craters of every size, crossed by old dry riverbeds and dark lava-flooded basins. With no air or weather, nothing ever erases a scar.",
		"facts": [
			"Many big craters hold smaller ones: impacts keep landing on old impacts.",
			"Its dry channels are fossils of a time when something once flowed here.",
			"With no atmosphere, the temperature swings hundreds of degrees between day and night.",
		],
	},
	PlanetTerrain.Kind.TOXIC: {
		"class": "Toxic world",
		"description": "Seas of acid lie in its lowlands under a dense, tinted haze, and the rock around them is pitted with collapsed sinkholes. The atmosphere would eat through an unprotected hull.",
		"facts": [
			"Sinkholes form where acid dissolves the rock underneath until the roof falls in.",
			"Its haze scatters light so strongly that the surface is seen only as a smudge from orbit.",
			"Landers bound here need acid-resistant plating.",
		],
	},
	PlanetTerrain.Kind.GAS_GIANT: {
		"class": "Gas giant",
		"description": "A world of hydrogen and helium with no solid surface. Its cloud bands, uneven in width, are torn at their edges by eddies.",
		"facts": [
			"Its bands are alternating jet streams, blowing in opposite directions.",
			"Dive deep enough and the hydrogen is squeezed into a liquid metal.",
			"A gas giant radiates more heat than it gets from its star - it is still cooling from its birth.",
		],
	},
	PlanetTerrain.Kind.ICE_GIANT: {
		"class": "Ice giant",
		"description": "A cold giant of hydrogen, helium and methane striped with bands of high cloud. Beneath the gas lies a thick mantle of water, ammonia and methane ices.",
		"facts": [
			"Methane in its air absorbs red light, which is what tints ice giants blue.",
			"Its winds are among the fastest in the system.",
			"Deep inside, the pressure may be high enough to crush carbon into diamond.",
		],
	},
	PlanetTerrain.Kind.FROZEN: {
		"class": "Frozen moonlike world",
		"description": "A small, cratered body buried in frost - part ice world, part airless moon. Craters and fractures cut through a crust of frozen gases.",
		"facts": [
			"Its frost is gas that froze out of a once-thicker atmosphere.",
			"Fresh craters punch through to darker rock and show up as dark rays in the ice.",
			"Sunlight alone can make its frost sublimate straight back into gas.",
		],
	},
	PlanetTerrain.Kind.SLIME: {
		"class": "Slime world",
		"description": "A planet smothered in a glossy biological scum that pools in every hollow and crater, broken only by lone, knife-sharp dark peaks that stand up out of it.",
		"facts": [
			"The scum is alive: a single colony may cover most of the planet.",
			"Its peaks stay bare because the slime cannot cling to their steep, dark flanks.",
			"Spore fog rises off it at dawn as the colony warms up.",
		],
	},
	PlanetTerrain.Kind.OCCULT: {
		"class": "Anomalous world",
		"description": "A black, dusty world marked by things no geology explains: huge crater-eyes whose irises glow red, and coiling ridges like tentacles, ringed with sucker-like bumps.",
		"facts": [
			"Its 'eyes' are real craters - rim, iris ring and a pupil pit - but no impact makes that shape.",
			"The glow comes only from the irises; the rest of each eye is stained, not lit.",
			"Surveys of this world tend to end early.",
		],
	},
	PlanetTerrain.Kind.GLOOM: {
		"class": "Gloom world",
		"description": "A dark planet under hard, contrasty light, its surface split by a web of cracks glowing from below with molten gold.",
		"facts": [
			"The cracks glow on the night side too, drawing the fault lines in light.",
			"Its thin, still air barely scatters light, so shadows fall pitch black.",
			"Heat leaking through the cracks keeps the crust from freezing solid.",
		],
	},
	PlanetTerrain.Kind.BLOOM: {
		"class": "Garden world",
		"description": "A flowering planet: vast fields of blossom cover its highlands, brown valleys wind between them, and a coloured mist of pollen settles in the low ground.",
		"facts": [
			"The mist is pollen - so much of it that it hangs in every valley.",
			"Its fields change colour with the seasons as different flowers take over.",
			"The air smells sweet even through a helmet filter, or so the pilots say.",
		],
	},
	PlanetTerrain.Kind.OASIS: {
		"class": "Oasis world",
		"description": "A dune world combed into east-west ridges by steady winds, with glossy, muddy pools in the pits between them ringed by spiky green buds.",
		"facts": [
			"Its dunes line up with the prevailing winds, like ripples on a beach.",
			"Life clusters where the water is - a green halo around every pool.",
			"The pools shrink and grow as the dunes creep over them.",
		],
	},
	PlanetTerrain.Kind.LOTUS: {
		"class": "Lotus world",
		"description": "A shallow global ocean with no land at all - only giant four-petalled flowers, white, pink and yellow, spread open on lily pads wide enough to land on.",
		"facts": [
			"Each flower is a single plant, rooted in the sea floor far below.",
			"Its pads float on the surface and ride the tides up and down.",
			"The petals close at night, so the planet looks greener after dark.",
		],
	},
	PlanetTerrain.Kind.SWIRL: {
		"class": "Spiral world",
		"description": "A crimson planet marked by about ten huge snail-shell spirals, each a raised orange ridge coiled around a sunken trench of the same shape.",
		"facts": [
			"Every spiral winds the same number of turns from the centre to its edge.",
			"The trenches run deeper than any canyon the wind could carve.",
			"No two neighbouring spirals are guaranteed to turn the same way.",
		],
	},
	PlanetTerrain.Kind.RINGS: {
		"class": "Ringmark world",
		"description": "A lush green planet in every happy shade, scarred here and there by onion-like sets of concentric rings, dark red and near black in turn and broken by gaps.",
		"facts": [
			"The rings stand slightly proud of the ground around them.",
			"Every ring breaks at a few points, and never at the same angle as its neighbour.",
			"Nothing grows on the rings themselves.",
		],
	},
	PlanetTerrain.Kind.QUAKE: {
		"class": "Quake world",
		"description": "A brown world washing into steel blue, covered in small silver scars - rings of cracks with fractures running out from them, left by countless quakes.",
		"facts": [
			"Each scar marks the epicentre of a single quake.",
			"The silver is fresh rock, still unweathered where the ground split open.",
			"Its crust is still settling - new scars appear every year.",
		],
	},
	PlanetTerrain.Kind.FRACTAL: {
		"class": "Fractal world",
		"description": "A barren brown-grey plain, free of craters, where a few great massifs rise in the exact shape of the Mandelbrot set - domed bulbs crowned in yellow over purple flanks, fringed with navy filament ridges.",
		"facts": [
			"Zoom in on any filament and it keeps branching; the survey drones never found the end of one.",
			"The thin straight ridge running off each massif is the set's own antenna.",
			"How the ground came to take this shape is still an open question.",
		],
	},
	PlanetTerrain.Kind.MERIDIAN: {
		"class": "Striped world",
		"description": "A planet covered pole to pole in side-by-side stripes, each its own shade from near-black through the planet's own colour to near-white, curving or zig-zagging as they run.",
		"facts": [
			"Every stripe starts at one pole and ends at the other.",
			"Neighbouring stripes never share a shade.",
			"Seen from orbit it spins like a barber's pole.",
		],
	},
}


## Class, description and facts for a body. `kind` is its terrain_kind and
## `params` its resolved terrain_params (may be empty until built).
static func describe(kind: int, params: Dictionary, is_star: bool) -> Dictionary:
	if is_star:
		return STAR

	var base: Dictionary = KINDS.get(kind, {})
	if base.is_empty():
		return {"class": "Uncharted body", "description": "No survey data yet.", "facts": []}

	var entry: Dictionary = base.duplicate(true)
	var extra: PackedStringArray = []

	if kind == PlanetTerrain.Kind.VOLCANIC:
		if params.get("variant", "") == "cryo":
			entry["class"] = "Cryovolcanic world"
			entry["description"] = "A frost-covered world where volcanoes erupt not rock but brine. Glowing, pale-blue cryolava fills the lowlands and a frozen crust drifts over it; cones with collapsed calderas stand on the highlands."
			entry["facts"] = [
				"Its 'lava' is salty water and ammonia, liquid well below the freezing point of pure water.",
				"The glow is the brine's own chemistry, strong enough to see on the night side.",
				"Cryovolcanoes may carry the planet's hidden ocean up to the surface.",
			]
		else:
			entry["class"] = "Volcanic world"
			entry["description"] = "A dark basalt crust split by glowing lava seas, with a cooling black skin drifting over the melt. Shield volcanoes with collapsed calderas dot the highlands."
			entry["facts"] = [
				"Its lava seas glow on the night side too - one of the few planets visible without the sun.",
				"The dimple in a volcano's summit is a caldera: left when the magma chamber empties and the top collapses.",
				"Its weather is ash, not water.",
			]

	var coverage: float = params.get("coverage", 0.0)
	if params.get("liquid", false) and coverage > 0.0:
		extra.append("About %d%% of its surface lies under liquid." % roundi(coverage * 100.0))
	if params.get("clouds", 0.0) > 0.0:
		extra.append("Clouds cover roughly %d%% of its sky." % roundi(params["clouds"] * 100.0))
	if params.get("aurora", 0.0) > 0.0:
		extra.append("Aurorae ripple over its poles.")
	var storm: Dictionary = params.get("storm", {})
	if storm.get("strength", 0.0) > 0.0:
		extra.append("A great oval storm spins in its %s hemisphere." % (
			"southern" if storm.get("latitude", -0.3) < 0.0 else "northern"
		))
	if not extra.is_empty():
		entry["description"] = entry["description"] + " " + " ".join(extra)
	return entry

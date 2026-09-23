class_name PlanetLore
extends RefCounted

## Catalog text for every body in the Vesperis system, keyed by body_name.
## Written to match what each world actually renders as (its terrain kind,
## seas, clouds and air - see PlanetTerrain.preset()), so keep the two in step
## when a planet's kind changes. Numbers (size, gravity, orbit) are not here:
## the catalog reads them live from the bodies.

const ENTRIES := {
	"Virelia": {
		"class": "Yellow dwarf star",
		"description": "The heart of the Vesperis system. Its photosphere is a boiling carpet of convection granules, freckled with sunspot groups and scattered pores, and its limb is fringed with red prominences - loops of plasma held up by magnetic fields. A pale corona streams out for several stellar radii.",
		"facts": [
			"Every granule is a column of hot plasma rising from below; each one lives only a few minutes before sinking back.",
			"Sunspots look dark only by contrast - they are cooler than the surface around them, but still hotter than molten iron.",
			"Prominences can stand for days, then snap and hurl their plasma into space.",
		],
	},
	"Emberrock": {
		"class": "Volcanic world",
		"description": "The innermost planet: a dark basalt crust split by glowing lava lakes that fill about a quarter of its lowlands. A cooling black skin drifts across the molten seas, shield volcanoes with collapsed calderas dot the highlands, and grey ash clouds hang over it all.",
		"facts": [
			"Its lava seas glow on the night side too - Emberrock is one of the few planets you can see without the sun.",
			"The dimples in the tops of its volcanoes are calderas: craters left when a magma chamber empties and the summit collapses.",
			"Ash clouds, not water, make up its weather.",
		],
	},
	"Coralyss": {
		"class": "Ocean world",
		"description": "A temperate, water-rich planet - roughly three fifths of it is ocean, from shallow turquoise shelves to deep blue abyss. Green lowlands climb into eroded mountain ranges capped with snow, dry belts spread across the subtropics, and white ice caps cover both poles. Its busy sky carries cumulus fields, fronts and spiralling cyclones.",
		"facts": [
			"Its cyclones spin opposite ways in the two hemispheres, as the planet's rotation dictates.",
			"The deserts sit where they do on Earth: in the subtropics, under the planet's descending dry air.",
			"The only world in the system with open water and a breathable, oxygen-rich atmosphere.",
		],
	},
	"Duskveil": {
		"class": "Toxic world",
		"description": "Behind a dense violet haze lie seas of acid, glowing a sickly green, covering nearly half the surface. The land is purple rock and pale mineral flats, cut by ridges. Thick lilac clouds and cyclones churn in an atmosphere that would dissolve an unprotected hull.",
		"facts": [
			"The faint green glow of its seas comes from chemistry, not heat.",
			"Its haze scatters violet light, which is why the whole planet looks bruised from orbit.",
			"Landers bound for Duskveil need acid-resistant plating.",
		],
	},
	"Thornix": {
		"class": "Desert world",
		"description": "A dry, rust-red planet with no seas at all. Wind has carved its highlands into stepped mesas whose cliffs show banded layers of sediment, and old impact craters pock the plains. A thin, dusty atmosphere gives it a faint orange rim, and frost gathers at the poles.",
		"facts": [
			"The stripes on its cliffs are rock layers laid down over ages - read top to bottom, they are the planet's history.",
			"Without seas or rain to wear them down, its craters survive for aeons.",
			"Its mesas are what is left of a plateau after the wind stripped away the softer rock around them.",
		],
	},
	"Glacenna": {
		"class": "Ice world",
		"description": "A frozen planet sheathed in ice sheets, split into huge polygonal plates by pressure cracks. Dark meltwater seas pool in about a fifth of the lowlands, broad ice caps crown both poles, and thin icy clouds drift through a cold nitrogen sky.",
		"facts": [
			"The cracks form as the ice shell flexes and freezes again, like the crazing on old glaze.",
			"Under the ice, tidal heating may keep a whole ocean liquid.",
			"Its ice is so reflective that the planet is one of the brightest objects in the sky.",
		],
	},
	"Marrow": {
		"class": "Barren moonlike world",
		"description": "An airless, grey-brown ball saturated with craters of every size - huge basins, overlapping mid-sized craters and fields of tiny pits. With no air, water or weather, nothing ever erases them. Its horizon is razor-sharp against space.",
		"facts": [
			"Nearly every crater on Marrow is older than the other planets' surfaces.",
			"Many big craters have smaller ones inside them: impacts keep landing on old impacts.",
			"With no atmosphere, the temperature swings hundreds of degrees between day and night.",
		],
	},
	"Vantauri": {
		"class": "Gas giant",
		"description": "The largest planet in the system, a world of hydrogen and helium with no solid surface. Its cream and amber cloud bands are torn at their edges by eddies, and a great oval storm spins in its southern hemisphere. A warm, hazy atmosphere glows around its limb.",
		"facts": [
			"Its bands are alternating jet streams, blowing in opposite directions.",
			"The great storm is wider than several rocky planets side by side.",
			"Dive deep enough and the hydrogen is squeezed into a liquid metal.",
		],
	},
	"Nyxholm": {
		"class": "Ice giant",
		"description": "A deep blue giant of hydrogen, helium and methane, striped with bright bands of high cloud and marked by a great storm. Beneath its gaseous envelope lies a thick mantle of water, ammonia and methane ices.",
		"facts": [
			"Methane in its air absorbs red light, which is what paints Nyxholm blue.",
			"Its winds are among the fastest in the system.",
			"Deep inside, the pressure may be high enough to crush carbon into diamond.",
		],
	},
}


static func entry(body_name: String) -> Dictionary:
	return ENTRIES.get(body_name, {})

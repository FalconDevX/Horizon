---
name: solar-system
description: Map of the Horizon orbital-sim codebase - solar_system.gd (2770 lines, the main scene script), celestial_body.gd, orbit_math.gd, interplanetary_planner.gd, ship.gd and solar_system.tscn. Use when adding or editing planets/moons/orbits, autopilot phases, trajectory prediction, SOI logic, the HUD, or anything else in solar_system.gd, so you can jump straight to the right region instead of reading the whole file.
---

# Horizon solar system

Godot 4.7 2D orbital-mechanics sim. Single main scene `solar_system.tscn`, driven by
`solar_system.gd` (2770 lines). All scripts live flat in the project root.

## Read this first

`solar_system.gd` is too big to read whole. Use
[references/function-map.md](references/function-map.md) to find the region you need,
then read only those lines. Line numbers are anchors as of commit `65b36d9`; if they
look off, re-derive with:

```bash
grep -n "^func \|^const \|^var \|^class " solar_system.gd
```

## Files

| File | Role |
| --- | --- |
| `solar_system.gd` | Main scene script: sim loop, autopilot, trajectory prediction, HUD, camera, input |
| `solar_system.tscn` | Scene: `Sun`, `Planets/*` (20 planets + the black hole Erebus), `Ship`, line/marker nodes, `HUD/*` |
| `celestial_body.gd` | `@tool` Node2D for the sun and every planet: exports, `_draw` (glow, SOI ring), surface sprite + spin |
| `planet_surface.gd` | `PlanetSurface` static lib: palette generator, blob generation, CPU-side blob lookup |
| `planet_surface.gdshader` | Canvas shader: projects a sphere onto the disc and colours it by nearest blob |
| `orbit_math.gd` | `OrbitMath` static lib: Kepler propagation, orbital elements, transfer solving |
| `interplanetary_planner.gd` | `InterplanetaryPlanner` static lib: off-thread transfer planning |
| `ship.gd` | Ship node: main engine (no RCS), flight assist, attitude hold, throttle lock, engine/laser/beep sounds |
| `*_panel.gd`, `*_gauge.gd`, `hud_panel_style.gd` | HUD widgets, all custom `_draw` |

## How the simulation works

- **World scale 4x.** Every distance and radius is 4x what the system was first built
  at, and `G = 192000.0` (= 3000 x 4^3), so orbital periods are unchanged and speeds
  are 4x. Distance-type constants (autopilot tolerances/altitudes, planner tolerances,
  belts, spawn offset) were scaled with it; `planet_info_panel.gd` reads `G` from the
  script, so there is only one copy.
- `PLANET_GRAVITY_SCALE := 0.4` multiplies every planet's `mass` once in `_ready()`
  (planets only feel the sun, so this only weakens their pull on the ship). Sim,
  predictor, autopilot, SOI sizes and the catalog all see the scaled mass - scene
  masses in the table below are pre-scale.
- `_physics_process` accumulates `delta * time_scale` and runs fixed `SIM_DT = 1/120`
  steps (velocity Verlet) via `simulation_step`, up to `MAX_SIM_STEPS_PER_FRAME`.
- Positions are held in `PhysicsBody` wrappers (`physics_planets`, `physics_ship`) as
  plain floats and pushed back into the nodes at the end of each step. Read node
  `position` for display; use `get_precise_xy` / `get_relative_position_precise` for math.
- **Planets feel only the sun** (`get_planet_acceleration_precise`). No planet-planet
  gravity anywhere - not in the sim, not in the predictor, not in the planner.
- The ship feels the sun, *or* - when inside one planet's SOI - that planet plus the
  planet's own sun-acceleration (patched conics, first match wins, `break`).
- `get_soi_radius(body) = max(distance_to_sun * (mass / sun_mass) ** 0.4,
  radius * MIN_SOI_RADII)` (floor 5 radii, so small planets near the sun still have
  room to orbit). Recomputed every physics frame into `soi_radii_cache`.

## Planets

Planets are **pure scene data**. `_ready()` walks every `Node2D` child of `$Planets`, in
scene order, and for each one:

1. appends it to `planets` / `celestial_bodies` / `autopilot_selectable_bodies`,
2. sets `velocity = get_circular_orbit_velocity(position, sun.position, sun_mass)` -
   a perfect circle derived from the node's `position` alone,
3. creates a `Line2D` orbit trail in `$OrbitLines` tinted with the planet's `color`,
4. appends a `PhysicsBody` and a `mu = G * mass` entry.

So **adding a planet needs no code change** - add a `Node2D` child of `Planets` in
`solar_system.tscn` with `script = ExtResource("1_hbvo3")` (`celestial_body.gd`) and the
exports below. Existing nodes are the template (`solar_system.tscn` lines ~151-235).

`celestial_body.gd` exports: `radius`, `visual_radius`, `color`, `mass`, `body_name`,
`atmosphere`, `show_soi`, `soi_radius`, `soi_line_width`. Existing planets set
`visual_radius = radius` and `show_soi = true`; `soi_radius` / `soi_line_width` are
overwritten every frame by `update_soi_visuals` / `update_screen_space_visuals`.

Current system (sun `Virelia`, mass 1000, radius 3 200), 4x scale. Asteroid belts
(`asteroid_belts.gd` `BELTS`) fill 154 000-177 200, 752 000-864 000 and
4 160 000-4 800 000; keep planets and their SOIs out:

| # | Name | Orbit radius | Radius | Mass |
| --- | --- | --- | --- | --- |
| 0 | Emberrock | 36 000 | 880 | 9 |
| 1 | Coralyss (home) | 70 000 | 1 720 | 50 |
| 2 | Duskveil | 129 200 | 1 200 | 12 |
| 3 | Thornix | 231 200 | 2 000 | 25 |
| 4 | Glacenna | 409 200 | 1 400 | 14 |
| 5 | Marrow | 655 200 | 1 040 | 6 |
| 6 | Vantauri | 1 180 000 | 2 800 | 34 |
| 7 | Nyxholm | 2 194 000 | 2 240 | 18 |
| 8 | Anthea | 20 000 | 640 | 4 |
| 9 | Dunmere | 527 000 | 1 280 | 1.8 |
| 10 | Cindral | 27 600 | 520 | 0.6 |
| 11 | Vesk | 99 200 | 760 | 1.0 |
| 12 | Ashkar | 312 000 | 920 | 0.4 |
| 13 | Oruvel | 3 400 000 | 2 080 | 15 |
| 14 | Mireth | 45 000 | 800 | 0.5 |
| 15 | Cinderhal | 291 000 | 1 200 | 0.04 |
| 16 | Aurumbra | 1 552 000 | 1 520 | 0.2 |
| 17 | Hoarveil | 1 688 000 | 1 320 | 0.2 |
| 18 | Rimebeck | 2 700 000 | 600 | 0.04 |
| 19 | Taurvane | 5 600 000 | 2 600 | 8 |
| 20 | Erebus (black hole) | 14 000 000 | 30 000 | 300 |

Starting phases are random every launch: `_ready()` keeps each planet's orbit
radius from the scene but rotates it to a random angle round the sun (then calls
`snap_visual_position()` so the 3D visuals don't interpolate across). Angles
authored in the scene no longer matter.

The tightest SOI gaps (after the 0.4 gravity scale and the 5-radii floor) are
Emberrock-Mireth (~600), Cindral-Emberrock (~1 400) and Anthea-Cindral (~1 800); Taurvane
clears Erebus's SOI by ~1.8 M. Recheck every gap (and the belts) after touching a mass,
radius or orbit - a quick script over `solar_system.tscn` computing
`max(d * (0.4 m / 1000)^0.4, 5 r)` per body does it.

### Constraints when touching the planet set

- `HOME_PLANET_INDEX := 1` indexes `planets` **by scene child order**. The ship spawns
  4000 units from that planet. Inserting a node above `Coralyss` silently moves the
  spawn - append new planets at the end, or update the constant.
- Only the distance of a planet's scene `position` from the sun matters - the start
  angle is randomised in `_ready()`, and the circular velocity follows automatically.
- **Circular orbits are assumed in three more places.** Elliptical planet orbits are not
  a data-only change:
  - `update_orbit_line` draws a circle of radius = current distance to the sun;
  - `build_route_context` reduces each planet to a constant `omega`, and
    `InterplanetaryPlanner.simulate` advances them as `rel[i].rotated(omega[i] * dt)`;
  - `OrbitMath.closest_approach_numeric` / `_numeric_acceleration` do the same.
- **SOIs must not overlap.** `get_current_orbit_body` and the ship's acceleration both
  take the *first* planet whose SOI contains the ship. SOI grows linearly with distance
  from the sun, so a distant low-mass planet still has a large SOI.
- Per-planet per-frame cost is real: the SOI cache and orbit-line update run over all
  planets every physics frame, and `build_trajectory_snapshot` copies all of them every
  0.1 s. `update_orbit_line` is already guarded by `ORBIT_RADIUS_REBUILD_THRESHOLD`
  because `Line2D` rebuilds its whole geometry on every `add_point`.
- New planets automatically become autopilot targets (`autopilot_selectable_bodies`) and
  work in the planet info panel, which reads the exports directly.
- There is no moon/satellite support: the hierarchy is sun -> planets, one level deep,
  and both the SOI test and the planner assume a planet orbits the sun.

## Planet surfaces

Orthogonal to the sim — nothing in the physics, SOI or autopilot layers knows surfaces
exist. A body with `surface_blob_count == 0` (the sun) keeps the old flat `draw_circle`.

- **Representation.** A surface is a list of blobs, each a direction on the unit sphere
  plus a palette index, generated from `surface_seed`. Colour at any direction is the
  colour of the *nearest* blob — a spherical Voronoi lookup. Region shapes are never
  stored, only implied. More blobs than palette colours is deliberate: same-coloured
  neighbours merge into continents.
- **Two copies of one lookup.** `PlanetSurface.blob_at()` (GDScript, for gameplay) and
  the loop in `planet_surface.gdshader` (per pixel) must stay in sync.
- **Placing objects.** Objects belong to a blob, not to the planet: filter with
  `blobs_with_color()`, then `sample_point_in_color()` samples inside a matching blob's
  cap rather than guessing at the whole sphere (~1.2 tries versus ~10 for a 10% colour).
  Store the blob id on the object at spawn; never re-query per frame. Project with
  `surface_point_to_local()`, gated on `is_surface_point_visible()` — a `.z > 0` test
  replaces a depth buffer. Always go through the `CelestialBody` wrappers, not
  `PlanetSurface` directly, or the warp settings get dropped and answers stop matching
  the pixels.
- **Rendering.** `celestial_body.gd` adds an unowned child `Sprite2D` carrying a
  `ShaderMaterial`. The shader inverts the disc projection per pixel to get a sphere
  point, rotates it into planet space, then looks up the nearest blob. The circle's
  outline never changes — only the colours inside it.
- **Orientation** is one `Quaternion` (`surface_rotation`), mapping planet space into
  view space. It is the entire surface state: position plus heading. Advance it by
  composing rotations (`delta * rotation`), never by adding a tangent — a tangent step
  leaves the sphere and compounds. Currently `_process` auto-spins about `Vector3.UP`;
  while landed (`surface_driven`) the ship drives it instead - see Landing.
- **View-space axes are constants:** `Vector3.RIGHT` = forward, `Vector3.BACK` = turn.
  Turning leaves position untouched because the ship sits on the turn axis.
- **Per-planet values** (`surface_seed`, `surface_blob_count`, `surface_color_count`) are
  hardcoded in `solar_system.tscn`, as with every other planet property.
- **Seeds.** `surface_seed` is only a planet's *local* seed. Everything — blob rolls,
  terrain colours, the elevation bake, the shaders' `seed_offset` — reads
  `generation_seed = PlanetSurface.planet_seed(world_seed, surface_seed)`, set at the
  top of `_ready()`. `world_seed` is an export on the scene root (`solar_system.gd`, default 1461402483),
  read through `owner` in `get_world_seed()` because planets `_ready` before the root.
  Changing the script default of `surface_seed` does nothing - every planet overrides
  it in the scene. `set_world_seed(value)` clears `PlanetTerrain`'s bake cache and
  calls `rebuild_surface()` on every planet; `N` in game does it with `randi()` and
  prints the seed. A rebuilt terrain planet keeps its old look until the new bake
  lands; in-flight bakes go to `_stale_terrain_tasks` and are reaped in `_process`.
- **Palette.** `PlanetSurface.generate_palette()` rolls HSV colours from the seed in
  three brightness bands — dominant is muted and dark, secondary is analogous and
  mid, accents are golden-angle hues, saturated and bright. The bands are what make the
  colours readable apart; hue alone is not enough.
- **Colour count is rolled**, not authored: `roll_color_count()` weights 3 colours at 54%
  down to 8 at 1%, so count doubles as the rarity tier. A body's
  `surface_color_count` export above 0 pins it instead, for testing.
- **Area follows 60/30/10.** `color_weights()` gives the target share per colour; each
  colour past the third takes another 10 points, drawn 2:1 from the dominant and
  secondary. `apportion()` converts those shares into exact cell counts by
  largest-remainder.
- **Three layout styles**, rolled per planet by `roll_style()` (`surface_style` export
  pins one). Every style emits the same thing — directions plus colour indices — so the
  shader, warp and gameplay lookup never learn which was used. All three hold 60/30/10
  to within ~0.6pp; only the shapes differ.
  - `SCATTERED` (30%): even points, colours shuffled. Mottled. Only the dominant holds
    together — at 30% and 10% a colour shatters into ~8 specks. That is the style, not
    a bug; use it for barren worlds.
  - `CONTINENTS` (54%): even points, colours seeded (`CELLS_PER_SEED`) and grown
    round-robin through the adjacency graph. Solid landmasses, accents ~100% contiguous.
  - `BANDS` (16%): points laid along meridians that drift in longitude as they run pole
    to pole. Equal steps in z, not latitude, keeps rows equal-area. One colour per whole
    band, and `interleave_bands()` spreads each colour around the ring rather than
    giving it one unbroken arc — otherwise the dominant eats a hemisphere and only the
    10% accent reads as a stripe. Longest run drops from ~10 bands to 2.
    `choose_band_layout()` picks the band count that spells the weights most exactly
    (10 bands express 60/30/10 as 6/3/1; 12 bands cannot), holding rows at 4+ so
    meridians have enough points to curve.
- `build_adjacency()` links each cell to its 6 nearest points, which only approximates
  Voronoi neighbours because the points are evenly spread.
- **Points are jittered Fibonacci, not random** (`distribute_points`). Random points
  clump, cell areas vary wildly and the colour split drifts off target — measured worst
  case around 7 points of error versus under 3 for the spiral. Even spacing is what
  makes blob share equal area share.
- **Textures are optional and purely visual.** `surface_textures` takes a
  `Texture2DArray` — one layer per palette slot — and stays off (flat colours) while it
  is null. A sphere has no sensible UVs, so the shader samples **triplanar**: three
  reads blended by which way the surface faces, no seams and no pole pinching. It is an
  array rather than separate samplers because GLSL cannot index a sampler array with a
  value it cannot resolve at compile time. Layers are read at `(color_index +
  texture_offset) % layers`, the offset rolled per seed. Textures multiply the generated
  palette colour (`surface_texture_tint`), so the 60/30/10 hue work still shows through.
  `blob_at()` is untouched — texturing changes no gameplay answer.
- **Edges.** Two separate mechanisms, both tunable per body: `surface_warp_*` bends the
  lookup direction before the nearest-blob test so straight Voronoi edges come out
  ragged, and `surface_edge_softness` blends the nearest against the second-nearest so
  boundaries fade instead of stepping. The warp must be mirrored exactly in
  `PlanetSurface.surface_warp()` — it is built from sines, not a hash, because a hash is
  chaotic and 32-bit GPU floats would diverge from 64-bit CPU floats into a different
  field entirely. Any replacement must stay smooth for the same reason.
- **Blob count sets feature scale, not edge quality.** Adding blobs makes regions
  smaller; it does not make them less faceted. Warp is what fixes faceting.
- **Limits:** `MAX_BLOBS = 256`, `MAX_COLORS = 8`, mirrored as array sizes in the shader.
  Raising either means editing both files. The per-pixel loop is O(blobs), so cost is
  pixels × blobs; past ~512 blobs move to a texture lookup or a spatial structure.

## Heightmap terrain

At runtime a body with `terrain_kind != None` skips the blob surface entirely and
uses `planet_terrain.gd` (`PlanetTerrain`) + `planet_terrain.gdshader`. The editor
still shows the blob preview.

- **Kinds** (`PlanetTerrain.Kind`, order shared with the `terrain_kind` export enum,
  the bake's constants and the gallery's `KIND_NAMES`): Terran, Desert, Volcanic, Ice,
  Barren, Toxic, Gas giant, Ice giant, then Frozen (ice + barren moon), Slime (scummed
  slime with lone sharp dark peaks from `peak_layer()`), Occult (black dust, red eye
  sigils), Gloom (dark blue, glowing gold cracks, hard lighting), Bloom (navy/crimson
  flower fields, brown valleys, purple ground mist), Oasis (east-west dunes, muddy
  glossy puddles filling `pit_layer()` pits - coverage kept to about the pits' own area
  or the dune troughs flood - and spiky green buds), Lotus (ocean whose only land is
  giant four-petal flowers on lily pads, `flower_layer()`; sea level pinned by
  `sea_fixed` instead of the coverage histogram), Swirl (crimson ground, ~10 snail-shell
  spirals: one arm a raised orange ridge, the other a pit), Rings (greens with a few dark-red/black onion rings broken by
  gaps), Quake (brown with a steel-blue cast, small silver circle scars from
  `quakes_at()`), Fractal (craterless brown-grey barren with big Mandelbrot-set massifs,
  `mandel_height()`: bulbs domed, filaments lower ridges, coloured by height navy →
  purple → yellow crown; the thin straight ridge off each massif is the set's real
  antenna), Meridian (any hue; 14–24 pole-to-pole mountain ridges and carved valleys
  from `meridian_relief()` in the bake, one feature slot per line, each on its own
  course - straight, curving or zig-zag, own swing/frequency/phase/lean - so they
  cross; tapered out near the poles; pink-and-white seas (30–45% coverage) flood
  the valleys and low plains - the land hue is rolled from 0.03–0.8 so it is never
  pink/magenta/red; coloured by height: thin dark shore rim → base plains →
  near-white crests. Nothing drawn in the planet shader). There are no fixed presets: `resolve()` dispatches to one
  `_roll_<kind>()` per kind, which builds the whole look from ranges that keep the
  kind's idea (Terran water always blue-ish, grass green-ish in many shades, desert
  palette *families* - sand/orange/rust/ochre/rose/salt - always on a strong
  dark→light value ramp so relief stays readable, giants any-hue colour harmonies).
  A `Roller` does the draws: `between()` is pulled to its range's middle as
  `planet_chaos` (export on `solar_system.gd`, default 1.0) drops; discrete picks stay
  random. Volcanic rolls a `variant`: 35% `"cryo"` (glowing light-blue brine on
  frost) vs `"lava"`. `crust` (shader `liquid_crust`) is separate from `emission`:
  lava/cryo crust over, acid does not (a crust on acid reads as polka dots).
  Liquid kinds: Terran (water), Volcanic (lava or cryo, emissive), Ice, Toxic (acid).
  `terrain_liquid_coverage` overrides the share (0 = dry).
- **Per-kind variants** (rolled in `_roll_*()`, named in `params.variant` - plus the
  flags `blind`, `julia`, `rings` - and described by `PlanetLore.VARIANT_NOTES` /
  `FLAG_NOTES`): Terran temperate/autumn (autumn grass + forests, more sand);
  Rings green/sandy/volcanic/autumn/flooded (flooded = every ring set an island;
  islands = plateau + moat per `ISLAND_MOAT`, sea coverage 0.27·size² each; violet
  bushes round every set via `bud_near_features`); Occult dust/obsidian_purple/
  obsidian_yellow + `blind` (eye `style.y` 3 = closed lid, both shaders' `eye_parts`);
  Lotus open/night (petals folded to buds via bake `b.x` openness, pads glow via
  `land_glow`)/giant (one continent-sized flower from `sigils[0]`, `flower_shape()`);
  Fractal palettes classic/ember/verdigris/orchid/frozen + `julia` (Julia sets:
  `extra.x` 1, constant in `extra.yz`); Meridian pink/inverted (white seas, dark
  land); Quake settled/active (`quake_glow`, orange)/terraced (bake `c.x` steps) and
  every scar a carved hole (`quake_holes()` mirrors `quakes_at()` via `hash3_plain()`
  and `quake_shift`); Bloom fields/winter/dried; Oasis dry season/monsoon (+50% muddy
  rivers); Barren spiked/cracks/red mist + `rings` (master's `_build_rings()`, the roll
  tips the axis with `spin_axis` - see below); Toxic still/crystal (`crust_color`)/
  boiling (`boil*`, `bubbles_at()`); Desert open/lava/glass (`rock_patches`)/sandstorm
  (`cloud_speed`); Slime slick/bubbling/petrified (solid: liquid off, chalky low
  ground, cracks); Gloom single/twin (`crack_twin`, second `cracks_at()` pass); Frozen
  white/pink; Ice sheet/geysers.
- **Forcing a variant**: `terrain_variant` on a planet (comma-separated, e.g.
  `"julia,frozen"`, `"rings,spiked"`) reaches `resolve()` as `forced_variant`; the
  rolls pick through `Roller.variant()` / `Roller.flag()`, which still draw their
  random numbers and then return the forced name, so the rest of the look stays as
  the world seed made it. Empty = rolled. The scene currently forces a showcase
  variant on 16 planets (temporary - clear the fields to go back to rolling).
- **A roll can tilt the spin axis**: `params.spin_axis` replaces the scene's
  `surface_spin_axis` for that world (restored from `_scene_spin_axis` otherwise), set
  in `build_terrain()` before anything reads the pole; `surface_rotation` resets when
  the axis changes, or the spin would wobble.
- **Bake recipe per planet.** `recipe` (continent warp, mountain-belt thresholds,
  ridge sharpness) is shared by every rocky kind; `detail` is 16 kind-specific floats
  sent as `detail[4]` in the bake's `Params` - their meaning is commented per branch
  of `raw_height()` in `planet_terrain_bake.glsl`, and must match the order the
  `_roll_*()` writes them. Kind features: Terran/Toxic continents (Toxic with its own
  finer erosion scale and sinkholes), Desert terraces (3–12 steps), Volcanic cones and
  calderas, Ice fractures (warped-noise zero lines with raised flanks, not Worley
  cells), Barren craters + dry riverbeds (`channels()`) + maria basins, giants with
  uneven band widths, sharpness, turbulence and an optional storm (`params.storm`).
  `cache_key()` hashes everything the bake reads (`_bake_values()`).
- **Cloud deck height** is `relief * cloud_height` (+ `CLOUD_CLEARANCE`); `cloud_height`
  defaults to 0.45 (over the plains), Swirl sets 1.0 so its raised spirals do not poke
  through. The atmosphere shell follows the same height.
- **Clouds and air are separate shells** (from master): `_build_clouds()` /
  `_build_atmosphere()` add `planet_clouds.gdshader` / `planet_atmosphere.gdshader`
  meshes as children of the sphere; the terrain shader only reads
  `planet_clouds.gdshaderinc` for cloud shadows, and noise helpers live in
  `planet_noise.gdshaderinc`. Cyclones come from `PlanetTerrain.roll_cyclones()`,
  seeded by `generation_seed`. `rebuild_surface()` frees both shells before
  rebuilding. The catalog (J key) calls `make_preview()` on each body; unknown names
  in `PlanetLore` (Anthea, Dunmere) just show blank lore. Cloud *amount* reads much
  heavier on the shell than it did in-shader, so the `clouds` ranges in `_roll_*()`
  may want lowering.
- **Drawn-on effects** (planet shader only, not in the heightmap, pushed by
  `_push_terrain_effects()`; all off unless a `_roll_*()` sets them): aurora curtains
  on the auroral oval (Ice, Frozen), glowing cracks (`cracks_at()`, Gloom), low-ground
  mist (Bloom, capped at 55% opacity - it is a veil, not a lid), buds (`buds_at()`,
  Oasis: one jittered spiky dot per 3D cell, each testing the height under its own
  centre so it is whole or absent, denser in the wet band above the waterline, faded
  out once under a pixel).
- **Placed features ("sigils") are carved *and* drawn.** Up to `MAX_SIGILS` = 24 per
  planet, each a dict `{direction, size, reach, style: Vector4, extra: Vector4}`;
  `_place_features()` / `_spaced_direction()` scatter them without overlap, and
  `sigil_mode` (`FeatureMode`: EYES = Occult, SWIRLS, RINGS, BAKE_ONLY = Fractal and
  Meridian, whose lines use the slots with `direction` unused) says
  how the planet shader colours them. `PlanetTerrain.sigil_arrays()` packs `sigils`,
  `sigil_styles`, `sigil_extra` for both shaders; what style/extra mean is commented in
  each `_roll_*()`. `sigil_frame()` is azimuthal-equidistant (|q| = true angle / size),
  so big features keep their shape and the `s.w * 1.4` cull matches the fades. Swirl/Rings/Fractal relief comes from `feature_relief()` in the
  bake, with `swirl_parts()` / `ring_parts()` mirrored in the planet shader
  (`feature_color_at()`).
- **Occult eyes and tentacles.** `_roll_occult()` places eyes, plus 1–2 eyeless
  tentacle nests (`pupil` < 0). The
  bake carves eye craters (`eye_relief()`: bowl, rim, hood, iris ring, pupil pit, drip
  grooves) and tentacle ridges (`tentacle_ridges()`: curling, tapering, rounded, sucker
  bumps) via `occult_marks()`; the planet shader mirrors `sigil_frame()`, `eye_lens()`,
  `eye_parts()` and `tentacle_ridges()` to stain bowls red, tint tentacles dark blood
  and glow only the iris. Change a shape in one shader and it must change in the
  other, or the stain slides off the crater. Lighting
  character is per planet too: `ambient`, `light_wrap`, `terminator_softness`,
  `shade_contrast` (Gloom runs them hard). Emissive light goes through `emit`, added
  after lighting; lava's `glow` path is separate.
- **Scene right now** (temporary until every planet rolls a biome per world):
  Coralyss = Terran (home), Emberrock = Swirl, Duskveil = Rings, Thornix = Occult,
  Glacenna = Lotus, Marrow = Fractal, Vantauri = Meridian, Nyxholm = Quake, plus
  **Anthea** (Bloom, radius 160, mass 4, at 5000 from the sun - inside Emberrock,
  outside the corona (4000) - so it orbits ~2.4x faster) and **Dunmere** (Oasis).
  Cindral (Barren), Vesk (Toxic), Ashkar (Desert) and Oruvel (Ice giant) give the
  older kinds a planet each; the three small ones bake at `terrain_resolution = 512`
  to save memory. **Mireth** (Slime) was added back, then the last unused kinds got
  a planet each: Cinderhal (Volcanic), Aurumbra (Gloom), Hoarveil (Ice), Rimebeck
  (Frozen, bakes at 512) and Taurvane (Gas giant, past Oruvel and belt 3 - its SOI
  fits no inner gap; it carries the system's **rings**, with its spin axis leaned
  toward the camera so they are not edge-on). **Erebus**, the black hole, is last in
  `Planets`, at 14 M. At 4x scale Mireth sits between Emberrock and Coralyss and
  Cinderhal between Thornix and Ashkar (both moved out of the asteroid belts;
  Cinderhal's mass cut to 0.04 to fit). Masses kept low so each SOI clears its
  neighbours by ~1 500-19 000 (Taurvane clears belt 3). Every kind has a planet.
- **Catalog text** (`scripts/data/PlanetLore.gd`) is written per *kind*, not per planet
  name, and `describe()` adds what the roll produced (lava vs cryo, liquid share,
  clouds, aurora, storm) - so a reroll or a kind change never leaves stale text. A new
  kind needs an entry there too.
- **Resource deposits** are separate objects, not terrain: `MeshInstance3D`s under a
  `Deposits` node parented to `_sphere_3d` (planet space, unit radius), so they spin
  with the surface. `resource_deposits.gd` (`ResourceDeposits`) holds two tables:
  `TYPES` (per resource: `mesh` look, `size` in planet radii, colour, `shine`, `glow`,
  optional `wiggle` / `spots`) and `SPAWNS` (per `PlanetTerrain.Kind`: entries with
  `type`, `count`, `on` land/liquid/any, `land` height band in colour-gradient units,
  `lowest` (the planet's lowest share of land, via `Ground.land_below()` - use it for
  valleys, since a roll's heights may never reach a fixed band), `above`, `slope`,
  `only` / `except` (variant names or true flags), `chance`, `cluster`, `color` /
  `glow` overrides, type `&"random"` (any collectible but `except_types`),
  `feature` (`&"swirl_ridge"` - CPU mirror of `swirl_parts()`; `&"ring_centre"`;
  `&"quake_hole"` - snaps to hole centres via `_shader_hash()`, a GDScript PCG3D),
  `motion`). Kinds missing from `SPAWNS` get nothing (gas giants, Volcanic and
  Gloom for now). `place()` runs once the bake lands
  (`_apply_terrain()` → `_place_deposits()`), rolled from `generation_seed`, using
  `PlanetTerrain.height_at()`; liquid spawns sit at the unit sphere (the sea surface).
  Shapes are built per deposit from its seed in `deposit_meshes.gd` (`DepositMeshes`:
  crystals, tiles, scrap, beanstalk (green/frozen/dried), pillars, egg, pebbles,
  bones, slabs, spikes, jelly, tumbleweed, geyser; +Y up,
  ~1 unit across, feet sunk; vertex colours for inner shading); add a look there and
  in `build()`. Lit by `resource_deposit.gdshader` (`sun_position` global, wiggle
  driven by the pausable `planet_time` global, procedural spots). Data per deposit in
  the body's `resource_deposits`: `type`, `direction` (kept current as it moves),
  `lift`, `size`, `seed`, `motion`, `node`. `rebuild_surface()` clears them.
- **Deposit motions** are pluggable: each deposit owns a `DepositMotion`
  (`deposit_motion.gd`; the base stands still). A walk is a subclass overriding
  `start()` (seeded `rng`), `update(ground, delta, time)` (steer with `walk()` /
  `turn()`, which follow the sphere in ≤ `MAX_STEP` substeps and refuse any spot the
  deposit's own `SPAWNS` rule would not allow), `pose(time)` (bob / waddle / spin in
  the deposit's frame: +Y up, -Z heading, cluster units) and `animates()`; register
  it in `ResourceDeposits.MOTIONS`. A spawn's `motion` defaults to still;
  `DepositRoll` (tumbleweeds) and `DepositHop` (slime jellies) are in use,
  `DepositDrift` (slow meandering slide) is not. Types with `collectible` false
  (tumbleweed, dried beanstalk, geyser) are scenery: deposits carry `collectible`. The beanstalks' sway is
  shader-only (`wiggle`), not a motion.
  `celestial_body._process()` calls `ResourceDeposits.advance()` with game time.
- **Catalog (I key, `planet_info_panel.gd`)** has two tabs (click, Tab or Left/Right):
  PLANETS - stats now start with a "Variant" row (`PlanetLore.variant_label()`, names
  from `VARIANT_LABELS` / `FLAG_LABELS`), a RESOURCES tally of the body's
  `resource_deposits` (scenery marked), and the globe preview (`make_preview()`)
  carries a copy of the deposits; RESOURCES - one row per `ResourceDeposits.TYPES`
  entry, a turning model (`ResourceDeposits.make_showcase()`, side-on camera), this
  world's counts per planet, and FOUND ON: every kind that spawns it
  (`spawns_of()`, random entries included) with the system's planets of that kind
  and `spawn_notes()` - where, which variants, how many. List rows shrink to fit.
  A new variant needs a label in `PlanetLore.VARIANT_LABELS`; a new spawn key needs
  words in `spawn_notes()`.
- **What the player knows** gates the catalog. `solar_system.gd` keeps
  `charted_bodies` (the sun and home planet from the start; `_chart_nearby_bodies()`
  adds a planet once the ship is within max(SOI, `CHART_RADII` radii) of it, with a
  "SURVEYED" notice through `music_toast.show_message()`) and `found_resources`
  (body -> {type: true}; empty - gathering is to call `mark_resource_found(body,
  type)`). Scenery types count as found on any charted planet they stand on.
  `is_resource_found_on()`, `is_resource_known()` (found anywhere) and
  `bodies_where_found()` drive the panel: unknown planets and resources are dark rows,
  black silhouettes and redaction bars (`_draw_redacted()`); a planet page names only
  resources found on it, the rest summed as "Unidentified signals"; a resource page
  ("OCCURS ON n planets") lists every planet holding it now - in full (count, that
  kind's spawn notes) where it was found, as redaction bars everywhere else, known
  resource or not.
  Nothing is saved - a new session starts uncharted.
- **Gallery tool.** `scripts/tools/planet_gallery.gd` photographs every planet across
  world seeds: `godot --path . -s scripts/tools/planet_gallery.gd -- --worlds 6
  --seed 1000 [--chaos C] [--out DIR]` (needs rendering, not `--headless`). Writes a
  captioned close-up per planet and `gallery.png`.
- **Heightmap** is baked on the GPU by `planet_terrain_bake.glsl` (compute, via a
  local `RenderingDevice`, one bake at a time behind `_gpu_mutex`; ~1.2 s for all 8
  at 1024²). Warped fBm continents, ridged-multifractal mountain belts, eroded fBm,
  per-cell craters (summed over neighbours - no Voronoi seams). No RenderingDevice
  (headless, Compatibility) → `bake()` returns `{}` and the body stays a flat ball.
  Do not use `.length()` on SSBO arrays there - the D3D12 backend can't translate it.
  6 cube-sphere faces, uploaded as a mipmapped 6-layer `Texture2DArray`. The
  face layout is our own (`FACE_FORWARD/RIGHT/UP` ↔ `face_uv()` in both shaders),
  not the GPU cubemap convention; edge texels lie on the cube edges so faces meet
  without seams. Keep `PlanetTerrain.face_uv()` and the shaders' in sync.
- **Mesh** is a cube-sphere (`_make_sphere()`, equal-angle, 12 / 160 quads per face
  edge), displaced in the vertex shader at LOD 0 (any blurrier mip cracks seams).
- **Shading** (`planet_terrain.gdshader`): bicubic height near the camera (bilinear
  within 3 texels of a face edge), procedural sub-texel detail faded by pixel
  footprint, cavity from a blurrier mip, dry biome, rock strata, surf, lava crust,
  waves + fresnel, cloud shadows. `relief` is the silhouette height, `bump` only
  steepens the lighting.
- **Stars**: `is_star` (the Sun) uses `planet_star.gdshader` (granulation, spots,
  limb darkening, HDR ~1.25) and `planet_corona.gdshader` on the glow plane; the
  3D `Environment` has glow on at HDR threshold 1.0 so only >1 values bloom.
- Sea level is the height at which `coverage` of the *area* lies below (weighted
  histogram, cube texels are not equal-area). Liquid is drawn flat at sea level.
- Bakes are cached statically by `cache_key()` for scene reloads (~25 MB of heights
  each at 1024²), and dropped by `clear_cache()` on a world reroll. The body polls the
  task in `_process` and waits for it in `_exit_tree`.
- Gameplay: `terrain_height_at(dir)` / `is_liquid_at(dir)` read the same texels.
- Poles/bands/caps use `surface_spin_axis` as the planet-space pole.

## Asteroid belts, rings, loading screen

- **Belts** (`asteroid_belts.gd`, `asteroid_belt.gdshader`) are scenery: no gravity,
  no collisions, unknown to SOI/autopilot/planner. Three belts in `BELTS` (154-177.2k,
  752-864k, 4.16-4.8M) sit in SOI gaps - recheck the gaps before moving one. Each belt
  is 3 MultiMeshes (rock shape variants); orbits advance on the GPU from
  `total_sim_time` (split hi/lo for float32), rocks grow to >= 1.1 px when zoomed out,
  and the mesh swaps between 3 LODs by on-screen size. `asteroid_belt_map.gd` tints
  each band light red on the `BehindWorld` layer.
- **Rings**: `has_rings` / `ring_inner_radius` / `ring_outer_radius` exports on
  `celestial_body.gd` (terrain planets only; Taurvane has them). The ring plane is
  perpendicular to `surface_spin_axis`, so the axis must lean toward the viewer or the
  rings are edge-on. Profile lives in `planet_rings.gdshaderinc`, shared by
  `planet_rings.gdshader` and `planet_terrain.gdshader` (ring shadow on the globe).
- **Loading screen** (`scripts/ui/LoadingScreen.gd`): the menu puts it on the root
  before `change_scene_to_file`; `solar_system.gd` takes it over via
  `LoadingScreen.current` and waits on `is_surface_ready()` of every body. While it is
  up (`loading_screen != null`) `_physics_process` and `_unhandled_input` return early.
  A threaded `load_threaded_request` of the scene fails on the scripts' preloads.

## Landing

`ENTER` lands on / takes off from a planet; `landing_prompt.gd` (a HUD Control
added to `$HUD` in `_ready`) is the top-centre "ENTER - LAND ON X" / "TAKE OFF"
plate, fed by `_update_landing_prompt()` every frame.

- **Candidate**: `_find_landing_candidate()` - nearest planet within
  `min(radius * LANDING_RANGE_RADII, SOI)`. ENTER is read in `_input` (not
  `_unhandled_input`, a focused button would eat it) and ignored while the catalog,
  settings, pause menu or builder is open.
- **Landed** (`landed_body != null`): the ship is not integrated - `_pin_ship_to()`
  holds it on the planet centre every sim step, so SOI, camera and HUD keep working.
  `ship.get_manual_acceleration()` (W / RMB aim / A D, same as in space) feeds
  `ground_velocity`, and `CelestialBody.roll_surface(ground_velocity * dt)` rolls
  the planet the opposite way under the ship (rotation about `step x BACK`, angle
  `|step| / draw radius`). `surface_driven` stops the auto-spin;
  `point_under_view()` is the planet-space point under the ship.
- **Locks while landed**: time warp forced and clamped to 1x (`set_time_scale`),
  `$BehindWorld`, time-warp panel and Pe/Ap gauges hidden, zoom clamped to
  `LANDED_VIEW_MAX_RADII` planet radii when zooming out (zooming in only by `ZOOM_MAX`, so the true-scale ship sprite shows past zoom 4), no pan / body picking / autopilot (F). HUD speed
  shows ground speed, orbit row "Landed <name>".
- **Take-off**: circular orbit round the planet, prograde in the direction the ship
  came in, at the landing distance clamped to `[TAKE_OFF_MIN_RADII * R, 0.8 * SOI]`;
  camera and overlays restored. Both land and take-off call
  `_restart_trajectory_prediction()`, and no prediction runs while landed.
- **Collecting** (`E` while landed; in space `E` is still the enemy menu):
  `CelestialBody.deposit_under_view(reach)` is the collectible deposit whose
  footprint (`size * 0.5` rad, plus `reach / draw radius`, reach = ship
  `collision_radius`) holds `point_under_view()` - deposit `direction`s are in
  the same planet space. `collect_under_ship()` removes it (`collect_deposit`,
  node freed; back on a world reroll), adds it to `inventory` (with the
  planet's name as its source) and calls `mark_resource_found()`, which unlocks it in the catalog. A second
  `landing_prompt.gd` instance (`collect_prompt`, key "E", row 1) shows "COLLECT
  <name>" or, for a type not yet found on this planet, "COLLECT UNIDENTIFIED
  SAMPLE". Prompts start at y 52, under `HUD/MusicToast` (16-44).
- The predictor's ORBIT/ESCAPE test is made against the planet whose SOI the
  prediction ends in (planet-relative velocity), not always the sun - against the sun,
  low planet orbits read ESCAPE on every prograde half.

## Black hole / wormhole

Erebus has `is_anomaly`: `_roll_anomaly()` rolls from `generation_seed` (again on a world
reroll) a black hole with `BLACK_HOLE_CHANCE` = 10%, otherwise a wormhole sized from `WORMHOLE_SIZES`
(Small to Giant, 0.05-0.8 of the authored radius and mass; `set_world_seed` refreshes
`mu_planets`). Both keep `is_black_hole` = true and use the same shader. With `wormhole` set, the
shader skips the disk, the captured rays show a tinted fisheye of another patch of sky
(`far_tint` / `far_offset`) and the throat gets a glowing lip. Its catalog text is `PlanetLore.WORMHOLE`.

`is_black_hole` on a `celestial_body.gd` body (Erebus): `radius` is the event horizon.
`build_black_hole()` hides the sphere and turns the glow plane into a quad
`BLACK_HOLE_EXTENT` (16) horizon radii across each way, shaded by `black_hole.gdshader`:
per-pixel ray tracing in Schwarzschild units (Rs = 1, photon bending
`-1.5 h^2 x / r^5`), a tilted thin accretion disk with Doppler beaming and gravitational
redshift, and lensing of whatever is behind (stars, orbit lines) through the screen
texture - the `Environment` background mode is Canvas up to layer -5, so those layers
are in it. Up to `max_steps` (180) steps per pixel: expensive when it fills the
screen. Its own orbit line is hidden (it would be lensed into streaks). Physics, SOI,
autopilot and the catalog (`PlanetLore.BLACK_HOLE`) treat it as a planet; flying into
the horizon is an impact. Camera2D limits are +-50 M and `ZOOM_MIN` is 0.00002 so it
can be reached.

## Flight model

- **No RCS.** Main engine only: A/D (or arrows) turn, RMB aims at the cursor, W burns,
  S cuts, X locks the throttle (W/S then trim it, a beep per two bar segments from
  `sounds/throttle_beep_1..9.wav`), Z/C hold prograde/retrograde, Shift = 20% precision.
- **Flight assist** (V, on by default, `[FA]` in the HUD): W pushes along the nose like
  the locked throttle (no speed cap) plus vectored sideways thrust that cancels drift
  relative to the SOI body, so velocity follows the nose; S brakes to a stop. Knobs in
  `ship.gd`: `MAIN_ENGINE_BOOST` (12 = 3 for handling x 4 for world scale),
  `TURN_RATE_SCALE`, `ASSIST_MAX_ACCEL`, `ASSIST_RESPONSE`, `throttle_ramp_time`.
- Manual thrust/turn input (W/A/S/D, arrows, RMB) disengages the autopilot with
  `sounds/autopilot_off.wav`; X disengages it silently (`disengage_autopilot(false)`).
- The speed gauge shows speed relative to the current SOI body (the sun out in deep
  space), not relative to the sun.
- **Trajectory line**: predictions carry per-point sim times and are redrawn every frame
  from the ship (`refresh_trajectory_line`); when the whole prediction stays inside the
  starting SOI it is stored and drawn relative to that planet (a clean ellipse). Points
  are added every `PREDICTION_DRAW_INTERVAL` steps or sooner on turns
  (`PREDICTION_DRAW_TURN`).

## Autopilot

The `AutopilotPhase` enum drives everything; `autopilot_phase` is the state variable.
Two families:

- **Local** (same SOI): `WAIT_FIRST_BURN -> FIRST_BURN -> COAST -> SECOND_BURN ->
  COMPLETE`, then `STATION_KEEPING_WAIT / STATION_KEEPING_BURN`. Hohmann-style apsis burns.
- **Interplanetary** (route): `DEPARTURE_WAIT -> DEPARTURE_BURN -> DEPARTURE_COAST ->
  TRANSFER_BURN -> TRANSFER_COAST -> ARRIVAL_COAST -> ARRIVAL_BURN`, then hands off to
  the local family. `ESCAPE_BURN / INTERPLANETARY_CRUISE / CAPTURE_BURN` are the older
  non-route path.

- Engaging on an escape path (unbound, even from the sun) goes to `CAPTURE_BURN` first,
  which brakes into orbit and hands over to the local plan.
- F in free flight (outside every planet SOI) defaults the target to the **nearest
  planet**, not the sun (Tab still reaches the sun). `engage_autopilot()` clamps the
  target altitude to the body's range, so it never aims outside the SOI.
- `INTERPLANETARY_CRUISE` from free flight flies a **Lambert intercept**
  (`OrbitMath.lambert`, `plan_intercept()`): it samples `INTERCEPT_SAMPLES` flight times
  in both directions, scores burn-now + arrival-speed + `INTERCEPT_TIME_COST` per second
  (so it heads more or less straight in), then burns continuously onto the transfer and
  re-solves it in flight. Inside `INTERPLANETARY_HOMING_SOI_FACTOR` x SOI the homing
  branch takes over, then `CAPTURE_BURN`. Falls back to `_cruise_match_target_radius()`
  when no transfer is found.

Use `is_interplanetary_autopilot_phase()` / `is_route_phase()` rather than testing phases
by hand. Route planning and trajectory prediction both run on `WorkerThreadPool` with a
dictionary holder (`route_task_holder`, `trajectory_task_holder`); anything they touch
must be a plain snapshot, never a live node.

## Conventions

- Tabs for indent, GDScript with explicit types on nearly everything
  (`var x: float = ...`), `snake_case`, two blank lines between top-level functions.
- Node fields are read with `body.get("radius")` rather than typed access, because
  planets are plain `Node2D` with an attached script.
- Long argument lists are wrapped one per line with a trailing `) -> Type:`.
- A few explanatory comments are in Polish - match the language already used in the area
  you are editing.
- HUD text is built through `hud_row(label, value)` with `HUD_LABEL_WIDTH := 14`.
- Every `.gd` has a paired `.gd.uid`; a new script needs one (Godot generates it).

## Verifying changes

There is no test suite. Changes are checked by running the game in Godot 4.7
(`run/main_scene` is the main menu; New Game shows the loading screen, then
`solar_system.tscn`). Controls: `F` arm/disarm autopilot, `Tab` cycle target, mouse wheel
zoom (or altitude while arming), middle-drag pan, `1`-`7` time warp, `.` toggle camera
follow, `N` reroll the world seed, `B` ship builder, `I` cargo hold, `J` planetary log (catalog), `T` tech tree, `M` galaxy map,
`E` collect while landed (enemy menu in space), `ENTER` land / take off, plus the flight keys above.

## Inventory

Three layers, so the hold can move into a bigger interface later without
touching the data or the drawing:

- `inventory.gd` - `class_name Inventory` (RefCounted): item id -> count in
  pickup order, plus id -> {source: count}; `add(id, n, source)`, `remove`,
  `count`, `ids`, `sources`, `total`; emits `changed`. `PlayerProgress.inventory`
  is the one hold (static, so it survives scene reloads); `solar_system.gd`'s
  `inventory` points at it and the tech tree spends from it. Ids are
  `ResourceDeposits.TYPES` keys.
- `inventory_view.gd` - `class_name InventoryView` (Control), the component:
  `bind(inventory)`, then give it any rect. Slots stretch to fill the width,
  as many rows as fit (clips, no scrolling yet); the details column (`DETAIL_WIDTH`,
  at most 42%) drops away under `DETAIL_MIN_TOTAL`. Each item held gets its own
  small SubViewport (`ResourceIcons.make_stage`) with the showcase model
  spinning, rendered only while visible.
  `step(dx, dy)` for keys, `item_selected` signal, `item_info(id)` is the one
  place that names an item.
- `inventory_screen.gd` - the disposable full-screen frame ("CARGO HOLD") around
  a view; `solar_system.gd` routes keys while open (arrows step, I/Esc close,
  J switches to the log). New `class_name`s need a rescan (`--import`, or the
  editor) before a headless run sees them.
- `resource_icons.gd` - `class_name ResourceIcons`: `icon(id)` a still cached
  Texture2D of a type's model for plain UI (tech tree), `make_stage(id, px)` a
  scene to animate, `display_name` / `color`. Icons are lit by the deposit
  shader's `fixed_light` uniform (zero = the sun as in space), so they look the
  same in any scene.

## Resources and the tech tree

Master's raw-material list (`ResourceCatalog`, 14 materials in 3 tiers with PNG
icons and a per-planet yield table) was removed: the game's resources are the
`ResourceDeposits` types gathered on planets. `PlayerProgress` holds the
`Inventory` (no starting stock - tier-1 nodes are free) and `TechTree` recipes
name deposit types; the board's materials were mapped onto them (listed in
`TechTree.gd`'s header). `TechTree.TIER_NAMES` / `TIER_COLORS` are the tree's own
tiers. `set_world_seed` (galaxy-map travel, `N`) takes off if landed and resets
`charted_bodies` / `found_resources`; `known_resources` (types ever found)
survives.

## Ship builder engines

`ModuleCatalog.engines()` builds 5 families (Chemical, Nuclear Thermal, Ion, Plasma,
Fusion) x 3 sizes S/M/L = footprints 1x1/2x1/2x2, from star ratings
(`_STAR_*` tables, `_ENGINE_SIZES` multipliers). Sprites are
`textures/modules/engine_<type>_<1|2|3>.png` (nozzle pointing left, the aft side: main
engines go in open space touching a hull's left face, grid -x, whatever the hull's rotation); an optional `..._plan.png` (`plan_texture`) is
drawn over the footprint while a module is held. The inventory shows one engine family
per row. Modules are placed click-to-hold (no drag-and-drop); `ShipGridUI` rotates
engine art with the module. There is no RCS / corrective engine any more.

## Resources, tech tree, builder inventory

From the Horizon Miro board ("Moduły statku", "Receptury modułów", "Planety → surowce").

- Resources are the `ResourceDeposits` types (see "Resources and the tech tree"
  above); master's `ResourceCatalog` is gone.
- `scripts/data/TechTree.gd`: `NODES` (branch, tier, recipe, requires, modules). Tier 1
  is open from the start. Higher tiers need `requires` (my own links, not from the board) and pay
  `UNLOCK_COST[tier]` of each recipe resource. A catalog module in no node is always
  available.
- `scripts/data/PlayerProgress.gd`: the static cargo hold (`inventory`, filled by
  collecting with E on planets) and the unlocked set.
- The builder inventory (B) lists every module by category as before (FLOOR, TRUSS
  included). Locked ones are greyed out and not clickable (`ShipBuilderController._hook_slot`), and
  the list refreshes when the yard opens. The tree itself is `scripts/ui/TechTreePanel.gd` (branch
  tabs, resource bar, scrolling `TechTreeView`) in its own window, `TechTreeWindow`, which
  `solar_system.gd` creates next to the planet catalog. **T** opens and closes it, apart from
  the **J** log and the **I** cargo hold.
- New structure categories: `FLOOR` (deck tiles that edge-attach to a hull or floor, +1 slot/cell)
  and `TRUSS` (built on the weapon-mount ring; the ring also grows from floor and truss,
  `ModuleData.is_frame()`; guns may stand on truss, `ShipHull.is_truss_beam_cell`;
  truss does not block line of sight).
- Module art is cut from `Downloads/horizon_png` into N×128 px PNGs, loaded by
  `ModuleCatalog._use_art(m, name)` when the file exists.

## Galaxy map

A star system is its `world_seed`. `scripts/data/GalaxyMap.gd` (static, no save yet)
records every seed the player has been in (`visit()` from `_ready()` and
`set_world_seed()`, so `N` adds one) and derives from the seed alone a spot on a
4-arm spiral (`position_for()`) and a name (`system_name()`). `scripts/ui/GalaxyMapWindow.gd`,
opened with **M**, draws the galaxy (`galaxy_map.gdshader`: barred spiral on the same
arm curve as `arm_angle()`, dust lanes, H II knots, point stars that resolve as you zoom;
its noise uses an integer PCG hash - a float hash breaks into squares on the GPU), the visited systems joined in visit order and the
current one pulsing, plus `GalaxyMap.systems()` (a fixed catalogue of `SYSTEM_COUNT`
seeds, drawn faint while unexplored). Selecting a system offers SET COURSE
(`GalaxyMap.set_target()`, `course_set` signal); the jump is made from the HUD's
`WarpButton` (`scripts/ui/WarpButton.gd`, under the left panel), lit only with a course
set, not landed, and past the outer edge of the last `AsteroidBelts.BELTS` belt
(`_warp_clearance()`). `start_hyperspace_jump()` adds a `HyperspaceJump`
(`scripts/ui/HyperspaceJump.gd` + `hyperspace.gdshader`: star streaks, blue tunnel,
exit flash); the sim and input are held while it runs (`hyperspace_jump != null`), the
ship runs ahead along its nose, and at the spool's end `_arrive_in_system()` calls
`set_world_seed()`, spreads the planets round their orbits and puts the ship in a
circular orbit round a random planet; the tunnel holds until every body
`is_surface_ready()`. `set_world_seed()` saves the system left
(`GalaxyMap.save_state`: charted bodies, finds, and each planet's
`collected_deposit_seeds`, which `_place_deposits()` skips) and restores it on return.
The HUD panel header and the catalog name the current system via `GalaxyMap.system_name()`.
Systems are drawn in their star's colour (`GalaxyMap.star_class()`, `STAR_CLASSES` O..M),
with a legend bottom right. Zoomed far out (`ZOOM_MIN` 0.06) the map shows
`GalaxyMap.NEIGHBOURS` - spirals, ellipticals and irregular clouds drawn by
`far_galaxy()` in `galaxy_map.gdshader` from the `nb_place` / `nb_shape` / `nb_tint`
arrays; they can be picked for an info card but are out of hyperdrive range.

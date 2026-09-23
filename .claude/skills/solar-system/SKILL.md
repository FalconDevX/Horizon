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
| `solar_system.tscn` | Scene: `Sun`, `Planets/*` (8 planet nodes), `Ship`, line/marker nodes, `HUD/*` |
| `celestial_body.gd` | `@tool` Node2D for the sun and every planet: exports, `_draw` (glow, SOI ring), surface sprite + spin |
| `planet_surface.gd` | `PlanetSurface` static lib: palette generator, blob generation, CPU-side blob lookup |
| `planet_surface.gdshader` | Canvas shader: projects a sphere onto the disc and colours it by nearest blob |
| `orbit_math.gd` | `OrbitMath` static lib: Kepler propagation, orbital elements, transfer solving |
| `interplanetary_planner.gd` | `InterplanetaryPlanner` static lib: off-thread transfer planning |
| `ship.gd` | Ship node: thrust, RCS, rotation, throttle lock |
| `*_panel.gd`, `*_gauge.gd`, `hud_panel_style.gd` | HUD widgets, all custom `_draw` |

## How the simulation works

- Gravity constant `G = 3000.0` in `solar_system.gd`; `planet_info_panel.gd` hardcodes
  its own copy as `GRAVITY_CONSTANT` - keep them in sync.
- `_physics_process` accumulates `delta * time_scale` and runs fixed `SIM_DT = 1/120`
  steps (velocity Verlet) via `simulation_step`, up to `MAX_SIM_STEPS_PER_FRAME`.
- Positions are held in `PhysicsBody` wrappers (`physics_planets`, `physics_ship`) as
  plain floats and pushed back into the nodes at the end of each step. Read node
  `position` for display; use `get_precise_xy` / `get_relative_position_precise` for math.
- **Planets feel only the sun** (`get_planet_acceleration_precise`). No planet-planet
  gravity anywhere - not in the sim, not in the predictor, not in the planner.
- The ship feels the sun, *or* - when inside one planet's SOI - that planet plus the
  planet's own sun-acceleration (patched conics, first match wins, `break`).
- `get_soi_radius(body) = distance_to_sun * (mass / sun_mass) ** 0.4`. Recomputed every
  physics frame into `soi_radii_cache`.

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

Current system (sun `Virelia`, mass 1000, radius 800):

| # | Name | Orbit radius | Radius | Mass |
| --- | --- | --- | --- | --- |
| 0 | Emberrock | 9 000 | 220 | 9 |
| 1 | Coralyss (home) | 17 500 | 430 | 50 |
| 2 | Duskveil | 32 300 | 300 | 12 |
| 3 | Thornix | 57 800 | 500 | 25 |
| 4 | Glacenna | 102 300 | 350 | 14 |
| 5 | Marrow | 163 800 | 260 | 6 |
| 6 | Vantauri | 295 000 | 700 | 34 |
| 7 | Nyxholm | 548 500 | 560 | 18 |

### Constraints when touching the planet set

- `HOME_PLANET_INDEX := 1` indexes `planets` **by scene child order**. The ship spawns
  1000 units from that planet. Inserting a node above `Coralyss` silently moves the
  spawn - append new planets at the end, or update the constant.
- Every planet currently sits at `position = Vector2(R, 0)`, so they all start phased at
  angle 0. Give a new planet a starting phase with `position = R * Vector2(cos t, sin t)`;
  the circular velocity follows automatically.
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
  a landed ship will drive it later.
- **View-space axes are constants:** `Vector3.RIGHT` = forward, `Vector3.BACK` = turn.
  Turning leaves position untouched because the ship sits on the turn axis.
- **Per-planet values** (`surface_seed`, `surface_blob_count`, `surface_color_count`) are
  hardcoded in `solar_system.tscn`, as with every other planet property.
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

- **Kinds** (`PlanetTerrain.Kind`): Terran, Desert, Volcanic, Ice, Barren, Toxic,
  Gas giant, Ice giant. `preset()` holds each kind's palette (6-stop height
  gradient), liquid colours/gloss/emission, caps, atmosphere, clouds, relief and
  noise frequency; `resolve()` drifts hue/sat/value, coverage and frequency per
  `surface_seed`. Liquid kinds: Terran (water), Volcanic (lava, emissive), Ice,
  Toxic (acid). `terrain_liquid_coverage` overrides the share (0 = dry).
- **Heightmap** is baked from FastNoiseLite on `WorkerThreadPool` (~1 s for all 8
  at 192²) into 6 cube-sphere faces, uploaded as a 6-layer `Texture2DArray`. The
  face layout is our own (`FACE_FORWARD/RIGHT/UP` ↔ `face_uv()` in the shader),
  not the GPU cubemap convention; edge texels lie on the cube edges so faces meet
  without seams. Keep `PlanetTerrain.face_uv()` and the shader's `face_uv()` in sync.
- Sea level is the height at which `coverage` of the *area* lies below (weighted
  histogram, cube texels are not equal-area). Liquid is drawn flat at sea level.
- Bakes are cached statically by `cache_key()` for scene reloads. The body polls the
  task in `_process` and waits for it in `_exit_tree`.
- Gameplay: `terrain_height_at(dir)` / `is_liquid_at(dir)` read the same texels.
- Poles/bands/caps use `surface_spin_axis` as the planet-space pole.

## Autopilot

The `AutopilotPhase` enum drives everything; `autopilot_phase` is the state variable.
Two families:

- **Local** (same SOI): `WAIT_FIRST_BURN -> FIRST_BURN -> COAST -> SECOND_BURN ->
  COMPLETE`, then `STATION_KEEPING_WAIT / STATION_KEEPING_BURN`. Hohmann-style apsis burns.
- **Interplanetary** (route): `DEPARTURE_WAIT -> DEPARTURE_BURN -> DEPARTURE_COAST ->
  TRANSFER_BURN -> TRANSFER_COAST -> ARRIVAL_COAST -> ARRIVAL_BURN`, then hands off to
  the local family. `ESCAPE_BURN / INTERPLANETARY_CRUISE / CAPTURE_BURN` are the older
  non-route path.

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

There is no test suite. Changes are checked by running the scene in Godot 4.7
(`run/main_scene = res://solar_system.tscn`). Controls: `F` arm/disarm autopilot,
`Tab` cycle target, mouse wheel zoom (or altitude while arming), middle-drag pan,
`1`-`7` time warp, `.` toggle camera follow.

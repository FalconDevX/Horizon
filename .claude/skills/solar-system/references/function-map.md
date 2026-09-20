# solar_system.gd - region map

Line anchors as of commit `65b36d9` (2770 lines). Re-derive after edits with
`grep -n "^func \|^const \|^var \|^class " solar_system.gd`.

## 1-153 - Header, state, tuning constants

- `1-3` `extends Node2D`, `const G := 3000.0`.
- `5-24` `enum AutopilotPhase` (19 phases).
- `26-55` `@onready` node refs: `$Sun`, `$Planets`, `$Ship`, `$Camera2D`, `$OrbitLines`,
  the `Line2D`s (`TrajectoryPrediction`, `OsculatingOrbitLine`, `TargetOrbit`,
  `InterplanetaryRoute`), the marker `Node2D`s, and every `HUD/*` widget.
- `57-115` mutable state: `planets`, `orbit_lines`, `orbit_line_radii`,
  `celestial_bodies`, camera/zoom flags, trajectory status, `time_scale`, apsis readouts,
  the whole `autopilot_*` block, `route_*` task state, `total_sim_time`,
  `physics_planets` / `physics_ship`, `soi_radii_cache`, `mu_sun`, `mu_planets`.
- `62` `HOME_PLANET_INDEX := 1` - ship spawn planet, index into `planets`.
- `117-153` tuning constants: zoom limits, `PREDICTION_*`, `SIM_DT`,
  `MAX_SIM_STEPS_PER_FRAME`, autopilot tolerances and scroll steps, station keeping,
  interplanetary and route thresholds.

## 155-192 - `PhysicsBody` + ship state

- `155-186` `class PhysicsBody` - float-precision mirror of a node
  (`pull_from_node`, `push_to_node`, `advance_position`, `advance_velocity`).
- `187-192` `set_ship_state` - teleport/inject ship state and resync the mirror.

## 194-262 - Input

`_unhandled_input`: `F` arm/engage autopilot, `Tab` cycle target, `1`-`7` time warp,
`.` camera follow, wheel = zoom (or autopilot altitude while arming), middle-drag pan.

## 264-318 - `_ready`

Planet discovery from `$Planets` children, circular velocities, per-planet orbit
`Line2D`, `PhysicsBody` and `mu` arrays, ship spawn at `HOME_PLANET_INDEX` + 1000 units,
all signal wiring (ship click, blueprint, main thruster toggle, time warp, Pe/Ap gauges,
orbit info button). **This is where new planets are picked up automatically.**

## 320-371 - Frame update

- `320-336` `_process` - visuals, hover selection, async trajectory, osculating orbit,
  target orbit, route planning + visual, HUD, camera follow lerp.
- `338-370` `update_screen_space_visuals` - keeps line widths, marker scales, SOI ring
  width and `visual_radius` constant in screen space by dividing by `camera_zoom`.

## 372-534 - Autopilot target selection

`start_autopilot_selection`, `get_autopilot_altitude_range`, `change_autopilot_altitude`,
`can_edit_autopilot_apsis_targets`, `change_autopilot_target_pe` / `_ap`,
`disengage_autopilot`, `cycle_autopilot_target_body`, `set_autopilot_target_body`,
`update_autopilot_hover_selection` (mouse-over picking against
`autopilot_selectable_bodies`).

## 535-576 - Precise-position helpers

`get_precise_xy`, `get_relative_position_precise` (read from the `PhysicsBody` mirrors),
`get_orbit_elements` (bound flag, periapsis/apoapsis altitude relative to a body).

## 577-692 - Engaging autopilot

`engage_autopilot` (dispatches local vs interplanetary), `engage_local_autopilot`,
`engage_interplanetary_autopilot`, `is_interplanetary_autopilot_phase`, `is_route_phase`.

## 693-934 - Local orbit autopilot

`update_orbit_autopilot` (dispatcher), `update_local_orbit_autopilot` (phase machine +
station keeping), `is_apsis_burn_window`, `get_apsis_burn_delta_v`,
`execute_apsis_change_burn`, `get_apsis_radius`.

## 935-1082 - Interplanetary phase machine

`update_interplanetary_autopilot`, `update_departure_wait`, `update_departure_burn`,
`update_departure_coast`, `begin_transfer_burn`, `update_transfer_burn`,
`update_transfer_coast`, `update_arrival_coast`, `get_autopilot_max_acceleration`,
`get_autopilot_thrust_force`, `is_autopilot_using_main_engine`.

## 1084-1220 - Route planning (threaded)

- `1084-1120` `build_route_context` - snapshot handed to `InterplanetaryPlanner`:
  per-planet `rel`, `omega`, `mu`, `soi`, plus `dep` / `target` indices. **Models every
  planet as a circular orbit at constant angular rate.**
- `1122-1155` `build_route_request` - per-stage request payload.
- `1156-1186` `update_route_planning` - `WorkerThreadPool` dispatch every
  `ROUTE_REPLAN_INTERVAL`.
- `1187-1214` `accept_route_plan` - applies the result, may trigger a mid-course
  correction burn.
- `1215-1220` `_exit_tree` - waits for pending worker tasks.

## 1222-1427 - Legacy interplanetary path + circularization

`update_interplanetary_escape_burn`, `update_interplanetary_cruise`,
`update_interplanetary_capture_burn`, `begin_local_capture`, `set_autopilot_direction`,
`update_circularization_burn`, `finish_autopilot_maneuver`.

## 1428-1527 - Orbit bookkeeping

`execute_apsis_targeting_burn`, `is_bound_to_body`, `refresh_orbit_parameters_for_body`
(fills `current_periapsis`, `current_apoapsis`, `current_eccentricity`, altitudes,
`osculating_periapsis_direction`).

## 1529-1684 - Route and target-orbit visuals

`flash_target_orbit`, `update_target_orbit_visual`, `update_interplanetary_route_visual`,
`place_route_marker`, `format_duration`.

## 1686-1995 - HUD

- `1686-1692` HUD color constants.
- `1695-1767` `update_hud` - the main left-panel readout.
- `1768-1802` `hud_row`, `get_body_display_color`, `get_delta_v_color`, `get_phase_color`.
- `1804-1866` `update_autopilot_hud`.
- `1867-1925` `get_autopilot_eta`, `get_local_orbit_eta`, `time_to_apsis`.
- `1926-1995` `get_body_name`, `get_rcs_status`, `get_autopilot_status`.

## 1997-2357 - Trajectory prediction

- `1997-2016` `update_trajectory_prediction_async` - throttled by
  `PREDICTION_UPDATE_INTERVAL`, dispatched to `WorkerThreadPool`.
- `2018-2056` `build_trajectory_snapshot` - plain-data copy of ship, sun and **all**
  planets (positions, velocities, radii, masses, SOI radii, names).
- `2057-2077` `apply_trajectory_result` - points + status color
  (IMPACT red / ESCAPE orange / ORBIT cyan / interplanetary pink).
- `2078-2320` `static func predict_trajectory(snap)` - the off-thread integrator.
  Static and snapshot-only: it must not touch nodes or instance state.
- `2321-2357` `update_trajectory_status` - debounced by `TRAJECTORY_CONFIRM_FRAMES`.

## 2358-2389 - Click and toggle handlers

`_on_ship_clicked` (camera follow), `_on_orbit_info_pressed` (feeds
`planet_info_panel.show_body` from the body's exports), `_on_main_thruster_toggled`,
`_on_time_scale_selected`.

## 2390-2494 - Orbital helpers

`get_circular_orbit_velocity`, `get_orbital_energy`, `get_orbiting_body`,
`get_soi_radius`, `is_inside_soi`, `get_current_soi`, `get_current_orbit_body`
(first-match SOI lookup), `is_bound_orbit`.

## 2495-2624 - Osculating orbit and SOI rings

`update_osculating_orbit_line` (dashed current-orbit ellipse + Pe/Ap markers),
`update_soi_visuals` (pushes `get_soi_radius` into each planet's `soi_radius` export).

## 2626-2747 - Simulation core

- `2626-2645` `_physics_process` - time accumulator, per-frame `soi_radii_cache` refresh,
  fixed-step loop, then one `update_orbit_line` per planet.
- `2647-2693` `simulation_step` - autopilot tick, input/rotation/throttle, velocity Verlet
  over planets + ship, push back to nodes.
- `2695-2747` `get_gravity_precise`, `is_inside_soi_precise`,
  `get_planet_acceleration_precise` (sun only), `get_ship_acceleration_precise`
  (patched conics + thrust/RCS/autopilot acceleration).

## 2749-2770 - Orbit trail rendering

`ORBIT_TRAIL_POINTS_PER_ORBIT := 300`, `ORBIT_RADIUS_REBUILD_THRESHOLD := 0.001` (with a
Polish comment explaining the `Line2D` rebuild cost), and `update_orbit_line`, which draws
a **perfect circle** of radius = current distance to the sun.

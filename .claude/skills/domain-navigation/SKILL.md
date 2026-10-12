---
name: domain-navigation
description: Deep implementation detail for the Navigation domain (scenes/navigation/) — baking the house into a walkable nav map so characters can path around walls. Use when editing scenes/navigation/ or working on nav baking, NavigationRegion2D, agent radius, or doorway walkability. Complements the `architecture` skill, which holds the cross-domain interfaces.
---

# Navigation domain

A leaf: it builds the map; everyone else just pathfinds. Navigation imports nothing from other
domains (a plain `rooms` array + a Node), depending only on Godot's `NavigationServer2D`.

## Baking

`NavBuilder.build(house, rooms, parent, agent_radius=14.0) -> NavigationRegion2D` bakes one
`NavigationRegion2D` whose walkable area is the house footprint (union of `rooms` rects, grown by
`BOUNDS_PAD` = 160 px so a walkable **outdoor ring** surrounds the house — characters that start
outside, like the invader NPC, can path around it to the front entrance) minus the house's **static** wall colliders (parsed via `NavigationServer2D`), so doorways — gaps in the
walls — stay open. It also **bakes each solid furniture footprint in as a hole**
(`_add_furniture_holes`): every `CollisionShape2D` on the piece — the intact primitives
(`RectangleShape2D` / `CircleShape2D`) and the `ConvexPolygonShape2D` pieces a **damaged** piece's
collider is rebuilt into (`environment_object._rebuild_collider`), inflated by `OBSTACLE_MARGIN` (via
`Geometry2D.offset_polygon` for the polygon case) — is added to the source geometry as an obstruction
outline, so paths route **around** furniture and reroute through another doorway when the near one is
blocked (and a piece that seals the only route leaves the far side unreachable — the AI's cue to shove
through). Handling every shape (not just the primitives) is what keeps a dented piece's hole from
vanishing on a re-bake. A body's footprint is the **convex hull** of all its collider shapes: a dent's
notches are far smaller than the agent, and baked in they leave sub-pixel navmesh edges the
NavigationServer cannot merge ("navigation map synchronization error"). Overlapping footprints are
then fused (`_union_outlines`, which skips the polygon merge for two outlines whose bounding boxes are apart: the union would keep them as two; `tests/navigation/furniture_union_fast_path_test.gd` pins it to the every-pair merge, and it was most of a re-bake's cost) and every outline is snapped to the 1 px grid with repeated points dropped (`_on_grid`). The bake runs in the
house's local frame and the region is offset by `house.position`, so the map lands in world space.
`main.gd` calls it once after `WorldGen.generate`. `build` and every re-bake share one private
`_bake_polygon` helper, so both carve furniture holes identically.

## Characters at rest are holes too (the steering map)

A character that stands in the way is as much an obstacle as a chair, so `NavBuilder.character_holes(root)` returns the footprint of
each **living character at rest** under `root` (`house.get_parent()`: the node the region lives under) as a world-space polygon: a
`CharacterBody2D` that still has a collision layer (death clears it, so a corpse is walked over) and moves slower than `REST_SPEED`
(10 px/s), grown by the same `OBSTACLE_MARGIN` and fed through the same union + 1 px snap as furniture. Only characters **at rest**:
every character is inside its own hole, and a walking one's would seal or split the passage around itself (a doorway, the 110 px hall)
and send its own path the long way round.

These holes live in a **second map**, not the world's: `build` adds a child region `NavSteering` (`steering_region(region)`) on a map of
its own (`steering_map(world_map)`, made on first use with the project's 2D navigation defaults and freed with its last region).
The world's own map stays furniture-only, because the AI plans on it (flank/fire/retreat spots, route length and exposure, tactical
entry slots, search coverage) and a body's hole would bend every one of those. Only a `NavigationAgent2D` walks the steering map, and
the AI's `Locomotion` chooses per walk (see `domain-ai-behavior`). `rebake_steering(region, house, rooms)` re-bakes it; it is baked
with `weld=true`, which merges the vertices that share a 1 px cell (`_weld_vertices`): a hole meeting a wall leaves vertices a fraction
of a pixel apart, and the server rejects such an edge ("navigation map synchronization error").

Solid furniture is recognised by engine type alone — a non-frozen `RigidBody2D` with a
`CollisionShape2D` (walls are `StaticBody2D`; non-solid decor freezes itself) — so Navigation stays a
leaf that imports nothing.

## Keeping the holes current (`nav_updater.gd`)

The holes a `build` carves are a snapshot of where the furniture stood at bake time. Furniture is
`RigidBody2D` and gets shoved around in play, so those holes go stale. `NavBuilder.rebake(region,
house, rooms, agent_radius=14.0)` re-bakes `region`'s polygon **in place** (same region + world
offset; reassigning `navigation_polygon` re-registers the mesh) with the holes re-measured at the
furniture's **current** positions — `furniture_holes` reads each collider's live `global_transform`,
so moved pieces carve at their new spots. `rebake_async(region, house, rooms, agent_radius, done)` does the same with the
bake on the NavigationServer's worker thread: the source geometry (walls from the scene tree, the footprint, the furniture
holes) is gathered on the main thread by `_source_for`, `bake_from_source_geometry_data_async` bakes it, and the polygon is
assigned (slivers dropped) when the bake lands, then `done` runs; a region freed meanwhile is left alone. The sync `rebake`
stays for a caller that needs the map now (`perf/bake_and_path_stress` times it); the re-baker uses the async one, so no
frame pays for a bake (`tests/navigation/rebake_runs_off_the_main_thread_test.gd`).

`nav_updater.gd` (a script-only Node; `main.gd` builds it once right after the bake and hands it the
region, house, rooms and the overlay) drives the re-bake on an interval. Each tick it recomputes
`furniture_holes` and `character_holes` (cheap — transforms only, no bake) and re-bakes **only** when a piece moved past
`move_threshold` (4 px): furniture re-bakes both regions (the planning one on the server's worker thread, `rebake_async`; a
tick while that bake is still in flight (`_baking`) leaves the planning region alone, and its baseline is set from what the
bake carved when it lands, so a move during a bake is caught by the next tick), a character that stopped, set off, appeared
or died re-bakes the steering one in place. An at-rest scene costs just the compare. Exports: `enabled`,
`interval` (0.75 s between checks), `move_threshold`. After a re-bake (once the planning one lands) it calls the overlay's `setup`
again so the overlay re-snapshots. **Bulldozing is still the behaviour between re-bakes** (and for
non-solid decor, which is never carved): a piece just shoved is run over by the character's push
physics until the next re-bake routes paths around its new position.

Any `NavigationAgent2D` (the NPC's) then pathfinds against the global map automatically. The AI's
locomotion sets `target_position` and steers at `get_next_path_position()`; it does **not** turn on
the agent's RVO avoidance.

## Debug overlay (`nav_debug.gd`)

`nav_debug.gd` is an optional, draw-only overlay (a single world-space `Node2D`, since the map is
global — not per-NPC) that draws the furniture HOLES carved out of the navmesh as filled polygons +
outlines. `main.gd` builds it once right after the bake: `nav_debug.setup(house)` snapshots the holes
via `NavBuilder.furniture_holes(house)`, and `show_holes` toggles it (wired from the setup window's
"Navigation holes" checkbox / toggle-bar button, whose starting state is `main.gd`'s `show_nav_holes` export — off).
`furniture_holes(house) -> Array` returns each solid piece's grown footprint as a closed WORLD-space
polygon, using the exact same selection and footprint helpers the bake feeds the obstruction baker
(`_add_furniture_holes` calls it), so the overlay cannot drift from what was carved. `nav_updater.gd`
calls `setup` again after each re-bake, so the overlay **re-snapshots** and follows the furniture
to its current positions. The characters' holes are drawn too, in another colour. The overlay reads nothing back and feeds nothing in.

## Interface recap (authoritative in the `architecture` skill)

- **Main / AI → Navigation** (interface 9): `NavBuilder.build(house, rooms, parent,
  agent_radius)` bakes the region; consumers only set a `NavigationAgent2D`'s `target_position`
  and read `get_next_path_position()`. `NavBuilder.rebake(region, house, rooms, agent_radius)`
  re-carves the holes in place as furniture moves (driven internally by `nav_updater.gd`).
  `NavBuilder.furniture_holes(house) -> Array` is the debug read Main snapshots for the
  `nav_debug.gd` overlay. `NavBuilder.character_holes(root)`, `steering_map(world_map) -> RID` (invalid when the world has none),
  `steering_region(region)` and `rebake_steering(region, house, rooms)` are the characters-at-rest side (above).

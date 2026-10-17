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
then fused (`_union_outlines`, which skips the polygon merge for two outlines whose bounding boxes are apart: the union would keep them as two; `tests/navigation/furniture_union_fast_path_test.gd` pins it to the every-pair merge) and every outline is snapped to the 1 px grid with repeated points dropped (`_on_grid`). The bake runs in the
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
its own (`steering_map(planning_map)`, made on first use with the project's 2D navigation defaults and freed with its last region).
`steering_map` names it from NavBuilder's own count of steering regions, so it is valid the moment `build` returns, before the server has
taken the region in (Main drops the NPCs in within that frame, and each NPC's locomotion asks for it as it is set up); whether it answers
queries yet is `ready`, as for any map (`tests/navigation/steering_map_named_once_built_test.gd`).
The world's own map stays furniture-only, because the AI plans on it (flank/fire/retreat spots, route length and exposure, tactical
entry slots, search coverage) and a body's hole would bend every one of those. Only a `NavigationAgent2D` walks the steering map, and
the AI's `Locomotion` chooses per walk (see `domain-ai-behavior`). The map carves every body at rest, seen or not; which bodies a walk
accounts for is the walker's business (the AI goes round by it only for a body it knows of, and stops short when it has no way round).
`rebake_steering(region, house, rooms)` re-bakes it.

**Every bake is welded** (`_weld_vertices`, run by `_bake_polygon` and by `rebake_async` when its bake lands): it merges the vertices that
share a 1 px cell, because a hole meeting a wall leaves vertices a fraction of a pixel apart and the server rejects such an edge
("navigation map synchronization error"). A character's hole does it, and so does a piece of furniture's, a turned chair beside a wall for one,
so the planning re-bake welds too (`tests/navigation/furniture_beside_wall_bakes_clean`, `character_beside_wall_bakes_clean`).

Solid furniture is recognised by engine type alone — a `RigidBody2D` with a `CollisionShape2D`: shoved
furniture, and an anchored piece (frozen static, a streetlight's post: it never moves, and is carved like any other;
`tests/navigation/anchored_hole`). Walls are `StaticBody2D` (parsed, not carved); non-solid decor is frozen too but has no
collider, so it leaves no hole — so Navigation stays a leaf that imports nothing.

## Avoid maps (`avoid_map`): the planning bake plus holes someone wants to keep out of

A walk that should keep out of some stretch of floor (the AI's doorway views, `docs/tactical-entry.md` E18) plans on a map that has it
carved out: `NavBuilder.avoid_map(region, key, holes) -> RID`. `region` is the planning region (`planning_region(planning_map)` finds the
one `build` put on a world map), `holes` are closed world-space polygons, `key` names the set. The planning bake keeps what it was made
from on its region (`_remember_source`: the walkable outline, the obstructions and the agent radius, with a version that counts the
bakes), so the avoid bake is the same geometry with the holes added as obstructions, fused (`_union_outlines`), snapped to the grid and
simplified like the furniture's, then welded and stripped of slivers. Each key gets a map of its own (`_new_map`, the project's 2D defaults)
holding one child region `NavAvoid` of the planning region; the bake runs on the NavigationServer's worker thread
(`bake_from_source_geometry_data_async`), so a frame never pays for it, and the region is awaited like any (`ready(map)` is false until it
answers queries). Asking again for the key returns the same map and marks it asked; once the planning bake has been redone (furniture
shoved, `rebake` / `rebake_async`) it is baked again in place, the old mesh answering meanwhile. A map nobody has asked for in
`avoid_idle_ms` (a static var, 20 s of wall clock) is freed with its region (its `tree_exited` frees the map) by the next ask for another
key on the same planning map (the sweep runs only inside `avoid_map`: with no further asks an idle map lives on), and every one is freed with its world.
Invalid when the region has no bake to start from. The world's own map and the steering map are not touched. Test:
`tests/navigation/avoid_map_carves_the_views_test.gd`.

## Keeping the holes current (`nav_updater.gd`)

The holes a `build` carves are a snapshot of where the furniture stood at bake time. Furniture is
`RigidBody2D` and gets shoved around in play, so those holes go stale. `NavBuilder.rebake(region,
house, rooms, agent_radius=14.0)` re-bakes `region`'s polygon **in place** (same region + world
offset; reassigning `navigation_polygon` re-registers the mesh) with the holes re-measured at the
furniture's **current** positions — `furniture_holes` reads each collider's live `global_transform`,
so moved pieces carve at their new spots. `rebake_async(region, house, rooms, agent_radius, done)` does the same with the
bake on the NavigationServer's worker thread: the source geometry (walls from the scene tree, the footprint, the furniture
holes) is gathered on the main thread by `_source_for`, `bake_from_source_geometry_data_async` bakes it, and the polygon is
assigned (slivers dropped) when the bake lands, then `done` runs; a region freed meanwhile is left alone (the callback holds it
by a `WeakRef`: a lambda capturing a node freed before it runs logs an engine error into whatever runs next, a test world torn
down mid-bake; `tests/navigation/rebake_outlives_region`). The sync `rebake`
stays for a caller that needs the map now (`perf/bake_and_path_stress` times it); the re-baker uses the async one, so no
frame pays for a bake (`tests/navigation/rebake_runs_off_the_main_thread_test.gd`).

`nav_updater.gd` (a script-only Node; `main.gd` builds it once right after the bake and hands it the
region, house, rooms and the overlay) drives the re-bake on an interval. Each tick it recomputes
`furniture_holes` and `character_holes` (cheap — transforms only, no bake) and re-bakes **only** when a piece moved past
`move_threshold` (4 px): furniture re-bakes both regions (the planning one on the server's worker thread, `rebake_async`; a
tick while that bake is still in flight (`_baking`) leaves the planning region alone, and its baseline is set from what the
bake carved when it lands, so a move during a bake is caught by the next tick), a character that stopped, set off, appeared
or died re-bakes the steering one in place. An at-rest scene costs just the compare. Exports: `enabled`,
`interval` (0.75 s between checks), `move_threshold`. Both bakes of a tick carve the footprints it just measured (the
domain-internal `NavBuilder._rebake_async` / `_rebake_steering` take them; the public `rebake_async` / `rebake_steering` measure
their own), so a tick measures the furniture once, and parses the walls once (`_walls_of`: the static colliders' outlines on the
1 px grid, handed to both; `tests/navigation/walls_parsed_once_bake_the_same_test.gd`). `_simplified` keeps each vertex's distance
from its neighbours' line and measures again only the two neighbours of a dropped one
(`tests/navigation/outline_simplify_matches_plain_test.gd`). `furniture_holes` finds the pieces with `find_children` (depth first, as a walk
of the house's nodes would) and keeps each body's hull (`_hulls`) with what it was made from (`_hull_inputs`: each shape's global
transform and size, radius or points), so only a piece that moved, turned or was dented is measured again
(`tests/navigation/furniture_holes_follow_the_pieces_test.gd`). After a re-bake (once the planning one lands) it calls the overlay's `setup`
again so the overlay re-snapshots. **Bulldozing is still the behaviour between re-bakes** (and for
non-solid decor, which is never carved): a piece just shoved is run over by the character's push
physics until the next re-bake routes paths around its new position.

Any `NavigationAgent2D` (the NPC's) then pathfinds against the global map automatically. The AI's
locomotion sets `target_position` and steers at `get_next_path_position()`; it does **not** turn on
the agent's RVO avoidance.

## Map queries (`ready` / `snap` / `route` / `path_length`)

The AI weighs points and routes against the planning map many times a decision, and every such read has to cope with
the first frames before a bake, when the map is valid but has never synchronized. `NavBuilder.ready(map)` is that one
rule (`map.is_valid()` and `map_get_iteration_id(map) != 0`, **and** every region `build` put on the map has been taken in).
The last part is the start of a match: the world's map is already live with the previous navmesh (the menu's, the last
match's) and takes a new house in only a frame later, on a worker thread, so a query in between answers from the old mesh
(`map_force_update` does not change that) and a room's centre snaps to a corner nowhere near the house (issue #49, a room
zone drawn outside the house). `build` therefore records each region it adds (planning and steering) with a probe point,
and `ready` stays false until a query at the probe is answered by that region (`_awaiting`; an entry is dropped when its region
leaves the tree). `tests/ai/perception/room_zones_inside_their_rooms_test.gd` builds a match over a live map and pins it. `snap(map, p)` returns `p` unchanged until then, else the
closest navmesh point (a room's geometric centre is often inside furniture); `route(map, from, to)` returns a straight
`[from, to]` until then — and when the server finds no path — else the waypoints; `path_length(path)` sums a path.
The AI's `Locomotion` (`reachable`, `on_navmesh`, the steering-map choice), `agent_tactics.gd`, `agent_entry.gd`,
`snapshot_options.gd` and `routes_debug.gd` all call these rather than keeping their own copy of the guard.

## Debug overlay (`nav_debug.gd`)

`nav_debug.gd` is an optional, draw-only overlay (a single world-space `Node2D`, since the map is
global — not per-NPC) that draws the furniture HOLES carved out of the navmesh as filled polygons +
outlines. `main.gd` builds it once right after the bake: `nav_debug.setup(house)` snapshots the holes
via `NavBuilder.furniture_holes(house)`, and `show_holes` toggles it (wired from the toggle bar's
"Navigation holes" button; it starts from `main.gd`'s `show_nav_holes` export — off — unless a saved toggle in `Settings.overlays` overrides it).
`furniture_holes(house) -> Array` returns each solid piece's grown footprint as a closed WORLD-space
polygon, using the exact same selection and footprint helpers the bake feeds the obstruction baker
(`_add_furniture_holes` calls it), so the overlay cannot drift from what was carved. `nav_updater.gd`
calls `setup` again after each re-bake, so the overlay **re-snapshots** and follows the furniture
to its current positions. The characters' holes are drawn too, in another colour. The overlay reads nothing back and feeds nothing in.

**Interfaces:** 9 (Main / AI → Navigation) — signatures in `architecture`.

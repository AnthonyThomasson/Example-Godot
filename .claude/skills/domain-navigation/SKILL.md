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
vanishing on a re-bake. The bake runs in the
house's local frame and the region is offset by `house.position`, so the map lands in world space.
`main.gd` calls it once after `WorldGen.generate`. `build` and every re-bake share one private
`_bake_polygon` helper, so both carve furniture holes identically.

Solid furniture is recognised by engine type alone — a non-frozen `RigidBody2D` with a
`CollisionShape2D` (walls are `StaticBody2D`; non-solid decor freezes itself) — so Navigation stays a
leaf that imports nothing.

## Keeping the holes current (`nav_updater.gd`)

The holes a `build` carves are a snapshot of where the furniture stood at bake time. Furniture is
`RigidBody2D` and gets shoved around in play, so those holes go stale. `NavBuilder.rebake(region,
house, rooms, agent_radius=14.0)` re-bakes `region`'s polygon **in place** (same region + world
offset; reassigning `navigation_polygon` re-registers the mesh) with the holes re-measured at the
furniture's **current** positions — `furniture_holes` reads each collider's live `global_transform`,
so moved pieces carve at their new spots.

`nav_updater.gd` (a script-only Node; `main.gd` builds it once right after the bake and hands it the
region, house, rooms and the overlay) drives the re-bake on an interval. Each tick it recomputes
`furniture_holes` (cheap — transforms only, no bake) and re-bakes **only** when a piece moved past
`move_threshold` (4 px), so an at-rest scene costs just the compare. Exports: `enabled`,
`interval` (0.75 s between checks), `move_threshold`. After a re-bake it calls the overlay's `setup`
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
"Furniture holes" checkbox, whose starting state is `main.gd`'s `show_nav_holes` export — on).
`furniture_holes(house) -> Array` returns each solid piece's grown footprint as a closed WORLD-space
polygon, using the exact same selection and footprint helpers the bake feeds the obstruction baker
(`_add_furniture_holes` calls it), so the overlay cannot drift from what was carved. `nav_updater.gd`
calls `setup` again after each re-bake, so the overlay **re-snapshots** and follows the furniture
to its current positions. The overlay reads nothing back and feeds nothing in.

## Interface recap (authoritative in the `architecture` skill)

- **Main / AI → Navigation** (interface 9): `NavBuilder.build(house, rooms, parent,
  agent_radius)` bakes the region; consumers only set a `NavigationAgent2D`'s `target_position`
  and read `get_next_path_position()`. `NavBuilder.rebake(region, house, rooms, agent_radius)`
  re-carves the holes in place as furniture moves (driven internally by `nav_updater.gd`).
  `NavBuilder.furniture_holes(house) -> Array` is the debug read Main snapshots for the
  `nav_debug.gd` overlay.

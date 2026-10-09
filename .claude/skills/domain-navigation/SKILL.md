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
outside, like the invader NPC, can path around it to a door) minus the house's **static** wall colliders (parsed via `NavigationServer2D`), so doorways — gaps in the
walls — stay open. It also **bakes each solid furniture footprint in as a hole**
(`_add_furniture_holes`): the piece's collider shape (`RectangleShape2D` / `CircleShape2D`), grown by
`OBSTACLE_MARGIN`, is added to the source geometry as an obstruction outline, so paths route **around**
furniture and reroute through another doorway when the near one is blocked (and a piece that seals the
only route leaves the far side unreachable — the AI's cue to shove through). The bake runs in the
house's local frame and the region is offset by `house.position`, so the map lands in world space.
`main.gd` calls it once after `WorldGen.generate`.

Baked holes are a **static snapshot** taken at build time. A piece shoved off its hole during play is
not re-baked and gets no dynamic avoidance — the NPC bulldozes it with its own push physics instead.
Solid furniture is recognised by engine type alone — a non-frozen `RigidBody2D` with a
`CollisionShape2D` (walls are `StaticBody2D`; non-solid decor freezes itself) — so Navigation stays a
leaf that imports nothing.

Any `NavigationAgent2D` (the NPC's) then pathfinds against the global map automatically. The AI's
locomotion sets `target_position` and steers at `get_next_path_position()`; it does **not** turn on
the agent's RVO avoidance.

## Debug overlay (`nav_debug.gd`)

`nav_debug.gd` is an optional, draw-only overlay (a single world-space `Node2D`, since the map is
global — not per-NPC) that draws the furniture HOLES carved out of the navmesh as filled polygons +
outlines. `main.gd` builds it once right after the bake: `nav_debug.setup(house)` snapshots the holes
via `NavBuilder.furniture_holes(house)`, and `show_holes` toggles it (wired from the setup window's
"Furniture holes" checkbox, off by default). `furniture_holes(house) -> Array` returns each solid
piece's grown footprint as a closed WORLD-space polygon, using the exact same selection and footprint
helpers the bake feeds the obstruction baker (`_add_furniture_holes` now calls it), so the overlay
cannot drift from what was carved. Like the baked holes it is a **static snapshot**: it does not follow
a piece shoved off its spot afterwards (that piece gets no dynamic avoidance anyway). The overlay reads
nothing back and feeds nothing in.

## Interface recap (authoritative in the `architecture` skill)

- **Main / AI → Navigation** (interface 9): `NavBuilder.build(house, rooms, parent,
  agent_radius)` bakes the region; consumers only set a `NavigationAgent2D`'s `target_position`
  and read `get_next_path_position()`. `NavBuilder.furniture_holes(house) -> Array` is the debug read
  Main snapshots for the `nav_debug.gd` overlay.

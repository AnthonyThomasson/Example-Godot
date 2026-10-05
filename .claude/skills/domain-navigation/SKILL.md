---
name: domain-navigation
description: Deep implementation detail for the Navigation domain (scenes/navigation/) — baking the house into a walkable nav map so characters can path around walls. Use when editing scenes/navigation/ or working on nav baking, NavigationRegion2D, agent radius, or doorway walkability. Complements the `architecture` skill, which holds the cross-domain interfaces.
---

# Navigation domain

A leaf: it builds the map; everyone else just pathfinds. Navigation imports nothing from other
domains (a plain `rooms` array + a Node), depending only on Godot's `NavigationServer2D`.

## Baking

`NavBuilder.build(house, rooms, parent, agent_radius=14.0) -> NavigationRegion2D` bakes one
`NavigationRegion2D` whose walkable area is the house footprint (union of `rooms` rects) minus the
house's **static** wall colliders (parsed via `NavigationServer2D`), so doorways — gaps in the
walls — stay open. It also **bakes each solid furniture footprint in as a hole**
(`_add_furniture_holes`): the piece's collider shape (`RectangleShape2D` / `CircleShape2D`), grown by
`OBSTACLE_MARGIN`, is added to the source geometry as an obstruction outline, so paths route **around**
furniture and reroute through another doorway when the near one is blocked (and a piece that seals the
only route leaves the far side unreachable — the AI's cue to shove through). The bake runs in the
house's local frame and the region is offset by `house.position`, so the map lands in world space.
`main.gd` calls it once after `WorldGen.generate`.

Baked holes are a **static snapshot** taken at build time. To cover a piece that gets shoved off its
hole during play, `_add_furniture_avoiders` also attaches a dynamic **avoidance** `NavigationObstacle2D`
(a circle of the piece's inscribed half-extent, `avoidance_enabled`, `affect_navigation_mesh = false`)
as a child of each solid body, so it follows the piece. Solid furniture is recognised by engine type
alone — a non-frozen `RigidBody2D` with a `CollisionShape2D` (walls are `StaticBody2D`; non-solid decor
freezes itself) — so Navigation stays a leaf that imports nothing.

Any `NavigationAgent2D` (the NPC's) then pathfinds against the global map automatically. The AI
controller sets `target_position`, reads `get_next_path_position()`, and additionally turns on the
agent's RVO **avoidance** (feeding `velocity` and applying the `velocity_computed` safe velocity) so it
steers around the avoidance obstacles.

## Interface recap (authoritative in the `architecture` skill)

- **Main / AI → Navigation** (interface 9): `NavBuilder.build(house, rooms, parent,
  agent_radius)` bakes the region; consumers only set a `NavigationAgent2D`'s `target_position`
  and read `get_next_path_position()`.

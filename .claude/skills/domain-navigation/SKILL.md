---
name: domain-navigation
description: Deep implementation detail for the Navigation domain (scenes/navigation/) — baking the house into a walkable nav map so characters can path around walls. Use when editing scenes/navigation/ or working on nav baking, NavigationRegion2D, agent radius, or doorway walkability. Complements AGENTS.md, which holds the cross-domain interfaces.
---

# Navigation domain

A leaf: it builds the map; everyone else just pathfinds. Navigation imports nothing from other
domains (a plain `rooms` array + a Node), depending only on Godot's `NavigationServer2D`.

## Baking

`NavBuilder.build(house, rooms, parent, agent_radius=14.0) -> NavigationRegion2D` bakes one
`NavigationRegion2D` whose walkable area is the house footprint (union of `rooms` rects) minus the
house's **static** wall colliders (parsed via `NavigationServer2D`), so doorways — gaps in the
walls — stay open and `RigidBody2D` furniture is ignored (it moves). The bake runs in the house's
local frame and the region is offset by `house.position`, so the map lands in world space.
`main.gd` calls it once after `WorldGen.generate`.

Any `NavigationAgent2D` (the NPC's) then pathfinds against the global map automatically — the only
consumer wiring is the AI controller setting `target_position` and reading
`get_next_path_position()`.

## Interface recap (authoritative in AGENTS.md)

- **Main / AI → Navigation** (interface 9): `NavBuilder.build(house, rooms, parent,
  agent_radius)` bakes the region; consumers only set a `NavigationAgent2D`'s `target_position`
  and read `get_next_path_position()`.

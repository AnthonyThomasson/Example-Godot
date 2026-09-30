---
name: domain-objects
description: Deep implementation detail for the Objects domain (scenes/objects/) — the world's furniture and walls: their data, how they're hit/pushed/deformed, and how they compose Physics. Use when editing scenes/objects/ (environment_object, wall, the factories) or working on the hittable/pushable/interactable contracts, object field schema, or wall segment math. Complements AGENTS.md, which holds the cross-domain interfaces.
---

# Objects domain

Owns the world's objects (furniture + walls): their data and how they're hit/pushed. Objects
owns the *field schema* and turns a plain definition dict from World-Gen into a node.

## The hittable contract (Objects ↔ strikers)

Every world object (furniture **and** walls) implements:
- `get_surface() -> Dictionary` → `{ coverage, penetration, material, color }`
- `take_hit(hit: HitInfo) -> void`

`HitInfo` (`physics/hit_info.gd`) carries `position, normal, direction, damage, speed_factor,
penetrated, source`. The projectile decides the ballistic outcome, then hands the object a
HitInfo; the object decides what a hit *does to it* (shove + deform + debris). The projectile is
the only striker that uses this; a melee punch shoves through the "pushable" contract below and
does **not** deform.

## The pushable contract

Anything shoveable exposes `apply_impulse(v)` + `get_mass()`. Furniture is a `RigidBody2D`, so
its native methods serve the contract (the engine integrates motion, collisions, pivoting and
settling). Used by furniture→character contact transfers, bullet impacts, melee punches (a
range-of-motion-scaled central shove), and the walking character.

## The interactable contract

Every world object implements `get_interactions() -> Array` (plain data dicts: `id`, `label`,
optional `move_to` / `requires_item`), advertised via the optional `interactions` object field.
Which objects offer which actions is pure catalogue data — the Interaction domain consumes this
and never learns what an interaction *means*.

## Objects → Physics (objects compose physics; Physics is a leaf)

- `Knockback` (Node child): RigidBody2D adapter — configures its parent body (no gravity,
  `mass`, damping, origin-pinned center of mass) and owns `apply_impulse(v, at_world)`.
- `Deformable` (Node child): `record(hit)`, `impacts`, `damage_total`, `changed` signal.
- `Deformation` (static): silhouette/collider polygons + drawing.
- `Physics.impact_impulse(hit) -> Vector2` and `Physics.spawn_debris(world, hit, surface)`.

## Runtime-shape convention (built in `_ready()`, not in the scene)

- `wall.gd._build_walls()` — a `RectangleShape2D` per wall segment (layout is data-driven from
  `size`/`openings`; `openings` are `{ side, offset, width }`). `wall.gd` owns the wall-segment
  math (`wall_segments()`) and colliders.
- `environment_object.gd` (a `RigidBody2D`) builds its collider only when `solid`; non-solid
  decor is `freeze`d (no shape) and gets `z_index = -1`. Physics components (`Knockback`,
  `Deformable`) are added as child Nodes in `environment_object._ready()`.

The editor shows "no shape" warnings on each `Wall` — expected; the shapes exist at runtime.

## Layering (control / animate / draw)

`environment_object.gd` / `wall.gd` are the control nodes (geometry + colliders, never draw).
`environment_object_visuals` / `wall_visuals` (own child `Node2D`s) read the deformed geometry
from their control node and draw it.

## Interface recap (authoritative in AGENTS.md)

- **World Generation → Objects** (interface 2): `ObjectFactory.spawn(definition, position,
  parent, opts) -> Node`, `WallFactory.spawn(rect, thickness, openings, name, parent) -> Node`,
  `Wall.Side` enum.
- Objects also implements the hittable (3), pushable (5) and interactable (8) contracts above.

---
name: domain-objects
description: Deep implementation detail for the Objects domain (scenes/objects/) — the world's furniture and walls: their data, how they're hit/pushed/deformed, how they're drawn (including the procedural top-down pixel art for the sofa, tables and chair), and how they compose Physics. Use when editing scenes/objects/ (environment_object, wall, the factories, art/) or working on the hittable/pushable/interactable contracts, object field schema, furniture pixel art / ObjectArtConfig, or wall segment math. Complements the `architecture` skill, which holds the cross-domain interfaces.
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

## Pixel art (`objects/art/`, private to Objects)

A piece whose definition sets `art` (a painter id) is drawn as procedural top-down pixel art
instead of a flat shape with its name label. Only `environment_object_visuals.gd` reads it.
- `object_art.gd` — `texture(art, size, color, facing, opts)`: picks the painter from `PAINTERS`
  (`sofa`, `table`, `chair`), paints at `size / ObjectArtConfig.pixel_size` in a **canonical frame**
  (front toward +y) under the world light turned into that frame, then rotates the image to
  `facing`, so lighting stays world-consistent. Textures are cached by their inputs (static, so
  they survive scene reloads).
- `pixel_canvas.gd` — the drawing surface: an RGBA8 Image + a height map. `Shape`s (`rounded()`,
  `bowed()`) are rasterized masks that also precompute each pixel's depth-from-edge and outward
  normal, which drive `bevel()` (light-facing edges lit, far edges shaded) and `outline()`. Plus
  `paint_over`, `speckle` (fabric), `grain`/`knot` (wood), and `cast_shadows()` (a taller part
  shades the lower pixels on its far side from the light, via the height map).
- `sofa_painter.gd` / `table_painter.gd` / `chair_painter.gd` — `static paint(canvas, base, opts)`.
  Each knob reads `opts.get(key, ObjectArtConfig.<painter>_<key>)`, so a catalogue `art_opts`
  overrides it for one piece (e.g. the coffee table's `inset`, the formal table's `runner`).
- `object_art_config.gd` — `ObjectArtConfig`, the static tuning holder: `pixel_size`,
  `light_from`, drop shadow, cast shadow, tone ramp, texture densities, and per-painter proportions.

Object fields for art: `art`, `art_opts` (from the definition) and `facing` (`opts.facing` from
World-Gen; visual only, a cardinal direction in the local frame — the `rotated` size swap still
owns the footprint). The visuals draw a world-aligned drop shadow, then call
`Deformation.draw_shape(..., texture)` so dents and chunks cut into the art. To add a painter:
write `<name>_painter.gd`, register it in `ObjectArt.PAINTERS`, add its knobs to
`ObjectArtConfig`, and set `"art": "<name>"` on catalogue definitions.

## Interface recap (authoritative in the `architecture` skill)

- **World Generation → Objects** (interface 2): `ObjectFactory.spawn(definition, position,
  parent, opts) -> Node`, `WallFactory.spawn(rect, thickness, openings, name, parent) -> Node`,
  `Wall.Side` enum.
- Objects also implements the hittable (3), pushable (5) and interactable (8) contracts above.

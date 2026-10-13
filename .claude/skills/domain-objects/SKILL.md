---
name: domain-objects
description: Deep implementation detail for the Objects domain (scenes/objects/) — the world's furniture, walls and floors: their data, how they're hit/pushed/deformed, how they're drawn (the procedural top-down pixel art for every piece, wall and floor: painters, props, PixelCanvas, ObjectArtConfig), and how they compose Physics. Use when editing scenes/objects/ (environment_object, wall, floor, the factories, art/) or working on the hittable/pushable/interactable contracts, object field schema, pixel art / painters / props / floor and wall tiles, or wall segment math. Complements the `architecture` skill, which holds the cross-domain interfaces.
---

# Objects domain

Owns the world's objects (furniture, walls, floors): their data, how they're hit/pushed, and
their procedural pixel art. Objects owns the *field schema* and turns a plain definition dict
from World-Gen into a node.

## The hittable contract (Objects ↔ strikers)

Every world object (furniture **and** walls) implements:
- `get_surface() -> Dictionary` → `{ coverage, penetration, material, color }` — `coverage` (0–100) is the
  object's **height**: a bullet flies at one height and strikes what stands above it (a character's is its posture's;
  see `docs/cover-and-stance.md`)
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
- `BloodSmear` (Node child, solid pieces only): fed the footprint polygon (`Deformation.shape_polygon`, re-fed
  when the collider is rebuilt); drags blood out of a puddle as streaks while the piece slides.
- `Deformation` (static): silhouette/collider polygons + drawing.
- `Physics.impact_impulse(hit) -> Vector2` and `Physics.spawn_debris(world, hit, surface)`.

## Runtime-shape convention (built in `_ready()`, not in the scene)

- `wall.gd._build_walls()` — a `RectangleShape2D` per wall segment (layout is data-driven from
  `size`/`openings`; `openings` are `{ side, offset, width }`). `wall.gd` owns the wall-segment
  math (`wall_segments()`) and colliders.
- `environment_object.gd` (a `RigidBody2D`) builds its collider only when `solid`; non-solid
  decor is `freeze`d (no shape), gets `z_index = ObjectArtConfig.rug_z_index` (-3) and registers a porous `BloodSurface` rect. Physics components (`Knockback`,
  `Deformable`, `BloodSmear`) are added as child Nodes in `environment_object._ready()`.

The editor shows "no shape" warnings on each `Wall` — expected; the shapes exist at runtime.

## Layering (control / animate / draw)

`environment_object.gd` / `wall.gd` / `floor/floor.gd` are the control nodes (geometry, colliders,
look data — never draw). `environment_object_visuals` / `wall_visuals` / `floor_visuals` (own
child `Node2D`s) read from their control node and draw it.

## Floors (`objects/floor/`)

`FloorFactory.spawn(rect, definition, name, parent)` builds a `Floor` (`Node2D`, no collider —
shots, navigation and AI perception all pass over it) holding `size`, `art`, `color`,
`floor_material`, `art_opts`. It sits at `ObjectArtConfig.floor_z_index` (beneath blood pools,
casings and rugs). `floor_visuals.gd` repeats `ObjectArt.tile(...)` across the rect
(`texture_repeat` on, nearest filter, scaled by `pixel_size`).

A floor registers itself with Physics' `BloodSurface` (`_ready`; unregisters on exit) with `flow_groove(world, half)`,
which asks `FloorPainter.groove(local, opts, half)` — analytic, mirroring the painted geometry (tile/mosaic/
slab grid lines, plank row seams, parquet borders + strips; butt joints and cracks aren't modelled) — and
`FloorPainter.porous(opts)` (carpet), so blood follows the texture and soaks into carpet. A non-solid piece (a rug, mat
or runner) registers its rect the same way as a porous surface and unregisters on exit, and draws at
`ObjectArtConfig.rug_z_index` (-3, above floors, below blood) so a pool shows on it. It also registers its rect, `floor_material` and
`art_opts.pattern` with the Audio domain's `SoundSurface` (interface 16) so footsteps sound like
the floor (planks and parquet wood, ceramic tile, slate stone, concrete, carpet; no floor = outdoors).

## Pixel art (`objects/art/`, private to Objects)

Every catalogue piece, every wall and every floor is drawn as procedural top-down pixel art,
rendered through the **Art** domain (`PixelArt` / `PixelCanvas` / `ArtConfig`, interface 12 —
see `domain-art` for the engine). A piece whose definition sets `art` (a painter id) is drawn as
art instead of a flat shape with its name label (the flat path stays for any definition without
`art`).
- `object_art.gd` — the painter registry: `PAINTERS` maps an `art` id to its painter;
  `texture(art, size, color, facing, material, opts)` renders it via `PixelArt.render` (a cardinal
  facing), `tile(art, color, material, opts)` at the painter's own `tile_size(opts)` (floors).
- Painters (`*_painter.gd`, each `static paint(canvas, base, material, opts)`): `sofa` (also the
  armchair), `table` (+ `gaps`, `props`; desks, benches, the workbench), `chair`, `cabinet`
  (doors/drawers front lip, crown, glass top, chest lid), `shelf` (books / boxes / shoes),
  `counter` (backsplash, basin, overhang), `appliance` (`panel`: burners, fridge, microwave,
  washer, dryer, tv), `bed`, `office_chair`, `toilet`, `bath` (tub / shower), `rug` (medallion,
  stripes, plush), `plant`, `lamp`, `coat_rack`, `car`, `fixture` (mirror / towel rack), and the
  tiling `floor` (`tile_size(opts)`; planks, parquet, tiles, checker, mosaic, carpet, concrete)
  and `wall` (plaster / brick cap, symmetric across the thickness). Each knob reads
  `opts.get(key, ObjectArtConfig.<painter>_<key>)`, so a catalogue `art_opts` picks the variant
  or overrides it for one piece. Round footprints keep their art inside the inscribed circle.
- `props.gd` — small props dressing a surface (monitor, keyboard, mug, papers, book,
  clock, bowl, fruit bowl, vase, cutting board, tools, vise, crayons, plate),
  drawn by `table` / `cabinet` / `counter` from `art_opts.props` (`{ kind, at }`, `at` relative
  to the surface), raised so they cast shadows; colors from `ObjectArtConfig.prop_colors`.
- `object_art_config.gd` — `ObjectArtConfig`, the Objects painters' tuning: per-painter
  proportions and colors, the prop palette, and the floor/wall tile sizes and floor z-index (the
  shared light, shadows, tones and finishes are `ArtConfig`).

Object fields for art: `art`, `art_opts` (from the definition) and `facing` (`opts.facing` from
World-Gen; visual only, a cardinal direction in the local frame — the `rotated` size swap still
owns the footprint). The visuals draw a drop shadow — the art's own alpha through the deformed
outline, offset away from the light in world space by `coverage × drop_shadow_per_coverage`
(capped; non-solid decor casts none) — then `Deformation.draw_shape(..., texture)` so dents and
chunks cut into the art. A piece repaints only when that can have changed — its `Deformable` recorded an impact or its rotation
changed (the shadow's offset is fixed in world space) — not every frame (a house has ~90 pieces); a hit also queues one deferred
collider rebuild however many hits land before it runs. Walls: `WallFactory`'s `style` sets `art` / `art_color` / `art_opts` on
the wall (`art_color` is also the debris color); `wall_visuals.gd` fetches a
`wall_tile_px × wall_thickness` tile and passes it to `Deformation.draw_wall(..., texture,
wall_tile_px)`. To add a painter: write `<name>_painter.gd`, register it in `ObjectArt.PAINTERS`,
add its knobs to `ObjectArtConfig`, and set `"art": "<name>"` on catalogue definitions.

## Interface recap (authoritative in the `architecture` skill)

- **World Generation → Objects** (interface 2): `ObjectFactory.spawn(definition, position,
  parent, opts) -> Node`, `WallFactory.spawn(rect, thickness, openings, name, parent, style) ->
  Node`, `WallFactory.openings_for(rect, doors) -> Array` (the doorways on a rect's walls, as `openings`),
  `FloorFactory.spawn(rect, definition, name, parent) -> Node`, `Wall.Side` enum.
- **Objects → Art** (interface 12): its painters render through `PixelArt.render`, draw on
  `PixelCanvas`, and read `ArtConfig`.
- Objects also implements the hittable (3), pushable (5) and interactable (8) contracts above.

---
name: domain-physics
description: Deep implementation detail for the Physics System domain (scenes/physics/) — physical reactions: forces, knockback, deformation, debris, blood pooling. Use when editing scenes/physics/ or working on HitInfo, Knockback, Deformable/Deformation, debris, blood, or PhysicsConfig/BloodConfig tuning. Complements the `architecture` skill, which holds the cross-domain interfaces.
---

# Physics System domain

Stateless helpers + reusable Node components, sharing no imports with other domains (a leaf).
Objects *compose* these components; Physics imports nothing outward.

- `HitInfo` — the one data packet a striker fills in (`position, normal, direction, damage,
  speed_factor, penetrated, source`).
- `Physics.impact_impulse(hit)` / `Physics.spawn_debris(world, hit, surface)`.
- `Knockback` — RigidBody2D adapter: configures its parent furniture body (no gravity, mass,
  `PhysicsConfig.body_*` damping, origin-pinned center of mass, contact reporting) and feeds it
  impulses via `apply_impulse(v, at_world)`. The engine does the sweeping, pivoting and settling;
  the component only hands momentum to the kinematic character on contact
  (`impact_transfer_scale`).
- `Deformable` — records local impacts (dents / carved "missing pieces") and emits `changed`; the
  owner redraws + rebuilds its collider from the same deformed polygon.
- `Deformation` — the polygon math + drawing (shared by furniture and walls).
- `DebrisSpawner` / `Debris` — material-styled chips (`STYLES` table). The global cap lives on
  `Despawner`.

## Blood pooling (self-contained, separate from debris/deformation)

`BloodSpawner` / `BloodPool` / `BloodPoolVisuals`. `Physics.spawn_blood(parent, hit, exclude,
source, active) -> Node` adds a flesh wound's blood to the body's pool and returns it; each drop
emerges from `source`'s live position, pushes outward and slides around walls/furniture
(`cast_motion` on layer 1) until it settles into a persistent, `Despawner`-tracked stain drawn
beneath everything.

Spread is accumulation-based per character: each character bleeds into one active pool
(`take_hit` keeps the returned pool in `_blood_pool`); a hit that lands on that pool grows it —
adding volume and widening its radius toward `pool_radius_max`, capped at `max_pool_volume` — so a
still victim shot repeatedly pools out wide, while moving off the pool starts a new one and trails
blood. Only the character's `take_hit` calls it (furniture bleeds no blood).

## Tuning

`PhysicsConfig` tunes impact + deformation; `BloodConfig` tunes blood pooling. Both are
`class_name` static holders — there is no `Config` autoload.

## Interface recap (authoritative in the `architecture` skill)

- **Objects → Physics** (interface 4): objects add `Knockback` / `Deformable` as child Nodes and
  call `Physics.impact_impulse` / `Physics.spawn_debris`. The character's `take_hit` calls
  `Physics.spawn_blood`. Debris / casings despawn via the Despawner.

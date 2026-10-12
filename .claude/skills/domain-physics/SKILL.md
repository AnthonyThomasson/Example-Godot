---
name: domain-physics
description: Deep implementation detail for the Physics System domain (scenes/physics/) — physical reactions: forces, knockback, deformation, debris, hit particles, and the generic 3D ragdoll solver; the blood system is its own sub-domain (`domain-physics-blood`, scenes/physics/blood/). Use when editing scenes/physics/ or working on HitInfo, Knockback, Deformable/Deformation, debris, hit particles, Ragdoll (joint limits, floor/wall contact, sleeping), or PhysicsConfig tuning. Complements the `architecture` skill, which holds the cross-domain interfaces.
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
  owner redraws + rebuilds its collider from the same deformed polygon. `record(hit, turn)` stores
  the impact un-turned by `turn`, for a body drawn turned beyond its node rotation (a character
  facing its aim); the owner turns the impacts back when drawing.
- `Deformation` — the polygon math + drawing (shared by furniture and walls). `draw_shape` takes
  an optional `texture`: the deformed polygon is then drawn textured (UVs from the intact
  footprint, so dents cut into the image), tinted darker by damage, without the smooth outline;
  `texture_angle` turns the image within the unturned silhouette (a round body facing any way);
  with `marks` false the hit marks are left to the caller's `draw_marks`, to draw over parts
  layered on top.
  `draw_wall` takes an optional repeating `texture` + `tile_length`: UVs run in the segment's own
  frame (u along the wall per tile, v across its thickness), so the tile follows every wall.
- `DebrisSpawner` / `Debris` — material-styled chips (`STYLES` table). The global cap lives on
  `Despawner`.

## Hit particles (entry and exit bursts)

`HitParticles.spawn(position, direction, parent, surface, kind, strength)` (`hit_particles.gd`, static) bursts a one-shot
`CPUParticles2D` (named `HitParticles`, frees itself on `finished`, `Despawner`-tracked, no gravity: top-down) styled by
`surface.material` from its `STYLES` table (wood splinters, metal sparks, glass shards, ceramic, fabric puff, foliage,
flesh/blood droplets, `default` plaster dust for walls). `Kind.EXIT` (the strongest burst, thrown on along the shot) is paired with a much weaker `Kind.ENTRY` when a round passes through
(`has_exit`); a hit that stays in the object (blocked, ricochet, no exit found) gets one `Kind.IMPACT` burst back along the normal at exit strength. `Physics.spawn_debris` (what every `take_hit` already calls) fires the entry burst,
the exit burst when `HitInfo.has_exit`, and the material chips. Tuning: `PhysicsConfig.hit_particles_enabled` (test switch
`physics.hit_particles`), `hit_particles_scale`, `hit_particles_max`.

**Blood carried onto a surface.** A hit with `HitInfo.blood > 0` also throws red droplets and `flesh` chips from the entry,
and the object keeps a bloody mark: `Deformable.record` and the wall's segment impacts store `"blood"`, and
`Deformation.draw_marks` draws a red blot (`PhysicsConfig.blood_mark_color` / `blood_mark_radius`) under the hole, riding
with the object (`hit_marks()` on an `EnvironmentObject` or `Wall` returns them). A character hit with an exit also throws a splatter out the far side (`BloodWound.record`).

## Ragdoll (a generic 3D body falling to the floor)

`ragdoll.gd` (`class_name Ragdoll`, `RefCounted`) knows nothing of what the body is; the owner (the
Character domain's humanoid) builds and steps it. Space is the owner's local floor plane (x, y)
plus z = height; gravity pulls to z = 0.
- Building: `add_point(at, radius, mass)`, `add_bone(a, b, stiffness)` (rest length = current
  distance), `add_rigid(indices)` (all pairs), `add_frame(origin, up, right, forward_hint)` (an
  orthonormal frame read off three points every step; forward signed by the hint),
  `add_swing(frame, joint, child, rest, {right, left, front, back})` (a cone around `rest` along the
  frame's y, its reach toward each frame axis in radians, blended linearly by direction between
  them) and `add_hinge(frame, parent, joint, child, rest, bend, min, max, slack)` (a one-way hinge:
  the bend side `bend` is carried onto the live parent bone by the shortest turn from `rest`; the
  child's bend off straight is held to [min, max] and its twist off that plane to ±slack).
  `push(i, v)` seeds velocities; `exclude` lists colliders the wall sweep ignores.
- `step(delta, space, origin)`: position-based dynamics in `ragdoll_substeps` sub-steps — predict
  under gravity and air drag; `ragdoll_iterations` passes of bones, limits and the floor (limits
  correct `LIMIT_STIFFNESS` of the error per pass, turning a bone at most `LIMIT_MAX_TURN`, split
  by inverse mass); sweep each point's x/y move against layer 1 with `cast_motion` (stop + slide);
  then derive velocities. A point leaves the constraints no faster than it came in plus
  `ragdoll_max_push` (and never past `ragdoll_max_speed`), so constraints fighting the floor can't
  fling the body. Floor contact bounces (`ragdoll_floor_bounce`) and skids to a stop
  (`ragdoll_floor_friction`); `ragdoll_joint_friction` pulls each limited child's velocity toward
  its joint's so limbs swing heavy. The first step pulls any point that starts inside a wall back
  toward the origin.
- Sleeps once every point stays under `ragdoll_sleep_speed` for `ragdoll_sleep_time`, or after
  `ragdoll_max_time`; then `asleep` is true and `step` does nothing.
- Reading: `point(i)`, `point_count()`, `frame_basis(f)`.

## Blood (its own sub-domain: `scenes/physics/blood/`)

Wound spray and drips (`BloodWound`), splatters, a dead body's bleed-out pool and its floor-steered flow, and blood that is
carried (wetness, footprints, smears) are the **`domain-physics-blood`** skill — load it for anything in `physics/blood/` or `BloodConfig`.
The core keeps only the entry points: `Physics.spawn_debris` (draws a bullet's `HitInfo.blood` as droplets and a mark, see above) and
`Physics.bleed_out(parent, source, exclude)`.

## Tuning

`PhysicsConfig.debris_enabled` is the debris master switch (off: `Physics.spawn_debris` spawns nothing; the Testing domain's
`physics.debris` switch). `PhysicsConfig` tunes impact + deformation and the ragdoll solver (`ragdoll_*`), and holds `wall_mask`
(the layer the ragdoll sweep and the blood queries treat as blocking). `BloodConfig` (blood tuning and its master switches) is
documented in `domain-physics-blood`. Both are `class_name` static holders — there is no `Config` autoload.

## Interface recap (authoritative in the `architecture` skill)

- **Objects → Physics** (interface 4): objects add `Knockback` / `Deformable` as child Nodes and
  call `Physics.impact_impulse` / `Physics.spawn_debris`. The character composes a `BloodWound` (see `domain-physics-blood`), and its death builds its fallen body on a `Ragdoll` and, once it rests,
  calls `Physics.bleed_out`. Debris / casings
  despawn via the Despawner.

---
name: domain-physics
description: Deep implementation detail for the Physics System domain (scenes/physics/) — physical reactions: forces, knockback, deformation, debris, blood pooling, and the generic 3D ragdoll solver. Use when editing scenes/physics/ or working on HitInfo, Knockback, Deformable/Deformation, debris, blood, Ragdoll (joint limits, floor/wall contact, sleeping), or PhysicsConfig/BloodConfig tuning. Complements the `architecture` skill, which holds the cross-domain interfaces.
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

## Blood (self-contained, separate from debris/deformation)

Three parts, all tuned by `BloodConfig`: a wound's **spray**, its **drips**, and a dead body's **bleed-out**.

- `BloodWound` (`class_name`, a Node the character composes like `Knockback`): `record(hit)` throws
  `ceil(damage / hit_splat_damage)` splatters (max `hit_splat_max`) out the wound's exit side at once, then adds
  `ceil(damage * drips_per_damage)` to a drip budget (cap `max_pending_drips`). While it lasts, one drop falls
  every random `drip_interval_min..max` s (3..10) from the host's `blood_origin()`; it keeps the host's
  `velocity` for `drip_fall_time`, so a walker's drops land ahead and splat stretched along its heading
  (`energy` = speed / `drip_full_energy_speed`). `stop()` on death ends dripping. Each body keeps at most
  `max_splats_per_body` splatters (oldest freed); the global `Despawner` cap applies too.
- `BloodSplat` (`blood_splat.gd`, built by `BloodSpawner.splat`, named `BloodSplat`, `Despawner`-tracked,
  colliderless): one impact, built once in `setup(radius, direction, energy, exclude)` and then static. A lumpy
  core stretched along the throw, tapered crown spikes (forward ones longer with energy; some throw a tail
  droplet), and satellite droplets, all clipped by walls/furniture (a ray from the centre, `PhysicsConfig.wall_mask`)
  and merged (`Geometry2D.merge_polygons`) into opaque outlines so overlaps don't darken. A wet highlight fleck
  fades and the colour dries to `dried_color` over `splat_dry_time`. Shape knobs: `splat_*`, `drip_size_*`.
- Bleed-out: `Physics.bleed_out(parent, source, exclude)` (`BloodSpawner.bleed`) starts a dead body's pool where
  its blood leaves it (`blood_origin()`: the trunk's middle once fallen): a `BloodPool` holding
  `BloodConfig.bleed_out_cells` grid cells claimed by a `BloodFlow` flood-fill: cheapest-first with
  noise-roughened cost (`flow_*` tuning), cells overlapping a `PhysicsConfig.wall_mask` collider never fill, so the
  puddle is one continuous irregular shape wrapping around walls and furniture. All cells are claimed up front (a
  batch per frame); a front then sweeps through flow-cost over `bleed_out_duration`, so each cell's fill rises
  continuously. Drawn by blurring the fill field into a small image and thresholding it in a shader (one smooth
  outline, darker rim).

The floor steers the flow: each cell's step cost is multiplied by `BloodSurface.resistance(world_pos)` —
surfaces (Objects' floors) register a world rect + a `groove` Callable, so blood runs cheaply along grooves
(`groove_resist`), slowly across smooth surface (`smooth_resist`) and barely at all over porous carpet
(`porous_resist`); outdoors = 1. Newest-registered surface wins on overlap. Master switch
`BloodConfig.surface_flow`.

## Tuning

`PhysicsConfig.debris_enabled` and `BloodConfig.enabled` are master switches (off: `Physics.spawn_debris`
spawns nothing; `BloodWound.record` / `Physics.bleed_out` spawn nothing — used by the Testing
domain's `physics.debris` / `physics.blood` switches). `BloodSpawner` adds each splatter and pool with a readable
name (`BloodSplat`, `BloodSplat2`, … / `BloodPool`, …) so observers can tell them apart.
`PhysicsConfig` tunes impact + deformation and the ragdoll solver (`ragdoll_*`), and holds `wall_mask`
(the layer the ragdoll sweep and the blood queries treat as blocking); `BloodConfig`
tunes blood (splatter, drips, bleed-out). Both are `class_name` static holders — there is no `Config` autoload.

## Interface recap (authoritative in the `architecture` skill)

- **Objects → Physics** (interface 4): objects add `Knockback` / `Deformable` as child Nodes and
  call `Physics.impact_impulse` / `Physics.spawn_debris`. The character composes a `BloodWound` (its `take_hit` calls `record`, its death `stop`), and its death builds its fallen body on a `Ragdoll` and, once it rests,
  calls `Physics.bleed_out`. Debris / casings
  despawn via the Despawner.

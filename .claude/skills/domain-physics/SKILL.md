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

Drops emerge at the source's `blood_origin()` when it has one (else its position): the character
returns its trunk's middle once fallen, so a pool still filling at death flows from the body as it
falls and rests. Each pool releases at its own rate. `Physics.bleed_out(parent, source, exclude)`
(`BloodSpawner.bleed`) starts a dead body's bleed-out where its blood leaves it: a pool holding
`BloodConfig.bleed_out_cells` grid cells claimed by a `BloodFlow` flood-fill
(`BloodPool.seed_bleed_out`): cheapest-first with noise-roughened cost (`flow_*` tuning), cells
overlapping a `PhysicsConfig.wall_mask` collider never fill, so the puddle is one continuous irregular
shape wrapping around walls and furniture. All cells are claimed up front (a batch per frame); a front
then sweeps through flow-cost over `bleed_out_duration`, so each cell's fill rises continuously. Drawn by
blurring the fill field into a small image and thresholding it in a shader (one smooth outline, darker
rim); wound spatter keeps the drop model.

## Tuning

`PhysicsConfig` tunes impact + deformation and the ragdoll solver (`ragdoll_*`), and holds `wall_mask`
(the layer the ragdoll sweep and the blood queries treat as blocking); `BloodConfig`
tunes blood pooling. Both are `class_name` static holders — there is no `Config` autoload.

## Interface recap (authoritative in the `architecture` skill)

- **Objects → Physics** (interface 4): objects add `Knockback` / `Deformable` as child Nodes and
  call `Physics.impact_impulse` / `Physics.spawn_debris`. The character's `take_hit` calls
  `Physics.spawn_blood`, and its death builds its fallen body on a `Ragdoll` and, once it rests,
  calls `Physics.bleed_out`. Debris / casings
  despawn via the Despawner.

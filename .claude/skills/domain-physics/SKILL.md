---
name: domain-physics
description: Deep implementation detail for the Physics System domain (scenes/physics/) — physical reactions: forces, knockback, deformation, debris, hit particles, and the generic 3D ragdoll solver; the blood system is its own sub-domain (`domain-physics-blood`, scenes/physics/blood/). Use when editing scenes/physics/ or working on HitInfo, Knockback, Deformable/Deformation, debris, hit particles, Ragdoll (joint limits, floor/wall contact, sleeping), or PhysicsConfig tuning. Complements the `architecture` skill, which holds the cross-domain interfaces.
---

# Physics System domain

Stateless helpers + reusable Node components (a leaf).
Objects, the character and a vehicle *compose* these components; Physics imports nothing from other domains but General's
infrastructure (`Despawner`, `PhysicsLayers`, `DrawLayers`).

- `HitInfo` — the one data packet a striker fills in (`position, normal, direction, damage,
  speed_factor, penetrated, has_exit, exit_position, exit_normal, blood, height, source`); `height` is the 0..100 height the striker flew at
  (a bullet's one height, which picks a character's hit zone), −1 = none (the default, and a frag's blast: the whole body).
- `Physics.impact_impulse(hit)` / `Physics.spawn_debris(world, hit, surface)`.
- `Knockback` — RigidBody2D adapter: configures its parent furniture body (no gravity, mass,
  `PhysicsConfig.body_*` damping, origin-pinned center of mass, contact reporting) and feeds it
  impulses via `apply_impulse(v, at_world)` (central with no point; off the centre the body pivots under its own
  torque, slowed by `body_angular_damp`; a character's shoves reach the body's native `apply_impulse(v, at)` the same way,
  interface 5). The engine does the sweeping, pivoting and settling; the component only hands momentum to the kinematic
  character on contact (`impact_transfer_scale`).
- `Deformable` — records local impacts (dents / carved "missing pieces") and emits `changed`; the
  owner redraws + rebuilds its collider from the same deformed polygon. `record(hit, turn)` stores
  the impact un-turned by `turn`, for a body drawn turned beyond its node rotation (a character
  facing its aim); the owner turns the impacts back when drawing. A vehicle (Vehicles domain) composes one with `allow_chunks`
  off, its own `max_depth` / `max_impacts`, and leaves its collider alone (it does not listen to `changed`); it has no
  `Knockback`, being a `RigidBody2D` of its own, and draws the dents with `Deformation.draw_marks`.
- `Deformation` — the polygon math + drawing (shared by furniture and walls). `shape_polygon` keeps its last 256 dented
  silhouettes, keyed by everything they are made from (shape, size, the dents, the deformation tuning) and checked for equality:
  each hit asks for the same one three times (collider, shadow, drawing) and every repaint of a wounded character asks again
  (`tests/physics/shape_polygon_cache_test.gd`). `convex_shapes` cuts a silhouette into convex collider pieces (Hertel-Mehlhorn
  over its triangulation) finding neighbouring pieces through a directed-edge map, remembering failed pairs by piece id and
  checking only the two corners a merge joins; after a merge the scan goes on from the merged piece, having first tried the pairs
  the new piece makes with the pieces before it (every other pair before it has failed), and an attempt hands back its union;
  `tests/physics/convex_pieces_match_plain_scan_test.gd` pins it to the plain every-pair, every-corner scan; `convex_pieces(polygon)` gives the pieces' points (pure, for a worker thread) and
  `shapes_of` makes the shapes; `cut_shape(shape, size, impacts)` / `cut_wall(a, b, thickness, impacts)` return `[polygon, pieces]`
  for a dented silhouette computed without the caches (pure: Objects' `ColliderCuts` runs them on worker threads; a circle's unit
  ring is made afresh there, never read from or written to the kept one). `wall_polygon` keeps its last 256 dented segments like `shape_polygon` (a wall repaints every segment when
  one is struck), a fresh array each ask, and `draw_wall` skips the triangulation check for an undented segment. Its circle `base_ring`
  is the unit ring (kept per point count) scaled, a fresh array each call; `draw_shape` maps its texture with one transform of the
  ring and skips the triangulation check for an undented shape (it is the intact ring already); `draw_marks` draws each mark's
  discs as one General `FillBatch` before its cracks. `draw_shape` takes
  an optional `texture`: the deformed polygon is then drawn textured (UVs from the intact
  footprint, so dents cut into the image), tinted darker by damage, without the smooth outline;
  `texture_angle` turns the image within the unturned silhouette (a round body facing any way);
  with `marks` false the hit marks are left to the caller's `draw_marks`, to draw over parts
  layered on top.
  `draw_wall` takes an optional repeating `texture` + `tile_length`: UVs run in the segment's own
  frame (u along the wall per tile, v across its thickness), so the tile follows every wall.
- `DebrisSpawner` / `Debris` / `DebrisLayer` — material-styled chips (`STYLES` table). A chip is a node only while it
  flies (Despawner-tracked); as it lands it hands its place, turn, colour, size and shape to the parent's `DebrisLayer`
  (`DebrisLayer.layer(parent)`) and frees itself, so a floor strewn with a thousand chips costs a few draw calls and no nodes; a chunk
  draws all its chips (disc, triangle or rect, each at its own place and turn) as one General `FillBatch` (the triangle and rect
  convex, uncut; under the headless display each by its own command, `_draw_each`). The layer
  keeps at most `Despawner.max_scene_objects` chips, dropping the oldest; it draws under whatever joins its node after it.
  Test: `tests/physics/debris_rests_in_a_layer_test.gd`.
- `chunked_layer.gd` (no `class_name`; `DebrisLayer`, `ScorchDecals` and the blood's `BloodDecals` extend it by path) — the
  batched decal store they share: every mark kept as plain data in one node under a world node, grouped in 128 px chunks
  (`CHUNK`) drawn by a few chunk nodes, only the chunk that gained or lost a mark redrawing, and a capped FIFO (`_add(mark, cap)`
  drops the oldest past the layer's cap and flags it `dead`); `count()`, `items()`, `marks_in(cell)`. A layer names only its
  recipe, its cap and its chunk's `_draw` (`_make_chunk`); its typed `find(parent)` / `layer(parent)` wrap `_get_or_make`.

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
  `wake()` undoes it and restarts both clocks.
- Reading: `point(i)`, `point_count()`, `frame_basis(f)`.

## Explosion look (`explosion_fx.gd`, `scorch_decals.gd`)

`Physics.spawn_explosion(world, at, kind)` (kind `&"frag"` / `&"stun"`; the Projectile System's `Explosion` calls it) is the look of a grenade's burst, all
procedural in the same stepped-pixel style as the debris and the blood (every disc is rows of `PhysicsConfig.explosion_pixel` px). `ExplosionFx.spawn` adds
up to three colliderless nodes under `world`, each named for what it is, animated in `_process`, freed at the end of its life and `Despawner`-tracked:
`ExplosionFlash` (frag only: a pale disc over a white one that swells a little and fades in `flash_time`; a stun's row has `flash_radius` 0, its
white flash being the Lighting domain's flash light, `docs/lighting.md` L9), `ExplosionFireball` (frag only: a lumpy puff that swells and
cools from yellow to deep red, fading over its last stretch) and `ExplosionSmoke` (puffs that drift out, swell and fade over `smoke_time`, ~4 s for a frag, a
thin ~2.6 s for a stun). A frag also burns a mark into the world's `ScorchDecals` layer (`ScorchDecals.layer(world).burn(at, radius)`, node `ScorchDecals`):
ragged stepped rows, a darker core in a lighter rim and a few specks, a `chunked_layer.gd` like `DebrisLayer` and `BloodDecals` (only the chunk that gained a
mark redraws), drawn at the blood decals' depth (`BloodConfig.print_z_index`, `DrawLayers.BLOOD`) and kept for good up to `Despawner.max_scene_objects` marks (the oldest dropped). A stun leaves no scorch.
Tuning is `PhysicsConfig.explosion_looks` (one row per kind: `flash_*`, `fireball_*`, `smoke_*`, `scorch_radius`), `explosion_pixel` and `scorch_color`;
`PhysicsConfig.explosion_fx_enabled` is the master switch (off: nothing spawns). Test: `tests/physics/explosion_fx`.

`Ragdoll.wake()` clears `asleep` and both sleep clocks (`_time`, `_still`): a body that slept through `ragdoll_max_time` would otherwise go straight back to
sleep after one step of an explosion's push. The Character domain's `CharacterRagdoll.blast` calls it (test: `tests/physics/frag_blast_pushes`).

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

**Interfaces:** 4 (Objects / Character / Vehicles → Physics), 11 (`PhysicsLayers` in `PhysicsConfig.wall_mask`; `DrawLayers`: blood and scorch decals `BLOOD`, `ExplosionFx.Z_INDEX` = `EFFECTS`) — signatures in `architecture`.

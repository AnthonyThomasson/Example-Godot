---
name: domain-physics-blood
description: Deep implementation detail for the Physics blood sub-domain (scenes/physics/blood/) — a wound's spray and drips (BloodWound), splatters (BloodSplat), a dead body's bleed-out pool and its flood-fill flow (BloodPool, BloodFlow, BloodSurface), and blood that is carried (BloodField wetness, BloodDecals, BloodFootprints, BloodSmear), all tuned by BloodConfig. Use when editing scenes/physics/blood/ or working on blood splatter, drips, pools, footprints, smears, floor-steered flow, or BloodConfig tuning. Complements the `domain-physics` overview and the `architecture` skill (interface 4).
---

# Physics · Blood sub-domain (`scenes/physics/blood/`)

Self-contained and separate from debris / deformation: `blood_config, blood_field, blood_decals, blood_splat, blood_pool,
blood_pool_visuals, blood_flow, blood_smear, blood_footprints, blood_wound, blood_spawner, blood_surface`. The rest of
`physics/` (hit packet, knockback, deformation, debris, hit particles, ragdoll) reaches it only through `Physics.spawn_debris`
(a hit that carries blood; the bloody mark a bullet's `HitInfo.blood` leaves on an object is drawn by the core's
`Deformation.draw_marks`) and `Physics.bleed_out`; every other domain meets it through the classes in interface 4, all
resolved by `class_name`. It imports nothing outside Physics except `Despawner` (General).

**Master switches** (`BloodConfig.enabled`, and under it `footprints_enabled` / `smear_enabled`, `surface_flow`): off, `BloodWound.record` /
`Physics.bleed_out` spawn nothing (`bleed_out` returns null); used by the Testing domain's `physics.blood` switch. `BloodSpawner` adds each
splatter and pool with a readable name (`BloodSplat`, `BloodSplat2`, … / `BloodPool`, …) so observers can tell them apart.
`BloodConfig` is a `class_name` static holder (splatter, drips, bleed-out, flow, footprints, smears); `PhysicsConfig.wall_mask` is the
layer the splat clipping and flow queries treat as blocking.

Three parts, all tuned by `BloodConfig`: a wound's **spray**, its **drips**, and a dead body's **bleed-out**.

- `BloodWound` (`class_name`, a Node the character composes like `Knockback`; the character's `take_hit` calls `record`): `record(hit)` throws
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
  and merged (`Geometry2D.merge_polygons`, skipped for two outlines whose boxes are apart — the union would keep them as two;
  `tests/physics/blood_splat_merge_fast_path_test.gd` pins the build to the merge-against-every-outline one) into opaque outlines
  so overlaps don't darken. Each outline is
  run through `BloodSplat.drawable` once built: about 1 splat in 100,000 unions into a polygon the engine
  cannot triangulate, which is swapped for its convex hull (or dropped) instead of logging an error when drawn.
  Test: `tests/physics/blood_splat_shapes_valid_test.gd`. A wet highlight fleck
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
(`groove_resist`), slowly across smooth surface (`smooth_resist`) and slowest over a porous surface
(`porous_resist`: carpet floors and rugs); outdoors = 1. Newest-registered surface wins on overlap, except
that any porous surface at a point counts (`BloodSurface.is_porous`), so a rug over tile is porous whichever
registered first. Master switch `BloodConfig.surface_flow`.

**Soaking.** Blood on a porous surface sinks in: once the flood has mostly reached a porous cell (>= 0.5),
`BloodFlow.tick(delta)` (called from `BloodPool`, which keeps processing after the front settles while
`soaking()`) takes its soak 0 -> 1 over `soak_time`. Soaking never changes `fill(c)` or the pool's outline: the blood
still covers everything it covered, with no holes; it turns translucent (`soak_opacity`) so the carpet or rug pattern shows through it. `wetness(c)` = `fill * (1 - soak)` is what
`BloodField.wetness_at` reads, so soaked blood leaves no prints or smears. Dragged-out trail cells are not soaked.
**Slower, shorter and tufted:** `BloodFlow.advance` stretches the sweep by `porous_spread_slowdown` in proportion to the share of
claimed cells on porous surface, so blood creeps over carpet; and each porous cell costs `porous_cell_weight` cells of the
bleed-out budget (`BloodFlow.budget_used`, `step(..., budget)`), so the pool does not travel as far. The pool texture is RG8 (red = `fill(c)`, green =
`soak_level(c)`, only written when `has_porous()`); the shader splits the pool into irregular `soak_tuft_size` px tufts
fixed to the pool, each with its own soak rate (`soak_tuft_spread` wide) and its own shade of red (`soak_tuft_contrast`, kept subtle), plus a
faint crease where tufts meet. Only colour and opacity change, so some tufts are still bright while others have gone dull. Tests: `blood_soaks_into_carpet`, `blood_soaks_into_rug`.

## Footprints and smears (blood that is carried)

A carrier soaks up a *load* (0..1) of wet blood where it touches it and deposits it with the load fading,
so trails taper. All tuning is `BloodConfig` (`footprints_enabled`, `smear_enabled`, `pickup_gain`,
`print_*`, `smear_*`, `thick_blood`, `pool_wet_time`, `splat_wetness`).
- `BloodField` (static): `wetness_at(world_pos) -> 0..1`. `BloodSplat.setup` and `BloodPool.seed_bleed_out`
  register themselves (spatial hash for splatters, a list for pools; entries drop on `tree_exited`). A
  splatter is a thin film (`splat_wetness`) drying to 0 over `splat_dry_time`; a pool is its flow fill, wet for
  `pool_wet_time`. Dried blood returns 0. Ages count physics frames.
- `BloodDecals` (`Node2D`, one per parent via `layer(parent)` / `find(parent)`): batches prints (polygons) and
  smear ribbons, drawn in 128 px chunks (each with its own mark list) that redraw only when they gain a mark or a
  ribbon grows (and at 2 Hz while drying, `print_dry_time`); own FIFO cap `print_max` (not the Despawner).
  `ribbon_begin(point, width, alpha) -> mark`, `ribbon_extend(mark, point, width, alpha)` (width 0 = taper to a
  point), `ribbon_count()`; a ribbon is drawn as two quads per segment via `draw_primitive`, solid on its centre line
  and fading to `smear_feather` at the edges. `items()` / `print_count()` for tests. `print_at` drops polygons the
  engine can't triangulate.
- `BloodFootprints` (Node child of a walker): `step(...)` per footfall (the character's `character_footsteps.gd` calls it). Per foot id: soak `max(load, wetness *
  pickup_gain)` (sampled heel/middle/toe), stamp a mirrored sole (heel, arch on the `inner` side, ball, toe) with
  alpha from the load unless already in thick blood, then lose `print_decay`. Low load = thin arch + rough edge;
  speed and load slip the print forward.
- `BloodSmear` (Node child of a RigidBody2D): `set_footprint(local polygon)` lays a grid of "fingers" fixed to the
  body; while `linear_velocity` > `smear_min_speed` each finger soaks blood under it and every
  `smear_segment_length` px extends its ribbon: width `smear_width` x spacing x sqrt(load), alpha from load, the
  centre line wandering on smooth noise (`smear_wobble`, `smear_wobble_freq`) so streaks drift and cross. Load falls
  by `smear_decay_per_px`; below `smear_break_load` the ribbon breaks into dry-brush dashes; where it ends (rest,
  no load) it tapers to a point. Per-finger variation makes streaks end and thicken unevenly.
  **Blending into the puddle:** a finger lays a ribbon even over blood already there, but the ribbon is
  see-through where the floor is wet (`smear_absorb_lo..hi` on `BloodField` wetness), eases in over its first
  `smear_fade_in` px, and its opacity may only rise `smear_alpha_rise` per sample, so the streak swells out of a
  splatter's crisp edge or a pool's soft rim with no start line (`thick_blood` gates footprints only).
  **Pulled out of a pool:** a finger carrying >= `smear_trail_min` load within `smear_trail_reach` px of a pool calls
  `BloodPool.drag_out(pos, load x smear_trail_gain)`, which adds `BloodFlow.trail` cells (3x3, max-merged, capped at
  `pool_trail_max`, level tapering to 0 at `pool_trail_length` px (50) from the flooded cells = how far a pool can be dragged; `fill(c)` = max(flood, trail), `covers(c)`). The pool's own visuals draw the trail, so the pool's
  outline stretches into a tongue of the same colour, rim and edge that tapers as the load decays, and the ribbons
  continue as the wispy tail (`BloodField.pool_near(pos, radius)` finds the pool; wetness includes the trail).
- Tests: `tests/physics/footprints_*`, `object_smear*` (incl. `object_smear_pool`), `smear_ribbon_shape`, `blood_pool_trail`, `blood_field_query`, `blood_decals_cap`.

**Interfaces:** 4 (Objects / Character → Physics) — signatures in `architecture`.

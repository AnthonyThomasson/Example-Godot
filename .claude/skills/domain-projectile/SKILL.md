---
name: domain-projectile
description: Deep implementation detail for the Projectile System domain (scenes/projectile/) — shooting: penetration, damage, cover, ricochet. Use when editing scenes/projectile/ or working on the bullet impact model, fly-over/ricochet/penetrate/blocked resolution, casings, or BallisticsConfig tuning. Complements the `architecture` skill, which holds the cross-domain interfaces.
---

# Projectile System domain

Owns shooting: penetration, damage, cover, ricochet, and a grenade's burst (`Explosion`, below). The shooting knobs live in `BallisticsConfig`,
the burst's in the grenade's `GrenadeConfig` row (Items), which it receives as a plain dict.

## Impact model

A fired bullet (`projectile.gd`) is a **multi-hit traveler**: each physics frame it sweeps
forward with a raycast and resolves every collider it crosses against that object's
`get_surface()` `coverage`/`penetration` (0–100; a collider with no surface uses
`BallisticsConfig.wall_*`). It flies until `speed < BallisticsConfig.projectile_min_speed` or it
passes `max_distance`. Non-solid decor has no collider, so it's never raycast.

Per hit, with squareness `s = |dir·normal|`, speed factor `v = speed / muzzle_speed` (the round's own muzzle speed, so a weapon's
`damage` is what it deals at full speed head-on), the bullet's own penetration power `p` (`penetration_power`, 1 = a pistol round), coverage
`C`, the target's penetration `P`, `_resolve()` picks one outcome in order:

1. **Fly over** — the bullet's `height` is at or above `clamp(100 − (100 − C) × cover_flyover_scale, 0, 100)`; no damage, excluded, flies on.
   **Coverage is a height (0–100) and a bullet flies at one height for its whole flight**: `height` is drawn uniformly 0–100 when it is fired
   (`BallisticsConfig.bullet_height` pins it for tests; negative = random) and kept through ricochets and penetrations. It strikes every collider
   whose coverage is above it and clears the rest, so a collider of coverage C is cleared with chance (100 − C)/100 but the same
   height serves everything along the path: behind cover of 50, a body of 60 is struck only by the shots between 50 and 60 (or those that punch
   through the cover), and a body of 35 (a crouch) by none that cleared it. A character's coverage is its posture's. Spec: `docs/cover-and-stance.md`.
   Tests: `tests/projectile/cover_shared_bullet_height_test.gd`, `posture_hit_chance_test.gd`.
2. **Ricochet** (`P ≥ penetration_bounce_min` and `s < bounce_square_max`) — reflects,
   `speed ×= bounce_speed_retention`, deals `damage × s × v × bounce_damage_retention`.
3. **Penetrate** (else, while `speed ≥ penetration_min_speed / p`) — deals `damage × s × v`, bleeds
   speed by `loss = (P/100) × penetrate_loss_scale × (2 − s) / p`, deflects by up to `penetrate_deflect_max_deg × P/100 / p`.
   **Blocked** if too slow: deals the impact and embeds.

**Two kinds of penetration.** `P` is a property of the *target's surface* (flesh 15, a wardrobe 55, a wall 100); `p` is the *bullet's* power, set
per gun by `ProjectileSpawner.spawn(..., muzzle_speed, penetration)` from `GunConfig` (pistol 1.0, SMG 0.8, rifle 2.2). A higher `p` loses less speed to
the same surface and needs less speed to get through, so a pistol round (3200 px/s) dies in a wall (it leaves at ~320 px/s) while a rifle round
(4400 px/s, `p` 2.2) leaves it at ~59% speed and can wound someone behind it, with its damage scaled down by the speed it has left. `muzzle_speed` also sets
`v`'s reference, so the pistol (3200 = `BallisticsConfig.projectile_speed`) is unchanged. Tests: `tests/projectile/gun_penetration_test.gd`,
`gun_damage_test.gd`.

On any *damaging* outcome the projectile packages a `HitInfo` and calls `body.take_hit(info)` (the
object then shoves/deforms/sprays via Physics), re-emits `hit(body, damage)` — which a gun
forwards to the character's `hit_landed` — and posts a `&"hit"` event on `EventBus`
(`{ position, victim, source, direction, damage, attacker }`, interface 10 — `attacker` is the
shooter, the projectile's `ignore` body; plus `outcome` (`&"ricochet"` / `&"blocked"` / `&"penetrate"`), the struck
`material` (`surface.material`, `""` for a wall), `speed_factor` and the round's `power`,
which the Audio domain voices impacts from; a fly-over posts nothing) so decoupled listeners (the AI's combat awareness and
hostility) learn what was struck, where, and by whom. Console lines: `Shot flew over /
ricocheted off / penetrated / blocked by …`.

**Exit point and blood carry.** A penetrating hit also fills `HitInfo.has_exit / exit_position / exit_normal`:
`_find_exit` casts a probe ray back from `BallisticsConfig.exit_probe_distance` ahead toward the entry, skipping other
colliders, until it meets the penetrated collider's far face (none found = thicker than the probe, no exit). A bullet
that penetrates a `BallisticsConfig.blood_material` (flesh) surface carries that body's blood from its exit; the next
non-flesh surface it strikes (any outcome but fly-over) within `blood_carry_distance` px gets `HitInfo.blood`
= `1 − distance / blood_carry_distance`, and the bullet then carries no more. Tests: `tests/physics/hit_particles_*`,
`blood_carries_past_character`, `blood_carry_distance_limit`.

## Layering

`projectile.gd` / `casing.gd` are control; `projectile_visuals.gd` / `casing_visuals.gd` draw.
`projectile_spawner.gd` / `casing_spawner.gd` are the spawn entry points the guns call
(`ProjectileSpawner.spawn(position, direction, parent, ignore, item_damage, muzzle_speed := -1, penetration := 1.0, max_range := -1, strikes_shooter := false)`).
`max_range` is `Projectile.max_distance`: the round is spent exactly there (the last step is clamped, so it is never seen past it); `strikes_shooter`
leaves `ignore` in the sweep, so the shooter can be hit while still being the `attacker` of its hits (a grenade's fragments). A bullet is added with a
readable name (`Projectile`, `Projectile2`, ...), which is how the tests count them. A casing is Despawner-tracked by
`CasingSpawner`; its toss lasts `eject_time` (~0.3 s), then it rests.

## Explosion (`explosion.gd`, `class_name Explosion`): a grenade's burst

Called by Items' `ThrownGrenade` when its fuse is out: `Explosion.frag(at, world, source, row)` and `Explosion.stun(at, world, source, row)`
(`source` the thrower or null, `row` its `GrenadeConfig` row). Both post `&"explosion"` `{ position, kind, attacker, radius }` first, call
`Physics.spawn_explosion(world, at, kind)` and then do their work. Spec: `docs/grenades.md` G7 to G12; friendly fire is on (G9), the thrower is struck like anyone.

- **The line.** `_reach(space, at, body, characters)` casts a ray from the burst to the body's centre on `PhysicsLayers.SOLID`, skipping the other
  characters, and returns where it met the body (`{ position, normal }`; the hit's contact point) or `{}` when something stops it first:
  a `StaticBody2D` (a wall) always does, a piece of furniture when its `get_surface().coverage` is above the **body's own height** (a character's is
  its posture's: crouched 35, standing 60, so a crouched character behind a couch (45) is shielded and a standing one is not; a table (30) shields
  nobody). Lower pieces are cleared and the ray goes on. A body with no collider (the fallen) is reached at its centre. The same rule serves the blast, the
  flash; the bang asks it with `walls_only` (only a wall stops the line: furniture muffles nothing).
- **Frag blast** (`_blast`): the bodies near are the circle's overlaps on the solid layer (walls left out: they only block) plus every dead character
  (they left the layer but are still thrown). Each within `blast_radius` of the blast point (to its centre) with a clear line takes `blast_damage` (full to
  `kill_radius`, `blast_damage * (R - d) / (R - kill)` beyond) through `take_hit` (a `HitInfo` with `speed_factor` 0: no impact of its own) and posts
  `&"hit"` with `outcome` `&"blast"`, the thrower as `attacker`. A dead body is not struck (nothing to damage) but is shoved. Every body reached
  is then shoved away by `blast_impulse` with the same fall-off, capped at `mass * blast_max_speed` so a light chair is not fired across the house:
  `blast_push(from, impulse)` on a character (living: knockback; dead: its ragdoll thrown and woken, `Ragdoll.wake()`), `apply_impulse(v)` on furniture.
- **Fragments** (`_fragments`): `fragments` bullets evenly round the circle (each jittered within its share), through `ProjectileSpawner.spawn` with the
  row's `fragment_speed`, `fragment_penetration`, `fragment_range` and `strikes_shooter`; their `damage` is `fragment_damage` at full speed head-on
  (not added to the bullet's base, unlike a gun's `damage`). So cover, penetration, ricochet, blood, debris and impact sounds all work as for bullets.
- **Stun** (`stun`): every living character within the larger of `flash_radius` and `bang_radius`. The **flash** works by sight: with a clear line
  it blinds `max_blind * (flash_radius - d) / (flash_radius - flash_full)` (full inside `flash_full`) times the facing factor (the dot of its `facing` with the
  direction to the burst: 1 -> x1, 0 -> x0.6, -1 -> x0.25, linear between); no clear line, none. A wall always stops the line; a piece of furniture taller than the
  character stops it only when the character is within the row's `flash_cover_reach` (30 px) of it on the burst's side (`_reach`'s `cover_reach`, `_against`: a reverse ray from the body to the burst), so a crouched body hunched against a couch is
  shielded and one 120 px behind it is flashed. The blast (`_reach` without a reach) keeps the plain rule. The **bang** works by range: deaf
  `max_deaf * (1 - d / bang_radius)`, x`wall_factor` when a wall stands between (`_reach(..., walls_only)`; a character hunched against a couch is out of the flash, not out of the bang). Both go through `Character.take_stun(blind, deaf, at)`, which posts the
  `&"stun"` event; within `point_blank` the character also takes `point_blank_damage` through `take_damage`. A stun does no other damage.

Tests: `tests/projectile/frag_blast_by_distance`, `frag_blast_blocked_by_wall`, `frag_blast_low_cover_by_posture`, `frag_fragments_hit`,
`grenade_friendly_fire`, `tests/physics/frag_blast_pushes`, `tests/character/stun_flash_by_sight`, `stun_flash_cover_reach`, `stun_bang_by_range`, `stun_bang_through_furniture`.

Interface notes: the blast's `&"hit"` events carry `attacker` = the thrower, so the AI's "attacked me" hostility sees a victim's own teammate as an
attacker when it throws; the Audio domain ignores `&"blast"` hits (no impact profile), the burst has its own sound.

**Interfaces:** 3 (hittable), 4 (`Physics.spawn_explosion`), 5 (pushable), 6 (the guns' `ProjectileSpawner` / `CasingSpawner`, `ThrownGrenade` → `Explosion`), 7 (what `Explosion` calls on a character), 10 (EventBus `&"hit"`, `&"explosion"`), 11 (`PhysicsLayers`) — signatures in `architecture`.

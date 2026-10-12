---
name: domain-projectile
description: Deep implementation detail for the Projectile System domain (scenes/projectile/) — shooting: penetration, damage, cover, ricochet. Use when editing scenes/projectile/ or working on the bullet impact model, fly-over/ricochet/penetrate/blocked resolution, casings, or BallisticsConfig tuning. Complements the `architecture` skill, which holds the cross-domain interfaces.
---

# Projectile System domain

Owns shooting: penetration, damage, cover, ricochet. All knobs live in `BallisticsConfig`.

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
   whose coverage is above it and clears the rest, so a collider of coverage C is cleared with chance (100 − C)/100 (the old rate) but the same
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
(4400 px/s, `p` 2.2) leaves it at ~55% speed and can wound someone behind it, with its damage scaled down by the speed it has left. `muzzle_speed` also sets
`v`'s reference, so the pistol (3200 = `BallisticsConfig.projectile_speed`) is unchanged. Tests: `tests/projectile/gun_penetration_test.gd`,
`gun_damage_test.gd`.

On any *damaging* outcome the projectile packages a `HitInfo` and calls `body.take_hit(info)` (the
object then shoves/deforms/sprays via Physics), re-emits `hit(body, damage)` — which a gun
forwards to the character's `hit_landed` — and posts a `&"hit"` event on `EventBus`
(`{ position, victim, source, direction, damage, attacker }`, interface 10 — `attacker` is the
shooter, the projectile's `ignore` body; plus `outcome` (`&"ricochet"` / `&"blocked"` / `&"penetrate"`), the struck
`material` (`surface.material`, `""` for a wall), `normal`, `speed_factor`, the firing `gun` and the round's `power`,
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
(`ProjectileSpawner.spawn(position, direction, parent, ignore, item_damage, muzzle_speed := -1, penetration := 1.0)`).

## Interface recap (authoritative in the `architecture` skill)

- Reaches into Objects only through the hittable contract (interface 3): reads `get_surface()`
  and calls `take_hit(HitInfo)`. The guns (Items, `GunItem`) are the one caller of `ProjectileSpawner` /
  `CasingSpawner` (`ProjectileSpawner.spawn` / `CasingSpawner.spawn` take the firing `gun` id and the round's penetration
  `power`, carried on the round's `hit` events and its `casing` event). Casings despawn via the Despawner; a casing posts a
  `&"casing"` event (`{ position, gun, power }`) when its ~0.3 s toss ends (nothing consumes it). Each damaging hit also posts a `&"hit"` event
  on `EventBus` (interface 10).

---
name: domain-items
description: Deep implementation detail for the Items domain (scenes/items/) — the things the character holds and the actions they perform (fists, the guns — pistol, SMG, assault rifle —, key, unarmed). Use when editing scenes/items/ or working on item slots, the Item contract, adding a new item or gun, GunConfig (damage, fire rate, penetration, spread, recoil), how a long gun is held and raised against a wall, magazines, an item dropped on death (DroppedItem), or a gun's link into the projectile system. Complements the `architecture` skill, which holds the cross-domain interfaces.
---

# Items domain

Owns the things the character holds and the actions they perform. Alternation/reload/aim state
lives in the item, not the character.

## Slots

Number keys 1–9 select a slot (`ItemRegistry`):
- **1** unarmed — no hands, F/LMB do nothing.
- **2** fists — both hands, F alternates (alternation state lives in the item).
- **3** pistol — right hand + pistol art; F jabs, LMB fires (one round per click), R reloads.
- **4** key — inert carryable; it exists so a `requires_item: 4` interaction has something to
  gate on (gates the wardrobe's "Rummage" interaction).
- **5** SMG, **6** assault rifle — automatic guns held two-handed (hold LMB to keep firing).

A gun's slot is the `slot` of its `GunConfig` row; `ItemRegistry.default_inventory()` has everything,
`inventory_for(slots)` just some, and `loadout_for(gun_slot)` / `spares_for(gun_slot)` / `random_gun_slot(rng)` are what Main uses to
arm a spawn (see `LoadoutConfig` below and `domain-character`, `set_loadout`).

## Guns (`gun.gd`, `gun_config.gd`)

Every firearm is a `GunItem` (`class_name GunItem extends Item`) whose numbers come live from its row in `GunConfig`
(`GunConfig.guns`, a static-var holder like `MagazineConfig`, so a test or tool can retune it — tests use `set_static`):

| Key | Meaning |
|---|---|
| `name`, `slot` | display name (HUD, and how the AI words it); inventory slot / number key |
| `damage` | added to the bullet's base damage (`Projectile.damage`, 10) at full speed head-on |
| `fire_interval` | seconds between rounds (at most one round per physics frame) |
| `automatic` | holding the trigger keeps firing (a controller re-presses `shoot()` every frame); false = one round per click |
| `penetration` | power multiplier for punching through what it hits (1 = a pistol round); see `domain-projectile` |
| `muzzle_speed`, `spread_deg`, `recoil` | speed a round leaves at; random cone half-angle; scale of the kick (`user.kick(hand, recoil)`) |
| `magazine`, `spare_magazines` | the `MagazineConfig.types` id it is built loaded with; how many spares a character carrying it carries |
| `raises_at_contact` | the barrel is too long to use against a wall (below) |

First-pass numbers: pistol 15 dmg / 0.10 s / semi / ×1.0 / 12 rounds; SMG 5 dmg / 0.07 s / auto / ×0.8 / 2.5° / 32 rounds;
rifle 22 dmg / 0.11 s / auto / ×2.2 / 4400 px/s / 24 rounds. They are one table, for tuning.

`GunItem` holds everything a gun does: the magazine, `rounds_loaded` / `ammo_capacity` / `can_reload` / `finish_reload`, `reload_time()`
(the loaded magazine type's, `MagazineConfig.reload_time_of`), `secondary(user) -> bool` (refuses while reloading, empty or still cycling;
else spends a round, rotates the aim by the spread, calls `ProjectileSpawner.spawn(muzzle_origin, dir, world, user, damage, muzzle_speed,
penetration)`, ejects a casing, kicks the hand and posts a `&"shot"` event on `EventBus`
(`{ position` (muzzle)`, gun, attacker, power }`, which the Audio domain voices)) and `primary` (a melee jab with the weapon hand). **Fire rate** is a cooldown: `tick(delta)`
counts it down (the character ticks every item it carries, before its controller runs, so it is deterministic and independent of the
wall clock); firing does `cooldown += fire_interval`, carrying an overshoot so 0.07 s is not rounded to 5 frames, with the idle credit
capped at one frame so a gun never bursts to catch up.

A subclass supplies only its look and its hold: the gun id (`GUN`, also the `Magazine.gun` key), `painter()` / `flat_painter()` and
`art_size()` / `flat_size()`, `grip_back()` (px the butt sits behind the weapon hand), and the stance names (`grip_stance()` /
`fore_stance()`, and `raised_grip_stance()` / `raised_fore_stance()`). `muzzle_ahead()` = `art_size().y − grip_back()` (the pistol's is 11), which `Character.muzzle_origin` uses, so a long gun's muzzle is further out.

- **Pistol** (`pistol.gd`): 5×13 art, held at arm's length (`aim`) with the other fist beside it on the grip (`support`: same forward point, both hands together).
- **SMG** (`smg.gd`): 6×28 art, `GRIP_BACK` 10; shouldered (butt on the right shoulder; `smg_grip` / `smg_fore`), the other hand out on the shroud.
- **Zeroing:** `GunItem.secondary` aims the round from the muzzle at the point `GunConfig.zero_range` (300 px) ahead on the aim line, not parallel to `facing`, so a
  shouldered gun (muzzle 9 px off the line) still hits where the character points; the spread is applied around that direction.
- **Rifle** (`rifle.gd`): 7×36 art, `GRIP_BACK` 13; shouldered, butt on the right shoulder (`rifle_grip` at the grip, `rifle_fore` out along the
  handguard), both hands on the barrel's line.

## Raised against a wall (`raises_at_contact`)

A long gun (SMG, rifle) cannot be used against a wall or object: `Item.raises_at_contact()` makes the character test the barrel each frame
(see `domain-character`). While it touches, `raised_stance(hand)` (`ready_grip` / `ready_fore`: hands drawn in to the chest) is held, and
`draw_weapon` reads `user.weapon_raise()` (0..1) to foreshorten the barrel — "pointed up" seen from above — rendering the painter at
`RAISE_STEPS` lengths down to `RAISED_LENGTH` (crisp and cached, not a stretched texture), scaled about the weapon hand. `shoot()` does
nothing while it is raised. The pistol does not raise.

## Ammo, magazines and reloading

`Magazine` (`magazine.gd`, an `Item` subclass; `Magazine.create(type, loaded := -1)`) holds `rounds` of a `capacity`
for a `gun`. Types, capacities, optional per-type `reload_time` and the shared fallback `reload_time` live in `MagazineConfig` (a static-var
holder; add a row to `types` for a new magazine): standard / extended for each gun — pistol 12 / 20, SMG 32 / 50, rifle 24 / 40, rifle and SMG
reloads slower. A magazine only fits its own `gun` (`Character.best_magazine(gun)` filters on it). Magazines are **carried by the character, never
held**: they are not in any slot, so nothing can switch to them, and several can be carried (`ItemRegistry.create_magazines(type_ids)`).
A gun (`magazine: Magazine`) spends one round per shot (`secondary` does nothing when empty or reloading, with no
casing and no recoil) and reports `rounds_loaded()` / `ammo_capacity()`. `can_reload(user)` is true when a carried magazine
holds more rounds than the loaded one; `finish_reload(user)` seats the fullest compatible spare (`user.take_magazine`) and
stows the old one with its remaining rounds (`user.stow_magazine`), dropping it only if empty. `ItemRegistry.create(slot, rounds)`
builds a gun loaded with its `GunConfig.magazine` type (`rounds` < 0 = full). The base `Item` keeps all of this inert
(`rounds_loaded()` = -1). The reload timer and R binding are the Character's, see `domain-character`.

## Adding an item

Write an `Item` subclass in `items/` and add a case in `ItemRegistry.create`. To add a **gun**: a row in `GunConfig.guns` (with a free
`slot`), a `GunItem` subclass (painters, sizes, `grip_back`, stances — add any new stance rows to `CharacterConfig.stances`), a case in
`ItemRegistry._new_gun`, and magazine rows in `MagazineConfig.types` for its `gun` id.

## Loadouts

`LoadoutConfig` (static holder) is what a match hands a character: `options()` is the plain-data list a UI shows — **Random**
first, then every gun in `GunConfig.guns` by slot, each with its `MagazineConfig` types (its own `magazine` first) — so a gun
added to `GunConfig` is offered automatically. `normalize(loadout)` makes a `{ weapon, magazine, spares }` dict valid,
`apply(character, loadout, rng)` calls `Character.set_loadout` (bare hands, fists, key and the one gun, loaded with the chosen
magazine and carrying `spares` of it; `random` draws a gun from `rng`) and returns the gun id, `random(rng)` draws a valid
loadout. `ItemRegistry.create` / `inventory_for` take an optional loaded-`magazine` override.

## Gun art

A gun's `draw_weapon` draws its painter (`pistol_painter.gd`, `smg_painter.gd`, `rifle_painter.gd`; Items-private) through the Art domain:
`PixelArt.render_turned(painter, size, color, PixelArt.snap_angle(angle), "metal")`, drawn rotated to the exact angle of the character's
`weapon_facing()` (which trails the aim a touch as it turns) with its butt `grip_back()` px behind the weapon hand. Painters draw in the
canonical frame — muzzle toward +y, butt at y = 0 — and scale their parts from `c.w` / `c.h`, so the same painter renders the shortened raised
barrel. The weapon hand's stance is steady (arm reaching out, steady while walking) and the other hand's holds the gun forward: a two-handed hold.
The character visuals draw the weapon under the torso and before the fists, so its butt tucks behind the shoulder and the fists grip it. The weapon hand is hand 0 (the character's right as drawn). Firing calls `user.kick(WEAPON_HAND, recoil)`, so the weapon hand
(and the gun in it) recoils, and the supporting hand with it by its stance's `recoil_share`.

## Dropping on death

When its user dies the character calls `item.drop(user, velocity)`. The base `Item` leaves nothing
(returns null); a gun spawns a `DroppedItem` (`dropped_item.gd`, `class_name DroppedItem`, a
`Node2D` in the world root) where its art was drawn, pulled back toward the hand (`held_from`) if
that spot is inside a wall. The dropped item falls from about hand height on a pseudo-height,
bounces, skids to a stop with a fading spin and glances off walls and solid furniture (circle
`cast_motion` on layer 1); it picks which side lands up once (`flip`) and draws through
`item.draw_dropped(canvas, at, angle, modulate, opts)` over
a shadow that closes in as it lands, at `z_index` −1, and stops processing once at rest. Tuning is
its exports. Visual only: nothing picks it up and the Despawner never frees it. A gun's
`draw_dropped` paints its flat painter (`pistol_flat_painter.gd`, `smg_flat_painter.gd`, `rifle_flat_painter.gd`; Items-private): the gun's
side profile lying on the floor — receiver with sights and muzzle, grip (and, on the long guns, magazine and stock) raked off one side
(`flip` mirrors it) — at `flat_size()`.

## Link into the Projectile System

Guns are the one place Items reach into the Projectile System
(`ProjectileSpawner` / `CasingSpawner`). No other item crosses that boundary.

## Interface recap (authoritative in the `architecture` skill)

- **Items ↔ Character** (interface 6): `Item` (`items/item.gd`) exposes `display_name`, `reach`,
  `hand_stance(hand)` (how that hand is held: a `CharacterConfig.stances` name — `relaxed` by default,
  `guard` for fists, `aim` / `support` for the pistol, `smg_*` / `rifle_*` for the long guns), `primary(user)` (F),
  `secondary(user) -> bool` (LMB), `tick(delta)`, `is_automatic()`, `weapon_hand()`, `muzzle_ahead()`, `raises_at_contact()`,
  `raised_stance(hand)`, `draw_weapon(canvas, user)`, `drop(user, velocity)` and `draw_dropped(canvas, at, angle, modulate, opts)`.
  The character API an item may call: `facing`, `punch(hand)`, `hand_position(hand)`,
  `hand_world(hand)`, `muzzle_origin(hand)`, `world_root()`, `report_shot(body, dmg)`, `kick(hand, strength)`, `weapon_facing()`,
  `weapon_raise()`, and for reloading
  `best_magazine(gun)` / `take_magazine(gun)` / `stow_magazine(m)`. Ammo hooks on `Item`: `rounds_loaded()`,
  `ammo_capacity()`, `reload_time()`, `can_reload(user)`, `finish_reload(user)`, `reloading`; and `gun_id()` / `round_power()`
  (the gun's id and its rounds' penetration power; `&""` / 1 on a non-gun), read for the character's `reload` event.
- **Items → Art** (interface 12): each gun's art via `PixelArt.render_turned` / `snap_angle`.

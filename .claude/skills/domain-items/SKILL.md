---
name: domain-items
description: Deep implementation detail for the Items domain (scenes/items/) — the things the character holds and the actions they perform (fists, pistol, key, unarmed). Use when editing scenes/items/ or working on item slots, the Item contract, adding a new item, an item dropped on death (DroppedItem), or the pistol's link into the projectile system. Complements the `architecture` skill, which holds the cross-domain interfaces.
---

# Items domain

Owns the things the character holds and the actions they perform. Alternation/reload/aim state
lives in the item, not the character.

## Slots

Number keys 1–9 select a slot (`ItemRegistry`):
- **1** unarmed — no hands, F/LMB do nothing.
- **2** fists — both hands, F alternates (alternation state lives in the item).
- **3** pistol — right hand + pistol art; F jabs, LMB fires, R reloads.
- **4** key — inert carryable; it exists so a `requires_item: 4` interaction has something to
  gate on (gates the wardrobe's "Rummage" interaction).

## Ammo, magazines and reloading

`Magazine` (`magazine.gd`, an `Item` subclass; `Magazine.create(type, loaded := -1)`) holds `rounds` of a `capacity`
for a `gun`. Types, capacities, `default_loaded` and `reload_time` live in `MagazineConfig` (a static-var holder; add a
row to `types` for a new magazine). Magazines are **carried by the character, never held**: they are not in any slot, so
nothing can switch to them, and several can be carried (`ItemRegistry.create_magazines(type_ids)`).
The pistol (`magazine: Magazine`) spends one round per shot (`secondary` does nothing when empty or reloading, with no
casing and no recoil) and reports `rounds_loaded()` / `ammo_capacity()`. `reload_time()` is `MagazineConfig.reload_time`. `can_reload(user)` is true when a carried magazine
holds more rounds than the loaded one; `finish_reload(user)` seats the fullest compatible spare (`user.take_magazine`) and
stows the old one with its remaining rounds (`user.stow_magazine`), dropping it only if empty. `ItemRegistry.create(3, rounds)`
builds a pistol loaded with a `default_loaded` magazine (`rounds` < 0 = full). The base `Item` keeps all of this inert
(`rounds_loaded()` = -1). The reload timer and R binding are the Character's, see `domain-character`.

## Adding an item

Write an `Item` subclass in `items/` and add a case in `ItemRegistry`. `ItemRegistry.create(id)`
/ `default_inventory()` build them.

## Pistol art

`pistol.gd`'s `draw_weapon` draws `pistol_painter.gd` (Items-private; slide, ejection port,
sights, grip) through the Art domain: `PixelArt.render_turned(PistolPainter, ART_SIZE, color,
PixelArt.snap_angle(angle), "metal")`, drawn rotated to the exact angle of the character's
`weapon_facing()` (which trails the aim a touch as it turns) with its grip `GRIP_BACK` px behind
the weapon hand. Its `hand_stance()` is `aim` for `WEAPON_HAND` (arm reaching out, steady while walking)
and `support` for the other hand, which cups the grip: a two-handed hold. The character visuals draw the
weapon before the fists, so they grip it. Firing calls `user.kick(WEAPON_HAND)`, so the weapon hand
(and the gun in it) recoils, and the supporting hand with it by its stance's `recoil_share`.

## Dropping on death

When its user dies the character calls `item.drop(user, velocity)`. The base `Item` leaves nothing
(returns null); the pistol spawns a `DroppedItem` (`dropped_item.gd`, `class_name DroppedItem`, a
`Node2D` in the world root) where its art was drawn, pulled back toward the hand (`held_from`) if
that spot is inside a wall. The dropped item falls from about hand height on a pseudo-height,
bounces, skids to a stop with a fading spin and glances off walls and solid furniture (circle
`cast_motion` on layer 1); it picks which side lands up once (`flip`) and draws through
`item.draw_dropped(canvas, at, angle, modulate, opts)` over
a shadow that closes in as it lands, at `z_index` −1, and stops processing once at rest. Tuning is
its exports. Visual only: nothing picks it up and the Despawner never frees it. The pistol's
`draw_dropped` paints `pistol_flat_painter.gd` (Items-private): the gun's side profile lying on
the floor — slide with sights and muzzle, grip raked back off one side (`flip` mirrors it), trigger
guard — at `FLAT_SIZE`.

## Link into the Projectile System

The pistol is the one place Items reaches into the Projectile System
(`ProjectileSpawner` / `CasingSpawner`). No other item crosses that boundary.

## Interface recap (authoritative in the `architecture` skill)

- **Items ↔ Character** (interface 6): `Item` (`items/item.gd`) exposes `display_name`, `reach`,
  `hand_stance(hand)` (how that hand is held: a `CharacterConfig.stances` name — `relaxed` by default,
  `guard` for fists, `aim` / `support` for the pistol), `primary(user)` (F), `secondary(user)` (LMB),
  `draw_weapon(canvas, user)`, `drop(user, velocity)` and `draw_dropped(canvas, at, angle, modulate, opts)`.
  The character API an item may call: `facing`, `punch(hand)`, `hand_position(hand)`,
  `hand_world(hand)`, `muzzle_origin(hand)` (`CharacterConfig.muzzle_ahead` past the hand),
  `world_root()`, `report_shot(body, dmg)`, `kick(hand)`, `weapon_facing()`, and for reloading
  `best_magazine(gun)` / `take_magazine(gun)` / `stow_magazine(m)`. Ammo hooks on `Item`: `rounds_loaded()`,
  `ammo_capacity()`, `reload_time()`, `can_reload(user)`, `finish_reload(user)`, `reloading`.
- **Items → Art** (interface 12): the pistol's art via `PixelArt.render_turned` / `snap_angle`.

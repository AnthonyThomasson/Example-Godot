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
- **3** pistol — right hand + pistol art; F jabs, LMB fires.
- **4** key — inert carryable; it exists so a `requires_item: 4` interaction has something to
  gate on (gates the wardrobe's "Rummage" interaction).

## Adding an item

Write an `Item` subclass in `items/` and add a case in `ItemRegistry`. `ItemRegistry.create(id)`
/ `default_inventory()` build them.

## Pistol art

`pistol.gd`'s `draw_weapon` draws `pistol_painter.gd` (Items-private; slide, ejection port,
sights, grip) through the Art domain: `PixelArt.render_turned(PistolPainter, ART_SIZE, color,
PixelArt.snap_angle(angle), "metal")`, drawn rotated to the exact angle of the character's
`weapon_facing()` (which trails the aim a touch as it turns) with its grip `GRIP_BACK` px behind
the weapon hand. Its `aiming_hands()` is `[WEAPON_HAND]`, so that hand stays steady while walking. The character visuals draw the
weapon before the hands, so the fist grips it. Firing calls `user.kick(WEAPON_HAND)`, so the hand
(and the gun in it) recoils.

## Dropping on death

When its user dies the character calls `item.drop(user, velocity)`. The base `Item` leaves nothing
(returns null); the pistol spawns a `DroppedItem` (`dropped_item.gd`, `class_name DroppedItem`, a
`Node2D` in the world root) where its art was drawn, pulled back toward the hand (`held_from`) if
that spot is inside a wall. The dropped item falls from about hand height on a pseudo-height,
bounces, skids to a stop with a fading spin and glances off walls and solid furniture (circle
`cast_motion` on layer 1); it draws through `item.draw_dropped(canvas, at, angle, modulate)` over
a shadow that closes in as it lands, at `z_index` −1, and stops processing once at rest. Tuning is
its exports. Visual only: nothing picks it up and the Despawner never frees it. The pistol's
`draw_weapon` and `draw_dropped` share one `_draw_art`.

## Link into the Projectile System

The pistol is the one place Items reaches into the Projectile System
(`ProjectileSpawner` / `CasingSpawner`). No other item crosses that boundary.

## Interface recap (authoritative in the `architecture` skill)

- **Items ↔ Character** (interface 6): `Item` (`items/item.gd`) exposes `display_name`, `reach`,
  `visible_hands()`, `aiming_hands()`, `primary(user)` (F), `secondary(user)` (LMB),
  `draw_weapon(canvas, user)`, `drop(user, velocity)` and `draw_dropped(canvas, at, angle, modulate)`.
  The character API an item may call: `facing`, `punch(hand)`, `hand_position(hand)`,
  `hand_world(hand)`, `muzzle_origin(hand)`, `world_root()`, `report_shot(body, dmg)`,
  `kick(hand)`, `weapon_facing()`.
- **Items → Art** (interface 12): the pistol's art via `PixelArt.render_turned` / `snap_angle`.

---
name: domain-items
description: Deep implementation detail for the Items domain (scenes/items/) — the things the character holds and the actions they perform (fists, pistol, key, unarmed). Use when editing scenes/items/ or working on item slots, the Item contract, adding a new item, or the pistol's link into the projectile system. Complements AGENTS.md, which holds the cross-domain interfaces.
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

## Link into the Projectile System

The pistol is the one place Items reaches into the Projectile System
(`ProjectileSpawner` / `CasingSpawner`). No other item crosses that boundary.

## Interface recap (authoritative in AGENTS.md)

- **Items ↔ Character** (interface 6): `Item` (`items/item.gd`) exposes `display_name`, `reach`,
  `visible_hands()`, `primary(user)` (F), `secondary(user)` (LMB), `draw_weapon(canvas, user)`.
  The character API an item may call: `facing`, `punch(hand)`, `hand_position(hand)`,
  `hand_world(hand)`, `muzzle_origin(hand)`, `world_root()`, `report_shot(body, dmg)`.

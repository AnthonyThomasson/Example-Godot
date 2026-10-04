---
name: domain-character
description: Deep implementation detail for the Character domain (scenes/character/) — the player character (built so other character types can exist): facing, movement, hands, the punch, and the control/animate/draw layering. Use when editing scenes/character/ or working on character movement, facing, hands, punch hit detection, or the player/NPC scene wiring. Complements the `architecture` skill, which holds the cross-domain interfaces.
---

# Character domain

Owns the player character, built so other character types can exist. Reads intent from a
pluggable controller child and integrates knockback into locomotion (it is the one "pushable"
that isn't a RigidBody2D — it integrates knockback into its own walk).

## Layering (control / animate / draw)

The three verbs live in separate files, wired via the scene tree (no `class_name` on scene
scripts; cross-file calls resolve through `$` / `get_parent()`). A "draw" file is attached to
its own child `Node2D`.

- **Control** (`character.gd`, root body) owns state + physics: computes `facing`, moves, and
  forwards intent from its controller. Never draws.
- **Animate** (`character_hands.gd`, a child `Node2D`) owns hand geometry, the punch tween, and
  punch hit detection; exposes `hand_position(i)` and the `punched` signal.
- **Draw** (`character_visuals.gd`) owns appearance: draws the body, the hands the held item
  wants shown, then `item.draw_weapon()`.

Ordering: a parent's `_physics_process` runs before its children's, so the hands see the
character's fresh `facing`, and the character pulls its controller's intent at the top of its own
`_physics_process` (lag-free).

## Facing & hands

- **Facing:** `character.gd` points `facing` from itself to `aim_point` (the mouse, set by the
  controller) each frame. The node is never rotated, so hand math stays in local space.
- **Hands:** two circles positioned from `facing` + its perpendicular, collision-resolved so they
  rest on walls/objects. Tunable via `character_hands.gd`'s `hand_*` exports.

## Punch hit detection

During a swing `character_hands.gd` runs a shape query (`intersect_shape`) at the fist's *raw*
punch position — which extends into what is hit, unlike the drawn hand that rests on the surface
— and dedupes per swing. Each new hit shoves the body via the "pushable" contract
(`apply_impulse`) and deals damage, both scaled by the swing's range of motion (how fast the fist
is moving this frame; 1.0 = full-speed extend). It emits `punched(hand, body, damage)` → the
character re-emits `hit_landed(body, damage, hand)`. A punch pushes but never deforms; walls (no
`apply_impulse`) take damage without moving. Tuned by `CharacterConfig.punch_impulse` /
`punch_damage` (walking push tuned by the same holder).

## Runtime shapes (built in `_ready()`)

`character.gd` builds its body `CircleShape2D`; `character_hands.gd` builds the fist query
`CircleShape2D`. The editor shows a "no shape" warning on `Player/CollisionShape2D` — expected.

## Scenes

`character/npc.tscn` is a generic goal-driven agent driven by `ai/goal_controller.gd` (see the
`domain-ai` skill). The player uses `player_controller.gd`.

## Interface recap (authoritative in the `architecture` skill)

- **Character ↔ Controller** (interface 7): the character reads intent from a controller child
  (any node with `control(character, delta)`) that writes `move_input` / `aim_point` and calls
  the action API: `melee()`, `shoot()`, `select_slot(id)`, `try_interact()` /
  `interact_with(object, id)` / `end_interaction()`. Signals: `hit_landed(body, damage, hand)`
  (hand 0/1 = melee, −1 = shot), `item_changed(item)`, `interaction_changed(active, label)`.
  Observers (debug HUD, camera) attach by exported node path and read only the public API/signals.
- **Items ↔ Character** (interface 6): the character API an item may call — `facing`,
  `punch(hand)`, `hand_position(hand)`, `hand_world(hand)`, `muzzle_origin(hand)`, `world_root()`,
  `report_shot(body, dmg)`.

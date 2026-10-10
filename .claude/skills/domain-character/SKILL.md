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
  punch hit detection; exposes `hand_position(i)` and the `punched` signal. `character_pose.gd`
  (a `RefCounted` the character owns as `pose`) owns the living motion of head, shoulders and
  hands (below).
- **Draw** (`character_visuals.gd`) owns appearance: a drop shadow, the shoulders, the head (with
  its shadow on the shoulders), then `item.draw_weapon()`, then the hands the held item wants
  shown (on top, gripping the weapon), then the wound marks over all of it.

## Pose (the living motion)

`character_pose.gd` layers motion over the aim; it is visual only (aim, shots and punches stay on
`facing`). `character.gd` steps it with `pose.update(delta, facing, get_real_velocity(), speed,
aiming)` (`aiming` = the held item's `aiming_hands()`) right after `move_and_slide()` (and with zero velocity while busy in an interaction; a dead
character stops stepping it), before the Hands child's `_physics_process`, so hands build on this
frame's pose.
- `head_angle`, `hand_angles[hand]`, `weapon_angle`, `torso_angle` each chase `facing` on their
  own damped angular spring — the head first, an aiming hand next, the weapon a touch behind the
  hand holding it, each free hand at its own pace (`pose_hand_pace_spread`), the shoulders last —
  so a turn ripples through the body. Past its `max_lag` a part is reeled in at `pose_lag_catch`
  rather than snapped, so a sudden flick stays continuous.
- A stride phase advances with distance walked: the shoulders sway, free hands swing fore/aft in
  opposite phase while an aiming hand stays steady and only drifts sideways (`hand_offset(hand)`),
  the head bobs per step. `head_offset` leans the head into the movement on a soft spring plus a
  slow breath; standing still the head also glances a little off the aim. Each character gets a
  random phase.
- `weapon_angle` is published as the character's `weapon_facing()`, which an item draws its weapon
  along.
- `kick(hand)` (the character's `kick`, called by the pistol on firing) throws the hand back on a
  recoil spring and twists the shoulders back on its side.
- Tuning: `CharacterConfig.pose_*` (per-part spring `freq` / `damping` / `max_lag` for head, aiming
  hand, weapon, free hands and shoulders; lag catch, hand pace spread, stride, sway, hand swing, aim
  drift, bob, lean, breath, glance, recoil).

## Pixel art

The character is top-down pixel art rendered through the Art domain (interface 12):
- Three private painters, each its own part: `body_painter.gd` — shoulders in the shirt color
  (`body_color`) with sleeve seams, the dark neck ring and an optional backpack with straps;
  `head_painter.gd` — skin with ears and a nose toward the front under a `hair_style` (`short` /
  `long` / `buzz` / `beanie` / `cap`) in `hair_color`, on its own canvas (`radius_for(width)`,
  `canvas_for(r)`); `hand_painter.gd` — a fist with knuckles to the front and the thumb on the
  inner side (`side`).
- `character_visuals.gd` renders each with `PixelArt.render_turned(..., snap_angle(angle), ...)` —
  lit for the nearest of `ArtConfig.turn_steps` steps — and draws it rotated to the exact angle of
  its part from the pose: the shoulders at `torso_angle`, the head at `head_angle` shifted by
  `head_offset`, each hand at its `hand_angles[hand]`. Each goes through `Deformation.draw_shape(..., texture,
  texture_angle, false)` so shots dent the art and darken it, then `Deformation.draw_marks` once
  on top in the flesh crack/hole/scorch colors. The head casts its shadow onto the shoulders (its
  silhouette `ArtConfig.cast_shadow_px` away from the light at `cast_shadow_darken`). The drop
  shadow is the shoulders' own silhouette, offset by `flesh_coverage × drop_shadow_per_coverage`
  like furniture.
- **Wounds turn with the shoulders:** `take_hit` records impacts relative to them
  (`Deformable.record(hit, pose.torso_angle)`) and the visuals turn them back to the current
  `torso_angle`, so a dent stays on the shoulder or hand that was hit. A part (hand or head) is
  dented by the shots whose path
  crossed it before they struck the body: each is re-seated where the shot entered the part, its
  depth scaled by part size / body radius. A hand mid-punch has left its wounds behind.
- Look exports on `Visuals`: `body_color`, `hand_color` (skin or glove), `skin_color`,
  `hair_color`, `hair_style`, `backpack`, `pack_color`. The defender preset wears a navy cap; the
  invader a dark beanie, gloves and a backpack. Proportions/defaults: `CharacterConfig.art_*`.

Ordering: a parent's `_physics_process` runs before its children's, so the hands see the
character's fresh `facing`, and the character pulls its controller's intent at the top of its own
`_physics_process` (lag-free).

## Facing & hands

- **Facing:** `character.gd` points `facing` from itself to `aim_point` (the mouse, set by the
  controller) each frame. The node is never rotated, so hand math stays in local space.
- **Hands:** two circles at a rest pose built in each hand's pose frame (`hand_angles[hand]` + its
  perpendicular, plus `pose.hand_offset(hand)` for walk swing and recoil), the punch extending
  straight along `facing`, collision-resolved so they rest on walls/objects. Tunable via `character_hands.gd`'s exports: `hand_radius`, `hand_gap`
  (negative: the fists rest in against the chest), `hand_lateral`, and `punch_gap`. A punch
  swings the fist from its rest pose to `punch_gap + reach` beyond the body edge, so the rest pose
  doesn't change how far a punch lands.

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

`character/npc.tscn` (the house defender) is a generic goal-driven agent driven by
`ai/goal_controller.gd` (see the `domain-ai` skill); `character/npc_invader.tscn` is an inherited
scene of it that only overrides data (faction, goal, hostility exports, colour). The player uses
`player_controller.gd`.

Every character has an exported `faction` (`&"player"` by default; the NPC presets set
`&"household"` / `&"invader"`), read by AI perception to tell allies from potential hostiles. A
landed punch is surfaced as `hit_landed` **and** posted as a `&"hit"` `EventBus` event with
`attacker = self` (like a projectile's), so a punch counts as an attack for AI hostility.

## Interface recap (authoritative in the `architecture` skill)

- **Character ↔ Controller** (interface 7): the character reads intent from a controller child
  (any node with `control(character, delta)`) that writes `move_input` / `aim_point` and calls
  the action API: `melee()`, `shoot()`, `select_slot(id)`, `try_interact()` /
  `interact_with(object, id)` / `end_interaction()`, and may read `damage_taken()` (accumulated hit
  damage, for injury sensing). Signals: `hit_landed(body, damage, hand)`
  (hand 0/1 = melee, −1 = shot), `interaction_changed(active, label)`.
  Observers (debug HUD, camera) attach by exported node path and read only the public API/signals.
- **Character → Art** (interface 12): the body/hand painters render through
  `PixelArt.render_turned` / `snap_angle`, draw on `PixelCanvas`, and read `ArtConfig`.
- **Items ↔ Character** (interface 6): the character API an item may call — `facing`,
  `punch(hand)`, `hand_position(hand)`, `hand_world(hand)`, `muzzle_origin(hand)`, `world_root()`,
  `report_shot(body, dmg)`, `kick(hand)`, `weapon_facing()`; and reads the item's
  `aiming_hands()`.

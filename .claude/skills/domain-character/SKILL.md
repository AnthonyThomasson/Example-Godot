---
name: domain-character
description: Deep implementation detail for the Character domain (scenes/character/) — the player character (built so other character types can exist): facing, movement, hands, the punch, death and the ragdoll fall, and the control/animate/draw layering. Use when editing scenes/character/ or working on character movement, facing, hands, punch hit detection, death / the fallen body, or the player/NPC scene wiring. Complements the `architecture` skill, which holds the cross-domain interfaces.
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
  hands (below); `character_ragdoll.gd` (owned as `ragdoll` once dead) owns the fall.
- **Draw** (`character_visuals.gd`) owns appearance: a drop shadow, the shoulders, the head (with
  its shadow on the shoulders), then `item.draw_weapon()`, then the hands the held item wants
  shown (on top, gripping the weapon), then the wound marks over all of it. Once dead it draws the
  fallen body instead (below).

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

## Death and the fall (the ragdoll)

`_apply_damage(amount, direction)` (shared by `take_hit`, which passes the shot's direction, and
`take_damage`, the punch path) calls `_die(direction)` at zero health. `_die` leaves layer 1 and
moves to `CharacterConfig.ragdoll_z_index` (beneath the living, above blood pools), ends any
interaction, builds `ragdoll` from the live pose with the body's momentum (walk + knockback,
including the killing blow's shove), lets go of the held item (`Item.drop(self, momentum + toss)`;
a returned node removes the slot, so `current_item()` may be null on a corpse), then emits `died`.
While dead `_physics_process` only steps the ragdoll (`step(delta, space, global_position)`); the
pose and hands stop.

`character_ragdoll.gd` builds a humanoid on the Physics domain's generic `Ragdoll` (3D points
over the floor: local x/y + height z), its indices as consts (`HEAD`, `CHEST`, `PELVIS`, `BELLY`,
`SPINE`, and per-side pairs `SHOULDER`, `HIP`, `ELBOW`, `HAND`, `KNEE`, `ANKLE`, side 0/1 matching the
hands):
- A rigid trunk (chest, pelvis, belly and back, shoulders, hips): the belly/back radii reach just
  to the trunk's surface so it lies flat on either side. Bones to the head, elbows, fists, knees and
  ankles.
- Limits in the trunk's frame (x toward hand 1's shoulder, y up the spine, z out of the chest):
  swing cones at the neck (rest up), shoulders and hips (rest down, out/in mirrored per side), and
  one-way hinges at the elbows (bend toward the front) and knees (toward the back), so no joint
  ever bends backward. Ranges are `CharacterConfig.ragdoll_*_limits` / `_bend` / `_slack` (degrees).
- Starts in the live pose: trunk upright turned to `pose.torso_angle`, head at `head_offset`, fists
  where the hands hold them (elbows by two-bone IK, pointing back and out), feet under the hips
  fore/aft by the stride (`pose.stride_phase()` / `walk_amount()`), knees a touch bent.
- Launch: every point carries the momentum, the upper body is pushed along the blow
  (`ragdoll_hit_topple`, fading to nothing at the hips; weaker and along the momentum or a random
  way with no blow), the knees buckle forward (`ragdoll_knee_buckle`) and each point gets a random
  jolt (`ragdoll_jitter`). The legs give out, then the body topples and settles (≈ 2–3 s), then sleeps.
- Reads for the visuals: `point(i)`, `torso()` (the trunk's basis), `face()`, `toes(i)` (a
  trunk-frame direction carried onto the bone by the shortest turn), `is_settled()`.

**Drawing the fallen body** (`character_visuals.gd`, `_draw_fallen`): every part from its 3D
points seen from above, sorted by height (lowest first), so a standing body hides its legs under
the shoulders and a toppling one reveals them; lengths foreshorten as parts tip.
- Limbs are chains of tapered capsules between the projected joints (the true silhouette of a limb
  seen from any angle), widths per joint from `ragdoll_arm_widths` / `ragdoll_leg_widths` (hip,
  knee, calf, ankle) / `ragdoll_shoe_widths` / `ragdoll_neck_width`, so neighbours share a joint's
  width. A chain draws every segment a pixel wider in its outline tone first, then the fills, so its
  joints run together under one outline. Each fill maps a `limb_painter.gd` strip (shaded across,
  fabric for cloth) onto the capsule: sleeves (`body_color`), forearms and neck (`skin_color`),
  thighs and shins (`pants_color`), shoes (`shoe_color`, along `toes(i)`). Fists (`HandPainter`)
  turn along the forearm; the head (`HeadPainter`) to where the face looks, or front toward the neck
  when it looks up or down.
- The trunk is lofted: ellipse cross-sections across the spine, eased between
  `ragdoll_trunk_sections` (spine fraction, half-width, half-depth) and domed at both ends; its
  outline is the union of each neighbouring pair's hull — waisted and rounded from any side, the
  shoulder ellipse from above. It fills with the shirt, then the art of the side most turned to the
  camera mapped across it (UVs from that side's projected axes): the standing `BodyPainter`
  shoulders on top, or `torso_painter.gd` (a full strip: shirt with collar and buttons down to a
  belt, pants on the hips; the back with a seam and the backpack; a flank), then a 1 px outline.
- Wounds: each recorded impact sits on the trunk's surface around the body where it struck (its
  angle in the shoulders' frame) at a seeded height between waist and chest, drawn with
  `Deformation.draw_marks` only while that patch faces the camera — chest wounds on a body lying on
  its back, back wounds on one face down.
- A floor shadow per part (the trunk's is its outline) with each point shifted from the light by its
  height (`ragdoll_shadow_per_height`), drawn opaque inside a code-built `CanvasGroup` that carries
  the alpha, so overlaps don't stack. Redrawing stops once the body has settled.

**Bleeding out:** `blood_origin()` is the character's position while alive and its trunk's middle
once fallen (blood pools sample it). When the ragdoll first settles the character calls
`Physics.bleed_out(get_parent(), self, [get_rid()])`, so a pool spreads out from under the body.

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
  `hair_color`, `hair_style`, `backpack`, `pack_color`, and `pants_color` / `shoe_color` (seen once
  fallen). The defender preset wears a navy cap, khaki pants and brown shoes; the invader a dark
  beanie, gloves, a backpack and dark jeans. Proportions/defaults: `CharacterConfig.art_*`.

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
  (hand 0/1 = melee, −1 = shot), `died` (`is_dead`).
  Observers (debug HUD, camera) attach by exported node path and read only the public API/signals.
- **Character → Art** (interface 12): the body, head, hand, limb and trunk painters render through
  `PixelArt.render_turned` / `snap_angle`, draw on `PixelCanvas`, and read `ArtConfig`.
- **Character → Physics** (interface 4): `Deformable` / `Deformation` for wounds, `spawn_blood` on a
  hit, and the generic `Ragdoll` the fallen body is built on.
- **Items ↔ Character** (interface 6): the character API an item may call — `facing`,
  `punch(hand)`, `hand_position(hand)`, `hand_world(hand)`, `muzzle_origin(hand)`, `world_root()`,
  `report_shot(body, dmg)`, `kick(hand)`, `weapon_facing()`; and reads the item's
  `aiming_hands()`, calling its `drop(user, velocity)` on death.

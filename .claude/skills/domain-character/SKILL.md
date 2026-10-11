---
name: domain-character
description: Deep implementation detail for the Character domain (scenes/character/) — the player character (built so other character types can exist): facing, movement, the full standing body (arms, legs, feet on a solved skeleton), hand stances, the punch, death and the ragdoll fall, and the control/animate/draw layering. Use when editing scenes/character/ or working on character movement, facing, hands and arms, how a weapon is held, punch hit detection, the walk cycle, death / the fallen body, or the player/NPC scene wiring. Complements the `architecture` skill, which holds the cross-domain interfaces.
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
  punch hit detection; exposes `hand_position(i)`, `punch_amount(i)` and the `punched` signal.
  `character_pose.gd` (a `RefCounted` the character owns as `pose`) owns the living motion of head,
  shoulders, hips and hands, and each hand's stance (below); `character_rig.gd` (a `RefCounted`
  solved fresh by `character.rig()`) owns the standing skeleton, the 3D joints of the arms and legs
  (below); `character_ragdoll.gd` (owned as `ragdoll` once dead) owns the fall.
- **Draw** (`character_visuals.gd`) owns appearance: a drop shadow, the legs and shoes, the arms
  (sleeve, then forearm), the shoulders (at the pose's lunge), the head (with its shadow on the
  shoulders), then `item.draw_weapon()`, then both fists (on top, gripping the weapon), then the
  wound marks over all of it. Once dead it draws the fallen body instead (below).
  **A standing body is repainted only when its drawing changes.** Each frame `_process` solves the rig once
  (shared by the body's and the shadow's draw) and rounds its inputs to a key: every joint and foot, the
  shoulder / head / fist / weapon angles, the held slot, and the wound count and damage. The key is rounded
  to `REDRAW_POS_STEP` (0.1 px) and `REDRAW_ANGLE_STEP` (0.02 rad), below a visible pixel at the body's
  size; `queue_redraw()` (body and shadow) runs only when the key changes. A character standing still drifts
  by less than a step most frames (breath, glance), so it repaints about once in 15 frames; a walking one
  every frame. `redraws` counts the standing body's draws for tests. A new input to the standing draw must
  join `_redraw_key_of`, or the body will not repaint when it changes. Test:
  `tests/character/standing_body_repaints_on_change_test.gd`; the idle crowd's frame cost is guarded by
  `tests/physics/crowd_deaths_stress_test.gd`.

## Pose (the living motion)

`character_pose.gd` layers motion over the aim; it is visual only (aim, shots and punches stay on
`facing`). `character.gd` steps it with `pose.update(delta, facing, get_real_velocity(), speed,
stances, punch)` (`stances` = the held item's `hand_stance(0)` / `(1)`, `punch` = `Hands.punch_amounts()`)
right after `move_and_slide()` (and with zero velocity while busy in an interaction; a dead
character stops stepping it), before the Hands child's `_physics_process`, so hands build on this
frame's pose.
- `head_angle`, `hand_angles[hand]`, `weapon_angle`, `torso_angle` each chase `facing` on their
  own damped angular spring — the head first, a steady hand next, the weapon a touch behind the
  hand holding it, each free hand at its own pace (`pose_hand_pace_spread`), the shoulders last —
  so a turn ripples through the body. Past its `max_lag` a part is reeled in at `pose_lag_catch`
  rather than snapped, so a sudden flick stays continuous.
- **Hips:** `hip_angle` (the feet's facing) is planted while standing, so the shoulders twist over
  feet that stay put, and turns to the walking direction while walking (a backward step keeps the
  feet facing the aim). The shoulders may twist `pose_hip_twist` off the hips before the feet
  re-plant toward the aim.
- A stride phase advances with distance walked: the shoulders sway, free hands swing fore/aft in
  opposite phase (their stance's `swing`) while a steady hand only drifts sideways
  (`hand_offset(hand)`), the head bobs per step, and the rig strides the feet. `head_offset` leans
  the head into the movement on a soft spring plus a slow breath; standing still the head also
  glances a little off the aim. Each character gets a random phase.
- **Punch mechanics:** the fist lands about 51 px from the body centre but an arm is 38 px, so a
  punch commits the body, following the fist's extension: `torso_angle` includes a twist toward the
  punching side (`pose_punch_twist`; it sits on top of the spring's own angle, so wounds recorded
  against it stay consistent) and `torso_offset` lunges the upper body along `facing`
  (`pose_punch_lunge`; the head's `head_offset` includes it). The rig adds a capped residual shoulder
  lean-in.
- **Stances:** each hand eases (`stance_ease`) toward the stance its item names. `rest_forward(hand)`,
  `rest_lateral(hand)`, `grip_height(hand)` and `elbow_pole(hand)` are the eased values the hands layer
  and the rig read.
- `weapon_angle` is published as the character's `weapon_facing()`, which an item draws its weapon
  along.
- `kick(hand)` (the character's `kick`, called by the pistol on firing) throws the hand back on a
  recoil spring and twists the shoulders back on its side; the other hand feels its stance's
  `recoil_share` (a supporting hand recoils with the weapon hand).
- Tuning: `CharacterConfig.pose_*` (per-part spring `freq` / `damping` / `max_lag` for head, steady
  hands, weapon, free hands, shoulders and hips; lag catch, hand pace spread, hip twist, stride,
  sway, steady drift, punch twist and lunge, bob, lean, breath, glance, recoil) and
  `CharacterConfig.stances` / `stance_ease`.

## Stances (how a hand is held)

`CharacterConfig.stances` is a data table: stance name → `forward` / `lateral` (px, in the hand's
pose frame, from the body center), grip `height` (body radii, for the arm's IK), walk `swing` (px),
`steady` (aim-style spring: follows the aim closely, only drifts), `recoil_share` and `elbow_pole`
(out, forward, up). The held item picks one per hand through `Item.hand_stance(hand)`: `relaxed`
(arms hanging; unarmed, key), `guard` (fists up; fists), `aim` (the weapon arm reaching out) and
`support` (the other hand cupping it: the pistol's two-handed hold). To add a pose, add a table row
and have an item name it. `CharacterConfig.muzzle_ahead` is how far past the weapon hand bullets
leave (`muzzle_origin(hand)`).

## The rig (the standing skeleton)

`character_rig.gd` solves the body's 3D joints (local x/y plus height z) from the live pose and the
hands, every time `character.rig()` is called (cheap; no cache). It exposes them through `point(i)`
by index (`HEAD`, `CHEST`, `PELVIS`, `BELLY`, `SPINE` and per-side `SHOULDER`, `HIP`, `ELBOW`,
`HAND`, `KNEE`, `ANKLE`; side 0/1 matching the hands) and each foot's direction through `toes(i)`.
`character_ragdoll.gd` re-exports the same indices.
- Upper body: chest and shoulders sit in the pose's twisted torso frame, shifted by `torso_offset`;
  hips and feet in its `hip_angle` frame. Proportions are `CharacterConfig.body_*`, in body radii
  (shoulders at `body_shoulder_height`, hips at `body_hip_height`, arms `body_upper_arm` +
  `body_forearm` ≈ 38 px, legs `body_thigh` + `body_shin`).
- Arms: two-bone IK (`_bend`) from each shoulder to where the hands layer holds the fist, at the
  stance's grip height, the elbow toward the stance's pole. If the hand is out of reach
  (`body_arm_extension` of the arm's length) its shoulder follows it, up to `body_shoulder_reach`;
  past that the forearm stretches a little.
- Legs: each ankle strides along the hips' forward by `body_stride`, in opposition to the arm on its
  side, lifting `body_foot_lift` as it swings through; the knee is IK bent forward; toes follow
  `hip_angle`.
- The same rig is what the ragdoll starts from, so a body dies in exactly the pose it was drawn in.
- Test: `tests/character/standing_body_rig_test.gd` (bone lengths, stances, punch landing, hips,
  stride, death continuity).

## Death and the fall (the ragdoll)

`_apply_damage(amount, direction)` (shared by `take_hit`, which passes the shot's direction, and
`take_damage`, the punch path) calls `_die(direction)` at zero health. `_die` leaves layer 1 and
moves to `CharacterConfig.ragdoll_z_index` (beneath the living, above blood pools), ends any
interaction, builds `ragdoll` from the rig's joints with the body's momentum (walk + knockback,
including the killing blow's shove), lets go of the held item (`Item.drop(self, momentum + toss)`;
a returned node removes the slot, so `current_item()` may be null on a corpse), then emits `died`.
While dead `_physics_process` only steps the ragdoll (`step(delta, space, global_position)`); the
pose and hands stop.

`character_ragdoll.gd` builds a humanoid on the Physics domain's generic `Ragdoll` (3D points
over the floor: local x/y + height z), its indices the rig's (`HEAD`, `CHEST`, `PELVIS`, `BELLY`,
`SPINE`, and per-side pairs `SHOULDER`, `HIP`, `ELBOW`, `HAND`, `KNEE`, `ANKLE`, side 0/1 matching the
hands):
- A rigid trunk (chest, pelvis, belly and back, shoulders, hips): the belly/back radii reach just
  to the trunk's surface so it lies flat on either side. Bones to the head, elbows, fists, knees and
  ankles.
- Limits in the trunk's frame (x toward hand 1's shoulder, y up the spine, z out of the chest):
  swing cones at the neck (rest up), shoulders and hips (rest down, out/in mirrored per side), and
  one-way hinges at the elbows (bend toward the front) and knees (toward the back), so no joint
  ever bends backward. Ranges are `CharacterConfig.ragdoll_*_limits` / `_bend` / `_slack` (degrees).
- Starts exactly in the rig's pose (`character_rig.gd`): trunk upright turned to `pose.torso_angle`,
  head at `head_offset`, fists where the hands hold them (elbows by two-bone IK), feet striding
  under the hips, knees a touch bent.
- Launch: every point carries the momentum, the upper body is pushed along the blow
  (`ragdoll_hit_topple`, fading to nothing at the hips; weaker and along the momentum or a random
  way with no blow), the knees buckle forward (`ragdoll_knee_buckle`) and each point gets a random
  jolt (`ragdoll_jitter`). The legs give out, then the body topples and settles (≈ 2–3 s), then sleeps.
- Reads for the visuals: `point(i)`, `torso()` (the trunk's basis), `face()`, `toes(i)` (a
  trunk-frame direction carried onto the bone by the shortest turn), `is_settled()`.

**Drawing the fallen body** (`character_visuals.gd`, `_draw_fallen`): every part from its 3D
points seen from above, sorted by height (lowest first), so a standing body hides its legs under
the shoulders and a toppling one reveals them; lengths foreshorten as parts tip. The order carries
over from the last frame (`_stack`): a pair swaps only once their heights differ by more than
`STACK_BAND`, so a limb lying across the trunk doesn't flicker over and under it. Test:
`tests/character/fallen_draw_order_stable_test.gd`.
- Limbs are chains of tapered capsules between the projected joints (the true silhouette of a limb
  seen from any angle), widths per joint from `body_arm_widths` / `body_leg_widths` (hip,
  knee, calf, ankle) / `body_shoe_widths` / `body_neck_width`, so neighbours share a joint's
  width. A chain draws every segment a pixel wider in its outline tone first, then the fills, so its
  joints run together under one outline. Each fill maps a `limb_painter.gd` strip (shaded across,
  fabric for cloth) onto the capsule: sleeves (`body_color`), forearms and neck (`skin_color`),
  thighs and shins (`pants_color`), shoes (`shoe_color`, along `toes(i)`). Fists (`HandPainter`)
  turn along the forearm; the head (`HeadPainter`) to where the face looks, or front toward the neck
  when it looks up or down.
- The trunk is lofted: ellipse cross-sections across the spine, eased between
  `ragdoll_trunk_sections` (spine fraction, half-width, half-depth) and domed at both ends; its
  outline is the union of each neighbouring pair's hull — waisted and rounded from any side, the
  shoulder ellipse from above. Each hull grows by `HULL_OVERLAP` so neighbours overlap in area
  (seen edge-on they share only a line, and the union can come apart, flashing the torso as one
  small slice for a frame as the body landed); a union still in pieces falls back to the two slices'
  convex hull. Test: `tests/character/fallen_trunk_outline_steady_test.gd`. It fills with the shirt, then the art of the side most turned to the
  camera mapped across it (UVs from that side's projected axes): the standing `BodyPainter`
  shoulders on top, or `torso_painter.gd` (a full strip: shirt with collar and buttons down to a
  belt, pants on the hips; the back with a seam and the backpack; a flank), then a 1 px outline.
- Wounds: each recorded impact sits on the trunk's surface around the body where it struck (its
  angle in the shoulders' frame) at a seeded height between waist and chest, drawn with
  `Deformation.draw_marks` only while that patch faces the camera — chest wounds on a body lying on
  its back, back wounds on one face down.
- A floor shadow per part (the trunk's is its outline) with each point shifted from the light by its
  height (`body_shadow_per_height`), drawn opaque inside a code-built `CanvasGroup` that carries
  the alpha, so overlaps don't stack. Redrawing stops once the body has settled.

**Bleeding out:** `blood_origin()` is the character's position while alive and its trunk's middle
once fallen (blood drips and pools sample it). When the ragdoll first settles the character calls
`Physics.bleed_out(get_parent(), self, [get_rid()])`, so a pool spreads out from under the body.

## Pixel art

The character is top-down pixel art rendered through the Art domain (interface 12):
- Four private painters, each its own part: `body_painter.gd` — shoulders in the shirt color
  (`body_color`) with sleeve seams, the dark neck ring and an optional backpack with straps;
  `head_painter.gd` — skin with ears and a nose toward the front under a `hair_style` (`short` /
  `long` / `buzz` / `beanie` / `cap`) in `hair_color`, on its own canvas (`radius_for(width)`,
  `canvas_for(r)`); `hand_painter.gd` — a fist with knuckles to the front and the thumb on the
  inner side (`side`); `limb_painter.gd` — the shaded strip of one arm, leg or shoe segment, which
  the visuals map onto the limb's tapered capsule between two rig joints (the same drawing the
  fallen body uses: `_arm_chain` / `_leg_chain` / `_draw_chain`). Standing, the sleeve and forearm
  of each arm and the leg and shoe on each side draw under or around the shoulders (legs lowest,
  then arms, then the shoulders at `torso_offset`).
- `character_visuals.gd` renders each with `PixelArt.render_turned(..., snap_angle(angle), ...)` —
  lit for the nearest of `ArtConfig.turn_steps` steps — and draws it rotated to the exact angle of
  its part from the pose: the shoulders at `torso_angle`, the head at `head_angle` shifted by
  `head_offset`, each hand at its `hand_angles[hand]`. Each goes through `Deformation.draw_shape(..., texture,
  texture_angle, false)` so shots dent the art and darken it, then `Deformation.draw_marks` once
  on top in the flesh crack/hole/scorch colors. The head casts its shadow onto the shoulders (its
  silhouette `ArtConfig.cast_shadow_px` away from the light at `cast_shadow_darken`). The floor
  shadow (living and fallen alike) is one `CanvasGroup` of opaque shapes carrying
  `ArtConfig.drop_shadow_alpha` — the shoulders' own deformed silhouette, each limb's capsule, the
  fists and the head — every point shifted away from the light by `body_shadow_per_height × height`,
  so overlaps don't darken twice. It is redrawn with the body (see the Draw layer above), so only when
  the standing body's drawing changes.
- **Wounds turn with the shoulders:** `take_hit` records impacts relative to them
  (`Deformable.record(hit, pose.torso_angle)`) and the visuals turn them back to the current
  `torso_angle`, so a dent stays on the shoulder or hand that was hit. A part (hand or head) is
  dented by the shots whose path
  crossed it before they struck the body: each is re-seated where the shot entered the part, its
  depth scaled by part size / body radius. A hand mid-punch has left its wounds behind. Limbs are
  not dented (shots hit the body circle). While the upper body lunges, wounds move with it.
- Look exports on `Visuals`: `body_color`, `hand_color` (skin or glove), `skin_color`,
  `hair_color`, `hair_style`, `backpack`, `pack_color`, and `pants_color` / `shoe_color` (the legs and shoes, seen
  where they stride out from under the body). The defender preset wears a navy cap, khaki pants and brown shoes; the invader a dark
  beanie, gloves, a backpack and dark jeans. Proportions/defaults: `CharacterConfig.art_*`.

Ordering: a parent's `_physics_process` runs before its children's, so the hands see the
character's fresh `facing`, and the character pulls its controller's intent at the top of its own
`_physics_process` (lag-free).

## Walking into furniture

`_apply_pushes()` shoves each pushable the body slid into with `push_impulse` per *second* of contact
(× `delta`), capped so the object is carried at no more than `speed × push_carry_factor` along the
push (it is never launched ahead of the walker; the cap uses the walker's intent along the contact normal).
The body runs in `MOTION_MODE_FLOATING` (top-down: no floor), otherwise a body it walks "down" into would be ridden as a platform and lend the character its launch velocity. The resulting slow-down (`push_slow_per_weight`,
floored by `push_slow_min`) applies at once but eases back at `push_slow_release`/s, so a lost-contact
frame doesn't snap speed. Test: `tests/character/walk_into_furniture_speed_test.gd`.

## Facing & hands

- **Facing:** `character.gd` points `facing` from itself to `aim_point` (the mouse, set by the
  controller) each frame. The node is never rotated, so hand math stays in local space.
- **Hands:** two circles at a rest pose built in each hand's pose frame (`hand_angles[hand]` + its
  perpendicular): the hand's stance (`pose.rest_forward` / `rest_lateral`, from
  `CharacterConfig.stances`) plus `pose.hand_offset(hand)` for walk swing and recoil, the punch
  extending straight along `facing`, collision-resolved so they rest on walls/objects (the rig's
  arm just bends more when a wall pulls the hand in). Tunable via `character_hands.gd`'s exports:
  `hand_radius` and `punch_gap`. A punch swings the fist from its rest pose to `punch_gap + reach`
  beyond the body edge (`swing = radius + hand_radius + punch_gap + reach − rest_forward`), so the
  stance doesn't change how far a punch lands.

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
`player_controller.gd`. `character/character_base.tscn` is the bare character (body, shape, Hands,
Visuals) with **no controller**: a composer adds any `control()` child before it enters the tree
(`_find_controller()` runs at `_ready`) — the Testing domain adds its puppet `ScriptedController` or
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
- **Character → Physics** (interface 4): `Deformable` / `Deformation` for wounds, a `BloodWound`
  child (splatter spray + timed drips on a hit, stopped on death), and the generic `Ragdoll` the fallen body is built on.
- **Items ↔ Character** (interface 6): the character API an item may call — `facing`,
  `punch(hand)`, `hand_position(hand)`, `hand_world(hand)`, `muzzle_origin(hand)`, `world_root()`,
  `report_shot(body, dmg)`, `kick(hand)`, `weapon_facing()`; and reads the item's
  `hand_stance(hand)` (how each hand is held), calling its `drop(user, velocity)` on death.

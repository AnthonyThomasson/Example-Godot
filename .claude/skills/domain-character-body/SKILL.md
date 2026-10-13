---
name: domain-character-body
description: Deep implementation detail for the Character body sub-domain (scenes/character/body/) — the standing skeleton and its solved joints (CharacterRig), the living motion of head, shoulders, hips and hands (CharacterPose), leg/foot clamping against walls (CharacterLegs), hand geometry, the punch and its hit detection (CharacterHands), the ragdoll fall on death, and all the drawing (CharacterVisuals: standing body, fallen body, shadows, wounds) through the body/head/hand/limb/torso pixel-art painters. Use when editing scenes/character/body/ or working on the walk cycle, run pose, crouch look, how a weapon is held (stances), punch detection, the fallen body, the character's pixel art or redraw key. Complements the `domain-character` overview and the `architecture` skill.
---

# Character · Body sub-domain (`scenes/character/body/`)

Everything that gives the character a body: `character_rig, character_legs, character_pose, character_ragdoll, character_hands`
(animate; `body_sweep` is the collide-and-slide the hands and legs share) and `character_visuals` plus the `body / head / hand / limb / torso` painters (draw). `character.gd` (the root body, see
`domain-character`) owns state and physics and steps these each frame; nothing here decides what the character *does*. Cross-domain
edges: `Deformable` / `Deformation` and the generic `Ragdoll` (Physics), `PixelArt` / `PixelCanvas` / `ArtConfig` (Art, interface 12), and
`CharacterConfig` (this domain's tuning holder, in `character/`). `character_base.tscn` attaches
`character_hands.gd` and `character_visuals.gd` as the `Hands` / `Visuals` children (the NPC scenes and `main.tscn`'s `Player` inherit or instance it); the rest are `RefCounted` helpers the character owns.

## Animate and draw

- **Animate** (`character_hands.gd`, a child `Node2D`) owns hand geometry, the punch tween, and
  punch hit detection; exposes `hand_position(i)`, `punch_amount(i)` and the `punched` signal.
  `character_pose.gd` (a `RefCounted` the character owns as `pose`) owns the living motion of head,
  shoulders, hips and hands, and each hand's stance (below); `character_rig.gd` (a `RefCounted`
  solved by `character.rig()`, once per physics frame) owns the standing skeleton, the 3D joints of the arms and legs
  (below); `character_ragdoll.gd` (owned as `ragdoll` once dead) owns the fall.
- **Draw** (`character_visuals.gd`) owns appearance: a drop shadow, the legs and shoes, the arms
  (sleeve, then forearm), then `item.draw_weapon()` (under the torso, so a long gun's butt is tucked behind the shoulder), the shoulders (at the pose's lunge), then both fists (gripping the weapon; a hand gripping below `HAND_OVER_HEIGHT`, i.e. hanging relaxed, is drawn *before* the shoulders so they cover it — `tests/character/hanging_hands_under_shoulders_test.gd`), then the
  head last (it is the highest part, so it covers the gun and fists; its shadow falls on the shoulders), then the
  wound marks over all of it. A crouch (`_draw_lying`) keeps the same order: the head leaves the fallen-body stack and is drawn after the fists.
  `draw_order` records what the last living draw painted (`weapon`, `torso`, `hands`, `head`) for `tests/character/head_over_gun_test.gd`. Once dead it draws the fallen body instead (below).
  **A standing body is repainted only when its drawing changes.** Each frame `_process` solves the rig once
  (shared by the body's and the shadow's draw) and rounds its inputs to a key: every joint and foot, the
  shoulder / head / fist / weapon angles, the weapon raise (`REDRAW_RAISE_STEP`), the held slot, and the wound count and damage. The key is rounded
  to `REDRAW_POS_STEP` (0.1 px) and `REDRAW_ANGLE_STEP` (0.02 rad), below a visible pixel at the body's
  size; `queue_redraw()` (body and shadow) runs only when the key changes. A character standing still drifts
  by less than a step most frames (breath, glance), so it repaints about once in 15 frames; a walking one
  every frame. `redraws` counts the standing body's draws for tests. A new input to the standing draw must
  join `_redraw_key_of`, or the body will not repaint when it changes. Test:
  `tests/character/standing_body_repaints_on_change_test.gd`; the idle crowd's frame cost is guarded by
  `tests/perf/crowd_deaths_stress_test.gd`.
  **A body the camera cannot see is not drawn at all.** `_process` first asks `_in_view()`: the viewport's visible rect
  taken into world space through its canvas transform, grown by `CULL_MARGIN` (120 px, the longest reach of a limb or a
  held gun past the body centre). Outside it nothing is solved or repainted, standing or fallen, and its last drawing stays
  unseen; the redraw key is cleared so the first frame back in view repaints. A test whose camera does not frame a body it
  reads the drawing of (the spectator camera drops the dead from its framing) keeps it in view with `camera_follow`
  (`tests/character/fallen_draw_order_stable_test.gd`). Test: `tests/character/offscreen_body_is_not_drawn_test.gd`.

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
- `kick(hand, strength := 1.0)` (the character's `kick`, called by a gun on firing with its `recoil`) throws the hand back on a
  recoil spring and twists the shoulders back on its side, `strength` times a pistol's; the other hand feels its stance's
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
`support` (the other hand on the grip beside the aim hand: both fists at the same forward point, 2 px either side of the aim line, so they grip the pistol together) and `reload` (that hand dropped to the belt
for the next magazine, named by a gun's support hand while it reloads). The long guns have their own pairs, sized by the gun: `smg_grip` / `smg_fore`
and `rifle_grip` / `rifle_fore` (the butt in the right shoulder; the SMG's barrel line is 9 px to the character's right of the aim line, the rifle's only 5 px so it is held up in front of the face as if looking down the sight; the grip hand
just ahead of it, the other hand out along the handguard); both hands lie on one line along the barrel (hand 0 at +`lateral`, hand 1 at
−`lateral`) and an arm's stretch stays within the rig's tolerance. `ready_grip` / `ready_fore` are the shared **raised** pair (below).
A `run` stance (arms down, big swing) is applied to both hands by the character itself while running, whatever is held. To add a pose, add a table row
and have an item name it. `Item.muzzle_ahead()` is how far past the weapon hand bullets
leave (`muzzle_origin(hand)`); `Character._muzzle_ahead(item)` falls back to `CharacterConfig.muzzle_ahead` for an item whose `muzzle_ahead()` is negative (the base `Item`), so Items never read Character's config.

## The rig (the standing skeleton)

`character_rig.gd` solves the body's 3D joints (local x/y plus height z) from the live pose and the
hands. `character.rig()` solves it once per physics frame and hands every caller in that frame the same rig (the pose,
the hands and the feet's rests change only in `_physics_process`; selecting a slot, taking a posture and dying drop the
cached one at once, since they change its inputs mid-frame), so the draw, a footfall and a test share one solve; the
legs layer solves its own unclamped rig (`Rig.new(character, false)`). `CharacterRig.solves` counts every solve for
`tests/character/rig_is_solved_once_per_frame_test.gd`. It exposes the joints through `point(i)`
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
  camera mapped across it (UVs from that side's projected axes; the art is requested at whole pixels, because the spine's
  length flexes every frame and an exact size would paint and cache a new texture each frame): the standing `BodyPainter`
  shoulders on top, or `torso_painter.gd` (a full strip: shirt with collar and buttons down to a
  belt, pants on the hips; the back with a seam and the backpack; a flank), then a 1 px outline.
- Wounds: each recorded impact sits on the trunk's surface around the body where it struck (its
  angle in the shoulders' frame) at a seeded height between waist and chest, drawn with
  `Deformation.draw_marks` only while that patch faces the camera — chest wounds on a body lying on
  its back, back wounds on one face down.
- A floor shadow per part (the trunk's is its outline) with each point shifted from the light by its
  height (`body_shadow_per_height`), drawn opaque inside a code-built `CanvasGroup` that carries
  the alpha, so overlaps don't stack. Redrawing stops once the body has settled.

## Look when crouched, and the legs

- **Look:** the drawn body eases into the posture (`_posture_height`, `posture_ease`; read through `posture_height()` / `posture_folded()`). The rig
  (`character_rig.gd`) scales the standing hip height (and the hands' grip heights) by the height and, as the body
  folds, pitches the spine forward about the pelvis (`body_crouch_pitch`, 25°; the pelvis shifts back and the chest forward by half the lean so the body
  stays centred over its feet, and the neck pitches on, `body_crouch_neck_pitch`), narrows the hips and feet (`body_crouch_hip_width` /
  `body_crouch_foot_gap`), stands the feet ahead of the pelvis so the knees lead (`body_crouch_foot_ahead`), staggers the weapon hand's foot back
  (`body_crouch_stagger`) and shortens the stride (`body_crouch_stride`). The rig also answers `torso()` and `face()`, so a body folded past
  `FOLD_DRAW` is drawn by `_draw_lying`: `_draw_fallen(rig, false, weapon)` (a lofted trunk showing its back, the limbs by height), then the weapon and
  fists on top, with its shadow from `_draw_fallen_shadow`.
  **Arms:** the shoulders sprite and head are drawn at the rig's `CHEST` / `HEAD` xy (`shoulder_centre()` / `head_centre()` on the visuals), so a
  crouch's forward lean carries them with the sleeves. `posture_hand_ahead()` (`body_crouch_hand_ahead` x `posture_folded()`) is added to every
  hand's stance `forward` (`CharacterHands._raw_hand_position`) and to the wall-raise ray's reach, so the arms keep their reach past the leaning
  chest. **A long gun at a wall:** `_blocked` is judged in every posture and the gun is raised (`raised_stance`) whatever the posture. A pistol is
  never blocked: the wall pushes its hand back.
- **Legs** (`character_legs.gd`, a `RefCounted` stepped after the pose; spec P5): each ankle is swept from the body centre to where the unobstructed rig
  (`CharacterRig.new(self, false)`) would put it (a `leg_radius` circle through `body_sweep.gd`, as the hands are) and rests at the first wall, solid piece
  or character it meets, sliding the leftover; a knee that would pass through something moves the foot back (`KNEE_TRIES`); the rig reads the result
  through `foot_clamp(i)` (null = unobstructed) and re-solves the knee (`CharacterRig.knee_at`). A foot or knee swinging into a pushable
  (`apply_impulse` + `get_mass`, never another character) shoves it by `leg_push_impulse` scaled by its world speed into the piece and how far it wanted
  to go, capped at walking pace like the body's push; a foot at rest pushes nothing. Nothing is cast unless something is within `NEAR` px; cleared while
  busy in an interaction and on death.

**The run's legs and arms.** `pose.run_amount()` (0..1, smoothed from the speed past walking pace) blends the rig's
foot swing and lift from `body_stride` / `body_foot_lift` to `body_run_stride` / `body_run_foot_lift`, the stride
length from `pose_stride_length` to `pose_run_stride_length`, and sinks the hips by `body_run_hip_drop` so the knees
stay bent. A planted foot only stays put on the ground when the stride is 2π × the foot's swing (~130 px); shorter and
the feet scurry and everything stride-locked wobbles at 3+ Hz. While `_running`, `_stances()` ignores the held item
and puts both hands in the `run` stance: arms pumping at the sides, a pistol simply carried in its hand, and the
`stance_ease` blend lifts it back to aim on stopping. `grip_height` adds `pose_run_hand_rise` so the forward-swinging
hand rises toward the chest and the back one drops to the hip (keep the lowest ≥ ~4.1 body radii or the arm
overstretches). An elbow's bend lies in the plane through the shoulder, the hand and the pole, so `elbow_pole` adds
`pose_run_elbow_lift` of vertical swing with the arm (down under a forward hand, up behind a back one); a fixed pole
would throw the elbow out sideways at one end of the swing.

**The run's shoulders.** Added over the torso spring (too slow to follow a stride) and scaled by `run_amount()`: the
shoulders counter-rotate by `pose_run_sway` (the one on the forward-swinging arm's side comes forward), lead the hips by
`pose_run_lean` along the travel direction, and shift `pose_run_shoulder_shift` px sideways over the planted foot each
step. The lean and the side shift go through `torso_offset`, so the rig, wounds and fall follow; the counter-rotation is
added to `torso_angle`. The lean is in `head_offset` (the head
leads); the side shift is added after it, so the head stays steady over the rocking shoulders.
Test: `tests/character/run_pose_test.gd`.

## Pixel art

The character is top-down pixel art rendered through the Art domain (interface 12):
- Five private painters, each its own part: `body_painter.gd` — shoulders in the shirt color
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

## Hands and the punch

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
`punch_damage` (walking push tuned by the same holder). A long gun's butt strike (`domain-items`) shortens the hand's extension by `Item.strike_forward()` + `strike_short()` and queries the hit at the butt (`Item.strike_end`) once it is ahead of the fist; the other hand is placed rigidly on the barrel (`_raw_hand_position`: the weapon hand's place plus `strike_direction` x `strike_support_gap()`, toward the butt, gripping from the first frame of the swing) so both arms follow the turning gun, the swing takes `strike_tempo()` times a fist's extend/retract time (the damage's range of motion is normalised by it), and the redraw key carries both hands' punch amounts, since the gun turns with them.

## The leg kick

`character_kick.gd` (a `RefCounted` the character owns as `_kick`, stepped each physics frame after `move_and_slide` and before
`pose.update`) is the leg kick, independent of the held item and always with the right leg (side 0). `Character.leg_kick()` starts it (false when dead, crouched, in an interaction or a
kick is already under way), then a STRIKE (`kick_strike_time`, the foot thrown out) and a RECOVER
(`kick_recover_time`, drawn back) run; `amount()` is the foot's 0..1 extension, read by the rig through `character.leg_kick_amount(i)`.
The rig lifts the kicking ankle to `kick_foot_height` (body radii) first and throws it out along `facing` (never past `kick_reach` or the
leg's length at that height), the knee bent up toward the aim and the toes following; the other leg keeps striding. During the strike a
circle of `kick_radius` at `kick_reach * amount()` ahead of the body centre is queried on `PhysicsLayers.SOLID`: each body is hit once
per kick, shoved by `kick_impulse` along `facing` (`apply_impulse`) and dealt `kick_damage` (`take_damage`) at full strength, then
`kicked(body, damage)` → the character posts `hit_landed(body, damage, 2)` and the `&"hit"` event with outcome `punch` (so it sounds like
a punch; louder for its damage), like a punch it never deforms. The legs layer rests the thrown foot against walls like any other. Cleared
on an interaction and on death. Tuning: `CharacterConfig.kick_*`. Tests: `tests/character/kick_*_test.gd`.

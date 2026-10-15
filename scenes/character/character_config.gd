class_name CharacterConfig

## Tuning for a Character walking into / being shoved by world objects, being shot, being stunned, its
## pixel art, its body, hand stances and pose, and its fall on death (scenes/character/). A `class_name` holder of `static var`s — read as
## `CharacterConfig.<name>`; there is no instance and no autoload.
##
## Walking the character body into a pushable object (anything exposing `apply_impulse`
## — i.e. furniture, not walls) shoves it via the same impulse pipeline a projectile
## uses, divided by the object's mass. Pushing also slows the character (heavier =
## slower), and a fast object sliding into the character shoves them back.

# --- Postures (the body's height: stand or crouch; a controller picks one with `set_posture`) ---
# Not to be confused with `stances` below (how a hand is held). A posture trades speed for a smaller target:
# `speed` multiplies the walk speed; `turn` is the fastest the body swings round to the aim (rad/s, 0 = at once);
# `coverage` is the body's height on the same 0–100 scale as an object's
# coverage (a bullet carries one height, and strikes whatever is taller than it), so a lower posture is
# struck by fewer shots and hides behind lower cover; `height` scales the drawn body's standing heights.
# Keep `crouch` coverage at or below the AI's `cover_min` (40), so everything it treats as cover hides a crouch.
static var postures: Dictionary = {
	&"stand": { "speed": 1.0, "turn": 0.0, "coverage": 60.0, "height": 1.0 },
	&"crouch": { "speed": 0.6, "turn": 5.0, "coverage": 35.0, "height": 0.62 },
}
## Seconds after a posture change before the next one is allowed, so a controller can't flicker between them.
static var posture_change_time: float = 0.25
## How fast the drawn body eases into a new posture (1/s): the share of the way per second.
static var posture_ease: float = 9.0

## Base impulse per second of contact the character imparts to an object, scaled by how
## hard the character is moving into it (input strength 0–1). Frame-rate independent.
static var push_impulse: float = 54000.0
## How much each unit of the pushed object's `mass` reduces the character's speed while
## pushing (speed_mult = 1 − heaviest_mass × this, floored by `push_slow_min`).
static var push_slow_per_weight: float = 0.02
## Floor on the character's speed multiplier while pushing.
static var push_slow_min: float = 0.15
## Fraction of the character's walk speed an object it pushes may be driven up to (1 = it is
## carried at walking pace, never launched ahead of the character).
static var push_carry_factor: float = 1.0
## How fast (multiplier units per second) the push slow-down eases back to full speed once
## contact is lost, so a one-frame gap doesn't snap the character's speed.
static var push_slow_release: float = 3.0
## The character's mass for *incoming* knockback: an object sliding into the character
## shoves them by impulse / this. Higher = the character shrugs off hits unless struck hard.
static var player_mass: float = 40.0
## Deceleration (px/s²) that bleeds the character's knockback velocity back to zero.
static var push_knockback_friction: float = 1600.0

# --- Running (a controller sets `run_input`; stamina is spent only while moving) ---------

## Walk-speed multiplier while running.
static var run_speed_mult: float = 1.7
## Seconds of continuous running a full stamina bar lasts.
static var run_stamina_seconds: float = 4.0
## Stamina (fraction of a full bar) regained per second when not running.
static var stamina_regen_per_sec: float = 0.2
## After running dry the character walks until stamina refills to this fraction.
static var run_resume_fraction: float = 0.3
## Smallest `move_input` length that counts as moving, so holding run while standing spends nothing.
static var run_min_input: float = 0.1

## Base central impulse a full-extension punch imparts to a pushable object, scaled by the
## swing's range of motion (0 point-blank .. 1 full reach). A shoved RigidBody slides
## ≈ impulse / (mass × PhysicsConfig.body_linear_damp) before settling.
static var punch_impulse: float = 900.0
## Base damage a full-extension punch reports, scaled by the same range of motion. Surfaced
## through hit_landed for the HUD; a punch does not deform what it hits.
static var punch_damage: float = 8.0

# --- Being stunned (a grenade's flash and bang, `Character.take_stun`; docs/grenades.md G13) ---

## The most a stunned character moves of its speed (x0.45 at the full level).
static var stun_speed: float = 0.45
## Furthest (degrees) the aim sways off where it points at the full level; applied to where shots and throws go.
static var stun_sway: float = 25.0
## The effect tails off over the last this many seconds: the level falls linearly from 1 to 0 over them.
static var recover_tail: float = 1.5
## How fast (px/s) a stunned character drifts sideways of the way it walks, at the full level.
static var stun_drift: float = 20.0

# --- The leg kick (the right leg; character_kick.gd): harder than a punch, shorter in reach, and slower to come back ---
## Central impulse a kick imparts to a pushable object, and the damage it reports (both at full strength: a kick
## lands only while the foot is being thrown out).
static var kick_impulse: float = 2200.0
static var kick_damage: float = 14.0
## How far (px) from the body centre the foot is thrown along the facing, and the radius of the circle that strikes.
static var kick_reach: float = 44.0
static var kick_radius: float = 6.0
## Seconds the foot takes to be thrown out (the strike) and to be drawn back (no other kick starts meanwhile).
static var kick_strike_time: float = 0.09
static var kick_recover_time: float = 0.22
## How high (body radii) the thrown foot is held off the floor: it must stay within the leg's length of the hip.
static var kick_foot_height: float = 2.1

# --- Flesh: how a character reacts to being shot (the "hittable" contract) --------------
# Every value here is a tuning knob; a character reads them in _ready() / its visuals, so
# adjusting flesh damage response is a one-line change and needs no code edits.

## Material tag handed to the debris system; selects the blood chip style + tint.
static var flesh_material: String = "flesh"
## (The body's coverage is its posture's: see `postures`.)
## Resistance to being shot through, 0–100. Low: bullets tear through flesh.
static var flesh_penetration: float = 15.0
## Base color handed to debris styling; the "flesh" material re-tints chips blood-red, so
## this is only the color `get_surface()` reports.
static var flesh_color: Color = Color(0.85, 0.55, 0.5)
## Deepest a bullet dent may cave into the body silhouette (px). The central core keeps the
## deformed circle from folding, so this can be a large fraction of the body radius for
## pronounced dents without corrupting the polygon.
static var flesh_deform_max_depth: float = 9.0
## How many bullet dents the body remembers. Kept modest so dents from many angles don't
## saturate the small silhouette (recent hits replace old ones).
static var flesh_deform_max_impacts: int = 14
## Whether a hard hit carves a jagged "missing piece". Off for a small body: a chunk's reach
## would span the whole silhouette and fold it.
static var flesh_allow_chunks: bool = false
## Color of the cracks radiating from each bullet wound — a dark red, so hits read as
## bloody gashes rather than bright scratches.
static var flesh_crack_color: Color = Color(0.42, 0.05, 0.05)
## Color of the central bullet hole in each wound (the darkest part of the wound).
static var flesh_hole_color: Color = Color(0.25, 0.02, 0.03)
## Color of the faint scorch halo around each wound; dark red so it reads as bruising.
static var flesh_scorch_color: Color = Color(0.35, 0.02, 0.02)

# --- Where a round strikes, and what is worn (docs/outfits.md O2 to O4, O10) ---------------
# A bullet's height (0..100) over the posture's coverage picks the hit zone: up to each row's fraction, feet up; above the
# last, the head. The same fractions standing and crouched. A hit with no height (a frag's blast) strikes the whole body.

## `[zone, highest fraction]`, feet up; anything above the last row is the head.
static var hit_zones: Array = [[&"feet", 0.08], [&"legs", 0.45], [&"torso", 0.85]]
## The share of a round's damage each zone takes (melee, through `take_damage`, is not zoned).
static var zone_damage: Dictionary = { &"feet": 0.6, &"legs": 0.6, &"torso": 1.0, &"head": 2.0 }
## The side a round strikes: the angle (degrees) between the way back to the shooter and the shoulders' facing. Up to
## `side_front_deg` is the front, from `side_back_deg` the back, the flank between.
static var side_front_deg: float = 60.0
static var side_back_deg: float = 120.0  ## From this angle (degrees) on, the round strikes the back.
## What a body carries at its tuned speed (kg: ordinary clothes); only the outfit's weight above it slows and tires.
static var outfit_free_weight: float = 2.0
## Share of the move speed lost per kg worn above `outfit_free_weight` (a full plated kit, 12 kg over: about 8%), floored at
## `outfit_speed_min`.
static var outfit_speed_per_kg: float = 0.0067
static var outfit_speed_min: float = 0.6  ## The least share of the move speed an outfit's weight leaves.
## Extra share of stamina a run spends per kg worn above `outfit_free_weight` (the plated kit: about 1.3x).
static var outfit_stamina_per_kg: float = 0.025

# --- Pixel art (the body and hand painters; shared lighting/resolution is ArtConfig) ---
## Head radius as a fraction of the body's width.
static var art_head_size: float = 0.19
## Shoulder span depth (front to back) as a fraction of the body's width.
static var art_shoulder_depth: float = 0.54
## Default skin, hair and backpack colors (each character's visuals may override them).
static var art_skin_color: Color = Color(0.93, 0.76, 0.6)
static var art_hair_color: Color = Color(0.36, 0.24, 0.14)
static var art_pack_color: Color = Color(0.3, 0.32, 0.26)
## Default pants color (the legs and feet, seen where they stride out from under the body).
static var art_pants_color: Color = Color(0.22, 0.27, 0.4)

# --- Body (the skeleton the standing body is drawn from and the ragdoll falls from; character_rig.gd) ---
# Lengths are in body radii (a 14 px radius ≈ 0.225 m, half the shoulders), so a body stands
# ≈ 7.6 radii tall.
static var body_hip_height: float = 3.8        ## Hip joints above the floor (legs stand a touch bent).
static var body_shoulder_height: float = 6.3   ## Shoulder joints above the floor.
static var body_head_height: float = 7.2       ## Head center above the floor.
static var body_shoulder_width: float = 0.8    ## Each shoulder joint off the spine.
static var body_hip_width: float = 0.4         ## Each hip joint off the spine.
static var body_upper_arm: float = 1.35
static var body_forearm: float = 1.4           ## Elbow to the center of the fist.
static var body_thigh: float = 1.95
static var body_shin: float = 1.85             ## Knee to ankle.
static var body_foot: float = 1.0              ## Shoe length.
## How far an arm may stretch before its shoulder follows the hand (fraction of its length), and the
## furthest the shoulder joint follows a hand out of reach (body radii) — a punch's lean-in.
static var body_arm_extension: float = 0.98
static var body_shoulder_reach: float = 1.0
## How far each foot swings fore and aft mid-stride at full walking speed, and how high the
## swinging foot lifts (body radii).
static var body_stride: float = 0.85
static var body_foot_lift: float = 0.35
## The same at a full run: a longer, higher stride.
static var body_run_stride: float = 1.5
static var body_run_foot_lift: float = 0.6
## How far the hips sink at a full run (body radii): knees stay bent through the stride.
static var body_run_hip_drop: float = 0.35
## A crouch pitches the spine forward about the pelvis (degrees, at the crouch's height; the neck pitches on
## from the shoulders), and the pelvis shifts back and the chest forward by half the lean so the body stays
## centred over its feet.
static var body_crouch_pitch: float = 25.0
static var body_crouch_neck_pitch: float = -10.0
## A crouch narrows the stance: the hips and the feet sit this share of their standing width apart, the feet
## stand this far ahead of the pelvis (body radii, so the knees lead over the toes), the foot opposite the
## weapon hand steps back by the stagger (body radii), and the stride is this share of a standing one.
static var body_crouch_hip_width: float = 0.7
static var body_crouch_foot_gap: float = 0.5
static var body_crouch_foot_ahead: float = 0.9
static var body_crouch_stagger: float = 0.35
static var body_crouch_stride: float = 0.45
## How far further forward (px) the hands are held crouched (about the chest's forward shift, so the arms keep
## their reach and the gun is held out in front).
static var body_crouch_hand_ahead: float = 8.0

# --- Legs (they rest against walls and furniture and shove light pieces; character_legs.gd) ---
## Radius (px) of the circle a foot and a knee sweep with, and the shove (impulse per second of contact, divided
## by the piece's mass, like a walking body's `push_impulse`) a leg pressing a pushable piece gives it.
static var leg_radius: float = 3.5
static var leg_push_impulse: float = 30000.0

# --- Stances (how a hand is held; the held item picks one per hand through Item.hand_stance) ---
# A hand rests `forward` px ahead of the body center and `lateral` px out to its own side, in the
# frame it chases the aim in; its grip is `height` body radii off the floor (the arm bends to reach
# it) and its elbow bends toward `elbow_pole` (out, forward, up). `swing` is the walk's fore-and-aft
# swing of a free hand (px); a `steady` hand follows the aim closely and only drifts sideways;
# `recoil_share` is how much of a kick the hand feels when the other hand fires.
static var stances: Dictionary = {
	&"relaxed": { "forward": 2.0, "lateral": 13.0, "height": 3.7, "swing": 9.0, "steady": false,
		"recoil_share": 0.0, "elbow_pole": Vector3(0.2, -0.8, -0.2) },
	# Running: both arms hang and pump at the sides whatever is held (a pistol is just carried in its hand).
	&"run": { "forward": 2.0, "lateral": 10.5, "height": 4.9, "swing": 16.0, "steady": false,
		"recoil_share": 0.0, "elbow_pole": Vector3(0.05, -0.8, 0.0) },
	&"guard": { "forward": 11.5, "lateral": 7.0, "height": 6.0, "swing": 1.5, "steady": false,
		"recoil_share": 0.0, "elbow_pole": Vector3(0.35, -0.1, -1.0) },
	&"aim": { "forward": 27.0, "lateral": 2.0, "height": 6.0, "swing": 0.0, "steady": true,
		"recoil_share": 0.0, "elbow_pole": Vector3(0.3, 0.0, -1.0) },
	&"support": { "forward": 27.0, "lateral": 2.0, "height": 6.0, "swing": 0.0, "steady": true,
		"recoil_share": 0.7, "elbow_pole": Vector3(0.6, -0.1, -1.0) },
	# A grenade's wind-up: the throwing arm drawn back behind the shoulder and up, before it is thrown forward.
	&"throw": { "forward": -6.0, "lateral": 15.0, "height": 6.4, "swing": 0.0, "steady": true,
		"recoil_share": 0.0, "elbow_pole": Vector3(0.6, -0.8, -0.5) },
	# Reloading: the supporting hand drops to the belt for the next magazine.
	&"reload": { "forward": 1.0, "lateral": 11.5, "height": 4.4, "swing": 0.0, "steady": false,
		"recoil_share": 0.0, "elbow_pole": Vector3(0.1, -0.8, -0.2) },
	# A submachine gun: the butt on the right shoulder, the grip hand just ahead of it and the other hand out on the shroud.
	# Both hands lie on one line along the barrel (hand 0 at +lateral, hand 1 at -lateral; both land on the character's right), 9 px right of the aim.
	&"smg_grip": { "forward": 12.0, "lateral": 9.0, "height": 5.8, "swing": 0.0, "steady": true,
		"recoil_share": 0.0, "elbow_pole": Vector3(0.5, -0.1, -1.0) },
	&"smg_fore": { "forward": 24.0, "lateral": -9.0, "height": 5.8, "swing": 0.0, "steady": true,
		"recoil_share": 0.8, "elbow_pole": Vector3(0.4, 0.0, -1.0) },
	# An assault rifle: held in front of the face as if looking down the sight, the butt in the right shoulder, the
	# grip hand just ahead of it and the other hand reaching out along the handguard, both on the barrel line 5 px
	# right of the aim.
	&"rifle_grip": { "forward": 15.0, "lateral": 5.0, "height": 5.9, "swing": 0.0, "steady": true,
		"recoil_share": 0.0, "elbow_pole": Vector3(0.8, -0.1, -1.0) },
	&"rifle_fore": { "forward": 27.0, "lateral": -5.0, "height": 5.8, "swing": 0.0, "steady": true,
		"recoil_share": 0.8, "elbow_pole": Vector3(0.4, 0.0, -1.0) },
	# A long gun raised off a wall or object (butt still on the shoulder, barrel pointed up): both hands drawn in
	# toward the chest, the front one higher as the barrel tips up.
	&"ready_grip": { "forward": 8.0, "lateral": 9.0, "height": 6.4, "swing": 0.0, "steady": true,
		"recoil_share": 0.0, "elbow_pole": Vector3(0.8, -0.1, -1.0) },
	&"ready_fore": { "forward": 14.0, "lateral": -9.0, "height": 6.8, "swing": 0.0, "steady": true,
		"recoil_share": 0.0, "elbow_pole": Vector3(0.5, 0.0, -1.0) },
}
## How fast a hand eases from one stance to another (1/s).
static var stance_ease: float = 12.0
## How far ahead of a hand its weapon's muzzle is (px): bullets leave there. The default for an item that
## does not say (`Item.muzzle_ahead()`); a long gun reaches further.
static var muzzle_ahead: float = 11.0
## How fast a long gun comes up off a wall (and back down) once its barrel touches (or leaves) it: the share of
## the way per second (8 = about an eighth of a second).
static var weapon_raise_speed: float = 8.0
## Clearance (px) a raised gun needs beyond the touching distance before it comes back down, so it does not
## flicker at the edge.
static var weapon_contact_margin: float = 6.0

# --- Ragdoll (the fall on death; character_ragdoll.gd, solved by Physics' Ragdoll; angles in degrees) ---
static var ragdoll_belly: float = 0.4             ## Belly and back points off the spine (keep the trunk rigid).
## Collision radii: the trunk's is half its depth, so it lies on its back or front with thickness.
static var ragdoll_torso_radius: float = 0.5
static var ragdoll_head_radius: float = 0.38
static var ragdoll_limb_radius: float = 0.24
## Point masses (relative): a heavy trunk (seven points), lighter limbs toward their ends.
static var ragdoll_torso_mass: float = 1.0
static var ragdoll_head_mass: float = 0.8
static var ragdoll_elbow_mass: float = 0.25
static var ragdoll_hand_mass: float = 0.15
static var ragdoll_knee_mass: float = 0.6
static var ragdoll_ankle_mass: float = 0.35
## Drawn thickness of the body's limbs (body radii), at each joint down the chain: the neck;
## the arm at the shoulder, elbow and wrist; the leg at the hip, knee, calf and ankle; the shoe at
## the heel and toe. Neighbouring segments share a joint's width, so limbs taper smoothly.
static var body_neck_width: float = 0.42
static var body_arm_widths: Array = [0.48, 0.36, 0.3]
static var body_leg_widths: Array = [0.66, 0.46, 0.52, 0.32]
static var body_shoe_widths: Array = [0.38, 0.34]
## The fallen trunk's shape: cross-sections along the spine, each Vector3(where along it — 0 at the
## hip joints, 1 at the shoulder joints —, half-width, half-depth in body radii), bottom to top. Its
## outline is the hull of each neighbouring pair, so it is waisted and rounded at both ends.
static var ragdoll_trunk_sections: Array = [
	Vector3(-0.15, 0.62, 0.42), Vector3(0.0, 0.74, 0.5), Vector3(0.45, 0.64, 0.45),
	Vector3(0.8, 0.9, 0.55), Vector3(1.0, 1.0, 0.54), Vector3(1.1, 0.78, 0.4),
]
## Joint limits: how far each bone may swing off its rest (neck up; arms and legs down) toward the
## front / back / the body's outside / across it, and each hinge's bend range plus the twist out of
## its plane it allows (the elbow's stands in for the upper arm's roll; the knee barely twists).
static var ragdoll_neck_limits: Dictionary = { "front": 50.0, "back": 45.0, "out": 40.0, "in": 40.0 }
static var ragdoll_shoulder_limits: Dictionary = { "front": 170.0, "back": 60.0, "out": 160.0, "in": 40.0 }
static var ragdoll_hip_limits: Dictionary = { "front": 120.0, "back": 25.0, "out": 35.0, "in": 30.0 }
static var ragdoll_elbow_bend: Vector2 = Vector2(0.0, 145.0)
static var ragdoll_elbow_slack: float = 70.0
static var ragdoll_knee_bend: Vector2 = Vector2(0.0, 150.0)
static var ragdoll_knee_slack: float = 20.0
## The fall's launch: the upper body's push along the killing blow (px/s at the shoulders, fading
## to none at the hips), the knees' forward buckle (px/s) and a random jolt on every point (px/s).
static var ragdoll_hit_topple: float = 60.0
static var ragdoll_knee_buckle: float = 70.0
static var ragdoll_jitter: float = 15.0
## How much of an explosion's shove on a fallen body goes up (a hop off the floor), as a share of its speed along it.
static var ragdoll_blast_lift: float = 0.35
## Speed (px/s) a held item is tossed off at as the hand lets go, on top of the body's momentum.
static var ragdoll_drop_toss: float = 70.0
## A fallen part's floor shadow shift per px of height (matches the standing drop shadow).
static var body_shadow_per_height: float = 0.03
## Draw layer of a dead body: beneath the living, above blood pools.
static var ragdoll_z_index: int = -1

# --- Pose (the living motion of head, shoulders, hands and weapon; see character_pose.gd) ---
# Each part chases `facing` on a damped spring: `freq` is how fast (rad/s), `damping` how much it
# overshoots (1 = none, lower = more), `max_lag` how far it may trail the aim (rad) before it is
# reeled in at `pose_lag_catch`.
## How fast a part past its `max_lag` is reeled back toward it (1/s): high = tight, low = loose.
static var pose_lag_catch: float = 14.0
static var pose_head_freq: float = 12.0      ## Head: turns to the aim first.
static var pose_head_damping: float = 0.9    ## Head: barely overshoots.
static var pose_head_max_lag: float = 0.8    ## Head: furthest behind the aim.
static var pose_aim_freq: float = 11.0       ## Steady hands (aiming, supporting): follow the aim closely.
static var pose_aim_damping: float = 0.95    ## Steady hands: settle without wobble.
static var pose_aim_max_lag: float = 0.6     ## Steady hands: furthest behind the aim.
static var pose_weapon_freq: float = 7.0     ## Weapon: heavier than the hand holding it.
static var pose_weapon_damping: float = 0.8  ## Weapon: swings a hair past and settles.
static var pose_weapon_max_lag: float = 0.7  ## Weapon: furthest behind the aim.
static var pose_hand_freq: float = 8.0       ## Free hands: follow the aim loosely.
static var pose_hand_damping: float = 0.85   ## Free hands: a little give.
static var pose_hand_max_lag: float = 0.9    ## Free hands: furthest behind the aim.
## How far apart the two free hands' paces are (fraction of `pose_hand_freq`; left slower).
static var pose_hand_pace_spread: float = 0.3
static var pose_torso_freq: float = 5.5      ## Shoulders: follow last.
static var pose_torso_damping: float = 0.75  ## Shoulders: ease past and settle.
static var pose_torso_max_lag: float = 1.2   ## Shoulders: furthest behind the aim.
static var pose_hip_freq: float = 9.0        ## Hips (and feet): turn to the walking direction.
static var pose_hip_damping: float = 0.9     ## Hips: barely overshoot.
## How far the shoulders may twist off the planted hips before the feet re-plant toward the aim (rad).
static var pose_hip_twist: float = 0.9
## Distance walked per full stride (two steps), in px.
static var pose_stride_length: float = 48.0
## The same at a full run. A planted foot stays put on the ground when this is 2π × the foot's swing
## (`body_run_stride` × radius ≈ 21 px → ~130 px); shorter and the feet scurry and skate.
static var pose_run_stride_length: float = 130.0
## Shoulder sway either way at full walking speed (rad).
static var pose_walk_sway: float = 0.07
## A full run's shoulders counter-rotate against the hips by this much either way (rad).
static var pose_run_sway: float = 0.18
## ...and the upper body shifts this far (px) sideways over the planted foot, once per step.
static var pose_run_shoulder_shift: float = 1.2
## A full run's forward lean: the shoulders (and head) lead the hips this far (px) along the way it travels.
static var pose_run_lean: float = 2.5
## How far the forward-swinging hand rises above, and the back one drops below, its grip height (body radii).
static var pose_run_hand_rise: float = 0.7
## How far a running elbow's pole swings up and down with the arm (see `elbow_pole`): down under a forward hand, up behind a back one.
static var pose_run_elbow_lift: float = 0.5
## A steady hand's sideways drift at full walking speed (px).
static var pose_aim_drift: float = 0.5
## A punch's body: the shoulders twist toward the punching side by this much (rad) and the upper
## body lunges this far ahead (px) at full extension.
static var pose_punch_twist: float = 0.5
static var pose_punch_lunge: float = 4.0
## Head bob along the walk at full speed (px), twice per stride.
static var pose_head_bob: float = 0.4
## Head lean into the movement at full speed (px), on a soft spring so it settles on a stop.
static var pose_lean: float = 1.2
static var pose_lean_freq: float = 7.0       ## Lean spring speed (rad/s).
static var pose_lean_damping: float = 0.65   ## Lean spring damping.
## Breathing: the head's slow drift fore and aft (px).
static var pose_breath: float = 0.35
static var pose_breath_period: float = 3.8   ## Breath period (s).
## Idle glance: how far the head wanders off the aim while standing (rad), faded out when walking.
static var pose_glance: float = 0.1
## Recoil: how far a kick throws the hand back (px).
static var pose_recoil: float = 4.0
static var pose_recoil_twist: float = 0.08   ## Shoulder twist per kick (rad).
static var pose_recoil_freq: float = 18.0    ## Recoil spring speed (rad/s).
static var pose_recoil_damping: float = 0.6  ## Recoil spring damping.

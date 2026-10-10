class_name CharacterConfig

## Tuning for a Character walking into / being shoved by world objects, being shot, and its
## pixel art (scenes/character/). A `class_name` holder of `static var`s — read as
## `CharacterConfig.<name>`; there is no instance and no autoload.
##
## Walking the character body into a pushable object (anything exposing `apply_impulse`
## — i.e. furniture, not walls) shoves it via the same impulse pipeline a projectile
## uses, divided by the object's mass. Pushing also slows the character (heavier =
## slower), and a fast object sliding into the character shoves them back.

## Base impulse the character imparts to an object per physics frame of contact, scaled
## by how hard the character is moving into it (input strength 0–1).
static var push_impulse: float = 900.0
## How much each unit of the pushed object's `mass` reduces the character's speed while
## pushing (speed_mult = 1 − heaviest_mass × this, floored by `push_slow_min`).
static var push_slow_per_weight: float = 0.02
## Floor on the character's speed multiplier while pushing.
static var push_slow_min: float = 0.15
## The character's mass for *incoming* knockback: an object sliding into the character
## shoves them by impulse / this. Higher = the character shrugs off hits unless struck hard.
static var player_mass: float = 40.0
## Deceleration (px/s²) that bleeds the character's knockback velocity back to zero.
static var push_knockback_friction: float = 1600.0

## Base central impulse a full-extension punch imparts to a pushable object, scaled by the
## swing's range of motion (0 point-blank .. 1 full reach). A shoved RigidBody slides
## ≈ impulse / (mass × PhysicsConfig.body_linear_damp) before settling.
static var punch_impulse: float = 900.0
## Base damage a full-extension punch reports, scaled by the same range of motion. Surfaced
## through hit_landed for the HUD; a punch does not deform what it hits.
static var punch_damage: float = 8.0

# --- Flesh: how a character reacts to being shot (the "hittable" contract) --------------
# Every value here is a tuning knob; a character reads them in _ready() / its visuals, so
# adjusting flesh damage response is a one-line change and needs no code edits.

## Material tag handed to the debris system; selects the blood chip style + tint.
static var flesh_material: String = "flesh"
## Coverage rating 0–100: a partial-cover proxy (a body blocks some of a doorway).
static var flesh_coverage: float = 45.0
## Resistance to being shot through, 0–100. Low: bullets tear through flesh.
static var flesh_penetration: float = 15.0
## Base color handed to debris styling; the "flesh" material re-tints chips blood-red, so
## this only matters to any future non-blood use of the surface color.
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

# --- Pixel art (the body and hand painters; shared lighting/resolution is ArtConfig) ---
## Head radius as a fraction of the body's width.
static var art_head_size: float = 0.19
## Shoulder span depth (front to back) as a fraction of the body's width.
static var art_shoulder_depth: float = 0.54
## Default skin, hair and backpack colors (each character's visuals may override them).
static var art_skin_color: Color = Color(0.93, 0.76, 0.6)
static var art_hair_color: Color = Color(0.36, 0.24, 0.14)
static var art_pack_color: Color = Color(0.3, 0.32, 0.26)

# --- Pose (the living motion of head, shoulders, hands and weapon; see character_pose.gd) ---
# Each part chases `facing` on a damped spring: `freq` is how fast (rad/s), `damping` how much it
# overshoots (1 = none, lower = more), `max_lag` how far it may trail the aim (rad) before it is
# reeled in at `pose_lag_catch`.
## How fast a part past its `max_lag` is reeled back toward it (1/s): high = tight, low = loose.
static var pose_lag_catch: float = 14.0
static var pose_head_freq: float = 12.0      ## Head: turns to the aim first.
static var pose_head_damping: float = 0.9    ## Head: barely overshoots.
static var pose_head_max_lag: float = 0.8    ## Head: furthest behind the aim.
static var pose_aim_freq: float = 11.0       ## Aiming hand: follows the aim closely.
static var pose_aim_damping: float = 0.95    ## Aiming hand: settles without wobble.
static var pose_aim_max_lag: float = 0.6     ## Aiming hand: furthest behind the aim.
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
## Distance walked per full stride (two steps), in px.
static var pose_stride_length: float = 48.0
## Shoulder sway either way at full walking speed (rad).
static var pose_walk_sway: float = 0.07
## Free hands' swing fore and aft at full walking speed (px).
static var pose_hand_swing: float = 1.5
## An aiming hand's sideways drift at full walking speed (px).
static var pose_aim_drift: float = 0.5
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

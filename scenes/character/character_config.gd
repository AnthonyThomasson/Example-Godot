class_name CharacterConfig

## Tuning for a Character walking into / being shoved by world objects
## (scenes/character/). A `class_name` holder of `static var`s — read as
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

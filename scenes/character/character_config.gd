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

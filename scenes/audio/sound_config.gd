class_name SoundConfig

## Tuning for the sound system (scenes/audio/). A `class_name` holder of `static var`s — read as
## `SoundConfig.<name>`; there is no instance and no autoload (the autoload is `Sound`, the service).
##
## Every sound is synthesized in code (SoundSynth) from a recipe SoundBank builds for a *profile*, then
## played by the `Sound` service through a small pool of positional voices. A sound belongs to one of
## four categories — `shot`, `impact`, `footstep`, `reload` — and the per-category tables below are
## keyed by those names.

## Master switch: off = the `Sound` service synthesizes, plays and posts nothing.
static var enabled: bool = true

## --- Mix ---
## Overall trim (dB) added to every voice.
static var master_db: float = 0.0
## Trim (dB) per category, on top of each profile's own level.
static var category_db: Dictionary = { &"shot": 0.0, &"impact": -2.0, &"footstep": -8.0, &"reload": -6.0 }
## Random pitch swing either side of 1 (0.06 = ±6%) on every play, so a burst of identical events does not sound
## like one sample machine-gunned.
static var pitch_jitter: float = 0.06
## Random volume swing (dB) either side of the level, on every play.
static var volume_jitter_db: float = 1.5
## Per-category multiplier on those two swings. Steps are heard over and over, so they swing wider
## (a repeating sound is what makes a walk sound mechanical).
static var category_jitter_scale: Dictionary = { &"footstep": 1.7 }

## --- Voices ---
## Most voices a category may have sounding at once; past it the oldest of that category is cut off.
static var category_voices: Dictionary = { &"shot": 6, &"impact": 8, &"footstep": 8, &"reload": 3 }
## Distance (px, at camera zoom 1) beyond which a category cannot be heard. The AI's own hearing radius
## (`hearing_radius`, 900) is the reference for how far a human-scale sound carries.
static var category_range: Dictionary = { &"shot": 2400.0, &"impact": 1400.0, &"footstep": 900.0, &"reload": 800.0 }
## True = the range grows as the camera zooms out (and shrinks as it zooms in), because Godot's 2D
## attenuation is measured in world px and a zoomed-out spectator would otherwise hear nothing.
static var range_follows_zoom: bool = true

## --- Synthesis ---
## Sample rate (Hz) sounds are rendered at.
static var sample_rate: int = 22050
## Louder than this (0..1) never leaves the synth: every sound is normalized to it.
static var peak: float = 0.9
## Distinct renders per profile; each play picks one at random, so repeats differ.
static var variants: int = 2
## Renders per profile for the categories that want more than `variants`: a step is heard far more often than a
## shot, so it has more different takes to draw from.
static var category_variants: Dictionary = { &"footstep": 6 }
## A projectile's penetration power below this is "light" (SMG); the bands impacts are voiced in.
static var light_power_max: float = 0.9
## A projectile's penetration power from this up is "heavy" (rifle); between the two it is "medium" (pistol).
static var heavy_power_min: float = 1.6
## Seed of the private RNG that picks variants and jitter. Sound never touches the gameplay RNG.
static var rng_seed: int = 1177
## True = render the library in the background a few ms a frame after launch so no sound hitches the
## first time it plays. Skipped when there is no display (tests render lazily).
static var prewarm: bool = true
## Milliseconds a frame the background pre-render may take.
static var prewarm_budget_ms: float = 3.0

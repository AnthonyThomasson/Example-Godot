class_name ArtConfig

## Tuning shared by every procedural pixel-art painter (Art domain, scenes/art/): the art
## resolution, the light and the shadows it casts, the tone ramp around a base color, and the
## material surface finishes (fabric weave, wood grain, brushed metal, stone flecks). Each domain
## keeps its own painters' proportions and colors in its own config.
##
## A `class_name` holder of `static var`s — read as `ArtConfig.<name>`; there is no instance and
## no autoload.

# --- Resolution + lighting ---
## World px per art pixel (1 = one art pixel per world px; 2 = chunkier pixels, less detail).
static var pixel_size: float = 1.0
## World-space direction the light comes FROM (top-left). Edges facing it are highlighted,
## edges facing away are shaded, and raised parts cast shadows away from it.
static var light_from: Vector2 = Vector2(-1.0, -1.0)
## Lighting steps for freely turning art (characters, held items): the art is painted lit at this
## many evenly spaced angles and drawn rotated to the exact one in between.
static var turn_steps: int = 16
## Drop shadow on the floor, offset away from the light by a piece's height proxy: px per point
## of `coverage` (0 = none), capped at drop_shadow_max; and its opacity. Non-solid decor casts none.
static var drop_shadow_per_coverage: float = 0.06
static var drop_shadow_max: float = 6.0
static var drop_shadow_alpha: float = 0.28
## How far (art px) a raised part (a sofa arm, a chair's back rail) shades the lower surface
## beside it, and how much it darkens it.
static var cast_shadow_px: int = 2
static var cast_shadow_darken: float = 0.22

# --- Tone ramp (darken/lighten amounts applied to a piece's base color) ---
## How far each tone of `PixelCanvas.tones` darkens (`tone_outline`, `tone_shadow`, `tone_dark`) or lightens
## (`tone_light`, `tone_highlight`) a piece's base color.
static var tone_outline: float = 0.62
static var tone_shadow: float = 0.36
static var tone_dark: float = 0.18
static var tone_light: float = 0.14
static var tone_highlight: float = 0.3

# --- Surface texture ---
## Fraction of fabric pixels nudged a shade lighter/darker (a woven look).
static var fabric_speckle: float = 0.12
## Wood grain streaks per art pixel of plank area.
static var wood_grain_density: float = 0.018
## Chance that a plank carries a knot.
static var wood_knot_chance: float = 0.3
## Brushed-metal streaks per art pixel of metal area.
static var metal_brush_density: float = 0.012
## Fraction of stone pixels flecked lighter/darker (granite).
static var stone_fleck_density: float = 0.14

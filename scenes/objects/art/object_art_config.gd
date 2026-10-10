class_name ObjectArtConfig

## Tuning for the Objects domain's procedural pixel art (scenes/objects/art/): the art
## resolution, the lighting, the tone ramp, the surface texture and each painter's proportions.
##
## A `class_name` holder of `static var`s — read as `ObjectArtConfig.<name>`; there is no
## instance and no autoload. A piece's catalogue `art_opts` overrides a painter knob for that
## piece only, keyed by the knob's name without its painter prefix (`table_inset` → `inset`).

# --- Resolution + lighting ---
## World px per art pixel (1 = one art pixel per world px; 2 = chunkier pixels, less detail).
static var pixel_size: float = 1.0
## World-space direction the light comes FROM (top-left). Edges facing it are highlighted,
## edges facing away are shaded, and raised parts cast shadows away from it.
static var light_from: Vector2 = Vector2(-1.0, -1.0)
## Drop shadow on the floor, offset away from the light (px; 0 = none), and its opacity.
static var drop_shadow_offset: float = 3.0
static var drop_shadow_alpha: float = 0.28
## How far (art px) a raised part (a sofa arm, a chair's back rail) shades the lower surface
## beside it, and how much it darkens it.
static var cast_shadow_px: int = 2
static var cast_shadow_darken: float = 0.22

# --- Tone ramp (darken/lighten amounts applied to a piece's base color) ---
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

# --- Table ---
## Plank width (art px); planks run along the table's long side.
static var table_plank_px: int = 9
## Bevelled rim width (art px) inside the outline.
static var table_rim_px: int = 2
static var table_corner_radius: int = 3
## A recessed centre panel, inset this many art px from the edge.
static var table_inset: bool = false
static var table_inset_margin: int = 7
## A cloth runner down the long axis: its width as a fraction of the short side, and its color.
static var table_runner: bool = false
static var table_runner_width: float = 0.26
static var table_runner_color: Color = Color(0.9, 0.87, 0.78)

# --- Sofa ---
## Backrest depth and armrest width, as fractions of the sofa's depth / width.
static var sofa_back_depth: float = 0.3
static var sofa_arm_width: float = 0.1
## Target seat-cushion width (art px) and the most cushions a sofa gets.
static var sofa_cushion_width: float = 36.0
static var sofa_max_cushions: int = 4
## Throw pillows in the back corners, hue-shifted from the upholstery by this much.
static var sofa_pillows: bool = true
static var sofa_pillow_hue_shift: float = 0.09

# --- Chair ---
## Depth of the back (rail + slat gap) as a fraction of the chair's depth.
static var chair_back_depth: float = 0.26
## Spindles between the back rail and the seat.
static var chair_slats: int = 3

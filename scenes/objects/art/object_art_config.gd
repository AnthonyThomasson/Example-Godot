class_name ObjectArtConfig

## Tuning for the Objects domain's procedural pixel art (scenes/objects/art/): the art
## resolution, the lighting and shadows, the tone ramp, the surface textures, each painter's
## proportions and colors, the prop palette, and the floor and wall tiles.
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

# --- Cabinet (storage casegoods) ---
## Front lip strip depth as a fraction of the cabinet's depth, and what it shows by default.
static var cabinet_front_depth: float = 0.16
static var cabinet_front: String = "doors"
static var cabinet_count: int = 2
## Crown moulding around the top.
static var cabinet_crown: bool = false
static var cabinet_handle_color: Color = Color(0.8, 0.72, 0.45)
static var cabinet_glass_color: Color = Color(0.6, 0.7, 0.74)

# --- Shelf ---
static var shelf_contents: String = "books"
static var shelf_box_color: Color = Color(0.68, 0.52, 0.34)

# --- Counter ---
static var counter_backsplash: bool = true
static var counter_tap_color: Color = Color(0.76, 0.78, 0.82)

# --- Appliance ---
static var appliance_panel: String = "plain"
static var appliance_metal_color: Color = Color(0.68, 0.7, 0.74)
static var appliance_glass_color: Color = Color(0.16, 0.2, 0.26)

# --- Bed ---
## Pillows (0 = two on a double-width bed, else one), duvet pattern, quilt stitch spacing (art px).
static var bed_pillows: int = 0
static var bed_pattern: String = "quilt"
static var bed_quilt_px: int = 14
static var bed_frame_color: Color = Color(0.45, 0.3, 0.18)
static var bed_sheet_color: Color = Color(0.93, 0.92, 0.88)
static var bed_star_color: Color = Color(1.0, 0.93, 0.55)

# --- Office chair ---
static var office_chair_base_color: Color = Color(0.22, 0.22, 0.25)

# --- Bathroom ---
static var bath_water_color: Color = Color(0.55, 0.76, 0.88)
## Shower tray tile size (art px).
static var bath_tile_px: int = 8
static var shower_glass_color: Color = Color(0.7, 0.85, 0.92)

# --- Rug ---
static var rug_pattern: String = "medallion"
static var rug_fringe_color: Color = Color(0.92, 0.88, 0.78)

# --- Plant, lamp ---
static var plant_leaves: int = 8
static var plant_pot_color: Color = Color(0.72, 0.42, 0.28)
static var plant_soil_color: Color = Color(0.25, 0.18, 0.12)
static var lamp_glow_color: Color = Color(1.0, 0.95, 0.75)

# --- Car ---
static var car_tyre_color: Color = Color(0.12, 0.12, 0.13)
static var car_glass_color: Color = Color(0.2, 0.28, 0.36)
static var car_light_color: Color = Color(0.98, 0.95, 0.8)

# --- Fixture ---
static var fixture_frame_color: Color = Color(0.72, 0.6, 0.35)

# --- Props ---
## Colors for the small props dressing surfaces (desks, nightstands, counters, workbenches) and
## the assorted contents of shelves, washers and coat racks. Lists are picked from at random.
static var prop_colors: Dictionary = {
	"paper": Color(0.95, 0.94, 0.9),
	"ink": Color(0.62, 0.62, 0.66),
	"screen": Color(0.12, 0.14, 0.18),
	"glow": Color(0.45, 0.7, 0.9),
	"plastic_dark": Color(0.16, 0.16, 0.19),
	"plastic_light": Color(0.82, 0.82, 0.8),
	"metal": Color(0.66, 0.68, 0.72),
	"ceramic": Color(0.94, 0.93, 0.9),
	"glaze": Color(0.35, 0.55, 0.7),
	"coffee": Color(0.32, 0.2, 0.12),
	"wood_light": Color(0.82, 0.66, 0.44),
	"leaf": Color(0.3, 0.58, 0.3),
	"shade": Color(0.96, 0.92, 0.78),
	"accent": Color(0.9, 0.75, 0.2),
	"books": [Color(0.62, 0.18, 0.16), Color(0.18, 0.32, 0.55), Color(0.2, 0.45, 0.28), Color(0.78, 0.62, 0.25),
			Color(0.45, 0.25, 0.45), Color(0.25, 0.25, 0.28), Color(0.85, 0.82, 0.74), Color(0.7, 0.38, 0.2)],
	"fruit": [Color(0.95, 0.55, 0.15), Color(0.85, 0.15, 0.15), Color(0.95, 0.85, 0.25), Color(0.45, 0.7, 0.2)],
	"flowers": [Color(0.95, 0.35, 0.45), Color(0.98, 0.85, 0.3), Color(0.6, 0.4, 0.85), Color(0.98, 0.6, 0.25)],
	"shoes": [Color(0.18, 0.15, 0.13), Color(0.45, 0.28, 0.16), Color(0.85, 0.85, 0.85), Color(0.25, 0.3, 0.5)],
	"coats": [Color(0.2, 0.25, 0.4), Color(0.42, 0.3, 0.2), Color(0.55, 0.18, 0.18), Color(0.3, 0.35, 0.3)],
	"towels": [Color(0.95, 0.95, 0.93), Color(0.55, 0.7, 0.85), Color(0.9, 0.7, 0.72), Color(0.6, 0.78, 0.65)],
}

# --- Floors + walls ---
## Floors draw beneath everything else in the house (blood pools, casings, rugs).
static var floor_z_index: int = -4
## Floor pattern sizes (world px): plank width + board length, parquet square, glazed tile
## (also the checker cell), mosaic tile, concrete slab.
static var floor_plank_px: int = 8
static var floor_plank_length: int = 64
static var floor_parquet_px: int = 16
static var floor_tile_px: int = 24
static var floor_mosaic_px: int = 8
static var floor_slab_px: int = 128
## Chance that a glazed floor tile catches a glare streak.
static var floor_glare_chance: float = 0.2
## Wall cap tile length (world px) and pattern ("plaster" | "brick").
static var wall_tile_px: int = 48
static var wall_pattern: String = "plaster"

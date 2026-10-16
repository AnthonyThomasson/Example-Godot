class_name ObjectArtConfig

## Tuning for the Objects domain's painters (scenes/objects/art/): each painter's proportions and
## colors, the prop palette, the floor and wall tiles, and the run-down look they all draw in (the palette grade, grime,
## the neon share, the world-placed wear, the clutter and the street). The art resolution, lighting, shadows, tone ramp and
## surface textures every painter shares live in the Art domain's ArtConfig.
##
## A `class_name` holder of `static var`s — read as `ObjectArtConfig.<name>`; there is no
## instance and no autoload. A piece's catalogue `art_opts` overrides a painter knob for that
## piece only, keyed by the knob's name without its painter prefix (`table_inset` → `inset`).

# --- Table ---
## Plank width (art px); planks run along the table's long side.
static var table_plank_px: int = 9
## Bevelled rim width (art px) inside the outline.
static var table_rim_px: int = 2
## Corner rounding of the top (art px).
static var table_corner_radius: int = 3
## A recessed centre panel (`table_inset`), inset `table_inset_margin` art px from the edge.
static var table_inset: bool = false
static var table_inset_margin: int = 7
## A cloth runner down the long axis: its width as a fraction of the short side, and its color.
static var table_runner: bool = false
static var table_runner_width: float = 0.26
static var table_runner_color: Color = Color(0.5, 0.42, 0.3)

# --- Sofa ---
## Backrest depth and armrest width, as fractions of the sofa's depth / width.
static var sofa_back_depth: float = 0.3
static var sofa_arm_width: float = 0.1
## Target seat-cushion width (art px) and the most cushions a sofa gets.
static var sofa_cushion_width: float = 36.0
static var sofa_max_cushions: int = 4
## Throw pillows in the back corners, hue-shifted from the upholstery by this much (none on a run-down sofa).
static var sofa_pillows: bool = false
static var sofa_pillow_hue_shift: float = 0.09

# --- Chair ---
## Depth of the back (rail + slat gap) as a fraction of the chair's depth.
static var chair_back_depth: float = 0.26
## Spindles between the back rail and the seat.
static var chair_slats: int = 3

# --- Cabinet (storage casegoods) ---
## Front lip strip depth as a fraction of the cabinet's depth, what it shows by default
## ("doors", "drawers", "lid" or "none") and how many doors or drawers across it.
static var cabinet_front_depth: float = 0.16
static var cabinet_front: String = "doors"
static var cabinet_count: int = 2
## Crown moulding around the top.
static var cabinet_crown: bool = false
## The handles' metal, and the tint of a glass top.
static var cabinet_handle_color: Color = Color(0.5, 0.36, 0.2)
static var cabinet_glass_color: Color = Color(0.42, 0.42, 0.34)

# --- Shelf ---
## What fills the shelf by default ("books", "boxes" or "shoes"), and the cardboard of a box.
static var shelf_contents: String = "books"
static var shelf_box_color: Color = Color(0.5, 0.38, 0.24)

# --- Counter ---
## A backsplash band along the back edge by default, and the tap's metal (the bath's taps too).
static var counter_backsplash: bool = true
static var counter_tap_color: Color = Color(0.52, 0.46, 0.36)

# --- Appliance ---
## The front panel by default ("plain", "burners", "fridge", "microwave", "washer", "dryer" or
## "tv"), its metal parts, and the glass of a microwave or washer door.
static var appliance_panel: String = "plain"
static var appliance_metal_color: Color = Color(0.46, 0.4, 0.32)
static var appliance_glass_color: Color = Color(0.14, 0.15, 0.12)
## A TV's boxy CRT case (grimy grey plastic).
static var appliance_crt_color: Color = Color(0.32, 0.29, 0.24)

# --- Bed ---
## The bare mattress's ticking and the spacing (art px) of its quilted stripes.
static var bed_mattress_color: Color = Color(0.6, 0.55, 0.42)
static var bed_stripe_px: int = 6

# --- Office chair ---
## The star base's metal.
static var office_chair_base_color: Color = Color(0.24, 0.2, 0.16)

# --- Bathroom ---
## Water in a bath and a toilet bowl.
static var bath_water_color: Color = Color(0.42, 0.44, 0.3)
## Shower tray tile size (art px).
static var bath_tile_px: int = 8
## The shower screen's glass.
static var shower_glass_color: Color = Color(0.5, 0.52, 0.44)

# --- Rug ---
## The pattern by default ("medallion", "stripes" or "plush"), and the fringe's color.
static var rug_pattern: String = "medallion"
static var rug_fringe_color: Color = Color(0.58, 0.5, 0.36)

# --- Plant, lamp ---
## Leaves a plant gets (a dying plant has few), its pot and soil colors, and how far its leaves have wilted to
## `plant_dead_color` (0 green .. 1 dead brown).
static var plant_leaves: int = 5
static var plant_pot_color: Color = Color(0.42, 0.26, 0.16)
static var plant_soil_color: Color = Color(0.16, 0.11, 0.07)
static var plant_wilt: float = 1.0
static var plant_dead_color: Color = Color(0.42, 0.32, 0.16)
## The lamp: a dented tin shade over a bare bulb; the bulb's glow (drawn glowing).
static var lamp_tin_color: Color = Color(0.4, 0.34, 0.24)
static var lamp_glow_color: Color = Color(1.0, 0.85, 0.45)

# --- Car ---
## The parked car's tyres, windows and lamps.
static var car_tyre_color: Color = Color(0.1, 0.09, 0.08)
static var car_glass_color: Color = Color(0.24, 0.26, 0.24)
static var car_light_color: Color = Color(0.85, 0.75, 0.5)
## The parked car is a beater: its paint taken this far (0..1) to `car_beater_color` (rust-brown), patched with primer.
static var car_beater: float = 1.0
static var car_beater_color: Color = Color(0.42, 0.3, 0.2)

# --- The new rooms' pieces: tech, recliner, clinic, security, hotplate ---
## The den's hardware (tech_painter.gd): dark parts (rails, frames, cables), the keyboard ledge, and the LEDs a rack and the
## rig's halo show besides their screen colour.
static var tech_dark_color: Color = Color(0.14, 0.12, 0.09)
static var tech_ledge_color: Color = Color(0.36, 0.26, 0.16)
static var tech_led_colors: Array[Color] = [Color(0.85, 0.22, 0.14), Color(0.3, 0.95, 0.4)]
## The recliners (recliner_painter.gd): the surgical chair's pale vinyl padding, the frames and armrests, the surgeon's lamp
## (glowing).
static var recliner_vinyl_color: Color = Color(0.64, 0.6, 0.48)
static var recliner_frame_color: Color = Color(0.5, 0.47, 0.4)
static var recliner_lamp_color: Color = Color(0.92, 0.84, 0.58)
## The ripperdoc's steel (clinic_painter.gd): the cart's tray, the instruments and arms, the shelf's cyberware.
static var clinic_tray_color: Color = Color(0.56, 0.53, 0.44)
static var clinic_chrome_color: Color = Color(0.62, 0.58, 0.48)
static var clinic_joint_color: Color = Color(0.78, 0.22, 0.14)
static var clinic_eye_color: Color = Color(0.86, 0.84, 0.76)
static var clinic_chip_color: Color = Color(0.1, 0.28, 0.15)
static var clinic_pin_color: Color = Color(0.78, 0.66, 0.3)
static var clinic_jar_color: Color = Color(0.5, 0.66, 0.42)
## The vestibule's steel (security_painter.gd): the barricade's hazard stripe and sandbags, the scanner's beam (glowing),
## the lockers' numbers.
static var security_hazard_color: Color = Color(0.88, 0.68, 0.16)
static var security_sandbag_color: Color = Color(0.55, 0.47, 0.32)
static var security_beam_color: Color = Color(1.0, 0.22, 0.18)
static var security_number_color: Color = Color(0.86, 0.84, 0.76)
## The kitchenette's hotplate (hotplate_painter.gd): its crate, the hot ring (glowing) and the pan.
static var hotplate_crate_color: Color = Color(0.36, 0.26, 0.16)
static var hotplate_ring_color: Color = Color(1.0, 0.42, 0.12)
static var hotplate_pan_color: Color = Color(0.2, 0.19, 0.18)

# --- Streetlight (streetlight_painter.gd) ---
## The overhead head a streetlight draws by default (`cobra` lamp or `sign`), how long the head is along the arm (art px),
## the base plate, the arm and head housing, the flyer taped round the post, the lens (glowing: sodium) and a sign's board.
static var streetlight_head: String = "cobra"
static var streetlight_head_px: int = 15
static var streetlight_plate_color: Color = Color(0.2, 0.18, 0.15)
static var streetlight_head_color: Color = Color(0.3, 0.29, 0.25)
static var streetlight_flyer_color: Color = Color(0.82, 0.78, 0.62)
static var streetlight_lens_color: Color = Color(1.0, 0.74, 0.4)
static var streetlight_sign_color: Color = Color(0.07, 0.07, 0.08)

# --- Fixture ---
## A mirror's frame.
static var fixture_frame_color: Color = Color(0.4, 0.32, 0.2)

# --- Props ---
## Colors for the small props dressing surfaces (desks, nightstands, counters, workbenches) and
## the assorted contents of shelves, washers and coat racks. Lists are picked from at random.
static var prop_colors: Dictionary = {
	"paper": Color(0.575, 0.533, 0.456),
	"ink": Color(0.412, 0.398, 0.377),
	"glow": Color(0.45, 0.95, 0.42),
	"plastic_dark": Color(0.16, 0.14, 0.11),
	"plastic_light": Color(0.5, 0.45, 0.36),
	"metal": Color(0.66, 0.68, 0.72),
	"ceramic": Color(0.94, 0.93, 0.9),
	"glaze": Color(0.35, 0.55, 0.7),
	"coffee": Color(0.32, 0.2, 0.12),
	"wood_light": Color(0.82, 0.66, 0.44),
	"leaf": Color(0.3, 0.58, 0.3),
	"accent": Color(0.9, 0.75, 0.2),
	"books": [Color(0.42, 0.24, 0.14), Color(0.3, 0.3, 0.22), Color(0.5, 0.4, 0.22), Color(0.26, 0.2, 0.16),
			Color(0.55, 0.5, 0.38), Color(0.36, 0.18, 0.12)],
	"fruit": [Color(0.95, 0.55, 0.15), Color(0.85, 0.15, 0.15), Color(0.95, 0.85, 0.25), Color(0.45, 0.7, 0.2)],
	"flowers": [Color(0.95, 0.35, 0.45), Color(0.98, 0.85, 0.3), Color(0.6, 0.4, 0.85), Color(0.98, 0.6, 0.25)],
	"shoes": [Color(0.42, 0.24, 0.14), Color(0.3, 0.3, 0.22), Color(0.5, 0.4, 0.22), Color(0.26, 0.2, 0.16),
			Color(0.55, 0.5, 0.38), Color(0.36, 0.18, 0.12)],
	"coats": [Color(0.42, 0.24, 0.14), Color(0.3, 0.3, 0.22), Color(0.5, 0.4, 0.22), Color(0.26, 0.2, 0.16),
			Color(0.55, 0.5, 0.38), Color(0.36, 0.18, 0.12)],
	"towels": [Color(0.42, 0.24, 0.14), Color(0.3, 0.3, 0.22), Color(0.5, 0.4, 0.22), Color(0.26, 0.2, 0.16),
			Color(0.55, 0.5, 0.38), Color(0.36, 0.18, 0.12)],
}

# --- The lights the pieces give (object_lights.gd: a piece's `get_lights()`, read by the Lighting domain) ---
## One row per kind of light a piece gives: its `energy`, its pool's `radius` (px, out along the pool's long axis; a `wide`
## pool is half as deep, a `tube` a third), `shape` (`round`, `wide`: a screen's spill across its front, `tube`: along a neon
## tube), how far `ahead` (px) of the piece's front edge it stands (a screen's spill; none: the piece's centre), the rhythms it
## is drawn from by weight (`[[mode, weight], ...]`: steady, buzz, failing, blink, shimmer, pulse), `room_light` (it lights its
## room, so the room needs no ceiling fixture) and `height` (`overhead`: above the heads, a lamp's bulb, a street lamp's head,
## shadowed by the walls only and pooling downward; `low` when absent: shadowed by the walls and the tall pieces). Its colour
## is what the piece draws glowing (its neon, its screen, its bulb). `trim` is a piece's neon trim or under-glow; a tube's
## `radius` is its length × `tube_reach`.
static var light_specs: Dictionary = {
	"lamp": { "energy": 0.95, "radius": 160.0, "shape": &"round", "height": &"overhead",
		"rhythm": [[&"steady", 6.0], [&"buzz", 1.5], [&"pulse", 1.0], [&"failing", 1.5]], "room_light": true },
	"tv": { "energy": 0.8, "radius": 110.0, "shape": &"wide", "ahead": 26.0, "rhythm": [[&"shimmer", 1.0]] },
	"desk": { "energy": 0.6, "radius": 105.0, "shape": &"wide", "ahead": -12.0, "rhythm": [[&"shimmer", 1.0]] },
	"monitor_wall": { "energy": 0.9, "radius": 128.0, "shape": &"wide", "ahead": 30.0, "rhythm": [[&"shimmer", 1.0]] },
	"server_rack": { "energy": 0.5, "radius": 65.0, "shape": &"round", "ahead": 8.0, "rhythm": [[&"blink", 1.0], [&"pulse", 1.0]] },
	"rig": { "energy": 0.4, "radius": 80.0, "shape": &"round", "rhythm": [[&"shimmer", 1.0]] },
	"surgical": { "energy": 1.1, "radius": 160.0, "shape": &"round", "height": &"overhead", "rhythm": [[&"steady", 1.0]],
		"room_light": true },
	"tool_cart": { "energy": 0.4, "radius": 60.0, "shape": &"round", "rhythm": [[&"shimmer", 1.0]] },
	"scanner": { "energy": 0.6, "radius": 90.0, "shape": &"wide", "ahead": 9.0, "rhythm": [[&"pulse", 1.0]] },
	"hotplate": { "energy": 0.6, "radius": 60.0, "shape": &"round", "rhythm": [[&"pulse", 1.0]] },
	"neon_tube": { "energy": 0.85, "tube_reach": 1.7, "shape": &"tube",
		"rhythm": [[&"steady", 4.0], [&"failing", 3.5], [&"buzz", 2.5]] },
	"cobra": { "energy": 1.0, "radius": 130.0, "shape": &"round", "height": &"overhead",
		"rhythm": [[&"steady", 3.0], [&"failing", 1.0]] },
	"sign": { "energy": 1.0, "radius": 130.0, "shape": &"round", "height": &"overhead",
		"rhythm": [[&"blink", 3.0], [&"buzz", 2.0]] },
	"trim": { "energy": 0.45, "radius": 45.0, "shape": &"round", "rhythm": [[&"steady", 4.0], [&"buzz", 1.0]] },
}

# --- Floors + walls ---
## Floors draw beneath everything else in the house (blood pools, casings, rugs): `DrawLayers.FLOOR`.
static var floor_z_index: int = DrawLayers.FLOOR
## Rugs and mats lie on the floor but under blood (`BloodConfig.z_index`), so a pool shows on them: `DrawLayers.RUG`.
static var rug_z_index: int = DrawLayers.RUG
## A piece's overhang (a streetlight's arm and head) hangs over everyone under it and a vehicle's roof: `DrawLayers.OVERHEAD`.
static var overhang_z_index: int = DrawLayers.OVERHEAD
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
## A run-down floor's even dirt: what is packed into the seams between plank rows and round tiles, and the fine grime of
## single pixels over a tile (this many a pixel; a quarter of them pale dust).
static var floor_seam_dirt: Color = Color(0.06, 0.05, 0.04)
static var floor_grout_dirt: Color = Color(0.1, 0.08, 0.05)
static var floor_grime_density: float = 0.07
static var floor_grime_dark: Color = Color(0.12, 0.08, 0.04)
static var floor_grime_pale: Color = Color(0.7, 0.62, 0.5)
## Wall cap tile length (world px) and pattern ("plaster" | "brick").
static var wall_tile_px: int = 48
static var wall_pattern: String = "plaster"
## The cap's even grime: this many darkened pixels a pixel.
static var wall_grime_density: float = 0.1

# --- The run-down look (decay.gd): every piece, floor and wall ---
## The palette grade ObjectArt applies to every piece's, floor's and wall's colour: the hue pulled `grade_hue_pull` of the
## way to `grade_hue` (rust / dun; a colour no more saturated than `grade_grey_saturation` takes `grade_grey_hue`), then
## saturation × `grade_saturation.x` + `.y` and value × `grade_value.x` + `.y`, so everything goes dun, rusty or nicotine.
static var grade_hue: float = 0.08
static var grade_hue_pull: float = 0.5
static var grade_grey_hue: float = 0.09
static var grade_grey_saturation: float = 0.08
static var grade_saturation: Vector2 = Vector2(0.55, 0.12)
static var grade_value: Vector2 = Vector2(0.55, 0.04)
## Grime over a piece: one blotch per this many art px² (at least two), this much darker at its middle.
static var decay_grime_area: float = 260.0
static var decay_grime_amount: float = 0.24
## The glow of a cheap screen (a TV, a monitor, an appliance's display) without a neon of its own.
static var decay_screen_color: Color = Color(0.45, 0.95, 0.42)
## The neon pair: a piece with a `neon` option takes a trim or screen in one of them.
static var neon_cyan: Color = Color(0.15, 0.92, 1.0)
static var neon_magenta: Color = Color(1.0, 0.2, 0.72)
## The share of each kind of light-giving piece that takes a neon trim or screen (`ObjectArt.neon_for`): `tv` an appliance
## with a TV panel, `desk` a table with a monitor on it, the new rooms' pieces by their `kind` (`monitor_wall`,
## `server_rack`, `rig`, `tool_cart`), the rest by their painter id. A kind not listed never does.
static var neon_share: Dictionary = {
	"tv": 0.6, "desk": 0.5, "lamp": 0.45, "fixture": 0.5, "counter": 0.35, "cabinet": 0.3, "shelf": 0.35, "bed": 0.3,
	"appliance": 0.25, "monitor_wall": 0.6, "server_rack": 0.5, "rig": 0.6, "tool_cart": 0.4,
}

# --- Wear: marks placed in the world over a room's floor and walls (wear_painter.gd, room_wear.gd) ---
## A wear cluster's marks: 1 with this chance, else 2 with `wear_two_chance`, else 3; each further mark this far (px) from
## the cluster's centre.
static var wear_one_chance: float = 0.45
static var wear_two_chance: float = 0.65
static var wear_spread: Vector2 = Vector2(14, 40)
## Marks keep this far inside the room's rect (its edges are the walls' centre lines), and this far apart.
static var wear_inset: float = 8.0
static var wear_gap: float = 4.0
## The floor marks each floor pattern takes, by weight.
static var wear_floor_kinds: Dictionary = {
	"planks": [["plank_gap", 3.0], ["scuffs", 2.0], ["stain", 2.0], ["burns", 1.0]],
	"parquet": [["strip_gap", 3.0], ["scuffs", 2.0], ["stain", 2.0], ["burns", 1.0]],
	"tiles": [["missing_cells", 3.0], ["crack", 2.0], ["stain", 2.0]],
	"checker": [["missing_cells", 3.0], ["crack", 2.0], ["stain", 2.0]],
	"mosaic": [["missing_cells", 3.0], ["crack", 1.0], ["stain", 2.0]],
	"carpet": [["worn", 3.0], ["stain", 3.0], ["burns", 2.0]],
	"concrete": [["crack", 3.0], ["oil", 2.0], ["stain", 2.0]],
}
## A free floor mark's footprint: `[min, max]` along and across (px).
static var wear_sizes: Dictionary = {
	"crack": [Vector2(30, 9), Vector2(80, 16)], "stain": [Vector2(12, 10), Vector2(30, 24)], "oil": [Vector2(18, 12), Vector2(40, 28)],
	"worn": [Vector2(26, 20), Vector2(56, 40)], "burns": [Vector2(10, 10), Vector2(18, 18)], "scuffs": [Vector2(16, 10), Vector2(32, 20)],
}
## The wall marks, by weight, and each one's length range (px) along the wall.
static var wear_wall_kinds: Array = [["peel", 3.0], ["wall_stain", 2.0], ["wall_crack", 2.0], ["cable", 1.0]]
static var wear_wall_lengths: Dictionary = { "peel": Vector2(12, 36), "wall_stain": Vector2(10, 26), "wall_crack": Vector2(18, 48), "cable": Vector2(60, 200) }
## The wall cap's plaster as the wall marks see it (what a peel's lip and a stain sit on).
static var wear_plaster_color: Color = Color(0.52, 0.45, 0.33)
## The chance a cluster by a wall also marks that wall.
static var wear_wall_chance: float = 0.7
## Random-detail variants per mark kind and size (`v`): enough that no two neighbours match, few enough to cache.
static var wear_variants: int = 6

# --- Street (street_painter.gd, street_marks.gd): the ring round a house ---
## The tiles (world px) and their colours: asphalt big, so its even grain has no period the eye picks up; sidewalk two by
## two slabs of `street_slab_px`.
static var street_asphalt_px: int = 256
static var street_sidewalk_px: int = 64
static var street_slab_px: float = 32.0
static var street_asphalt_color: Color = Color(0.24, 0.21, 0.17)
static var street_sidewalk_color: Color = Color(0.42, 0.38, 0.32)
## The curb drawn along a sidewalk's road side, and the lane dashes' paint.
static var street_curb_color: Color = Color(0.3, 0.27, 0.22)
static var street_lane_color: Color = Color(0.85, 0.82, 0.62, 0.6)
## The marks laid over a piece of street: on the road one cluster of 1-3 per `street_road_cluster_area` px² (cracks,
## patches, oil), on the sidewalk one of 1-2 per `street_walk_cluster_run` px of its length (cracks, stains, gum, weeds) and a
## cluster of odd slabs per `street_slab_cluster_run`; litter and puddles in the gutter, one cluster per
## `street_litter_cluster_run` px of curb.
static var street_road_wear: Array = [["crack", 3.0], ["patch", 1.5], ["oil", 2.0]]
static var street_walk_wear: Array = [["crack", 3.0], ["stain", 2.0], ["gum", 2.0], ["weeds", 1.0]]
static var street_road_cluster_area: float = 120000.0
static var street_walk_cluster_run: float = 500.0
static var street_slab_cluster_run: float = 380.0
static var street_litter_cluster_run: float = 420.0

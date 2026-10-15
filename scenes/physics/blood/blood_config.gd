class_name BloodConfig

## Tuning for the blood system (scenes/physics/blood/). A `class_name` holder of `static var`s —
## read as `BloodConfig.<name>`; there is no instance and no autoload.
##
## Blood is its own physical reaction, kept separate from the debris and deformation knobs in
## PhysicsConfig. A wounded body (BloodWound) throws a quick spray of splatters when it is hit, then keeps
## dripping: one drop every `drip_interval_min`..`drip_interval_max` seconds while the wound lasts, each
## landing as a BloodSplat. A dead body also bleeds out one slow, wide pool (`bleed_out_*`) from where it
## came to rest.

## Master switch for blood: off = hits leave no splatter or drips and dead bodies no bleed-out
## (BloodWound.record / Physics.bleed_out spawn nothing).
static var enabled: bool = true

## --- Wound: the drip budget and timing ---
## Seconds between one drip and the next, re-rolled uniformly in [min, max] after every drip (and for the
## first drip after a hit).
static var drip_interval_min: float = 3.0
static var drip_interval_max: float = 10.0
## Drips a hit adds to the wound's budget per point of damage (rounded up, at least 1). The wound keeps
## dripping until the budget is spent, so a harder hit bleeds for longer.
static var drips_per_damage: float = 0.2
## Cap on the drips a wound may owe at once (repeated hits stop adding past it).
static var max_pending_drips: int = 12
## Seconds a drip falls before it lands: it keeps the body's walking velocity meanwhile, so a moving
## body's drops land ahead of where they left it.
static var drip_fall_time: float = 0.18
## Random offset (px) added to where a drip lands.
static var drip_jitter: float = 3.0
## Body speed (px/s) at which a drip lands with full energy (a fully stretched, forward-flung splat).
static var drip_full_energy_speed: float = 120.0

## --- Hit spray ---
## Damage per spray splatter a hit throws (rounded up, at least 1), and the most one hit throws.
static var hit_splat_damage: float = 8.0
static var hit_splat_max: int = 5
## How far (px) from the wound a spray splatter lands, in [min, max], along the wound's exit side
## (the surface normal) with a random spread of `hit_spray_spread` radians either side.
static var hit_spray_reach_min: float = 10.0
static var hit_spray_reach_max: float = 48.0
static var hit_spray_spread: float = 0.6
## Energy (0..1) of a spray splatter: how stretched along its flight and how far its satellites scatter.
static var hit_spray_energy: float = 0.8

## --- Splatter shape (BloodSplat) ---
## Core blob radius (px) of a drip, in [min, max]; spray splatters are scaled by `hit_splat_size`.
static var drip_size_min: float = 2.5
static var drip_size_max: float = 4.5
static var hit_splat_size: float = 0.7
## Crown spikes radiating from the core, and the satellite droplets scattered around it, in [min, max].
static var splat_spikes_min: int = 4
static var splat_spikes_max: int = 10
static var splat_satellites_min: int = 4
static var splat_satellites_max: int = 12
## How far a splatter stretches along its direction at full energy (core length = radius * (1 + this)).
static var splat_stretch: float = 0.9
## How lumpy the core outline is (1 +- this per vertex). 0 = a clean disc.
static var splat_wobble: float = 0.22
## Spike length, in core radii, in [min, max]; and how far satellites land, in core radii.
static var splat_spike_length_min: float = 0.4
static var splat_spike_length_max: float = 1.6
static var splat_satellite_reach_min: float = 1.4
static var splat_satellite_reach_max: float = 3.4
## Seconds a splatter takes to dry from `color` to `dried_color`.
static var splat_dry_time: float = 90.0
## Wet highlight painted on the core (a lighter fleck); alpha 0 hides it.
static var splat_highlight: Color = Color(0.75, 0.12, 0.12, 0.45)
## Cap on the splatters one body keeps in the world; the oldest are freed past it.
static var max_splats_per_body: int = 60

## --- Death bleed-out ---
## A body bleeding out where it came to rest after death (Physics.bleed_out): how many grid cells
## its flowing pool claims (area = cells * flow_cell_size²) and the seconds its edge takes to sweep
## out across them.
static var bleed_out_cells: int = 225
static var bleed_out_duration: float = 10.0
## Side (px) of a flow grid cell. Smaller = finer edge, more physics queries.
static var flow_cell_size: float = 4.0
## How strongly noise makes some directions cheap to flow into (fingers/bays) and others dear.
## 0 = an even disc; ~1 = strongly lobed.
static var flow_noise_strength: float = 0.9
## Noise frequency per cell; lower = broader lobes.
static var flow_noise_frequency: float = 0.12
## How much the flow favours the pool's random lean (0 none .. 1 strongly one way).
static var flow_aim_bias: float = 0.3
## Softness of the advancing edge, in cells of flow cost: how far behind the front a cell is still
## filling in. Larger = a wider, gentler fade at the edge.
static var flow_soft_edge: float = 3.0
## Floor texture steering a bleed-out flow (BloodSurface): off = the floor is ignored. Flow-cost
## multipliers per cell: on a groove (grout, plank seam, slab joint), on smooth surface between
## grooves, and on a porous surface (carpet). Low = blood runs there easily.
static var surface_flow: bool = true
static var groove_resist: float = 0.3
static var smooth_resist: float = 2.2
static var porous_resist: float = 3.0
## Blood on a porous surface (carpet, a rug) sinks in: seconds a flooded cell takes to soak. It still covers
## the same floor; it just stops being wet (no prints or smears) and its colour mottles.
static var soak_time: float = 20.0
## Fabric drinks the blood, so it does not travel as far: each cell a pool claims on porous surface counts as
## this many cells of the bleed-out budget (`bleed_out_cells`), so the pool covers a smaller area there.
static var porous_cell_weight: float = 3.0
## Blood spreading over porous surface creeps this many times slower (scaled by the share of the pool on it).
static var porous_spread_slowdown: float = 4.0
## Blood sinks into a carpet or rug tuft by tuft: each tuft (a spot `soak_tuft_size` px across) soaks at its own
## rate, `soak_tuft_spread` (0 all together .. 1 very uneven) wide, and ends up a dot of its own shade of red, so
## the pool turns into a spotted, mottled stain rather than one fading film.
static var soak_tuft_spread: float = 0.8
static var soak_tuft_size: float = 2.5
## How strongly the tufts differ in shade (0 all alike .. 1 very mottled), and how opaque soaked blood is
## (1 = as solid as fresh blood, lower lets the rug or carpet pattern show through the stain).
static var soak_tuft_contrast: float = 0.2
static var soak_opacity: float = 0.95
## Half width (px) around a groove line that still counts as on it; about half a flow cell so a cell
## centre reliably lands in a 1-px groove.
static var groove_half_width: float = 2.0
## Brightness drop of rim cells vs. the deep centre (0 none .. 1 black).
static var flow_edge_darken: float = 0.25
## --- Footprints and smears (BloodField, BloodDecals, BloodFootprints, BloodSmear) ---
## A foot or a sliding object soaks up wet blood where it touches it, then deposits it with the load
## fading, so a trail tapers off. Both switches also need `enabled`.
static var footprints_enabled: bool = true
static var smear_enabled: bool = true
## Seconds a bleed-out pool stays wet enough to be picked up (splatters use `splat_dry_time`).
static var pool_wet_time: float = 240.0
## Wetness (0..1) of a fresh splatter, a thin film next to a pool's deep fill.
static var splat_wetness: float = 0.7
## Load (0..1) a carrier soaks from blood of wetness 1; it keeps the larger of its load and this.
static var pickup_gain: float = 1.0
## Wetness above which the spot is already thick blood: a footprint is not stamped there.
static var thick_blood: float = 0.8
## Cap on the prints and smear ribbons kept in the world; the oldest are dropped past it.
static var print_max: int = 1000
## Seconds a print or smear takes to dry from `color` to `dried_color`.
static var print_dry_time: float = 90.0
## Draw order of prints and smears (and the scorch decals): blood's rung, `DrawLayers.BLOOD`; their decal layers are
## added after the first splat, so they draw over it.
static var print_z_index: int = DrawLayers.BLOOD
## Footprints: load a foot loses per print (so ~1/print_decay prints follow a soak), the load below
## which a foot prints nothing, and the print's opacity at load 1 and at the threshold.
static var print_decay: float = 0.09
static var print_min_load: float = 0.12
static var print_alpha_max: float = 0.85
static var print_alpha_min: float = 0.25
## Random placement offset (px) and turn (radians) of a print, and how far (px) a fast, heavy
## print slips forward along the heading.
static var print_jitter: float = 0.6
static var print_turn_jitter: float = 0.12
static var print_slip: float = 1.2
## Smears: an object drags blood as feathered ribbons, one per "finger" across its footprint. Finger
## spacing (px) and the most fingers; the speed (px/s) below which an object smears nothing; the distance
## (px) between ribbon samples; the load a finger loses per px; ribbon width as a multiple of the spacing
## (more than 1 so neighbours merge into one smudge); the opacity at load 1.
static var smear_finger_spacing: float = 6.0
static var smear_max_fingers: int = 14
static var smear_min_speed: float = 12.0
static var smear_segment_length: float = 3.0
static var smear_decay_per_px: float = 0.007
static var smear_width: float = 1.7
static var smear_alpha_max: float = 0.95
## How far a ribbon wanders sideways (in finger spacings) and how fast (cycles per px), so streaks
## drift, converge and cross instead of running dead straight.
static var smear_wobble: float = 0.6
static var smear_wobble_freq: float = 0.03
## Opacity at a ribbon's edges as a fraction of its centre (0 = fully soft, 1 = hard edge).
static var smear_feather: float = 0.25
## Below this load a ribbon starts to break into dry-brush dashes (more often the lower the load),
## and the most samples one ribbon holds before another takes over.
static var smear_break_load: float = 0.3
static var smear_max_ribbon_points: int = 60
## Blending into blood already on the floor: a new ribbon eases in over this many px, and is
## see-through where the floor is already wet — fully so above `smear_absorb_hi` wetness, not at all
## below `smear_absorb_lo` — so a smear grows out of its puddle with no edge.
static var smear_fade_in: float = 12.0
static var smear_absorb_lo: float = 0.1
static var smear_absorb_hi: float = 0.6
## The most a ribbon's opacity may rise per sample (it may fall at once), so a streak swells out of a
## puddle's crisp edge instead of switching on there.
static var smear_alpha_rise: float = 0.12
## Blood pulled out of a pool extends the pool's own outline: a finger carrying at least
## `smear_trail_min` load within `smear_trail_reach` px of a pool grows it by that load x
## `smear_trail_gain`, and the pool keeps at most `pool_trail_max` such cells. No trail cell lies more
## than `pool_trail_length` px from the pool's own flooded cells: the tongue tapers to nothing there, so
## this is how far a pool can be dragged (a full load would otherwise carry about 100 px).
static var smear_trail_min: float = 0.3
static var smear_trail_reach: float = 10.0
static var smear_trail_gain: float = 1.0
static var pool_trail_max: int = 600
static var pool_trail_length: float = 50.0
## Base blood color — dark red, semi-transparent, distinct from the debris "blood" chip tint
## so the two systems stay visually independent.
static var color: Color = Color(0.42, 0.02, 0.03, 0.85)
## What blood dries to (see `splat_dry_time`).
static var dried_color: Color = Color(0.24, 0.04, 0.03, 0.85)
## Draw order: `DrawLayers.BLOOD`, on the floor and rugs, under what lies there (a body, casings) and the standing world.
static var z_index: int = DrawLayers.BLOOD

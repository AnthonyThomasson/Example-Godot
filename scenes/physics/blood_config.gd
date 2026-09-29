class_name BloodConfig

## Tuning for the blood pooling system (scenes/physics/blood_*.gd): the pool of blood a flesh
## hit leaves, oozing out gradually and packing next to itself. A `class_name` holder of
## `static var`s — read as `BloodConfig.<name>`; there is no instance and no autoload.
##
## Blood pooling is its own physical reaction, kept separate from the debris and deformation
## knobs in PhysicsConfig. A wounded body bleeds into one accumulating pool: each hit adds
## `particle_count` drops (released steadily at a rate set by `spill_duration`) and widens the fill
## disc from `pool_radius_base` toward `pool_radius_max`, so a still victim shot repeatedly pools out
## wide while a lone wound stays small. Total volume per pool is capped at `max_pool_volume`. A body
## that moves off its pool (farther than its radius + `detection_margin`) starts a fresh one, so it
## trails blood. Drops creep out from the wound, slide around walls and furniture, and settle there.

## Drops one hit adds. Also the density reference: `pool_radius_base` holds about this many drops, and
## the disc widens only for volume beyond the first hit, so a single wound stays a small solid pool.
static var particle_count: int = 36
## Cap on the drops one body's pool may hold, bounding how much blood a single character can pool at
## once. Reached after about `max_pool_volume / particle_count` hits on a still victim.
static var max_pool_volume: int = 420
## Seconds one hit's worth of drops takes to emerge. Sets the steady release rate
## (particle_count / spill_duration drops per second); lower = blood appears faster.
static var spill_duration: float = 6.0
## Radius (px) a single wound's pool fills — the small "immediate surroundings" puddle.
static var pool_radius_base: float = 13.0
## Radius (px) a pool grows to at most, reached when a body is bled repeatedly in one spot.
static var pool_radius_max: float = 90.0
## Extra reach (px) beyond a pool's own radius within which a fresh hit still counts as landing on it
## (and so grows it). Larger = a body can drift further while bleeding and keep one growing pool.
static var detection_margin: float = 12.0
## Extra fill radius (px) per drop of accumulated volume above the first hit. Higher = the pool pools
## out to its max in fewer hits.
static var spread_per_volume: float = 0.5
## Random multiplier applied to each drop's target distance so the packing ring is uneven and
## the edge reads as organic rather than a perfect circle. Each drop draws from [min, max].
static var target_jitter_min: float = 0.85
static var target_jitter_max: float = 1.05
## Speed range (px/s) at which a released drop creeps from the wound to its spot in the pool.
static var speed_min: float = 50.0
static var speed_max: float = 90.0
## How far each drop's outward direction leans toward the shot direction, from none (0) to
## fully along the shot (1), so the puddle skews to the exit side of the wound.
static var directional_bias: float = 0.25
## Drawn blob radius (px): a drop grows from min toward max as it reaches its spot, so the
## pool reads as spreading blood rather than scattered dots. Max should exceed the packing
## spacing (≈ pool_radius_base / sqrt(particle_count)) so neighboring blobs merge into one puddle;
## the count scales with area as a pool spreads, so the spacing stays about constant.
static var drop_radius_min: float = 3.0
static var drop_radius_max: float = 6.5
## Radius (px) of the collision probe each drop sweeps to slide around obstacles. Small, so
## blood creeps right up to a surface before hugging it.
static var query_radius: float = 2.0
## How lumpy each pool's outline is: the fill radius is warped by a per-pool random ring of radius
## multipliers spanning 1 ± this, so no two pools share a silhouette. 0 = a clean disc; higher =
## more pronounced bulges and pinches.
static var edge_irregularity: float = 0.5
## How far each drawn blob's radius varies per vertex (1 ± this), so blobs read as organic splats
## rather than circles. 0 = plain circles.
static var blob_wobble: float = 0.35
## Base pool color — dark red, semi-transparent, distinct from the debris "blood" chip tint
## so the two systems stay visually independent.
static var color: Color = Color(0.42, 0.02, 0.03, 0.85)
## Draw order: negative so pools sit under the player and furniture (like spent casings).
static var z_index: int = -2

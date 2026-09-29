class_name BloodConfig

## Tuning for the blood pooling system (scenes/physics/blood_*.gd): the pool of blood a flesh
## hit leaves, oozing out gradually and packing next to itself. A `class_name` holder of
## `static var`s — read as `BloodConfig.<name>`; there is no instance and no autoload.
##
## Blood pooling is its own physical reaction, kept separate from the debris and deformation
## knobs in PhysicsConfig: a shot seeds a pool that fills in over `spill_duration` — drops
## emerge one at a time from the wound, creep out to their spot in the growing puddle, slide
## around walls and furniture, and settle adjacent to the blood already there.

## Total drops a pool contains once full. More drops = a denser, more solid puddle.
static var particle_count: int = 36
## Seconds from the shot until the whole pool has emerged and set. Drops are released evenly
## across this window, so the pool visibly grows for the full duration.
static var spill_duration: float = 10.0
## Radius (px) of the finished pool. Drops fill a disc of this radius, packed by area so they
## sit next to each other rather than piling at the center.
static var pool_radius: float = 28.0
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
## spacing (≈ pool_radius / sqrt(particle_count)) so neighboring blobs merge into one puddle.
static var drop_radius_min: float = 3.0
static var drop_radius_max: float = 6.5
## Radius (px) of the collision probe each drop sweeps to slide around obstacles. Small, so
## blood creeps right up to a surface before hugging it.
static var query_radius: float = 2.0
## Base pool color — dark red, semi-transparent, distinct from the debris "blood" chip tint
## so the two systems stay visually independent.
static var color: Color = Color(0.42, 0.02, 0.03, 0.85)
## Draw order: negative so pools sit under the player and furniture (like spent casings).
static var z_index: int = -2

class_name PhysicsConfig

## Tuning for the Physics System (scenes/physics/): the force a hit imparts to a world
## object, how a shoved object settles, and the damage-deformation geometry/rendering.
##
## A `class_name` holder of `static var`s — read as `PhysicsConfig.<name>`; there is no
## instance and no autoload. Owns the impact force and deformation knobs shared by every
## hittable object (furniture and walls). Ballistics (fly-over/ricochet/penetration)
## live in BallisticsConfig; the character's walking-push knobs in CharacterConfig.

# --- Impact force (a hit shoves the struck object) ---
## Base impulse magnitude at full speed and a head-on hit. Scaled by the hit's speed
## factor (speed / muzzle speed) and by the penetration multipliers below.
static var impact_impulse: float = 2200.0
## Impulse multiplier when the bullet did NOT penetrate (ricochet or blocked/embedded).
static var impact_no_penetration_scale: float = 1.0
## Impulse multiplier when the bullet penetrated (passed through) — less force.
static var impact_penetration_scale: float = 0.5
## Fraction of a flying object's momentum (velocity × mass) handed to the kinematic
## character it strikes. <1 so the shove loses energy. (Rigid-vs-rigid and rigid-vs-wall
## momentum is resolved by the physics engine, not this.)
static var impact_transfer_scale: float = 0.6

# --- RigidBody2D behavior (the engine integrates the shoved objects) ---
## Linear damping applied to furniture bodies — the drag that brings a shove to rest.
static var body_linear_damp: float = 4.0
## Angular damping applied to furniture bodies — the drag that brings a spin to rest.
static var body_angular_damp: float = 4.0
## Enable continuous collision detection on furniture bodies (prevents a fast, light
## object from tunneling through a thin wall, at some CPU cost).
static var body_continuous_cd: bool = false

# --- Deformation (damage) ---
## Rebuild the struck object's / wall segment's collider to follow the deformed shape.
static var deform_update_collider: bool = true
## Max impacts remembered per object / per wall segment (oldest dropped past this).
static var deform_max_impacts: int = 24

## Dents ----------------------------------------------------------------------
## Dent depth in px per point of dealt damage (a hit's depth = damage × this, capped).
static var deform_depth_per_damage: float = 0.6
## Cap on a single impact's dent depth (px).
static var deform_max_depth: float = 10.0
## How far along the surface a dent/notch spreads from the impact point (px).
static var deform_radius: float = 14.0

## Missing pieces (chunks) ----------------------------------------------------
## Dealt damage at or above which an impact carves a "missing piece" instead of a dent.
static var deform_chunk_damage: float = 18.0
## Extra depth multiplier for a chunk carve vs a normal dent's depth.
static var deform_chunk_depth: float = 1.6
## How much wider a chunk's reach is than `deform_radius`.
static var deform_chunk_reach_scale: float = 2.2
## Random ± jitter fraction applied to a chunk carve so the bite looks torn.
static var deform_chunk_jitter: float = 0.35

## Cracks ---------------------------------------------------------------------
## Extra cracks per point of dent depth (added to a base of 2), and base crack length px.
static var deform_crack_count: float = 0.4
static var deform_crack_length: float = 7.0
## Line width of drawn cracks (px).
static var deform_crack_width: float = 1.0

## Bullet hole / scorch -------------------------------------------------------
## Bullet-hole radius as a fraction of dent depth (min 1.5px).
static var deform_hole_radius_scale: float = 0.4
## Base scorch-halo radius (px); grows with dent depth.
static var deform_scorch_radius: float = 3.0
## Scorch-halo opacity (0–1).
static var deform_scorch_alpha: float = 0.12

## Fill darkening -------------------------------------------------------------
## Max amount the fill color is darkened toward black at full accumulated damage.
static var deform_darken_max: float = 0.35
## Accumulated damage at which fill darkening reaches `deform_darken_max`.
static var deform_darken_full: float = 100.0

## Silhouette resolution ------------------------------------------------------
## Perimeter sample counts: points around a circle, and points per rect edge.
static var deform_circle_points: int = 44
static var deform_rect_points_per_edge: int = 12

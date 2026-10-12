class_name PhysicsConfig

## Tuning for the Physics System (scenes/physics/): the force a hit imparts to a world
## object, how a shoved object settles, and the damage-deformation geometry/rendering.
##
## A `class_name` holder of `static var`s — read as `PhysicsConfig.<name>`; there is no
## instance and no autoload. Owns the impact force and deformation knobs shared by every
## hittable object (furniture and walls). Ballistics (fly-over/ricochet/penetration)
## live in BallisticsConfig; the character's walking-push knobs in CharacterConfig.

## Physics layer mask walls and furniture live on: the ragdoll's wall sweep and the blood pools' and
## flows' collision queries all test against it.
static var wall_mask: int = 1

## Master switch for debris: off = hits spray no chips (Physics.spawn_debris spawns nothing).
static var debris_enabled: bool = true

## Master switch for hit particles: off = hits emit no entry/exit particle bursts (HitParticles spawns nothing).
static var hit_particles_enabled: bool = true
## Scales every burst's particle count (1 = the style tables as written); 0 emits nothing.
static var hit_particles_scale: float = 1.0
## Most particles one burst may hold, however hard the hit.
static var hit_particles_max: int = 24
## A bloody mark's colour on an object a bullet carried blood onto (alpha is scaled by how much it carried).
static var blood_mark_color: Color = Color(0.55, 0.04, 0.05)
## Radius (px) of that mark.
static var blood_mark_radius: float = 4.5

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
static var deform_depth_per_damage: float = 0.3
## Cap on a single impact's dent depth (px).
static var deform_max_depth: float = 5.0
## How far along the surface a dent/notch spreads from the impact point (px).
static var deform_radius: float = 7.0
## Thickness of solid a dent must leave in front of the object's opposite face (px), so
## repeated hits cave inward but never punch through and grow out the back.
static var deform_back_margin: float = 2.0
## Solid core kept at the shape's center, as a fraction of its half-extent: no dented point
## may enter it, so opposite dents can't meet and fold the silhouette inside out. Big
## furniture never dents this deep, so it only binds on a small body (a character).
static var deform_core_fraction: float = 0.3

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

# --- Ragdoll (ragdoll.gd: a 3D point-mass body falling onto the floor plane) ---
## Gravity pulling ragdoll points toward the floor (px/s²): 9.8 m/s² at ~62 px per metre (a
## character's 28 px shoulders ≈ 0.45 m).
static var ragdoll_gravity: float = 610.0
## Sub-steps per physics frame, and constraint passes per sub-step: more = stiffer joints.
static var ragdoll_substeps: int = 2
static var ragdoll_iterations: int = 6
## Air drag on every point (1/s).
static var ragdoll_air_drag: float = 0.3
## Sliding deceleration of a point touching the floor (px/s²): high, so planted feet hold and the
## body topples over them instead of skating.
static var ragdoll_floor_friction: float = 2400.0
## Fraction of a point's downward speed kept as bounce when it strikes the floor.
static var ragdoll_floor_bounce: float = 0.15
## Hardest the bones and joint limits may speed a point up (px/s²), and a cap on any point's
## speed (px/s): together they keep a fight between constraints and the floor from flinging the body.
static var ragdoll_max_push: float = 1800.0
static var ragdoll_max_speed: float = 700.0
## How fast a limited joint's child is pulled toward its joint's velocity (1/s): limbs swing as
## heavy, loose parts rather than whipping.
static var ragdoll_joint_friction: float = 4.0
## A body sleeps once every point has stayed under this speed (px/s) for `ragdoll_sleep_time` (s),
## or after `ragdoll_max_time` (s) regardless.
static var ragdoll_sleep_speed: float = 5.0
static var ragdoll_sleep_time: float = 0.4
static var ragdoll_max_time: float = 5.0

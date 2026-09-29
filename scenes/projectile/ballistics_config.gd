class_name BallisticsConfig

## Ballistics tuning for the Projectile System (scenes/projectile/projectile.gd).
##
## A `class_name` holder of `static var`s — read as `BallisticsConfig.<name>`; there
## is no instance and no autoload. Owns ONLY the shooting model: muzzle speed, the
## speed thresholds, and the fly-over / ricochet / penetration knobs. The force a hit
## imparts and the visual deformation it causes belong to the Physics System
## (PhysicsConfig); the character's walking-push knobs belong to CharacterConfig.
##
## A bullet is a multi-hit traveler: on each collider it either flies over (no effect),
## ricochets, or penetrates (dealing damage, bleeding speed), and it frees itself once
## its speed drops below `projectile_min_speed` or it exceeds its own `max_distance`.
## Coverage/penetration come from the struck object's surface (see Objects'
## `get_surface()`, 0–100); a collider without a surface uses the `wall_*` fallbacks.

## Default projectile muzzle (top) speed in px/s. Copied onto each bullet's own
## `speed` at spawn (the projectile can still be overridden per-instance there).
static var projectile_speed: float = 3200.0

## Below this speed (px/s) a bullet is spent and frees itself. Head-on hits on hard
## material collapse speed past this in a hit or two, so walls naturally stop bullets.
static var projectile_min_speed: float = 800.0

## Minimum speed (px/s) required to penetrate. A bullet slower than this can no longer
## punch through a solid object: it's blocked — deals the impact and then stops
## (embeds). Fly-over and ricochet are unaffected. Set to the un-doubled muzzle speed,
## so penetration only happens in the upper half of the speed range.
static var penetration_min_speed: float = 1600.0

## Coverage/penetration used for colliders that expose no surface (rare — walls now
## report their own): full cover (never flown over) and high penetration.
static var wall_coverage: float = 100.0
static var wall_penetration: float = 100.0

## Fly-over: chance = clamp((1 − coverage/100) × this, 0, 1). At 1.0, coverage 30 is
## cleared ~70% of the time and coverage 90 ~10%; coverage 100 is never flown over.
static var cover_flyover_scale: float = 1.0

## Ricochet: only material with penetration ≥ this can bounce, and only on a glancing
## hit (squareness < `bounce_square_max`). Head-on shots always penetrate instead.
static var penetration_bounce_min: float = 80.0
## Squareness (|dir · normal|, 1 = head-on) below which a hard hit ricochets.
static var bounce_square_max: float = 0.5
## Fraction of the (already squareness-scaled) damage a ricochet still deals.
static var bounce_damage_retention: float = 0.3
## Fraction of speed kept after a ricochet.
static var bounce_speed_retention: float = 0.6

## Penetration speed loss: loss = clamp((penetration/100) × this × (2 − squareness),
## 0, 1); speed ×= (1 − loss). Glancing hits (squareness→0) bleed more than head-on.
static var penetrate_loss_scale: float = 0.9
## Max random deflection on penetration, scaled by penetration/100. Degrees.
static var penetrate_deflect_max_deg: float = 12.0

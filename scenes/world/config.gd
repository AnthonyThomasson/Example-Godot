extends Node

## General gameplay configuration — the one place to tune shared numbers.
##
## Autoloaded as `Config` (see project.godot [autoload]), so any script can read
## `Config.<name>`. Edit the values here; keep this file free of behavior — it is
## data only. Systems that use these:
##   - Despawner   reads `max_scene_objects` to cap transient debris (casings, ...).
##   - ProjectileSpawner reads `projectile_speed` as each bullet's default speed.

## Max number of tracked debris objects (casings, etc.) allowed in the scene at
## once. Spawning past this frees the oldest — see scenes/world/despawner.gd.
var max_scene_objects: int = 100

## Default projectile travel speed in px/s. Copied onto each bullet's own `speed`
## at spawn (the projectile can still be overridden per-instance there).
var projectile_speed: float = 1600.0

# --- Projectile impact (coverage / penetration) ---
## Read by scenes/projectile/projectile.gd. A bullet is now a multi-hit traveler:
## on each collider it strikes it either flies over (no effect), ricochets, or
## penetrates (dealing damage and bleeding speed), and it frees itself once its
## speed drops below `projectile_min_speed` or it exceeds its own `max_distance`.
## Coverage/penetration come from the struck object (environment_object.gd, 0–100);
## a collider without them (a room wall) uses the `wall_*` fallbacks below.

## Below this speed (px/s) a bullet is spent and frees itself. Head-on hits on hard
## material collapse speed past this in a hit or two, so walls naturally stop bullets.
var projectile_min_speed: float = 200.0

## Coverage/penetration used for colliders that expose neither (e.g. room walls):
## full cover (never flown over) and high penetration (glancing shots ricochet,
## head-on shots stop the bullet fast).
var wall_coverage: float = 100.0
var wall_penetration: float = 100.0

## Fly-over: chance = clamp((1 − coverage/100) × this, 0, 1). At 1.0, coverage 30 is
## cleared ~70% of the time and coverage 90 ~10%; walls (coverage 100) are never
## flown over. Raise for a "shoot over low cover" feel, lower to make hits reliable.
var cover_flyover_scale: float = 1.0

## Ricochet: only material with penetration ≥ this can bounce, and only on a glancing
## hit (squareness < `bounce_square_max`). Head-on shots always penetrate instead.
var penetration_bounce_min: float = 80.0
## Squareness (|dir · normal|, 1 = head-on) below which a hard hit ricochets.
var bounce_square_max: float = 0.5
## Fraction of the (already squareness-scaled) damage a ricochet still deals.
var bounce_damage_retention: float = 0.3
## Fraction of speed kept after a ricochet.
var bounce_speed_retention: float = 0.6

## Penetration speed loss: loss = clamp((penetration/100) × this × (2 − squareness),
## 0, 1); speed ×= (1 − loss). Glancing hits (squareness→0) bleed more than head-on.
var penetrate_loss_scale: float = 0.9
## Max random deflection on penetration, scaled by penetration/100 (harder material
## deflects the bullet more). Degrees; the bullet turns by ±(this × penetration/100).
var penetrate_deflect_max_deg: float = 12.0

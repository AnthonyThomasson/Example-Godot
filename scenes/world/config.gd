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

## Default projectile muzzle (top) speed in px/s. Copied onto each bullet's own
## `speed` at spawn (the projectile can still be overridden per-instance there).
var projectile_speed: float = 3200.0

# --- Projectile impact (coverage / penetration) ---
## Read by scenes/projectile/projectile.gd. A bullet is now a multi-hit traveler:
## on each collider it strikes it either flies over (no effect), ricochets, or
## penetrates (dealing damage and bleeding speed), and it frees itself once its
## speed drops below `projectile_min_speed` or it exceeds its own `max_distance`.
## Coverage/penetration come from the struck object (environment_object.gd, 0–100);
## a collider without them (a room wall) uses the `wall_*` fallbacks below.

## Below this speed (px/s) a bullet is spent and frees itself. Head-on hits on hard
## material collapse speed past this in a hit or two, so walls naturally stop bullets.
var projectile_min_speed: float = 800.0

## Minimum speed (px/s) required to penetrate. A bullet moving slower than this can
## no longer punch through a solid object: it's blocked — it deals the impact and
## then stops (embeds), rather than passing through. Fly-over and ricochet are
## unaffected (they don't depend on punch-through). Set to the un-doubled muzzle
## speed, so penetration only happens in the upper half of the speed range.
var penetration_min_speed: float = 1600.0

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

# --- Projectile impact force ---
## Read by scenes/projectile/projectile.gd: on a damaging hit the bullet shoves the
## struck object (environment_object.gd) along its travel direction, harder when it
## did not penetrate (a ricochet or a blocked/embedded shot dumps more momentum than
## a pass-through). Objects slide and settle; walls (no apply_impact) never move.

## Base impulse magnitude at full speed and a head-on hit. Scaled by the bullet's
## speed factor (speed / projectile_speed) and by the penetration multipliers below.
var impact_impulse: float = 2200.0
## Impulse multiplier when the bullet did NOT penetrate (ricochet or blocked/embedded).
var impact_no_penetration_scale: float = 1.0
## Impulse multiplier when the bullet penetrated (passed through) — less force.
var impact_penetration_scale: float = 0.5
## Deceleration (px/s²) that brings a shoved object back to rest.
var impact_friction: float = 1400.0
## Cap on how far an object can be displaced from its origin (px). `<= 0` means no
## cap — objects settle via friction wherever they stop, so they can be pushed clear
## across a room. A positive value re-caps displacement (objects snap back if exceeded).
## Shared by the projectile impact and the walking-push systems.
var impact_max_slide: float = 0.0
## Fraction of the shoving object's momentum (velocity × weight) handed to whatever
## it collides with (another EnvironmentObject) on a shove. <1 so cascades lose energy
## and settle rather than propagating forever. Walls have no apply_impact and get none.
var impact_transfer_scale: float = 0.6

# --- Push (walking into objects) ---
## Read by scenes/player/player.gd. Walking the player body into a pushable object
## (anything with apply_impact — i.e. furniture, not walls) shoves it via the same
## apply_impact pipeline the projectile uses, so a push is divided by the object's
## `weight`: light objects slide easily, heavy ones barely move. Pushing also slows
## the player (heavier = slower), and a fast object sliding into the player shoves the
## player back (they're pushable too, via player.apply_impact).

## Base impulse the player imparts to an object per physics frame of contact, scaled by
## how hard the player is moving into it (input strength 0–1).
var push_impulse: float = 900.0
## How much each unit of the pushed object's `weight` reduces the player's speed while
## pushing (speed_mult = 1 − heaviest_weight × this, floored by `push_slow_min`).
var push_slow_per_weight: float = 0.02
## Floor on the player's speed multiplier while pushing, so heavy objects nearly stop
## the player but never fully lock movement.
var push_slow_min: float = 0.15
## The player's mass for *incoming* knockback: an object sliding into the player shoves
## them by impulse / this. Higher = the player shrugs off hits unless struck hard.
var player_mass: float = 40.0
## Deceleration (px/s²) that bleeds the player's knockback velocity back to zero.
var push_knockback_friction: float = 1600.0

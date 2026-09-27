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

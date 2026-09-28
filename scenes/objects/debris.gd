extends Node2D

## Debris CONTROL layer. A small chip knocked off an object when it is hit, styled by
## the struck object's material (see debris_spawner.gd). It has no collider — pure
## world-space debris. The spawner calls start() with an eject direction; a tween
## slides + spins it out, then it simply rests on the floor. Like a casing it is NOT
## time-limited: chips persist until the general Despawner frees the oldest once the
## tracked count passes Config.max_scene_objects. Drawing lives in debris_visuals.gd.

## Chip color (read by debris_visuals.gd).
@export var color: Color = Color(0.6, 0.6, 0.6)
## Chip footprint in px (read by debris_visuals.gd).
@export var chip_size: Vector2 = Vector2(4, 4)
## Chip shape: "rect", "tri", or "circle" (read by debris_visuals.gd).
@export var chip_shape: String = "rect"
## How far the chip travels as it is ejected (px). Set per-instance by the spawner.
@export var eject_distance: float = 22.0
## Seconds spent flying out before it comes to rest.
@export var eject_time: float = 0.25


## Kick the chip out along `eject_dir` (need not be normalized), spin it, then let it
## rest. Called by DebrisSpawner right after add_child.
func start(eject_dir: Vector2) -> void:
	var dir := eject_dir.normalized() if eject_dir.length() > 0.001 else Vector2.RIGHT
	var target := position + dir * eject_distance
	var spin := TAU * randf_range(-1.5, 1.5)
	rotation = randf_range(0.0, TAU)

	# Fly out and spin (ease-out so it decelerates as it lands), then rest.
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(self, "position", target, eject_time).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "rotation", rotation + spin, eject_time).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

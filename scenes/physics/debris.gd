extends Node2D

## A small chip knocked off an object when it is hit: colliderless world-space debris that
## tweens out, spins, and rests. Styled by DebrisSpawner, Despawner-tracked. Drawing lives
## in debris_visuals.gd.

## Chip fill color.
@export var color: Color = Color(0.6, 0.6, 0.6)
## Chip footprint in px.
@export var chip_size: Vector2 = Vector2(4, 4)
## Chip shape: "rect", "tri", or "circle".
@export var chip_shape: String = "rect"
## How far the chip travels as it is ejected (px).
@export var eject_distance: float = 22.0
## Seconds spent flying out before it comes to rest.
@export var eject_time: float = 0.25


## Kick the chip out along `eject_dir` (need not be normalized), spin it, and let it settle.
func start(eject_dir: Vector2) -> void:
	var dir := eject_dir.normalized() if eject_dir.length() > 0.001 else Vector2.RIGHT
	var target := position + dir * eject_distance
	var spin := TAU * randf_range(-1.5, 1.5)
	rotation = randf_range(0.0, TAU)

	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(self, "position", target, eject_time).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "rotation", rotation + spin, eject_time).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

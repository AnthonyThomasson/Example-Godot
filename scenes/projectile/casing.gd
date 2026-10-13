extends Node2D

## A spent shell tossed out when a gun fires: colliderless world-space debris that tweens
## out, spins, and rests. Despawner-tracked. Drawing lives in casing_visuals.gd.

## Brass fill color.
@export var color: Color = Color(0.85, 0.7, 0.3)
## How far the casing travels as it is ejected (px).
@export var eject_distance: float = 15.0
## Seconds spent flying out before it comes to rest.
@export var eject_time: float = 0.3


func _ready() -> void:
	z_index = -1  # Draw beneath the player and furniture.


## Kick the casing out along `eject_dir` (need not be normalized) and let it settle.
func start(eject_dir: Vector2) -> void:
	var dir := eject_dir.normalized() if eject_dir.length() > 0.001 else Vector2.RIGHT
	var target := position + dir * eject_distance
	var spin := TAU * (1.0 if randf() > 0.5 else -1.0)

	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(self, "position", target, eject_time).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "rotation", rotation + spin, eject_time).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

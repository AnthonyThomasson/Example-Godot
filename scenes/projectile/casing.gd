extends Node2D

## Casing CONTROL layer. A spent shell ejected sideways when a gun fires. It has
## no collider — it is pure world-space debris. The spawner calls start() with an
## eject direction; a tween slides + spins it out, then it simply rests on the
## floor. It is NOT time-limited: casings persist until the general Despawner
## frees the oldest once the tracked count passes Config.max_scene_objects.
## Drawing lives in casing_visuals.gd.

## Brass color (read by casing_visuals.gd).
@export var color: Color = Color(0.85, 0.7, 0.3)
## How far the casing travels as it is ejected (px).
@export var eject_distance: float = 26.0
## Seconds spent flying out before it comes to rest.
@export var eject_time: float = 0.3


func _ready() -> void:
	# Draw beneath the player and furniture, like non-solid decor.
	z_index = -1


## Kick the casing out along `eject_dir` (need not be normalized), then let it
## rest. Called by CasingSpawner right after add_child.
func start(eject_dir: Vector2) -> void:
	var dir := eject_dir.normalized() if eject_dir.length() > 0.001 else Vector2.RIGHT
	var target := position + dir * eject_distance
	var spin := TAU * (1.0 if randf() > 0.5 else -1.0)

	# Fly out and spin (ease-out so it decelerates as it lands), then rest.
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(self, "position", target, eject_time).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "rotation", rotation + spin, eject_time).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

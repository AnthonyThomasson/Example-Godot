extends Node2D

## Draw layer for a bullet: a short streak along local +X (the bullet rotates itself to
## face travel). Reads `length` / `color` from the projectile.

@onready var _control := get_parent()  ## The projectile (control node).


func _draw() -> void:
	var length: float = _control.length
	var color: Color = _control.color
	draw_line(Vector2(-length, 0.0), Vector2.ZERO, color, 1.8)  # Trail behind the leading point.
	draw_circle(Vector2.ZERO, 1.2, color)

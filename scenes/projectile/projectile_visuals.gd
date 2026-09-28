extends Node2D

## Projectile DRAW layer. Renders the bullet as a short streak along the parent's
## local +X axis; the control node (projectile.gd) sets its own `rotation` so the
## streak points the way the bullet flies. Reads `length` / `color` from control.

@onready var _control := get_parent()  ## Projectile — streak length and color.


func _draw() -> void:
	var length: float = _control.length
	var color: Color = _control.color
	# Trail behind the leading point (which sits at the parent's origin).
	draw_line(Vector2(-length, 0.0), Vector2.ZERO, color, 1.8)
	draw_circle(Vector2.ZERO, 1.2, color)

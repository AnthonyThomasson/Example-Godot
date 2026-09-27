extends Node2D

## Casing DRAW layer. Renders the spent shell as a tiny brass rectangle. Reads
## `color` from the control node (casing.gd); the parent's rotation spins it.

@onready var _control := get_parent()  ## Casing — brass color.


func _draw() -> void:
	var color: Color = _control.color
	# A small shell: a rounded-ish brass rect centered on the origin.
	draw_rect(Rect2(-4.0, -2.0, 8.0, 4.0), color)
	draw_rect(Rect2(-4.0, -2.0, 8.0, 4.0), Color(0.5, 0.4, 0.15), false, 1.0)

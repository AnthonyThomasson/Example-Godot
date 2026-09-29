extends Node2D

## Draw layer for a casing: a tiny brass rectangle. Reads `color` from the casing.

@onready var _control := get_parent()  ## The casing (control node).


func _draw() -> void:
	var color: Color = _control.color
	draw_rect(Rect2(-2.25, -1.0, 4.5, 2.0), color)
	draw_rect(Rect2(-2.25, -1.0, 4.5, 2.0), Color(0.5, 0.4, 0.15), false, 1.0)

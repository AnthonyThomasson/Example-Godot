extends Node2D

## Debris DRAW layer. Reads chip color/size/shape off its parent control node
## (debris.gd) and draws a single small chip centered on the origin.

@onready var _control := get_parent()  ## Debris — chip color/size/shape.

func _draw() -> void:
	var color: Color = _control.color
	var s: Vector2 = _control.chip_size
	match _control.chip_shape:
		"circle":
			draw_circle(Vector2.ZERO, s.x * 0.5, color)
		"tri":
			var pts := PackedVector2Array([
				Vector2(0.0, -s.y * 0.5),
				Vector2(s.x * 0.5, s.y * 0.5),
				Vector2(-s.x * 0.5, s.y * 0.5),
			])
			draw_colored_polygon(pts, color)
		_:  # "rect"
			draw_rect(Rect2(-s * 0.5, s), color)

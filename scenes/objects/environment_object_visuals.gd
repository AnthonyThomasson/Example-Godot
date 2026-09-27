extends Node2D

@onready var _obj := get_parent()

func _process(_delta: float) -> void:
	queue_redraw()

func _draw() -> void:
	var shape := _obj.shape_type
	var size := _obj.size
	var color := _obj.color
	var text_color := _obj.text_color

	match shape:
		"circle":
			var radius := size.x / 2.0
			draw_circle(Vector2.ZERO, radius, color)
			draw_arc(Vector2.ZERO, radius, 0.0, TAU, 24, text_color, 1.5, true)

		"square", "rect":
			draw_rect(Rect2(-size / 2.0, size), color)
			draw_rect(Rect2(-size / 2.0, size), text_color, false, 1.5)

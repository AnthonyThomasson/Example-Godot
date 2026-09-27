extends Node2D

@onready var _obj := get_parent()

func _draw() -> void:
	var shape := _obj.shape_type
	var size := _obj.size
	var color := _obj.color
	var text_color := _obj.text_color
	var label := _obj.object_name

	match shape:
		"circle":
			draw_circle(Vector2.ZERO, size.x / 2.0, color)

		"square", "rect":
			draw_rect(Rect2(-size / 2.0, size), color)

	var font := ThemeDB.fallback_font
	var font_size := ThemeDB.fallback_font_size
	var text_size := font.get_string_size(label, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size)
	var text_pos := -text_size / 2.0
	draw_string(font, text_pos, label, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size, text_color)

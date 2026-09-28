extends Node2D

@onready var _obj := get_parent()

func _process(_delta: float) -> void:
	queue_redraw()

func _draw() -> void:
	var shape: String = _obj.shape_type
	var size: Vector2 = _obj.size
	var color: Color = _obj.color
	var text_color: Color = _obj.text_color

	# Damage-deformed silhouette (dents, missing pieces) + crack/hole marks.
	Deformation.draw_shape(self, shape, size, color, text_color, _obj._impacts, _obj._damage_total)

	# Draw the object's name centered on it.
	var name_text: String = _obj.object_name
	var font: Font = ThemeDB.fallback_font
	var font_size := 14
	var text_size := font.get_string_size(name_text, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size)
	var pos := Vector2(-text_size.x / 2.0, font_size / 2.0)
	draw_string(font, pos, name_text, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size, text_color)

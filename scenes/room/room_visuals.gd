extends Node2D

## Room DRAW layer. Draws the placeholder wall lines, matching the colliders built
## by the control node (room.gd). Reads the geometry (`wall_segments()`) and line
## width (`wall_thickness`) from the parent, so this file owns appearance only.

@export var line_color: Color = Color(0.7, 0.7, 0.7)

@onready var _room := get_parent()  ## Room (StaticBody2D) — wall geometry source.


func _ready() -> void:
	# The parent's _ready has already run (parent before child), so segments exist.
	# Walls are static, so a single draw is enough.
	queue_redraw()


func _draw() -> void:
	for seg in _room.wall_segments():
		if not seg[0].is_equal_approx(seg[1]):
			draw_line(seg[0], seg[1], line_color, _room.wall_thickness)

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
	var t: float = _room.wall_thickness
	for seg in _room.wall_segments():
		if seg[0].is_equal_approx(seg[1]):
			continue
		# Extend the ends by half the thickness, exactly like the colliders in room.gd,
		# so corners close up and doorways look as wide as they really are.
		var dir: Vector2 = (seg[1] - seg[0]).normalized()
		draw_line(seg[0] - dir * t * 0.5, seg[1] + dir * t * 0.5, line_color, t)

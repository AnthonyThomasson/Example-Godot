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
	var segs: Array = _room.wall_segments()
	for i in segs.size():
		var seg: PackedVector2Array = segs[i]
		if seg[0].is_equal_approx(seg[1]):
			continue
		# Deformed segment (dents / missing pieces where damaged) + crack/hole marks.
		# The helper extends the ends by half-thickness, matching the colliders in room.gd.
		Deformation.draw_wall(self, seg[0], seg[1], t, line_color, _room._seg_impacts.get(i, []))

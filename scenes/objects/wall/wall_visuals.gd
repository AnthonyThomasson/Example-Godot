extends Node2D

## Wall DRAW layer (Objects domain). Draws the wall caps, matching the colliders built by the
## control node (wall.gd): its pixel-art tile repeated along each segment, or a flat line when
## the wall has no art. Reads the geometry (`wall_segments()`), width (`wall_thickness`) and look
## (`art`, `art_color`, `art_opts`) from the parent, so this file owns appearance only.

const ObjectArt = preload("res://scenes/objects/art/object_art.gd")

@export var line_color: Color = Color(0.7, 0.7, 0.7)  ## Flat wall line color (walls without art).

@onready var _wall := get_parent()  ## Wall (StaticBody2D) — wall geometry source.
var _tile: Texture2D  ## The cap tile (x along the wall, y across it), or null for a flat line.


func _ready() -> void:
	if _wall.art != "":
		texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
		_tile = ObjectArt.texture(_wall.art, Vector2(ObjectArtConfig.wall_tile_px, _wall.wall_thickness),
				_wall.art_color, Vector2.DOWN, "", _wall.art_opts)
	# The parent's _ready has already run (parent before child), so segments exist.
	# Walls are static, so a single draw is enough.
	queue_redraw()


func _draw() -> void:
	var t: float = _wall.wall_thickness
	var segs: Array = _wall.wall_segments()
	for i in segs.size():
		var seg: PackedVector2Array = segs[i]
		if seg[0].is_equal_approx(seg[1]):
			continue
		# Deformed segment (dents / missing pieces where damaged) + crack/hole marks.
		# The helper extends the ends by half-thickness, matching the colliders in wall.gd.
		Deformation.draw_wall(self, seg[0], seg[1], t, line_color, _wall._seg_impacts.get(i, []),
				_tile, ObjectArtConfig.wall_tile_px)

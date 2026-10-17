extends Node2D

## Wall DRAW layer (Objects domain). Draws the wall caps, matching the colliders built by the
## control node (wall.gd): its pixel-art tile repeated along each segment, or a flat line when
## the wall has no art. Reads the geometry (`wall_segments()`), width (`wall_thickness`) and look
## (`art`, `art_color`, `art_opts`) from the parent, so this file owns appearance only. What in the cap tile gives light
## (`emissive()`; none of the caps glows) is drawn again by a child `Emissive` layer.

const ObjectArt = preload("res://scenes/objects/art/object_art.gd")
const EmissiveLayer = preload("res://scenes/objects/emissive_layer.gd")

@export var line_color: Color = Color(0.7, 0.7, 0.7)  ## Flat wall line color (walls without art).

@onready var _wall := get_parent()  ## Wall (StaticBody2D) — wall geometry source.
var _tile: Texture2D  ## The cap tile (x along the wall, y across it), or null for a flat line.
var _emissive: Texture2D  ## The tile's light-giving pixels, or null.
var _emissive_layer: Node2D  ## The child drawing `_emissive` (null without one).
## One child per wall segment (`wall_segments()` order), each drawing its own segment: a struck segment repaints alone
## (`redraw_segment`), the others keep their drawing. They draw in segment order.
var _segments: Array[Node2D] = []
var _segs: Array = []  ## The segments as they were at `_ready` (a wall's openings never change).


func _ready() -> void:
	if _wall.art != "":
		texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
		var tile_size := Vector2(ObjectArtConfig.wall_tile_px, _wall.wall_thickness)
		_tile = ObjectArt.texture(_wall.art, tile_size, _wall.art_color, Vector2.DOWN, "", _wall.art_opts)
		_emissive = ObjectArt.emissive(_wall.art, tile_size, _wall.art_color, Vector2.DOWN, "", _wall.art_opts)
		if _emissive:
			_emissive_layer = EmissiveLayer.new().setup(self)
	# The parent's _ready has already run (parent before child), so segments exist.
	# Walls are static, so each segment draws once, and again when it is struck.
	_segs = _wall.wall_segments()
	for i in _segs.size():
		var piece := Node2D.new()
		piece.name = "Segment%d" % i
		piece.draw.connect(_draw_segment.bind(piece, i))
		add_child(piece)
		_segments.append(piece)
	if _emissive_layer:
		move_child(_emissive_layer, -1)  # Over every segment, as over the whole wall.


## Repaint segment `i` (its dents changed), and the light-giving overlay that follows the dents.
func redraw_segment(i: int) -> void:
	if i >= 0 and i < _segments.size():
		_segments[i].queue_redraw()
	if _emissive_layer:
		_emissive_layer.queue_redraw()


## What in the cap tile gives light, or null when nothing does. Drawn over the walls by the `Emissive` child.
func emissive() -> Texture2D:
	return _emissive


## The `Emissive` child layer (null when the cap has nothing that gives light).
func emissive_layer() -> Node2D:
	return _emissive_layer


## Draw the light-giving pixels of the cap onto `layer` (the `Emissive` child) along every segment, as the cap is.
func draw_emissive(layer: CanvasItem) -> void:
	var t: float = _wall.wall_thickness
	var segs: Array = _wall.wall_segments()
	for i in segs.size():
		var seg: PackedVector2Array = segs[i]
		if not seg[0].is_equal_approx(seg[1]):
			Deformation.draw_wall(layer, seg[0], seg[1], t, line_color, _wall._seg_impacts.get(i, []), _emissive,
					ObjectArtConfig.wall_tile_px)


## Segment `i` on its child `piece`: the deformed segment (dents / missing pieces where damaged) + crack/hole marks. The helper
## extends the ends by half-thickness, matching the colliders in wall.gd.
func _draw_segment(piece: Node2D, i: int) -> void:
	var seg: PackedVector2Array = _segs[i]
	if seg[0].is_equal_approx(seg[1]):
		return
	Deformation.draw_wall(piece, seg[0], seg[1], _wall.wall_thickness, line_color, _wall._seg_impacts.get(i, []),
			_tile, ObjectArtConfig.wall_tile_px)

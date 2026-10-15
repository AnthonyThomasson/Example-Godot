extends Node2D

## Floor DRAW layer (Objects domain): repeats the floor's pixel-art tile across its rect, scaled so
## one art pixel covers ArtConfig.pixel_size world px (its grid from `tile_offset`), and lays the floor's world-placed
## `marks` over it (a street's: a child StreetMarks layer, street_marks.gd). What in the tile gives light (`emissive()`; none of the floors glows) is drawn
## again by a child `Emissive` layer. Floors are static: one draw.

const ObjectArt = preload("res://scenes/objects/art/object_art.gd")
const EmissiveLayer = preload("res://scenes/objects/emissive_layer.gd")
const StreetMarks = preload("res://scenes/objects/decals/street_marks.gd")

@onready var _floor := get_parent()  ## Floor — extent and look source.
var _tile: Texture2D  ## The repeating tile.
var _emissive: Texture2D  ## The tile's light-giving pixels, or null.
var _emissive_layer: Node2D  ## The child drawing `_emissive` (null without one).


func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	_tile = ObjectArt.tile(_floor.art, _floor.color, _floor.floor_material, _floor.art_opts)
	_emissive = ObjectArt.tile_emissive(_floor.art, _floor.color, _floor.floor_material, _floor.art_opts)
	if not (_floor.marks as Dictionary).is_empty():
		StreetMarks.new().setup_marks(self, _floor.size, _floor.art_opts, _floor.marks, _floor.tile_offset)
	if _emissive:
		_emissive_layer = EmissiveLayer.new().setup(self)
	queue_redraw()


## What in the floor's tile gives light, or null when nothing does. Drawn over the floor by the `Emissive` child.
func emissive() -> Texture2D:
	return _emissive


## The `Emissive` child layer (null when the floor has nothing that gives light).
func emissive_layer() -> Node2D:
	return _emissive_layer


func _draw() -> void:
	_draw_tiled(self, _tile)


## Draw the light-giving pixels of the tile onto `layer` (the `Emissive` child), tiled as the floor is.
func draw_emissive(layer: CanvasItem) -> void:
	_draw_tiled(layer, _emissive)


## Draw `tile` repeated over the floor on `canvas`, laid from the floor's `tile_offset` (nothing for a null tile).
func _draw_tiled(canvas: CanvasItem, tile: Texture2D) -> void:
	if tile == null:
		return
	var scale_px := ArtConfig.pixel_size
	var size: Vector2 = _floor.size / scale_px
	canvas.draw_set_transform(Vector2.ZERO, 0.0, Vector2(scale_px, scale_px))
	canvas.draw_texture_rect_region(tile, Rect2(Vector2.ZERO, size), Rect2(_floor.tile_offset / scale_px, size), Color.WHITE, false, false)

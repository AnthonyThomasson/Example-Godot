extends Node2D

## Floor DRAW layer (Objects domain): repeats the floor's pixel-art tile across its rect, scaled so
## one art pixel covers ObjectArtConfig.pixel_size world px. Floors are static: one draw.

const ObjectArt = preload("res://scenes/objects/art/object_art.gd")

@onready var _floor := get_parent()  ## Floor — extent and look source.
var _tile: Texture2D  ## The repeating tile.


func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	_tile = ObjectArt.tile(_floor.art, _floor.color, _floor.floor_material, _floor.art_opts)
	queue_redraw()


func _draw() -> void:
	if _tile == null:
		return
	var scale_px := ObjectArtConfig.pixel_size
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(scale_px, scale_px))
	draw_texture_rect(_tile, Rect2(Vector2.ZERO, _floor.size / scale_px), true)

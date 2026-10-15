extends Node2D

## A batch of pixel-art marks drawn where they lie (Objects domain): a room's wear, the street's marks and litter. One node
## draws them all, once, on its own draw-order rung (`setup`); draw-only: no collider, no nav change, registers nothing.

var _decals: Array = []  ## `[texture, rect]` per mark, in the layer's frame.


## Name the layer `layer_name` and put it on draw-order rung `z` (relative to its parent); returns it.
func setup(layer_name: String, z: int) -> Node2D:
	name = layer_name
	z_index = z
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	return self


## Draw `texture` stretched over `rect` (the layer's frame; at ArtConfig.pixel_size one texel per art pixel).
func add(texture: Texture2D, rect: Rect2) -> void:
	if texture:
		_decals.append([texture, rect])
		queue_redraw()


## How many marks the layer holds.
func count() -> int:
	return _decals.size()


func _draw() -> void:
	for d: Array in _decals:
		draw_texture_rect(d[0], d[1], false)

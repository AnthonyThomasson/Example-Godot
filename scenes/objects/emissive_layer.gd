extends Node2D

## The light-source overlay of an Objects visuals node (a piece's, a floor's or a wall's): a child `Emissive` drawn over its
## art, drawing only what in that art gives light (a screen's face, a neon tube, a bulb: the pixels its painter drew
## `glowing`, ObjectArt.emissive) through the same geometry. Its own canvas item, drawn UNSHADED: neither the dusk ambient nor
## any light changes a light source, while the art under it is lit like anything else; the Lighting domain dims it with the
## piece's light (its `modulate`, through the piece's `get_lights()` `glow`). Draw-only, it reads nothing but its parent's
## `draw_emissive(canvas)`.

static var _unshaded: CanvasItemMaterial


## Make this the `Emissive` child of `visuals` (which has `draw_emissive(canvas: CanvasItem)`) and return it.
func setup(visuals: Node2D) -> Node2D:
	name = "Emissive"
	if _unshaded == null:
		_unshaded = CanvasItemMaterial.new()
		_unshaded.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
	material = _unshaded
	use_parent_material = false
	texture_filter = visuals.texture_filter
	texture_repeat = visuals.texture_repeat
	visuals.add_child(self)
	return self


func _draw() -> void:
	get_parent().draw_emissive(self)

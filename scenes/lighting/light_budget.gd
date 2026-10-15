extends RefCounted

## Lighting domain (private): the per-floor light budget. Godot 4.4 lights a canvas item with at most 15 point lights and
## drops the rest, and a floor (with its room's walls and wear) is lit as one item: so no floor may be reached by more than
## `LightingConfig.per_floor()` of the world's piece and fixture lights (the flash pool keeps the rest of the 15). A light
## reaches a floor when its pool's box (its texture, scaled and turned) meets the floor's rect, grown by
## `LightingConfig.floor_reach` for the walls and wear drawn a little past it, and its item mask meets the floor's light
## layers (a house light never reaches the street, `LightMasks.STREET`).

var _rects: Array[Rect2] = []  ## Each floor's world rect, grown.
var _masks: PackedInt32Array = []  ## Each floor's light layers (the union over its canvas items).
var _load: PackedInt32Array = []  ## Each floor's lights so far.


## Count against floor `ground` (an Objects Floor: `size`, its canvas items' `light_mask`).
func add_floor(ground: Node2D) -> void:
	_rects.append(Rect2(ground.global_position, ground.get("size")).grow(LightingConfig.floor_reach))
	var mask := ground.light_mask
	for item in ground.find_children("*", "CanvasItem", true, false):
		mask |= (item as CanvasItem).light_mask
	_masks.append(mask)
	_load.append(0)


## Whether a light whose pool covers world rect `box` and lights items `item_mask` leaves every floor it reaches within the
## budget, counting it there if so; `always` counts it whatever (a room's own fixture).
func take(box: Rect2, item_mask: int, always := false) -> bool:
	var per_floor := LightingConfig.per_floor()
	for k in _rects.size():
		if not always and _reaches(k, box, item_mask) and _load[k] >= per_floor:
			return false
	for k in _rects.size():
		if _reaches(k, box, item_mask):
			_load[k] += 1
	return true


## The most lights any one floor is reached by.
func most() -> int:
	var out := 0
	for n in _load:
		out = maxi(out, n)
	return out


## Whether a light covering `box` and lighting items `item_mask` reaches floor `k`.
func _reaches(k: int, box: Rect2, item_mask: int) -> bool:
	return _masks[k] & item_mask != 0 and _rects[k].intersects(box)


## The world rect the pool of light `l` covers when placed by world transform `xf`.
static func box_of(l: PointLight2D, xf: Transform2D) -> Rect2:
	var half := Vector2(l.texture.get_size()) * l.texture_scale * 0.5
	var out := Rect2(xf * -half, Vector2.ZERO)
	for corner: Vector2 in [Vector2(half.x, -half.y), half, Vector2(-half.x, half.y)]:
		out = out.expand(xf * corner)
	return out

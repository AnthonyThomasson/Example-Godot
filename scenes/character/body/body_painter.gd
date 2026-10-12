extends RefCounted

## Top-down pixel-art CHARACTER SHOULDERS painter (Character domain, private; rendered through the
## Art domain's PixelArt). Painted in the canonical frame — facing +y — and kept within the body's
## round footprint: shoulders in the shirt color with sleeve seams, the dark ring of the neck where
## the head sits, and an optional backpack with straps. The head is its own part (head_painter.gd),
## drawn over this one so it can turn on its own. Options (`opts`, defaulting to
## CharacterConfig.art_*): `backpack`, `pack`.

const HeadPainter = preload("res://scenes/character/body/head_painter.gd")

const _SHOULDER_HEIGHT := 4  ## Heights for cast shadows, floor-up.
const _PACK_HEIGHT := 6


## Paint the shoulders onto `c` in a `base` shirt, facing +y.
static func paint(c: PixelCanvas, base: Color, material: String, opts: Dictionary) -> void:
	var t := PixelCanvas.tones(base)
	var o := Vector2i(c.w / 2, c.h / 2)
	var head_r := HeadPainter.radius_for(c.w)
	var depth := roundi(c.h * CharacterConfig.art_shoulder_depth)
	var span := Rect2i(1, o.y - depth / 2 - 1, c.w - 2, depth)
	var shoulders := PixelCanvas.ellipse(span)
	c.fill(shoulders, base, _SHOULDER_HEIGHT)
	c.surface(shoulders, material, base)
	c.bevel(shoulders, 1, 2, t.light, t.dark)
	c.outline(shoulders, t.outline)
	for side in [-1, 1]:
		var x: int = o.x + side * (c.w / 2 - 5)
		c.line(Vector2i(x, span.position.y + 3), Vector2i(x, span.end.y - 4), t.dark)
	if opts.get("backpack", false):
		_backpack(c, o, span, opts.get("pack", CharacterConfig.art_pack_color))
	c.outline(PixelCanvas.disc(o, head_r + 1), t.shadow)
	c.cast_shadows()


## A backpack on the back (toward -y): a padded body with a flap and buckle, straps running over
## the shoulders.
static func _backpack(c: PixelCanvas, o: Vector2i, span: Rect2i, col: Color) -> void:
	var pt := PixelCanvas.tones(col)
	var r := Rect2i(o.x - c.w / 4, span.position.y - 1, c.w / 2, roundi(c.h * 0.3))
	var pack := PixelCanvas.rounded(r, 2)
	c.fill(pack, col, _PACK_HEIGHT)
	c.surface(pack, "fabric", col)
	c.bevel(pack, 1, 1, pt.light, pt.dark)
	c.outline(pack, pt.outline)
	c.line(Vector2i(r.position.x + 1, r.position.y + r.size.y / 2), Vector2i(r.end.x - 2, r.position.y + r.size.y / 2), pt.dark)
	c.px(o.x, r.position.y + r.size.y / 2 + 1, Color(0.75, 0.7, 0.5), _PACK_HEIGHT)
	for x in [r.position.x + 1, r.end.x - 2]:
		c.line(Vector2i(x, r.end.y), Vector2i(x, span.end.y - 3), pt.dark, _SHOULDER_HEIGHT + 1)

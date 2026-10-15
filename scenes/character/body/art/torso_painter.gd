extends RefCounted

## Top-down pixel-art CHARACTER TRUNK painter (Character domain, private; rendered through the Art
## domain's PixelArt): the surface of a fallen body's trunk seen from its front, back or side, as a
## full strip the caller maps onto the trunk's rounded outline (which gives it its shape and outline).
## Canonical frame: shoulders toward −y, hips toward +y, across the body along x. The shirt runs down
## to the belt and pants cover the hips; the front has a collar and buttons, the back a seam and the
## optional backpack, the side a seam. A t-shirt (`sleeves` "short") has a round neck and no buttons; a vest is drawn over the
## shirt (vest_painter.gd). Options (`opts`, defaulting to CharacterConfig.art_*): `face` ("front" | "back" | "side"), `pants`,
## `backpack`, `pack`, `sleeves` and the vest's (body_painter.gd).

const VestPainter = preload("res://scenes/character/body/vest_painter.gd")

const _PANTS_HEIGHT := 3  ## Heights for cast shadows, floor-up.
const _SHIRT_HEIGHT := 4
const _PACK_HEIGHT := 7
## Share of the trunk's length the shirt covers, down to the belt.
const _WAIST := 0.8


## Paint the trunk's `face` onto `c` with a `base` shirt.
static func paint(c: PixelCanvas, base: Color, material: String, opts: Dictionary) -> void:
	var face := String(opts.get("face", "front"))
	var pants: Color = opts.get("pants", CharacterConfig.art_pants_color)
	var t := PixelCanvas.tones(base)
	var pt := PixelCanvas.tones(pants)
	var cx := int(c.w / 2.0)
	var waist := roundi(c.h * _WAIST)
	var hips := PixelCanvas.rounded(Rect2i(0, waist, c.w, c.h - waist), 0)
	c.fill(hips, pants, _PANTS_HEIGHT)
	c.surface(hips, "fabric", pants)
	var shirt := PixelCanvas.rounded(Rect2i(0, 0, c.w, waist), 0)
	c.fill(shirt, base, _SHIRT_HEIGHT)
	c.surface(shirt, material, base)
	var belt_in := 0

	match face:
		"front":
			if String(opts.get("sleeves", "")) == "short":
				c.line(Vector2i(cx - 3, 1), Vector2i(cx - 1, 3), t.dark)
				c.line(Vector2i(cx + 3, 1), Vector2i(cx + 1, 3), t.dark)
				c.px(cx, 3, t.dark)
			else:
				c.line(Vector2i(cx - 3, 1), Vector2i(cx, 4), t.shadow)
				c.line(Vector2i(cx + 3, 1), Vector2i(cx, 4), t.shadow)
				for y in range(7, waist - 2, 4):
					c.px(cx, y, t.dark)
			c.line(Vector2i(belt_in, waist), Vector2i(c.w - belt_in - 1, waist), pt.outline, _PANTS_HEIGHT)
			c.px(cx, waist, Color(0.75, 0.7, 0.5), _PANTS_HEIGHT)
		"back":
			c.line(Vector2i(cx, 3), Vector2i(cx, waist - 2), t.dark)
			c.line(Vector2i(belt_in, waist), Vector2i(c.w - belt_in - 1, waist), pt.outline, _PANTS_HEIGHT)
		_:
			c.line(Vector2i(cx, 2), Vector2i(cx, waist - 2), t.dark)
	VestPainter.paint_face(c, face, waist, opts)
	if face == "back" and opts.get("backpack", false):
		_backpack(c, cx, waist, opts.get("pack", CharacterConfig.art_pack_color))
	c.cast_shadows()


## A backpack on the back: a padded body with a flap and buckle, straps running up over the shoulders.
static func _backpack(c: PixelCanvas, cx: int, waist: int, col: Color) -> void:
	var pt := PixelCanvas.tones(col)
	var r := Rect2i(cx - int(c.w / 4.0), 3, int(c.w / 2.0), mini(roundi(c.h * 0.45), waist - 4))
	var pack := PixelCanvas.rounded(r, 2)
	c.fill(pack, col, _PACK_HEIGHT)
	c.surface(pack, "fabric", col)
	c.bevel(pack, 1, 1, pt.light, pt.dark)
	c.outline(pack, pt.outline)
	var flap := r.position.y + int(r.size.y / 3.0)
	c.line(Vector2i(r.position.x + 1, flap), Vector2i(r.end.x - 2, flap), pt.dark)
	c.px(cx, flap + 1, Color(0.75, 0.7, 0.5), _PACK_HEIGHT)
	for x in [r.position.x + 1, r.end.x - 2]:
		c.line(Vector2i(x, r.position.y), Vector2i(x, 0), pt.dark, _SHIRT_HEIGHT + 1)

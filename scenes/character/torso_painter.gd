extends RefCounted

## Top-down pixel-art CHARACTER TRUNK painter (Character domain, private; rendered through the Art
## domain's PixelArt): a fallen body's trunk seen from its front, back or side — the faces that turn
## toward the camera once the body is down. Canonical frame: shoulders toward −y, hips toward +y,
## across the body along x. The shirt runs from rounded shoulders to the belt, narrowing to the
## waist, and pants cover the narrower hips; the front has a collar and buttons, the back a seam and the
## optional backpack. Options (`opts`, defaulting to CharacterConfig.art_*): `face` ("front" |
## "back" | "side"), `pants`, `backpack`, `pack`.

const _PANTS_HEIGHT := 3  ## Heights for cast shadows, floor-up.
const _SHIRT_HEIGHT := 4
const _PACK_HEIGHT := 7
## Share of the trunk's length the shirt covers, down to the belt.
const _WAIST := 0.74
## How far the trunk narrows from the shoulders to the waist, and the hips' width (shares of the
## shoulders' width; the side view keeps its depth).
const _WAIST_TAPER := 0.28
const _HIP_WIDTH := 0.74


## Paint the trunk's `face` onto `c` with a `base` shirt.
static func paint(c: PixelCanvas, base: Color, material: String, opts: Dictionary) -> void:
	var face := String(opts.get("face", "front"))
	var pants: Color = opts.get("pants", CharacterConfig.art_pants_color)
	var t := PixelCanvas.tones(base)
	var pt := PixelCanvas.tones(pants)
	var cx := c.w / 2
	var waist := roundi(c.h * _WAIST)
	var side := face == "side"
	var taper := 0.0 if side else c.w * _WAIST_TAPER * 0.5
	var round_r := maxf(2.0, c.w * (0.12 if side else 0.2))
	var hip_in := 0 if side else roundi(c.w * (1.0 - _HIP_WIDTH) * 0.5)

	var hips := PixelCanvas.rounded(Rect2i(hip_in, waist - 2, c.w - hip_in * 2, c.h - waist + 2), 3)
	c.fill(hips, pants, _PANTS_HEIGHT)
	c.surface(hips, "fabric", pants)
	c.bevel(hips, 1, 1, pt.light, pt.dark)
	c.outline(hips, pt.outline)

	# The shirt: rounded shoulders, then easing in toward the waist.
	var shirt := PixelCanvas.Shape.new(Rect2i(0, 0, c.w, waist + 1), func(x: int, y: int) -> bool:
		var k := float(y) / maxf(waist, 1.0)
		var inset := taper * k * k
		if y < round_r:
			var dy := round_r - y - 0.5
			inset += round_r - sqrt(maxf(round_r * round_r - dy * dy, 0.0))
		return x >= roundi(inset) and x < c.w - roundi(inset))
	c.fill(shirt, base, _SHIRT_HEIGHT)
	c.surface(shirt, material, base)
	c.bevel(shirt, 1, 2, t.light, t.dark)
	c.outline(shirt, t.outline)
	var belt_in := roundi(taper) + 1

	match face:
		"front":
			c.line(Vector2i(cx - 3, 1), Vector2i(cx, 4), t.shadow)
			c.line(Vector2i(cx + 3, 1), Vector2i(cx, 4), t.shadow)
			for y in range(7, waist - 2, 4):
				c.px(cx, y, t.dark)
			c.line(Vector2i(belt_in, waist), Vector2i(c.w - belt_in - 1, waist), pt.outline, _PANTS_HEIGHT)
			c.px(cx, waist, Color(0.75, 0.7, 0.5), _PANTS_HEIGHT)
		"back":
			c.line(Vector2i(cx, 3), Vector2i(cx, waist - 2), t.dark)
			c.line(Vector2i(belt_in, waist), Vector2i(c.w - belt_in - 1, waist), pt.outline, _PANTS_HEIGHT)
			if opts.get("backpack", false):
				_backpack(c, cx, waist, opts.get("pack", CharacterConfig.art_pack_color))
		_:
			c.line(Vector2i(cx, 2), Vector2i(cx, waist - 2), t.dark)
	c.cast_shadows()


## A backpack on the back: a padded body with a flap and buckle, straps running up over the shoulders.
static func _backpack(c: PixelCanvas, cx: int, waist: int, col: Color) -> void:
	var pt := PixelCanvas.tones(col)
	var r := Rect2i(cx - c.w / 4, 3, c.w / 2, mini(roundi(c.h * 0.45), waist - 4))
	var pack := PixelCanvas.rounded(r, 2)
	c.fill(pack, col, _PACK_HEIGHT)
	c.surface(pack, "fabric", col)
	c.bevel(pack, 1, 1, pt.light, pt.dark)
	c.outline(pack, pt.outline)
	var flap := r.position.y + r.size.y / 3
	c.line(Vector2i(r.position.x + 1, flap), Vector2i(r.end.x - 2, flap), pt.dark)
	c.px(cx, flap + 1, Color(0.75, 0.7, 0.5), _PACK_HEIGHT)
	for x in [r.position.x + 1, r.end.x - 2]:
		c.line(Vector2i(x, r.position.y), Vector2i(x, 0), pt.dark, _SHIRT_HEIGHT + 1)

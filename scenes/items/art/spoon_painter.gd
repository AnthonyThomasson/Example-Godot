extends RefCounted

## Top-down pixel-art painter for a grenade's SPOON (the safety lever) lying flat on the floor (Items domain,
## private; rendered through the Art domain's PixelArt): a thin curved steel strip with a loop at one end, toward +y.

const _HEIGHT := 1  ## Height for cast shadows.


## Paint a spoon onto `c` in `base` steel, the loop toward +y.
static func paint(c: PixelCanvas, base: Color, _material: String, _opts: Dictionary) -> void:
	var t := PixelCanvas.tones(base)
	var cx := int(c.w / 2.0)
	for y in range(0, c.h - 1):
		c.px(cx, y, base, _HEIGHT)
	c.px(cx + 1, c.h - 1, t.light, _HEIGHT)
	c.px(cx, c.h - 1, t.dark, _HEIGHT)
	c.px(cx - 1, c.h - 2, t.dark, _HEIGHT)
	c.px(cx, 0, t.highlight, _HEIGHT)
	c.cast_shadows()

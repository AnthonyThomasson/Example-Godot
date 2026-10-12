extends RefCounted

## Top-down pixel-art HAND painter (Character domain, private; rendered through the Art domain's
## PixelArt): a fist seen from above in the canonical frame — knuckles toward the front (+y), the
## thumb tucked along the inner side. Options (`opts`): `side` (-1 = left hand, thumb toward +x;
## 1 = right hand, thumb toward -x).

const _FIST_HEIGHT := 3  ## Heights for cast shadows: the thumb sits over the fist.
const _THUMB_HEIGHT := 5


## Paint a fist onto `c` in `base` (skin or glove).
static func paint(c: PixelCanvas, base: Color, _material: String, opts: Dictionary) -> void:
	var t := PixelCanvas.tones(base)
	var o := Vector2i(c.w / 2, c.h / 2)
	var r := maxi(2, mini(c.w, c.h) / 2 - 1)
	var fist := PixelCanvas.disc(o, r)
	c.fill(fist, base, _FIST_HEIGHT)
	c.bevel(fist, 1, 2, t.light, t.dark)
	# Knuckles: a row of bumps along the front with creases between them.
	var ky := o.y + r - 2
	for x in range(o.x - r + 2, o.x + r - 1, 2):
		c.px(x, ky, t.highlight)
		c.px(x + 1, ky + 1, t.dark)
	c.outline(fist, t.outline)
	var side := int(opts.get("side", 1))
	var thumb := PixelCanvas.disc(o + Vector2i(-side * (r - 2), 0), maxi(1, r / 2 - 1))
	c.fill(thumb, base.lightened(0.04), _THUMB_HEIGHT)
	c.outline(thumb, t.dark)
	c.cast_shadows()

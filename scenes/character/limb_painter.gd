extends RefCounted

## Top-down pixel-art LIMB painter (Character domain, private; rendered through the Art domain's
## PixelArt): one segment of a fallen body's arm or leg, or a shoe, seen from above as a capsule
## along +y in the sleeve, skin, pants or shoe color — beveled toward the light and outlined, with
## the cloth's weave when `material` is "fabric".

const _LIMB_HEIGHT := 3  ## Height for cast shadows.


## Paint a capsule spanning `c` in `base`.
static func paint(c: PixelCanvas, base: Color, material: String, _opts: Dictionary) -> void:
	var t := PixelCanvas.tones(base)
	var limb := PixelCanvas.rounded(Rect2i(0, 0, c.w, c.h), c.w / 2)
	c.fill(limb, base, _LIMB_HEIGHT)
	if material != "":
		c.surface(limb, material, base)
	c.bevel(limb, 1, 1, t.light, t.dark)
	c.outline(limb, t.outline)

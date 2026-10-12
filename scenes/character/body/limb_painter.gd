extends RefCounted

## Top-down pixel-art LIMB painter (Character domain, private; rendered through the Art domain's
## PixelArt): the surface of one segment of a fallen body's arm, leg or shoe as a straight strip along
## +y in the sleeve, skin, pants or shoe color — shaded light to dark across it toward the light, with
## the cloth's weave when `material` is "fabric". The caller maps it onto the limb's tapered outline,
## which gives it its shape and outline.

const _LIMB_HEIGHT := 3  ## Height for cast shadows.


## Paint the strip spanning `c` in `base`.
static func paint(c: PixelCanvas, base: Color, material: String, _opts: Dictionary) -> void:
	var t := PixelCanvas.tones(base)
	var strip := PixelCanvas.rounded(Rect2i(0, 0, c.w, c.h), 0)
	c.fill(strip, base, _LIMB_HEIGHT)
	if material != "":
		c.surface(strip, material, base)
	c.bevel(strip, 1, maxi(1, int(c.w / 4.0)), t.light, t.dark)

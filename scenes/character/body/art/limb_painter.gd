extends RefCounted

## Top-down pixel-art LIMB painter (Character domain, private; rendered through the Art domain's
## PixelArt): the surface of one segment of a fallen body's arm, leg or shoe as a straight strip along
## +y in the sleeve, skin, pants or shoe color — shaded light to dark across it toward the light, with
## the cloth's weave when `material` is "fabric". The caller maps it onto the limb's tapered outline,
## which gives it its shape and outline; the strip runs from the joint nearer the body (y = 0) to the far one.
## What the outfit adds (`opts`, character_visuals.gd resolves it; none = the plain strip):
## - `cuff`: a long sleeve's cuff at the wrist end.
## - `pattern` with the segment's `part`:
##   - "jeans": a stitched seam down the outer side (`side`: -1 = toward x 0, 1 = toward the far edge), denim fading on the thigh.
##   - "tactical": a cargo pocket on the outer thigh, a knee pad on the knee, a seam down the shin.
##   - "boots": the boot's laced foot ("foot", a thick dark sole round it) and its shaft up the shin ("shaft", a padded rim on top).

const _LIMB_HEIGHT := 3  ## Height for cast shadows.
const _DETAIL_HEIGHT := 4
const _STITCH := Color(0.78, 0.6, 0.32)  ## Denim's orange thread.
const _LACE := Color(0.72, 0.68, 0.58)


## Paint the strip spanning `c` in `base`.
static func paint(c: PixelCanvas, base: Color, material: String, opts: Dictionary) -> void:
	var t := PixelCanvas.tones(base)
	var strip := PixelCanvas.rounded(Rect2i(0, 0, c.w, c.h), 0)
	c.fill(strip, base, _LIMB_HEIGHT)
	if material != "":
		c.surface(strip, material, base)
	c.bevel(strip, 1, maxi(1, int(c.w / 4.0)), t.light, t.dark)
	if opts.get("cuff", false):
		var cuff := maxi(2, roundi(c.h * 0.18))
		c.fill(PixelCanvas.rounded(Rect2i(0, c.h - cuff, c.w, cuff), 0), t.dark, _DETAIL_HEIGHT)
		c.line(Vector2i(0, c.h - cuff), Vector2i(c.w - 1, c.h - cuff), t.shadow, _DETAIL_HEIGHT)
		c.px(int(c.w / 2.0), c.h - int(cuff / 2.0) - 1, t.highlight, _DETAIL_HEIGHT)  # Its button.
	var outer := c.w - 2 if int(opts.get("side", 1)) > 0 else 1
	match [String(opts.get("pattern", "")), String(opts.get("part", ""))]:
		["jeans", var part]:
			for y in range(1, c.h - 1, 2):
				c.px(outer, y, _STITCH)
			if part == "thigh":
				for y in range(int(c.h / 3.0), c.h):  # Faded down the front of the thigh.
					c.px(int(c.w / 2.0), y, t.light)
		["tactical", "thigh"]:
			var w := maxi(3, int(c.w / 2.0))
			var x := c.w - w - 1 if outer > int(c.w / 2.0) else 1
			var pocket := PixelCanvas.rounded(Rect2i(x, int(c.h * 0.4), w, maxi(3, int(c.h * 0.45))), 1)
			c.fill(pocket, base.darkened(0.08), _DETAIL_HEIGHT)
			c.outline(pocket, t.shadow)
			c.line(Vector2i(x, pocket.bounds.position.y + 1), Vector2i(x + w - 1, pocket.bounds.position.y + 1), t.shadow, _DETAIL_HEIGHT)
		["tactical", "knee"]:
			var pad_col := base.darkened(0.55)
			var pad := PixelCanvas.rounded(Rect2i(1, 0, c.w - 2, c.h), 2)
			c.fill(pad, pad_col, _DETAIL_HEIGHT)
			c.bevel(pad, 1, 1, pad_col.lightened(0.2), pad_col.darkened(0.3))
			c.line(Vector2i(2, int(c.h / 2.0)), Vector2i(c.w - 3, int(c.h / 2.0)), pad_col.darkened(0.3), _DETAIL_HEIGHT)
		["tactical", "shin"]:
			c.line(Vector2i(outer, 1), Vector2i(outer, c.h - 2), t.shadow)
		["boots", "shaft"]:
			c.line(Vector2i(0, 0), Vector2i(c.w - 1, 0), t.highlight, _DETAIL_HEIGHT)
			c.line(Vector2i(0, 1), Vector2i(c.w - 1, 1), t.dark, _DETAIL_HEIGHT)
			_laces(c, 3, c.h - 1)
		["boots", "foot"]:
			c.outline(strip, t.outline)
			c.line(Vector2i(1, c.h - 2), Vector2i(c.w - 2, c.h - 2), t.shadow)  # The toe cap.
			_laces(c, 2, int(c.h * 0.55))


## Laces criss-crossing down the middle of a boot strip, rows `from`..`to`.
static func _laces(c: PixelCanvas, from: int, to: int) -> void:
	var cx := int(c.w / 2.0)
	for y in range(from, to, 2):
		c.px(cx - 1, y, _LACE, _DETAIL_HEIGHT)
		c.px(cx + 1, y, _LACE, _DETAIL_HEIGHT)
		c.px(cx, y + 1, _LACE.darkened(0.3), _DETAIL_HEIGHT)

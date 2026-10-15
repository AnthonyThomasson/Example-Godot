extends RefCounted

## Vehicles domain: a wheel seen from above, top-down pixel art (rendered through Art, `PixelArt.render_turned`): the tyre's
## tread rolling along it (canonical front, +y, the way it rolls), its rounded shoulders, and a glint of the hub on the
## outside face. Most of it hides under the body; a turned front wheel shows past the wing.

const _HEIGHT := 2


## Paint a wheel onto `c` with its tyre in `base`, rolling along +y.
static func paint(c: PixelCanvas, base: Color, _material: String, _opts: Dictionary) -> void:
	var t := PixelCanvas.tones(base)
	var tyre := PixelCanvas.rounded(Rect2i(0, 0, c.w, c.h), maxi(2, roundi(c.w * 0.3)))
	c.fill(tyre, base, _HEIGHT)
	c.bevel(tyre, 1, 1, t["highlight"], t["outline"])
	# Tread blocks across it, staggered.
	for y in range(3, c.h - 3, 3):
		var inset := 1 if posmod(y, 6) < 3 else 2
		c.line(Vector2i(inset, y), Vector2i(c.w - 1 - inset, y), t["outline"])
	var hub := Rect2i(c.w - 2, roundi(c.h * 0.3), 1, maxi(roundi(c.h * 0.4), 1))
	c.fill(PixelCanvas.rounded(hub, 0), VehicleConfig.hub_color, _HEIGHT + 1)
	c.outline(tyre, t["outline"])

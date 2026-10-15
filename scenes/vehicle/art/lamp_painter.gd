extends RefCounted

## Vehicles domain: a lit lamp, top-down pixel art (rendered through Art, `PixelArt.render_turned`): the lens glowing in
## `base` with a hot, pale core, drawn over a tail light while the vehicle brakes.

## Paint a lit lamp onto `c`, glowing in `base`.
static func paint(c: PixelCanvas, base: Color, _material: String, _opts: Dictionary) -> void:
	var lens := PixelCanvas.rounded(Rect2i(0, 0, c.w, c.h), 1)
	c.fill(lens, base)
	c.bevel(lens, 1, 1, base.lightened(0.5), base.darkened(0.2))
	var core := Rect2i(1, 1, maxi(c.w - 2, 1), maxi(c.h - 2, 1))
	c.fill(PixelCanvas.rounded(core, 1), base.lightened(0.35))
	c.outline(lens, VehicleConfig.trim_color)

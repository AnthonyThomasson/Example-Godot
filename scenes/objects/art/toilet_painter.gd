extends RefCounted

## Top-down pixel-art TOILET painter (Objects domain, private). Painted in the canonical frame
## (bowl toward +y, cistern against the wall) and kept within the inscribed circle of its round
## footprint: a glazed cistern with a flush button, and an oval bowl whose seat ring frames the
## water. No options.

const PixelCanvas = preload("res://scenes/objects/art/pixel_canvas.gd")

const _BOWL_HEIGHT := 4  ## Heights for cast shadows.
const _TANK_HEIGHT := 7


## Paint a toilet onto `c` in `base` glaze, bowl toward +y.
static func paint(c: PixelCanvas, base: Color, _material: String, _opts: Dictionary) -> void:
	var t := PixelCanvas.tones(base)
	var bowl_rect := Rect2i(roundi(c.w * 0.21), roundi(c.h * 0.26), roundi(c.w * 0.58), roundi(c.h * 0.68))
	var bowl := PixelCanvas.ellipse(bowl_rect)
	c.fill(bowl, base, _BOWL_HEIGHT)
	c.bevel(bowl, 1, 2, t.highlight, t.dark)
	c.outline(bowl, t.shadow)
	var water := PixelCanvas.ellipse(bowl_rect.grow(-maxi(2, c.w / 10)))
	c.fill(water, ObjectArtConfig.bath_water_color, 1)
	c.bevel(water, 1, 1, ObjectArtConfig.bath_water_color.darkened(0.25), ObjectArtConfig.bath_water_color.lightened(0.2))
	c.fill(PixelCanvas.ellipse(bowl_rect.grow(-maxi(4, c.w / 5))), ObjectArtConfig.bath_water_color.darkened(0.12))
	c.glare(water, Color(0.95, 0.98, 1.0), 1)

	var tank_rect := Rect2i(roundi(c.w * 0.2), roundi(c.h * 0.06), roundi(c.w * 0.6), roundi(c.h * 0.24))
	var tank := PixelCanvas.rounded(tank_rect, 3)
	c.fill(tank, base, _TANK_HEIGHT)
	c.bevel(tank, 1, 2, t.highlight, t.dark)
	c.outline(tank, t.shadow)
	var button := PixelCanvas.disc(tank_rect.position + tank_rect.size / 2, 1)
	c.fill(button, ObjectArtConfig.counter_tap_color, _TANK_HEIGHT + 1)
	c.cast_shadows()

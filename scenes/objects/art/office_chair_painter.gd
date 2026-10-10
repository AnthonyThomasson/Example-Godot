extends RefCounted

## Top-down pixel-art OFFICE CHAIR painter (Objects domain, private). Painted in the canonical
## frame (seat front toward +y): a five-star base with casters peeking out, a rounded padded seat,
## armrests at its sides and a curved mesh backrest. No options.

const PixelCanvas = preload("res://scenes/objects/art/pixel_canvas.gd")

const _BASE_HEIGHT := 1  ## Heights for cast shadows, floor-up.
const _SEAT_HEIGHT := 3
const _ARM_HEIGHT := 5
const _BACK_HEIGHT := 6


## Paint an office chair onto `c` in `base` with a `material` seat, front toward +y.
static func paint(c: PixelCanvas, base: Color, material: String, _opts: Dictionary) -> void:
	var t := PixelCanvas.tones(base)
	var o := Vector2i(c.w / 2, c.h / 2 + 1)
	var metal := ObjectArtConfig.office_chair_base_color
	var reach := mini(c.w, c.h) * 0.47
	for i in 5:
		var a := -PI * 0.5 + TAU * i / 5.0 + PI / 5.0
		var tip := o + Vector2i((Vector2(cos(a), sin(a)) * reach).round())
		c.line(o, tip, metal, _BASE_HEIGHT)
		c.fill(PixelCanvas.disc(tip, 1), metal.darkened(0.4), _BASE_HEIGHT)

	var seat := PixelCanvas.rounded(Rect2i(4, roundi(c.h * 0.28), c.w - 8, c.h - roundi(c.h * 0.28) - 3), 6)
	c.fill(seat, base, _SEAT_HEIGHT)
	c.surface(seat, material, base)
	c.fill(PixelCanvas.rounded(Rect2i(7, roundi(c.h * 0.36), c.w - 14, c.h / 3), 4), base.lightened(0.05))
	c.bevel(seat, 1, 2, t.light, t.dark)
	c.outline(seat, t.outline)

	for x in [1, c.w - 4]:
		var arm := PixelCanvas.rounded(Rect2i(x, roundi(c.h * 0.32), 3, roundi(c.h * 0.42)), 1)
		c.fill(arm, t.shadow, _ARM_HEIGHT)
		c.outline(arm, t.outline)

	var back_rect := Rect2i(4, 1, c.w - 8, maxi(5, roundi(c.h * 0.28)))
	var back := PixelCanvas.bowed(back_rect, 2, 2)
	c.fill(back, t.dark, _BACK_HEIGHT)
	for y in range(back_rect.position.y + 1, back_rect.end.y):
		for x in range(back_rect.position.x + 1 + (y % 2), back_rect.end.x - 1, 2):
			if back.has(x, y):
				c.px(x, y, t.shadow)
	c.bevel(back, 1, 1, t.light, t.outline)
	c.outline(back, t.outline)
	c.cast_shadows()

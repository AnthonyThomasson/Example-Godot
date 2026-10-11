extends RefCounted

## Top-down pixel-art SMG painter (Items domain, private; rendered through the Art domain's PixelArt).
## Painted in the canonical frame — muzzle toward +y, the butt at the back against the body: a slim
## shadowed stock, a boxy receiver with a lit top rail and an ejection port, a vented shroud and a short
## dark barrel with its muzzle. The proportions scale with the canvas, so a barrel pulled up off a wall
## (drawn shorter) keeps its parts in order. No options.

const _STOCK_HEIGHT := 3  ## Heights for cast shadows.
const _BODY_HEIGHT := 5
const _SHROUD_HEIGHT := 4


## Paint an SMG onto `c` in `base` metal, muzzle toward +y.
static func paint(c: PixelCanvas, base: Color, material: String, _opts: Dictionary) -> void:
	var t := PixelCanvas.tones(base)
	var cx := c.w / 2
	var stock_end := maxi(2, c.h * 24 / 100)
	var body_end := maxi(stock_end + 3, c.h * 62 / 100)
	var barrel_start := maxi(body_end, c.h * 86 / 100)

	# The stock: a slim frame at the back, darker than the metal.
	var stock := PixelCanvas.rounded(Rect2i(1, 0, maxi(c.w - 2, 2), stock_end + 1), 1)
	c.fill(stock, t.shadow, _STOCK_HEIGHT)
	c.outline(stock, t.outline)
	c.px(cx, 0, t.outline)

	# The receiver: the widest part, bevelled, a lit rail along the top and the ejection port.
	var body_rect := Rect2i(0, stock_end - 1, c.w, body_end - stock_end + 2)
	var body := PixelCanvas.rounded(body_rect, 1)
	c.fill(body, base, _BODY_HEIGHT)
	c.surface(body, material, base, false)
	c.bevel(body, 1, 1, t.light, t.dark)
	c.outline(body, t.outline)
	c.line(Vector2i(cx, body_rect.position.y + 2), Vector2i(cx, body_end - 1), t.highlight)
	var port_y := body_rect.position.y + body_rect.size.y / 3
	c.line(Vector2i(cx + 1, port_y), Vector2i(cx + 1, port_y + 2), t.outline)
	c.px(cx - 1, body_rect.position.y + 1, t.outline)  # Charging handle.

	# The shroud: narrower and darker, with cooling slots.
	var shroud := PixelCanvas.rounded(Rect2i(1, body_end - 1, maxi(c.w - 2, 2), barrel_start - body_end + 2), 1)
	c.fill(shroud, t.dark, _SHROUD_HEIGHT)
	c.bevel(shroud, 1, 1, t.base, t.shadow)
	c.outline(shroud, t.outline)
	for y in range(body_end + 1, barrel_start - 1, 2):
		c.px(cx - 1, y, t.outline)
		c.px(cx, y, t.outline)

	# The barrel: a short dark post with its muzzle.
	for y in range(barrel_start, c.h):
		c.px(cx - 1, y, t.outline, _SHROUD_HEIGHT)
		c.px(cx, y, t.dark, _SHROUD_HEIGHT)
	c.px(cx - 1, c.h - 1, Color(0.05, 0.05, 0.06))
	c.px(cx, c.h - 1, Color(0.05, 0.05, 0.06))
	c.cast_shadows()

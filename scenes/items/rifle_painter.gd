extends RefCounted

## Top-down pixel-art ASSAULT RIFLE painter (Items domain, private; rendered through the Art domain's
## PixelArt). Painted in the canonical frame — muzzle toward +y, the butt at the back on the shoulder:
## a tapered stock with a butt plate, a receiver with a lit top rail, ejection port and charging handle,
## a vented handguard, a gas block and a thin barrel ending in a flash hider. The proportions scale with the
## canvas, so a barrel pulled up off a wall (drawn shorter) keeps its parts in order. No options.

const _STOCK_HEIGHT := 3  ## Heights for cast shadows.
const _BODY_HEIGHT := 5
const _GUARD_HEIGHT := 4
const _BARREL_HEIGHT := 3


## Paint a rifle onto `c` in `base` metal, muzzle toward +y.
static func paint(c: PixelCanvas, base: Color, material: String, _opts: Dictionary) -> void:
	var t := PixelCanvas.tones(base)
	var cx := c.w / 2
	var stock_end := maxi(3, c.h * 26 / 100)
	var body_end := maxi(stock_end + 3, c.h * 50 / 100)
	var guard_end := maxi(body_end + 3, c.h * 80 / 100)

	# The stock: a polymer wedge, narrower toward the receiver, with a darker butt plate.
	var stock := PixelCanvas.Shape.new(Rect2i(0, 0, c.w, stock_end + 1), func(x: int, y: int) -> bool:
		var half := lerpf(float(c.w) * 0.5 - 0.5, float(c.w) * 0.5 - 1.5, float(y) / maxf(stock_end, 1.0))
		return y >= 0 and y <= stock_end and absf(x - (c.w - 1) * 0.5) <= half)
	c.fill(stock, t.shadow, _STOCK_HEIGHT)
	c.bevel(stock, 1, 1, t.dark, t.outline)
	c.outline(stock, t.outline)
	for x in range(1, c.w - 1):
		c.px(x, 0, t.outline)  # Butt plate.
	c.line(Vector2i(cx, 2), Vector2i(cx, stock_end - 1), t.dark)

	# The receiver: full width, bevelled, a lit rail along the top, ejection port and charging handle.
	var body_rect := Rect2i(0, stock_end - 1, c.w, body_end - stock_end + 2)
	var body := PixelCanvas.rounded(body_rect, 1)
	c.fill(body, base, _BODY_HEIGHT)
	c.surface(body, material, base, false)
	c.bevel(body, 1, 1, t.light, t.dark)
	c.outline(body, t.outline)
	c.line(Vector2i(cx, body_rect.position.y + 2), Vector2i(cx, body_end - 1), t.highlight)
	var port_y := body_rect.position.y + body_rect.size.y / 3
	c.line(Vector2i(cx + 2, port_y), Vector2i(cx + 2, port_y + 3), t.outline)
	c.px(cx - 2, body_rect.position.y + 1, t.outline)  # Charging handle.
	c.px(cx - 2, body_rect.position.y + 2, t.outline)

	# The handguard: slightly narrower, darker, with vent slots along both sides.
	var guard := PixelCanvas.rounded(Rect2i(1, body_end - 1, maxi(c.w - 2, 2), guard_end - body_end + 2), 1)
	c.fill(guard, t.dark, _GUARD_HEIGHT)
	c.bevel(guard, 1, 1, t.base, t.shadow)
	c.outline(guard, t.outline)
	c.line(Vector2i(cx, body_end + 1), Vector2i(cx, guard_end - 1), t.base)
	for y in range(body_end + 1, guard_end - 1, 3):
		c.px(1, y, t.outline)
		c.px(c.w - 2, y, t.outline)

	# The gas block, the barrel and a flash hider at the end.
	c.px(cx - 1, guard_end, t.outline, _BARREL_HEIGHT)
	c.px(cx, guard_end, t.dark, _BARREL_HEIGHT)
	c.px(cx + 1, guard_end, t.outline, _BARREL_HEIGHT)
	for y in range(guard_end + 1, c.h - 2):
		c.px(cx - 1, y, t.outline, _BARREL_HEIGHT)
		c.px(cx, y, t.dark, _BARREL_HEIGHT)
	for y in range(maxi(guard_end + 1, c.h - 3), c.h):
		c.px(cx - 1, y, t.outline, _BARREL_HEIGHT)
		c.px(cx, y, t.base, _BARREL_HEIGHT)
		c.px(cx + 1, y, t.outline, _BARREL_HEIGHT)
	c.px(cx, c.h - 1, Color(0.05, 0.05, 0.06))
	c.cast_shadows()

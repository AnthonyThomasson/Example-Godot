extends RefCounted

## Top-down pixel-art painter for an SMG LYING FLAT on its side (Items domain, private; rendered through the
## Art domain's PixelArt): the gun's side profile as it rests on the floor — a boxy receiver with its sights
## along the top edge, a slim stock behind and a short barrel ahead toward +y, the pistol grip raked back and
## a straight magazine hanging off the underside. Option `flip` (bool) lays it on its other side, so the
## grip and magazine point the other way.

const _PART_HEIGHT := 3  ## Heights for cast shadows.


## Paint the SMG's profile onto `c` in `base` metal, muzzle toward +y.
static func paint(c: PixelCanvas, base: Color, material: String, opts: Dictionary) -> void:
	# Its broad side faces up, catching more light than the receiver's edge seen in the hand.
	var metal := base.lightened(0.15)
	var t := PixelCanvas.tones(metal)
	var dark_part := base.darkened(0.25)
	var flip: bool = opts.get("flip", false)
	var mx := func(x: int) -> int: return c.w - 1 - x if flip else x
	var body_w := maxi(3, c.w * 3 / 8)       # The receiver's thickness.
	var stock_end := maxi(2, c.h * 24 / 100)
	var body_end := maxi(stock_end + 3, c.h * 64 / 100)
	var barrel_start := maxi(body_end, c.h * 86 / 100)
	var below := body_w + 1                  # First column below the receiver (the grip side).

	# The magazine: a straight slab hanging below the receiver, near its middle.
	var mag_top := stock_end + (body_end - stock_end) / 2
	var mag := PixelCanvas.Shape.new(Rect2i(0, 0, c.w, c.h), func(x: int, y: int) -> bool:
		var lx: int = mx.call(x)
		return lx >= below - 1 and lx <= below + 2 and y >= mag_top and y <= mag_top + maxi(3, c.h / 5))
	c.fill(mag, dark_part, _PART_HEIGHT)
	c.outline(mag, t.outline)

	# The pistol grip: a slab raked back off the underside of the receiver.
	var grip_len := maxi(3, c.h / 5)
	var grip := PixelCanvas.Shape.new(Rect2i(0, 0, c.w, c.h), func(x: int, y: int) -> bool:
		var lx: int = mx.call(x)
		if lx < below - 1 or lx > below + 1:
			return false
		var rake := float(lx - below) * 0.6
		return y >= stock_end - 1 - rake and y <= stock_end + grip_len - 1 - rake)
	c.fill(grip, dark_part, _PART_HEIGHT)
	c.outline(grip, t.outline)

	# The stock: a thin strut behind the receiver ending in a butt plate.
	var stock := PixelCanvas.Shape.new(Rect2i(0, 0, c.w, c.h), func(x: int, y: int) -> bool:
		var lx: int = mx.call(x)
		return (lx >= 1 and lx <= 2 and y >= 1 and y <= stock_end) or (lx >= 0 and lx <= body_w - 1 and y == 0))
	c.fill(stock, t.shadow, _PART_HEIGHT)
	c.outline(stock, t.outline)

	# The receiver and shroud along the gun's length, the barrel a post at the end.
	var body := PixelCanvas.Shape.new(Rect2i(0, 0, c.w, c.h), func(x: int, y: int) -> bool:
		var lx: int = mx.call(x)
		if y >= stock_end - 1 and y <= body_end:
			return lx >= 1 and lx <= body_w
		if y > body_end and y < barrel_start:
			return lx >= 2 and lx <= body_w - 1
		return false)
	c.fill(body, metal, _PART_HEIGHT + 1)
	c.surface(body, material, metal, false)
	c.bevel(body, 1, 1, t.light, t.dark)
	c.outline(body, t.outline)
	c.line(Vector2i(mx.call(2), stock_end + 1), Vector2i(mx.call(2), body_end - 1), t.highlight)
	var port := stock_end + (body_end - stock_end) / 3
	c.line(Vector2i(mx.call(body_w - 1), port), Vector2i(mx.call(body_w - 1), port + 2), t.outline)
	for y in range(body_end + 1, barrel_start - 1, 2):  # Cooling slots in the shroud.
		c.px(mx.call(3), y, t.outline)
	for y in range(barrel_start, c.h):
		c.px(mx.call(3), y, t.dark, _PART_HEIGHT + 1)
	c.px(mx.call(3), c.h - 1, Color(0.05, 0.05, 0.06))
	c.px(mx.call(1), stock_end + 1, t.outline, _PART_HEIGHT + 1)  # Rear sight.
	c.px(mx.call(1), body_end - 1, t.outline, _PART_HEIGHT + 1)   # Front sight.
	c.cast_shadows()

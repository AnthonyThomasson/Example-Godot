extends RefCounted

## Top-down pixel-art painter for an ASSAULT RIFLE LYING FLAT on its side (Items domain, private; rendered
## through the Art domain's PixelArt): the gun's side profile as it rests on the floor — a long receiver
## with its sights along the top edge, a stock behind it, a handguard and a thin barrel ahead toward +y, the
## pistol grip raked back and a curved magazine hanging off the underside. Option `flip` (bool) lays it on its
## other side, so the grip and magazine point the other way.

const _PART_HEIGHT := 3  ## Heights for cast shadows.


## Paint the rifle's profile onto `c` in `base` metal, muzzle toward +y.
static func paint(c: PixelCanvas, base: Color, material: String, opts: Dictionary) -> void:
	# Its broad side faces up, catching more light than the receiver's edge seen on the shoulder.
	var metal := base.lightened(0.15)
	var t := PixelCanvas.tones(metal)
	var dark_part := base.darkened(0.25)
	var flip: bool = opts.get("flip", false)
	var mx := func(x: int) -> int: return c.w - 1 - x if flip else x
	var body_w := maxi(3, int(c.w * 3 / 8.0))       # The receiver's thickness.
	var stock_end := maxi(4, int(c.h * 26 / 100.0))
	var body_end := maxi(stock_end + 4, int(c.h * 54 / 100.0))
	var guard_end := maxi(body_end + 3, int(c.h * 82 / 100.0))
	var below := body_w + 1                  # First column below the receiver (the grip side).

	# The magazine: a slab curving forward as it hangs below the receiver.
	var mag_top := stock_end + int((body_end - stock_end) / 2.0)
	var mag_len := maxi(4, int(c.h / 5.0))
	var mag := PixelCanvas.Shape.new(Rect2i(0, 0, c.w, c.h), func(x: int, y: int) -> bool:
		var lx: int = mx.call(x)
		var drop := lx - below
		if drop < -1 or drop > 3:
			return false
		var curve := int(float(maxi(drop, 0)) * 0.9)
		return y >= mag_top + curve and y <= mag_top + mag_len + curve and lx <= below + 3 and lx >= below - 1)
	c.fill(mag, dark_part, _PART_HEIGHT)
	c.outline(mag, t.outline)

	# The pistol grip: a slab raked back off the underside of the receiver.
	var grip_len := maxi(3, int(c.h / 8.0))
	var grip := PixelCanvas.Shape.new(Rect2i(0, 0, c.w, c.h), func(x: int, y: int) -> bool:
		var lx: int = mx.call(x)
		if lx < below - 1 or lx > below + 1:
			return false
		var rake := float(lx - below) * 0.6
		return y >= stock_end - 3 - rake and y <= stock_end + grip_len - 3 - rake)
	c.fill(grip, dark_part, _PART_HEIGHT)
	c.outline(grip, t.outline)

	# The stock: a polymer wedge behind the receiver, tapering toward it, with a butt plate.
	var stock := PixelCanvas.Shape.new(Rect2i(0, 0, c.w, c.h), func(x: int, y: int) -> bool:
		var lx: int = mx.call(x)
		if y < 0 or y > stock_end:
			return false
		var thick := lerpf(float(body_w) + 1.0, float(body_w) - 0.5, float(y) / maxf(float(stock_end), 1.0))
		return lx >= 0 and float(lx) < thick)
	c.fill(stock, t.shadow, _PART_HEIGHT)
	c.outline(stock, t.outline)
	for lx in range(0, body_w + 1):
		c.px(mx.call(lx), 0, t.outline)  # Butt plate.

	# The receiver, handguard and barrel along the gun's length.
	var body := PixelCanvas.Shape.new(Rect2i(0, 0, c.w, c.h), func(x: int, y: int) -> bool:
		var lx: int = mx.call(x)
		if y >= stock_end - 1 and y <= body_end:
			return lx >= 1 and lx <= body_w
		if y > body_end and y <= guard_end:
			return lx >= 1 and lx <= body_w - 1
		return false)
	c.fill(body, metal, _PART_HEIGHT + 1)
	c.surface(body, material, metal, false)
	c.bevel(body, 1, 1, t.light, t.dark)
	c.outline(body, t.outline)
	c.line(Vector2i(mx.call(2), stock_end + 1), Vector2i(mx.call(2), guard_end - 1), t.highlight)
	var port := stock_end + int((body_end - stock_end) / 3.0)
	c.line(Vector2i(mx.call(body_w - 1), port), Vector2i(mx.call(body_w - 1), port + 2), t.outline)
	for y in range(body_end + 2, guard_end - 1, 3):  # Handguard vent slots.
		c.px(mx.call(body_w - 1), y, t.outline)
	for y in range(guard_end + 1, c.h):  # The barrel, a post to the flash hider.
		c.px(mx.call(2), y, t.dark, _PART_HEIGHT + 1)
	c.px(mx.call(2), c.h - 3, t.outline, _PART_HEIGHT + 1)
	c.px(mx.call(2), c.h - 1, Color(0.05, 0.05, 0.06))
	c.px(mx.call(1), stock_end + 1, t.outline, _PART_HEIGHT + 1)  # Rear sight.
	c.px(mx.call(1), guard_end - 1, t.outline, _PART_HEIGHT + 1)  # Front sight.
	c.cast_shadows()

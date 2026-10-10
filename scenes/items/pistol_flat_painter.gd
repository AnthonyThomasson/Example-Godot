extends RefCounted

## Top-down pixel-art painter for a PISTOL LYING FLAT on its side (Items domain, private; rendered
## through the Art domain's PixelArt): the gun's side profile as it rests on the floor — a long
## slide with its sights along the top edge and a dark muzzle toward +y, the grip angling back off
## the slide's underside with the trigger guard just ahead of it. Option `flip` (bool) lays it on
## its other side, so the grip points the other way.

const _GRIP_HEIGHT := 2  ## Heights for cast shadows.
const _SLIDE_HEIGHT := 3


## Paint the pistol's profile onto `c` in `base` metal, muzzle toward +y.
static func paint(c: PixelCanvas, base: Color, material: String, opts: Dictionary) -> void:
	# Its broad side faces up, catching more light than the slide's edge seen in the hand.
	var metal := base.lightened(0.15)
	var t := PixelCanvas.tones(metal)
	var grip_color := base.darkened(0.2)
	var flip: bool = opts.get("flip", false)
	var mx := func(x: int) -> int: return c.w - 1 - x if flip else x
	var slide_w := maxi(3, c.w * 2 / 5)
	var bottom := slide_w + 1  # First column below the slide (the grip side).

	# The grip: a slab hanging off the slide's rear, raked back toward −y.
	var grip_len := c.h * 2 / 5
	var grip := PixelCanvas.Shape.new(Rect2i(0, 0, c.w, c.h), func(x: int, y: int) -> bool:
		var lx: int = mx.call(x)
		if lx < bottom - 1 or lx >= c.w:
			return false
		var rake := float(lx - bottom) * 0.6
		return y >= 1 - rake and y <= grip_len - rake)
	c.fill(grip, grip_color, _GRIP_HEIGHT)
	for y in range(2, grip_len, 2):  # Grip texture.
		for lx in range(bottom + 1, c.w - 1):
			if grip.has(mx.call(lx), y - roundi((lx - bottom) * 0.6)):
				c.px(mx.call(lx), y - roundi((lx - bottom) * 0.6), grip_color.darkened(0.35))
	c.outline(grip, t.outline)

	# The trigger guard: a small loop just ahead of the grip.
	var gy := grip_len + 1
	for lx in range(bottom, bottom + 3):
		c.px(mx.call(lx), gy + 3, t.outline, _GRIP_HEIGHT)
	c.line(Vector2i(mx.call(bottom + 2), gy), Vector2i(mx.call(bottom + 2), gy + 3), t.outline, _GRIP_HEIGHT)
	c.px(mx.call(bottom), gy + 1, t.dark, _GRIP_HEIGHT)

	# The slide along the gun's length, its sights on the far edge.
	var slide := PixelCanvas.Shape.new(Rect2i(0, 0, c.w, c.h), func(x: int, y: int) -> bool:
		var lx: int = mx.call(x)
		return lx >= 1 and lx <= slide_w and y >= 0 and y < c.h)
	c.fill(slide, metal, _SLIDE_HEIGHT)
	c.surface(slide, material, metal, false)
	c.bevel(slide, 1, 1, t.light, t.dark)
	c.outline(slide, t.outline)
	c.line(Vector2i(mx.call(2), 2), Vector2i(mx.call(2), c.h - 3), t.highlight)
	var port := c.h * 2 / 5
	c.line(Vector2i(mx.call(slide_w - 1), port), Vector2i(mx.call(slide_w - 1), port + 2), t.outline)
	c.px(mx.call(0), 1, t.outline, _SLIDE_HEIGHT)          # Rear sight.
	c.px(mx.call(0), c.h - 2, t.outline, _SLIDE_HEIGHT)    # Front sight.
	for lx in range(2, slide_w):
		c.px(mx.call(lx), c.h - 1, Color(0.05, 0.05, 0.06))  # Muzzle.
	c.cast_shadows()

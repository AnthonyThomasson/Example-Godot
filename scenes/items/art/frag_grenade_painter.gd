extends RefCounted

## Top-down pixel-art FRAG GRENADE painter (Items domain, private; rendered through the Art domain's PixelArt).
## Painted in the canonical frame — the fuze toward +y: an olive-drab egg scored with the grid of lines that
## break it into fragments, topped with a steel fuze. Option `spoon` (bool): the safety lever still held down
## along the body (a grenade in the hand); thrown, it is gone.

const _BODY_HEIGHT := 5  ## Heights for cast shadows.
const _FUZE_HEIGHT := 6
const _SPOON_HEIGHT := 6


## Paint a frag grenade onto `c` in `base` olive, the fuze toward +y.
static func paint(c: PixelCanvas, base: Color, material: String, opts: Dictionary) -> void:
	var t := PixelCanvas.tones(base)
	var cx := int(c.w / 2.0)
	var fuze_len := maxi(2, int(c.h * 22 / 100.0))
	var body := PixelCanvas.ellipse(Rect2i(0, 0, c.w, c.h - fuze_len + 2))
	c.fill(body, base, _BODY_HEIGHT)
	c.surface(body, material, base, false)
	c.bevel(body, 1, 1, t.light, t.dark)
	c.outline(body, t.outline)
	# The fragmentation grid: lines across and along the shell.
	for y in range(2, c.h - fuze_len, 2):
		c.line(Vector2i(1, y), Vector2i(c.w - 2, y), t.shadow)
	c.line(Vector2i(cx, 1), Vector2i(cx, c.h - fuze_len), t.shadow)
	c.px(cx - 2, 2, t.highlight)
	# The fuze.
	var steel := Color(0.52, 0.54, 0.58)
	var fuze := PixelCanvas.rounded(Rect2i(cx - 1, c.h - fuze_len - 1, 3, fuze_len + 1), 1)
	c.fill(fuze, steel, _FUZE_HEIGHT)
	c.bevel(fuze, 1, 1, steel.lightened(0.2), steel.darkened(0.3))
	c.outline(fuze, steel.darkened(0.55))
	if opts.get("spoon", false):
		var lever := Color(0.7, 0.72, 0.76)
		for y in range(3, c.h - 1):
			c.px(c.w - 2 if y < c.h - 3 else c.w - 3, y, lever, _SPOON_HEIGHT)
	c.cast_shadows()

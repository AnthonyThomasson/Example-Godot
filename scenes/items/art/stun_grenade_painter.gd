extends RefCounted

## Top-down pixel-art STUN GRENADE painter (Items domain, private; rendered through the Art domain's PixelArt).
## Painted in the canonical frame — the fuze end toward +y: a bevelled steel cylinder with a ring of vent holes
## round its middle (where the flash and the bang leave), a dark band at the base and a black fuze cap. Option
## `spoon` (bool): the safety lever still held down along the body (a grenade in the hand); thrown, it is gone.

const _BODY_HEIGHT := 5  ## Heights for cast shadows.
const _CAP_HEIGHT := 6
const _SPOON_HEIGHT := 6


## Paint a stun grenade onto `c` in `base` steel, the fuze toward +y.
static func paint(c: PixelCanvas, base: Color, material: String, opts: Dictionary) -> void:
	var t := PixelCanvas.tones(base)
	var cx := int(c.w / 2.0)
	var cap_len := maxi(2, int(c.h * 24 / 100.0))
	var body := PixelCanvas.rounded(Rect2i(0, 0, c.w, c.h - cap_len + 1), 1)
	c.fill(body, base, _BODY_HEIGHT)
	c.surface(body, material, base, false)
	c.bevel(body, 1, 1, t.light, t.dark)
	c.outline(body, t.outline)
	c.line(Vector2i(cx - 1, 1), Vector2i(cx - 1, c.h - cap_len - 1), t.highlight)
	# The base band and the ring of vent holes.
	c.line(Vector2i(1, 1), Vector2i(c.w - 2, 1), t.shadow)
	var vent_y := int(c.h * 40 / 100.0)
	for x in range(1, c.w - 1, 2):
		c.px(x, vent_y, t.outline)
		c.px(x, vent_y + 2, t.outline)
	# The fuze cap.
	var cap := PixelCanvas.rounded(Rect2i(1, c.h - cap_len, maxi(c.w - 2, 2), cap_len), 1)
	c.fill(cap, Color(0.1, 0.1, 0.12), _CAP_HEIGHT)
	c.bevel(cap, 1, 1, Color(0.22, 0.22, 0.25), Color(0.04, 0.04, 0.05))
	c.outline(cap, Color(0.02, 0.02, 0.03))
	if opts.get("spoon", false):
		var lever := Color(0.7, 0.72, 0.76)
		for y in range(2, c.h - 1):
			c.px(c.w - 1, y, lever, _SPOON_HEIGHT)
		c.px(c.w - 1, c.h - 1, t.outline, _SPOON_HEIGHT)
	c.cast_shadows()

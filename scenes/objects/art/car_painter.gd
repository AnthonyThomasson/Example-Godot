extends RefCounted

## Top-down pixel-art CAR painter (Objects domain, private). Painted in the canonical frame (nose
## toward +y): tyres peeking out at the four corners, a glossy rounded body with hood creases and
## a gloss highlight, headlights and a grille up front and tail lights behind, a tinted windscreen
## and rear window around a raised roof, door seams with handles, and wing mirrors. No options.

const PixelCanvas = preload("res://scenes/objects/art/pixel_canvas.gd")

const _TYRE_HEIGHT := 2  ## Heights for cast shadows, floor-up.
const _BODY_HEIGHT := 6
const _ROOF_HEIGHT := 10


## Paint a car onto `c` in `base` paint, nose toward +y.
static func paint(c: PixelCanvas, base: Color, _material: String, _opts: Dictionary) -> void:
	var t := PixelCanvas.tones(base)
	var tyre := ObjectArtConfig.car_tyre_color
	var tyre_w := maxi(4, roundi(c.w * 0.1))
	var tyre_h := maxi(6, roundi(c.h * 0.14))
	for fy in [0.14, 0.72]:
		for x in [0, c.w - tyre_w]:
			var r := Rect2i(x, roundi(c.h * fy), tyre_w, tyre_h)
			c.fill(PixelCanvas.rounded(r, 2), tyre, _TYRE_HEIGHT)
			for y in range(r.position.y + 2, r.end.y - 1, 3):
				c.line(Vector2i(r.position.x + 1, y), Vector2i(r.end.x - 2, y), tyre.lightened(0.15))

	var inset := tyre_w - 2
	var body_rect := Rect2i(inset, 1, c.w - inset * 2, c.h - 2)
	var body := PixelCanvas.rounded(body_rect, roundi(body_rect.size.x * 0.2))
	c.fill(body, base, _BODY_HEIGHT)
	c.bevel(body, 2, 3, t.highlight, t.dark)
	c.glare(body, base.lightened(0.3), 3)

	var glass := ObjectArtConfig.car_glass_color
	var cx := c.w / 2
	for side in [-1, 1]:
		var crease_x: int = cx + side * roundi(body_rect.size.x * 0.22)
		c.line(Vector2i(crease_x, roundi(c.h * 0.7)), Vector2i(crease_x, c.h - 8), t.dark)
		var lamp := PixelCanvas.ellipse(Rect2i(cx + side * roundi(body_rect.size.x * 0.32) - 5, c.h - 9, 10, 6))
		c.fill(lamp, ObjectArtConfig.car_light_color, _BODY_HEIGHT)
		c.outline(lamp, t.outline)
		var tail := PixelCanvas.rounded(Rect2i(cx + side * roundi(body_rect.size.x * 0.32) - 5, 2, 10, 3), 1)
		c.fill(tail, Color(0.8, 0.12, 0.1), _BODY_HEIGHT)
		var mirror := PixelCanvas.rounded(Rect2i(inset - 4 if side < 0 else body_rect.end.x - 1, roundi(c.h * 0.55), 5, 4), 1)
		c.fill(mirror, base, _BODY_HEIGHT)
		c.outline(mirror, t.outline)
		for fy in [0.42, 0.6]:
			var y := roundi(c.h * fy)
			var edge: int = body_rect.position.x + 2 if side < 0 else body_rect.end.x - 3
			c.line(Vector2i(edge, y), Vector2i(edge + side * -4, y), t.shadow)
			c.px(edge + side * -2, y + 4, t.highlight)
	var grille := PixelCanvas.rounded(Rect2i(cx - roundi(body_rect.size.x * 0.18), c.h - 6, roundi(body_rect.size.x * 0.36), 3), 1)
	c.fill(grille, t.outline, _BODY_HEIGHT)

	var screen := PixelCanvas.rounded(Rect2i(body_rect.position.x + 8, roundi(c.h * 0.56), body_rect.size.x - 16, roundi(c.h * 0.12)), 5)
	c.fill(screen, glass, _BODY_HEIGHT)
	c.glare(screen, glass.lightened(0.4), 2)
	var rear := PixelCanvas.rounded(Rect2i(body_rect.position.x + 10, roundi(c.h * 0.16), body_rect.size.x - 20, roundi(c.h * 0.09)), 4)
	c.fill(rear, glass, _BODY_HEIGHT)
	c.glare(rear, glass.lightened(0.35), 1)
	var roof_rect := Rect2i(body_rect.position.x + 9, roundi(c.h * 0.25), body_rect.size.x - 18, roundi(c.h * 0.31))
	var roof := PixelCanvas.rounded(roof_rect, 6)
	c.fill(roof, base.lightened(0.04), _ROOF_HEIGHT)
	c.bevel(roof, 1, 2, t.highlight, t.dark)
	c.outline(roof, t.shadow)
	for x in [roof_rect.position.x - 2, roof_rect.end.x + 1]:
		c.line(Vector2i(x, roof_rect.position.y + 3), Vector2i(x, roof_rect.end.y - 4), glass, _BODY_HEIGHT)
	c.outline(body, t.outline)
	c.cast_shadows()

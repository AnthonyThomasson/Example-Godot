extends RefCounted

## Top-down pixel-art PISTOL painter (Items domain, private; rendered through the Art domain's
## PixelArt). Painted in the canonical frame — muzzle toward +y, the grip at the back where the
## hand holds it: a brushed slide with a lit spine, an ejection port, rear and front sights and a
## dark muzzle. No options.

const _GRIP_HEIGHT := 3  ## Heights for cast shadows.
const _SLIDE_HEIGHT := 5


## Paint a pistol onto `c` in `base` metal, muzzle toward +y.
static func paint(c: PixelCanvas, base: Color, material: String, _opts: Dictionary) -> void:
	var t := PixelCanvas.tones(base)
	var cx := int(c.w / 2.0)
	var grip_len := maxi(3, int(c.h / 4.0))
	var grip := PixelCanvas.rounded(Rect2i(1, 0, c.w - 2, grip_len + 1), 1)
	c.fill(grip, t.shadow, _GRIP_HEIGHT)
	c.outline(grip, t.outline)
	var slide_rect := Rect2i(0, grip_len - 1, c.w, c.h - grip_len + 1)
	var slide := PixelCanvas.rounded(slide_rect, 1)
	c.fill(slide, base, _SLIDE_HEIGHT)
	c.surface(slide, material, base, false)
	c.bevel(slide, 1, 1, t.light, t.dark)
	c.outline(slide, t.outline)
	c.line(Vector2i(cx, slide_rect.position.y + 2), Vector2i(cx, c.h - 3), t.highlight)
	var port_y := slide_rect.position.y + int(slide_rect.size.y * 2 / 5.0)
	c.line(Vector2i(cx - 1, port_y), Vector2i(cx - 1, port_y + 2), t.outline)
	c.px(cx, slide_rect.position.y + 1, t.outline)
	c.px(cx, c.h - 2, t.highlight)
	c.px(cx, c.h - 1, Color(0.05, 0.05, 0.06))
	c.cast_shadows()

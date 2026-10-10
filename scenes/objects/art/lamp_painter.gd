extends RefCounted

## Top-down pixel-art FLOOR LAMP painter (Objects domain, private), kept within the inscribed circle
## of its round footprint: a lampshade in the piece's color with faint panel seams and a lit rim,
## and through its open top the dark inside and a glowing bulb. No options.

const PixelCanvas = preload("res://scenes/objects/art/pixel_canvas.gd")

const _SHADE_HEIGHT := 8  ## Cast-shadow height of the shade.


## Paint a lamp onto `c` with a `base` shade.
static func paint(c: PixelCanvas, base: Color, _material: String, _opts: Dictionary) -> void:
	var t := PixelCanvas.tones(base)
	var o := Vector2i(c.w / 2, c.h / 2)
	var radius := mini(c.w, c.h) / 2 - 1
	var shade := PixelCanvas.disc(o, radius)
	c.fill(shade, base, _SHADE_HEIGHT)
	var inner := maxi(2, roundi(radius * 0.45))
	for i in 8:
		var a := TAU * i / 8.0
		var d := Vector2(cos(a), sin(a))
		c.line(o + Vector2i((d * inner).round()), o + Vector2i((d * (radius - 1)).round()), base.darkened(0.08))
	c.bevel(shade, 1, 2, t.highlight, t.dark)
	c.outline(shade, t.outline)
	c.fill(PixelCanvas.disc(o, inner), base.darkened(0.3))
	c.fill(PixelCanvas.disc(o, maxi(1, inner - 2)), ObjectArtConfig.lamp_glow_color)
	c.px(o.x, o.y, Color.WHITE)

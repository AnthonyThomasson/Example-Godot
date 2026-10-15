extends RefCounted

## Top-down pixel-art FLOOR LAMP painter (Objects domain, private), kept within the inscribed circle
## of its round footprint: a dented tin shade, rusting, and through its open top the dark inside and a bare, dim bulb
## (drawn glowing: it gives light). Options (`art_opts`): `neon` (a neon ring tube inside the shade round the bulb, glowing).
## Its catalogue colour only tints its debris: the shade is ObjectArtConfig.lamp_tin_color.

const Decay = preload("res://scenes/objects/art/decay.gd")

const _SHADE_HEIGHT := 8  ## Cast-shadow height of the shade.


## Paint a lamp onto `c`, its tin shade, bulb and any neon from ObjectArtConfig and `opts`.
static func paint(c: PixelCanvas, _base: Color, _material: String, opts: Dictionary) -> void:
	var o := Vector2i(int(c.w / 2.0), int(c.h / 2.0))
	var radius := int(mini(c.w, c.h) / 2.0) - 2
	var tin := ObjectArtConfig.lamp_tin_color
	var shade := PixelCanvas.disc(o, radius)
	c.fill(shade, tin, _SHADE_HEIGHT)
	c.bevel(shade, 1, 1, tin.lightened(0.2), tin.darkened(0.3))
	c.outline(shade, tin.darkened(0.6))
	Decay.rust(c, 3)
	c.fill(PixelCanvas.disc(o, maxi(1, radius - 3)), tin.darkened(0.55))
	c.glowing(func() -> void:
		c.fill(PixelCanvas.disc(o, maxi(1, int(radius / 3.0))), ObjectArtConfig.lamp_glow_color)
		c.px(o.x, o.y, ObjectArtConfig.lamp_glow_color.lightened(0.8)))
	c.cast_shadows()
	var neon := Decay.neon(opts)
	if neon.a > 0.0:
		c.glowing(func() -> void: c.outline(PixelCanvas.disc(o, maxi(2, int(mini(c.w, c.h) / 2.0) - 4)), neon))

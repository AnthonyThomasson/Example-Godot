extends RefCounted

## Top-down pixel-art RECLINER painter (Objects domain, private): a long reclined chair seen from above, head at the back
## (-y): headrest, backrest, seat and leg rest as padded sections in a dark frame, armrests at its sides; `kind` in the
## options.
##   `rig`: the netrunner's jack-in rig, padded in the catalogue colour (the room palette's fabric), a neural halo of LEDs
##     round the headrest and cables off it to the back; the halo glows in its `neon` (or the cheap screens' green).
##   `surgical`: the ripperdoc's chair, padded in pale vinyl (ObjectArtConfig.recliner_vinyl_color), strapped, a lamp on an
##     arm over the chest; the lamp glows.
## Run down (decay.gd): the padding torn and taped, grime, rust on the frame. Knobs: ObjectArtConfig.recliner_*.

const Decay = preload("res://scenes/objects/art/decay.gd")
const Tech = preload("res://scenes/objects/art/tech_painter.gd")

const _FRAME_HEIGHT := 2  ## Heights for cast shadows.
const _PAD_HEIGHT := 4
const _ARM_HEIGHT := 5
const _LAMP_HEIGHT := 10
## The padded sections, as fractions of the inner length: headrest, backrest, seat, leg rest.
const _SECTIONS := [[0.0, 0.18], [0.2, 0.52], [0.54, 0.74], [0.76, 1.0]]


## Paint the recliner `opts.kind` onto `c`, padded in `base` (a rig) or pale vinyl (surgical), head toward -y.
static func paint(c: PixelCanvas, base: Color, _material: String, opts: Dictionary) -> void:
	var surgical := String(opts.get("kind", "rig")) == "surgical"
	var pad: Color = ObjectArtConfig.recliner_vinyl_color if surgical else base
	var frame := PixelCanvas.rounded(Rect2i(4, 2, c.w - 8, c.h - 4), 6)
	c.fill(frame, ObjectArtConfig.tech_dark_color, _FRAME_HEIGHT)
	var inner := Rect2i(7, 4, c.w - 14, c.h - 8)
	for k in _SECTIONS.size():
		var y0 := inner.position.y + roundi(inner.size.y * _SECTIONS[k][0])
		var y1 := inner.position.y + roundi(inner.size.y * _SECTIONS[k][1])
		var narrow := 4 if k == 0 else 0
		Tech.box(c, Rect2i(inner.position.x + narrow, y0, inner.size.x - narrow * 2, y1 - y0), pad, _PAD_HEIGHT if k < 2 else _PAD_HEIGHT - 1, 4)
	for x in [1, c.w - 5]:  # Armrests.
		Tech.box(c, Rect2i(x, roundi(c.h * 0.36), 4, roundi(c.h * 0.3)), ObjectArtConfig.recliner_frame_color, _ARM_HEIGHT, 1)
	Decay.tear(c)
	Decay.tape(c)
	if surgical:
		_straps_and_lamp(c, inner)
	else:
		_halo(c, inner, Decay.screen_color(opts))
	c.cast_shadows()
	Decay.grime(c)
	Decay.rust(c, 3)


## The surgical chair's two straps and its lamp on an arm from a mount behind, the lamp glowing.
static func _straps_and_lamp(c: PixelCanvas, inner: Rect2i) -> void:
	var dark := ObjectArtConfig.tech_dark_color
	for f in [0.36, 0.62]:
		var y := inner.position.y + roundi(inner.size.y * f)
		c.line(Vector2i(inner.position.x, y), Vector2i(inner.end.x - 1, y), dark, _PAD_HEIGHT + 1)
		c.px(int(c.w / 2.0), y, ObjectArtConfig.recliner_frame_color.lightened(0.3), _PAD_HEIGHT + 1)
	var lamp := Vector2i(int(c.w / 2.0), roundi(c.h * 0.42))
	c.line(Vector2i(c.w - 2, 4), lamp, ObjectArtConfig.recliner_frame_color, _LAMP_HEIGHT - 1)
	var head := PixelCanvas.disc(lamp, 6)
	c.fill(head, ObjectArtConfig.recliner_frame_color, _LAMP_HEIGHT)
	c.outline(head, dark)
	c.glowing(func() -> void: c.fill(PixelCanvas.disc(lamp, 3), ObjectArtConfig.recliner_lamp_color, _LAMP_HEIGHT))


## The rig's neural halo of LEDs round the headrest (glowing, every other one in `screen`) and its cables off to the back.
static func _halo(c: PixelCanvas, inner: Rect2i, screen: Color) -> void:
	var o := Vector2i(int(c.w / 2.0), inner.position.y + 5)
	var other := ObjectArtConfig.tech_led_colors[0]
	c.glowing(func() -> void:
		for i in 10:
			var a := PI + PI * i / 9.0
			var q := o + Vector2i((Vector2(cos(a), sin(a) * 0.7) * 10.0).round())
			c.px(q.x, q.y, screen if i % 2 == 0 else other, _PAD_HEIGHT + 3))
	for dx in [-4, 0, 4]:
		c.line(Vector2i(o.x + dx, inner.position.y), Vector2i(o.x + dx * 2, 0), ObjectArtConfig.tech_dark_color.lightened(0.2), _PAD_HEIGHT + 2)

extends RefCounted

## Top-down pixel-art BED painter (Objects domain, private). Painted in the canonical frame (foot
## toward +y, head at the back): a bare mattress straight on the floor, quilted in stripes and stained, one flat pillow at
## the head, and a crumpled blanket in the piece's fabric colour over its foot; run down (decay.gd) with grime. Options
## (`art_opts`): `neon` (a neon strip round the mattress, glowing).

const Decay = preload("res://scenes/objects/art/decay.gd")

const _STAIN := Color(0.42, 0.3, 0.12)  ## What soaked into the mattress.
const _MATTRESS_HEIGHT := 2  ## Heights for cast shadows, floor-up.
const _PILLOW_HEIGHT := 3
const _BLANKET_HEIGHT := 4


## Paint a bed onto `c` with a `base` blanket, foot toward +y.
static func paint(c: PixelCanvas, base: Color, _material: String, opts: Dictionary) -> void:
	var ticking := ObjectArtConfig.bed_mattress_color
	var mt := PixelCanvas.tones(ticking)
	var rect := Rect2i(3, 6, c.w - 6, c.h - 9)
	var mattress := PixelCanvas.rounded(rect, 4)
	c.fill(mattress, ticking, _MATTRESS_HEIGHT)
	for y in range(rect.position.y + 3, rect.end.y - 2, ObjectArtConfig.bed_stripe_px):
		for x in range(rect.position.x + 2, rect.end.x - 2, 2):
			c.px(x, y, mt.dark)
	c.bevel(mattress, 1, 2, mt.light, mt.dark)
	c.outline(mattress, mt.outline)

	var pillow := PixelCanvas.rounded(Rect2i(rect.position.x + 6, rect.position.y + 4, int(rect.size.x * 0.45), 14), 4)
	c.fill(pillow, ticking.lightened(0.08), _PILLOW_HEIGHT)
	c.outline(pillow, mt.dark)

	var blanket_rect := Rect2i(rect.position.x - 1, int(rect.size.y * 0.5), rect.size.x + 2, int(rect.size.y * 0.42))
	var blanket := PixelCanvas.bowed(blanket_rect, 4, 3)
	var bt := PixelCanvas.tones(base)
	c.fill(blanket, base, _BLANKET_HEIGHT)
	for _i in 6:  # Creases.
		var y := c.rng.randi_range(blanket_rect.position.y + 2, blanket_rect.end.y - 3)
		var x0 := c.rng.randi_range(blanket_rect.position.x + 2, blanket_rect.end.x - 12)
		Decay.line(c, Vector2i(x0, y), Vector2i(x0 + c.rng.randi_range(6, 14), y + c.rng.randi_range(-2, 2)), bt.dark, 1.0)
	c.bevel(blanket, 1, 2, bt.light, bt.dark)
	c.outline(blanket, bt.outline)
	for _i in 3:
		Decay.stain(c, _STAIN, 6)
	c.cast_shadows()
	Decay.grime(c)
	var neon := Decay.neon(opts)
	if neon.a > 0.0:
		Decay.neon_ring(c, 1, neon, 0.55)

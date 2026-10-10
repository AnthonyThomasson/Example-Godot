extends RefCounted

## Top-down pixel-art SOFA painter (Objects domain, private). Painted in the canonical frame
## (seat front at +y): a backrest with a rolled top and a row of back cushions, rolled armrests
## at both ends, puffy seat cushions lined up under the back cushions, optional throw pillows in
## the back corners, and a speckled weave over the upholstery. Raised parts shade the seat beside
## them. Options (`art_opts`, defaulting to ObjectArtConfig.sofa_*): `back_depth`, `arm_width`,
## `cushion_width`, `max_cushions`, `pillows`.

const PixelCanvas = preload("res://scenes/objects/art/pixel_canvas.gd")

const _FRAME_HEIGHT := 1  ## Heights for cast shadows, floor-up.
const _SEAT_HEIGHT := 2
const _PILLOW_HEIGHT := 3
const _BACK_CUSHION_HEIGHT := 4
const _BACK_HEIGHT := 5
const _ARM_HEIGHT := 6


## Paint a sofa onto `c` in `base` upholstery, seat front toward +y.
static func paint(c: PixelCanvas, base: Color, opts: Dictionary) -> void:
	var t := PixelCanvas.tones(base)
	var full := PixelCanvas.rounded(Rect2i(0, 0, c.w, c.h), 4)
	var back_d := clampi(roundi(c.h * float(opts.get("back_depth", ObjectArtConfig.sofa_back_depth))), 4, c.h / 2)
	var arm_w := clampi(roundi(c.w * float(opts.get("arm_width", ObjectArtConfig.sofa_arm_width))), 3, c.w / 4)
	var seat_w := c.w - 2 * arm_w
	var n := clampi(roundi(seat_w / float(opts.get("cushion_width", ObjectArtConfig.sofa_cushion_width))),
			1, int(opts.get("max_cushions", ObjectArtConfig.sofa_max_cushions)))
	# Back cushions lean away from the light overhead, so they sit a shade darker than the seat.
	var back_tone := base.darkened(0.1)

	# The frame shows only in the gaps between cushions.
	c.fill(full, t.shadow, _FRAME_HEIGHT)

	# Seat cushions.
	for i in n:
		var x0 := arm_w + roundi(float(i) * seat_w / n)
		var x1 := arm_w + roundi(float(i + 1) * seat_w / n)
		_cushion(c, Rect2i(x0, back_d - 1, x1 - x0, c.h - back_d), base, _SEAT_HEIGHT)

	# Backrest: a rolled top across the full width over a row of back cushions.
	var back := PixelCanvas.rounded(Rect2i(0, 0, c.w, back_d), 4)
	c.fill(back, base, _BACK_HEIGHT)
	c.bevel(back, 2, 2, t.highlight, t.dark)
	c.bevel(back, 3, 3, t.light, t.dark)
	var roll := maxi(3, back_d / 3)
	for i in n:
		var x0 := arm_w + roundi(float(i) * seat_w / n)
		var x1 := arm_w + roundi(float(i + 1) * seat_w / n)
		_cushion(c, Rect2i(x0, roll, x1 - x0, back_d - roll + 1), back_tone, _BACK_CUSHION_HEIGHT)

	# Rolled armrests, a ridge of light along each roll.
	for x: int in [0, c.w - arm_w]:
		var arm := PixelCanvas.rounded(Rect2i(x, 0, arm_w, c.h), 4)
		c.fill(arm, base, _ARM_HEIGHT)
		c.bevel(arm, 2, 2, t.highlight, t.shadow)
		c.bevel(arm, 3, 3, t.light, t.dark)
		var ridge := x + arm_w / 2 + (-1 if c.light.x < 0.0 else 0)
		for y in range(4, c.h - 4):
			c.px(ridge, y, t.light)
		c.outline(arm, t.outline)

	if opts.get("pillows", ObjectArtConfig.sofa_pillows):
		_pillows(c, base, back_d, arm_w, seat_w)

	var bounds := Rect2i(0, 0, c.w, c.h)
	for tone in [base, base.lightened(0.05), back_tone, back_tone.lightened(0.05)]:
		c.speckle(bounds, tone, ObjectArtConfig.fabric_speckle)
	c.cast_shadows()
	c.outline(full, t.outline)


## One puffy cushion in `tone`: a paler centre, light-aware bevel and a seam ring.
static func _cushion(c: PixelCanvas, r: Rect2i, tone: Color, height: int) -> void:
	var ct := PixelCanvas.tones(tone)
	var cushion := PixelCanvas.rounded(r, 3)
	c.fill(cushion, tone, height)
	c.fill(PixelCanvas.rounded(r.grow(-4), 4), tone.lightened(0.05))
	c.bevel(cushion, 2, 3, ct.light, ct.dark)
	c.outline(cushion, ct.shadow)


## A throw pillow in each back corner of the seat, hue-shifted from the upholstery, with a
## crease running in from its outer corner.
static func _pillows(c: PixelCanvas, base: Color, back_d: int, arm_w: int, seat_w: int) -> void:
	var size := mini(roundi(back_d * 1.0), seat_w / 4)
	if size < 6:
		return
	var col := Color.from_hsv(fposmod(base.h + ObjectArtConfig.sofa_pillow_hue_shift, 1.0),
			clampf(base.s * 1.15, 0.0, 1.0), clampf(base.v * 1.05, 0.0, 1.0))
	var pt := PixelCanvas.tones(col)
	var y := back_d - 3
	for left: bool in [true, false]:
		var x := arm_w + 1 if left else c.w - arm_w - 1 - size
		var r := Rect2i(x, y, size, size - 1)
		var pillow := PixelCanvas.rounded(r, 3)
		c.fill(pillow, col, _PILLOW_HEIGHT)
		c.fill(PixelCanvas.rounded(r.grow(-3), 3), col.lightened(0.06))
		c.bevel(pillow, 2, 2, pt.light, pt.dark)
		c.outline(pillow, pt.shadow)
		c.speckle(r, col, ObjectArtConfig.fabric_speckle)
		for i in range(2, size / 2):
			c.px(x + i if left else x + size - 1 - i, y + i, pt.dark)

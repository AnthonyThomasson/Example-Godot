extends RefCounted

## Top-down pixel-art wooden CHAIR painter (Objects domain, private). Painted in the canonical
## frame (front of the seat at +y): a rounded seat with a paler worn centre, cross grain and a
## bevelled edge, and across the back a curved crest rail whose ends sag toward the seat, joined
## to it by spindles. Options (`art_opts`, defaulting to ObjectArtConfig.chair_*): `back_depth`,
## `slats`.

const PixelCanvas = preload("res://scenes/objects/art/pixel_canvas.gd")

const _SEAT_HEIGHT := 1  ## Heights for cast shadows: the back stands over the seat.
const _SLAT_HEIGHT := 3
const _RAIL_HEIGHT := 5


## Paint a chair onto `c` in `base` wood, front toward +y.
static func paint(c: PixelCanvas, base: Color, _material: String, opts: Dictionary) -> void:
	var t := PixelCanvas.tones(base)
	var back_d := clampi(roundi(c.h * float(opts.get("back_depth", ObjectArtConfig.chair_back_depth))), 3, c.h / 2)
	var rail_th := maxi(2, roundi(back_d * 0.55))
	var bow := maxi(1, roundi(back_d * 0.3))
	var inset := maxi(1, c.w / 14)

	# Spindles run from under the rail down beneath the seat's back edge.
	var slats: int = opts.get("slats", ObjectArtConfig.chair_slats)
	for i in slats:
		var x := roundi(float(i + 1) * c.w / (slats + 1)) - 1
		var spindle := PixelCanvas.rounded(Rect2i(x, rail_th - 1, 2, back_d - rail_th + 2), 0)
		c.fill(spindle, t.dark, _SLAT_HEIGHT)

	# Seat: worn centre, grain across, bevelled edge.
	var seat_rect := Rect2i(inset, back_d - 1, c.w - 2 * inset, c.h - back_d + 1)
	var seat := PixelCanvas.rounded(seat_rect, 4)
	c.fill(seat, base, _SEAT_HEIGHT)
	c.fill(PixelCanvas.rounded(seat_rect.grow(-4), 4), base.lightened(0.05))
	c.grain(PixelCanvas.rounded(seat_rect.grow(-2), 3), true, ObjectArtConfig.wood_grain_density * 1.5,
			base.darkened(0.12), base.lightened(0.08))
	c.bevel(seat, 2, 2, t.light, t.dark)
	c.outline(seat, t.outline)

	# Curved crest rail across the back.
	var rail_rect := Rect2i(inset - 1, 0, c.w - 2 * inset + 2, rail_th + bow)
	var rail := PixelCanvas.bowed(rail_rect, 2, bow)
	c.fill(rail, base, _RAIL_HEIGHT)
	c.grain(rail, true, ObjectArtConfig.wood_grain_density * 2.0, base.darkened(0.12), base.lightened(0.08))
	c.bevel(rail, 2, 2, t.highlight, t.dark)
	c.outline(rail, t.outline)

	c.cast_shadows()

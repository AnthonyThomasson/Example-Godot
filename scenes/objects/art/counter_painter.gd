extends RefCounted

## Top-down pixel-art COUNTER painter (worktops, islands, vanities; Objects domain, private).
## Painted in the canonical frame (front toward +y): a stone or ceramic top with a backsplash
## along the back, a bullnose front edge, optionally a sunken basin with drain and mixer tap, and
## an island's seating overhang. Options (`art_opts`, defaulting to ObjectArtConfig.counter_*):
## `basin` ("none" | "single" | "deep"), `backsplash`, `overhang`, `props`.

const PixelCanvas = preload("res://scenes/objects/art/pixel_canvas.gd")
const Props = preload("res://scenes/objects/art/props.gd")

const _TOP_HEIGHT := 3     ## Heights for cast shadows.
const _SPLASH_HEIGHT := 6
const _TAP_HEIGHT := 8


## Paint a counter onto `c` in `base` with a `material` finish, front toward +y.
static func paint(c: PixelCanvas, base: Color, material: String, opts: Dictionary) -> void:
	var t := PixelCanvas.tones(base)
	var body := PixelCanvas.rounded(Rect2i(0, 0, c.w, c.h), 2)
	c.fill(body, base, _TOP_HEIGHT)
	c.surface(body, material, base)

	var splash := 0
	if opts.get("backsplash", ObjectArtConfig.counter_backsplash):
		splash = maxi(2, roundi(c.h * 0.07))
		var band := PixelCanvas.rounded(Rect2i(0, 0, c.w, splash), 1)
		c.fill(band, t.dark, _SPLASH_HEIGHT)
		c.line(Vector2i(1, splash - 1), Vector2i(c.w - 2, splash - 1), t.light)
	if opts.get("overhang", false):
		var oh := maxi(3, roundi(c.h * 0.14))
		c.paint_over(Rect2i(0, c.h - oh, c.w, oh), base.lightened(0.05))
		c.line(Vector2i(2, c.h - oh), Vector2i(c.w - 3, c.h - oh), t.dark)

	var basin := String(opts.get("basin", "none"))
	if basin != "none":
		_basin(c, base, t, splash, basin == "deep")

	c.bevel(body, 2, 2, t.highlight, t.dark)
	c.outline(body, t.outline)
	Props.draw_all(c, opts.get("props", []), Rect2i(0, splash, c.w, c.h - splash).grow(-3))
	c.cast_shadows()


## A sunken basin (inverted bevel, so the lit rim falls in shadow), a drain, and a mixer tap with
## two handles on the backsplash side.
static func _basin(c: PixelCanvas, base: Color, t: Dictionary, splash: int, deep: bool) -> void:
	var margin_x := maxi(3, roundi(c.w * 0.16))
	var top := splash + maxi(3, roundi(c.h * 0.12))
	var r := Rect2i(margin_x, top, c.w - margin_x * 2, maxi(4, c.h - top - maxi(3, roundi(c.h * 0.1))))
	var radius := mini(6, mini(r.size.x, r.size.y) / 3)
	var bowl := PixelCanvas.rounded(r, radius)
	var floor_col := base.darkened(0.16 if deep else 0.08)
	c.fill(bowl, floor_col, 1)
	c.bevel(bowl, 1, 1, t.shadow, t.light)
	c.bevel(bowl, 2, 3 if deep else 2, t.dark, floor_col.lightened(0.05))
	var centre := r.position + r.size / 2
	var metal := ObjectArtConfig.counter_tap_color
	var drain := PixelCanvas.disc(centre, 2)
	c.fill(drain, metal.darkened(0.3))
	c.px(centre.x, centre.y, metal.darkened(0.7))
	var tap_x := r.position.x + r.size.x / 2
	c.fill(PixelCanvas.rounded(Rect2i(tap_x - 1, maxi(0, splash - 1), 2, top - splash + 4), 0), metal, _TAP_HEIGHT)
	c.px(tap_x - 1, maxi(0, splash - 1), metal.lightened(0.4))
	for dx in [-5, 5]:
		var knob := PixelCanvas.disc(Vector2i(tap_x + dx, maxi(1, splash)), 1)
		c.fill(knob, metal, _TAP_HEIGHT)

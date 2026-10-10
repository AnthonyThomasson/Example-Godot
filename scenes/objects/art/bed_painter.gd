extends RefCounted

## Top-down pixel-art BED painter (Objects domain, private). Painted in the canonical frame (foot
## toward +y, headboard at the back): a wooden frame and headboard, a sheeted mattress, one or two
## puffy pillows, and a duvet in the piece's fabric color with the sheet turned down over its top
## and a quilted, starry or striped pattern. Options (`art_opts`, defaulting to
## ObjectArtConfig.bed_*): `pillows` (0 = by width), `pattern` ("quilt" | "stars" | "stripes"),
## `frame` (a Color).

const PixelCanvas = preload("res://scenes/objects/art/pixel_canvas.gd")

const _FRAME_HEIGHT := 2  ## Heights for cast shadows, floor-up.
const _MATTRESS_HEIGHT := 3
const _DUVET_HEIGHT := 4
const _PILLOW_HEIGHT := 5
const _HEAD_HEIGHT := 8


## Paint a bed onto `c` with a `base` duvet, foot toward +y.
static func paint(c: PixelCanvas, base: Color, _material: String, opts: Dictionary) -> void:
	var t := PixelCanvas.tones(base)
	var frame_col: Color = opts.get("frame", ObjectArtConfig.bed_frame_color)
	var ft := PixelCanvas.tones(frame_col)
	var sheet := ObjectArtConfig.bed_sheet_color
	var st := PixelCanvas.tones(sheet)

	var frame := PixelCanvas.rounded(Rect2i(0, 0, c.w, c.h), 3)
	c.fill(frame, frame_col, _FRAME_HEIGHT)

	var head_h := clampi(roundi(c.h * 0.06), 3, 12)
	var mattress_rect := Rect2i(2, head_h, c.w - 4, c.h - head_h - 2)
	var mattress := PixelCanvas.rounded(mattress_rect, 3)
	c.fill(mattress, sheet, _MATTRESS_HEIGHT)
	c.bevel(mattress, 1, 2, st.light, st.dark)

	var pillow_h := clampi(roundi(c.h * 0.13), 6, 26)
	var count := int(opts.get("pillows", ObjectArtConfig.bed_pillows))
	if count <= 0:
		count = 2 if c.w >= 100 else 1
	var gap := 3
	var pw := (mattress_rect.size.x - 6 - gap * (count - 1)) / count
	for i in count:
		_pillow(c, Rect2i(mattress_rect.position.x + 3 + i * (pw + gap), head_h + 2, pw, pillow_h), sheet.lightened(0.04))

	var duvet_top := head_h + pillow_h + 6
	var duvet_rect := Rect2i(1, duvet_top, c.w - 2, c.h - duvet_top - 1)
	var duvet := PixelCanvas.rounded(duvet_rect, 3)
	c.fill(duvet, base, _DUVET_HEIGHT)
	c.surface(duvet, "fabric", base)
	_pattern(c, duvet_rect, base, String(opts.get("pattern", ObjectArtConfig.bed_pattern)))
	var fold_h := clampi(roundi(c.h * 0.06), 4, 10)
	c.paint_over(Rect2i(duvet_rect.position.x, duvet_top, duvet_rect.size.x, fold_h), sheet.darkened(0.03))
	c.line(Vector2i(duvet_rect.position.x + 1, duvet_top + fold_h), Vector2i(duvet_rect.end.x - 2, duvet_top + fold_h), t.shadow)
	c.bevel(duvet, 1, 2, t.light, t.dark)
	c.outline(duvet, t.shadow)

	var head := PixelCanvas.rounded(Rect2i(0, 0, c.w, head_h), 2)
	c.fill(head, frame_col, _HEAD_HEIGHT)
	c.surface(head, "wood", frame_col)
	c.bevel(head, 2, 2, ft.highlight, ft.dark)
	c.outline(head, ft.outline)

	c.cast_shadows()
	c.outline(frame, ft.outline)


## A puffy pillow: a paler centre, a crease across it and a soft seam ring.
static func _pillow(c: PixelCanvas, r: Rect2i, col: Color) -> void:
	var pt := PixelCanvas.tones(col)
	var pillow := PixelCanvas.rounded(r, 4)
	c.fill(pillow, col, _PILLOW_HEIGHT)
	c.fill(PixelCanvas.rounded(r.grow(-3), 3), col.lightened(0.05))
	c.bevel(pillow, 1, 2, pt.light, pt.dark)
	c.outline(pillow, col.darkened(0.25))
	var cy := r.position.y + r.size.y / 2
	c.line(Vector2i(r.position.x + r.size.x / 3, cy), Vector2i(r.end.x - r.size.x / 3, cy + 1), pt.dark)


## Duvet surface pattern: quilting stitches on a grid, scattered stars, or broad stripes.
static func _pattern(c: PixelCanvas, r: Rect2i, base: Color, pattern: String) -> void:
	match pattern:
		"quilt":
			var step := maxi(6, ObjectArtConfig.bed_quilt_px)
			var stitch := base.darkened(0.12)
			for y in range(r.position.y + step, r.end.y - 2, step):
				for x in range(r.position.x + 2, r.end.x - 2, 2):
					c.px(x, y, stitch)
			for x in range(r.position.x + step, r.end.x - 2, step):
				for y in range(r.position.y + 2, r.end.y - 2, 2):
					c.px(x, y, stitch)
		"stars":
			var star := ObjectArtConfig.bed_star_color
			for _i in maxi(3, r.get_area() / 260):
				var p := r.position + Vector2i(c.rng.randi_range(3, r.size.x - 4), c.rng.randi_range(6, r.size.y - 4))
				for d in [Vector2i.ZERO, Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
					c.px(p.x + d.x, p.y + d.y, star if d == Vector2i.ZERO else star.darkened(0.15))
		"stripes":
			var band := maxi(4, ObjectArtConfig.bed_quilt_px / 2)
			for y in range(r.position.y, r.end.y, band * 2):
				c.paint_over(Rect2i(r.position.x, y, r.size.x, band), base.lightened(0.1))

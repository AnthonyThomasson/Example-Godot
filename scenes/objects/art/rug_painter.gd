extends RefCounted

## Top-down pixel-art RUG painter (Objects domain, private). A woven rug: a contrasting border with
## a pale inner line and a stitched band, a patterned field (a stepped central medallion with
## corner pieces, or stripes) and fringe at both short ends. A `plush` mat: rounded, densely tufted
## with a darker rim. Options (`art_opts`, defaulting to ObjectArtConfig.rug_*): `pattern`
## ("medallion" | "stripes" | "plush").

const PixelCanvas = preload("res://scenes/objects/art/pixel_canvas.gd")


## Paint a rug onto `c` in `base` fabric.
static func paint(c: PixelCanvas, base: Color, _material: String, opts: Dictionary) -> void:
	var pattern := String(opts.get("pattern", ObjectArtConfig.rug_pattern))
	if pattern == "plush":
		_plush(c, base)
		return
	var along_x := c.w >= c.h
	var fringe := clampi(roundi(maxi(c.w, c.h) * 0.025), 2, 5)
	var body_rect := Rect2i(fringe, 0, c.w - fringe * 2, c.h) if along_x else Rect2i(0, fringe, c.w, c.h - fringe * 2)
	var body := PixelCanvas.rounded(body_rect, 1)
	var border_col := base.darkened(0.38)
	c.fill(body, border_col)
	c.surface(body, "fabric", border_col)
	var border := clampi(roundi(mini(body_rect.size.x, body_rect.size.y) * 0.1), 3, 10)
	var field_rect := body_rect.grow(-border)
	var field := PixelCanvas.rounded(field_rect, 0)
	c.fill(field, base)
	c.surface(field, "fabric", base)
	c.outline(PixelCanvas.rounded(field_rect.grow(1), 0), base.lightened(0.3))
	var mid := border / 2
	var stitch := base.lightened(0.15)
	for x in range(body_rect.position.x + mid, body_rect.end.x - mid, 3):
		c.px(x, body_rect.position.y + mid, stitch)
		c.px(x, body_rect.end.y - 1 - mid, stitch)
	for y in range(body_rect.position.y + mid, body_rect.end.y - mid, 3):
		c.px(body_rect.position.x + mid, y, stitch)
		c.px(body_rect.end.x - 1 - mid, y, stitch)
	if pattern == "stripes":
		var band := maxi(3, field_rect.size.y / 8 if along_x else field_rect.size.x / 8)
		var i := 0
		for a in range(0, field_rect.size.y if along_x else field_rect.size.x, band):
			if i % 2 == 1:
				var r := Rect2i(field_rect.position.x, field_rect.position.y + a, field_rect.size.x, band) if along_x \
						else Rect2i(field_rect.position.x + a, field_rect.position.y, band, field_rect.size.y)
				c.paint_over(r, base.darkened(0.12))
			i += 1
	else:
		_medallion(c, field_rect, base, border_col)
	_fringe(c, body_rect, fringe, along_x)


## A stepped diamond medallion in the middle of the field, nested in three tones, plus quarter
## diamonds in the field's corners.
static func _medallion(c: PixelCanvas, field: Rect2i, base: Color, border_col: Color) -> void:
	var o := field.position + field.size / 2
	var ax := field.size.x * 0.32
	var ay := field.size.y * 0.32
	var accent := base.lightened(0.28)
	for y in range(field.position.y, field.end.y):
		for x in range(field.position.x, field.end.x):
			var d := absf(x - o.x) / ax + absf(y - o.y) / ay
			if d <= 0.3:
				c.px(x, y, accent)
			elif d <= 0.55:
				c.px(x, y, border_col)
			elif d <= 1.0:
				c.px(x, y, accent if d > 0.9 else base.darkened(0.12))
			var cx := minf(x - field.position.x, field.end.x - 1 - x) / ax
			var cy := minf(y - field.position.y, field.end.y - 1 - y) / ay
			if cx + cy <= 0.35:
				c.px(x, y, border_col if cx + cy > 0.22 else accent)


## Fringe threads past both short ends: every other thread, a pale knot where it leaves the rug.
static func _fringe(c: PixelCanvas, body: Rect2i, length: int, along_x: bool) -> void:
	var col := ObjectArtConfig.rug_fringe_color
	var span := body.size.y if along_x else body.size.x
	for a in range(1, span - 1, 2):
		for i in length:
			var near := Vector2i(body.position.x - 1 - i, body.position.y + a) if along_x else Vector2i(body.position.x + a, body.position.y - 1 - i)
			var far := Vector2i(body.end.x + i, body.position.y + a) if along_x else Vector2i(body.position.x + a, body.end.y + i)
			var shade := col if i > 0 else col.darkened(0.15)
			c.px(near.x, near.y, shade)
			c.px(far.x, far.y, shade)


## A plush bath mat: rounded, densely tufted in two tones, with a darker rim.
static func _plush(c: PixelCanvas, base: Color) -> void:
	var mat := PixelCanvas.rounded(Rect2i(0, 0, c.w, c.h), mini(6, mini(c.w, c.h) / 3))
	c.fill(mat, base)
	var r := Rect2i(0, 0, c.w, c.h)
	c.speckle(r, base, 0.45, 0.08)
	c.speckle(r, base, 0.2, 0.16)
	c.bevel(mat, 1, 2, base.darkened(0.2), base.darkened(0.2))
	c.outline(mat, base.darkened(0.35))

extends RefCounted

## Top-down pixel-art TABLE painter (Objects domain, private). A planked wooden top — planks
## along the long side with dark seams, staggered butt joints, a slight tone per plank, grain and
## the odd knot — inside a light-aware bevelled rim with rounded corners, optionally dressed with
## props. Options (`art_opts`, defaulting to ObjectArtConfig.table_*): `plank_px`, `rim_px`,
## `corner_radius`, `inset` (a recessed centre panel), `runner` (a cloth runner down the long
## axis), `gaps` (open slats, as on a bench) and `props`. A table is symmetric, so its facing only
## turns the plank direction with the footprint.

const PixelCanvas = preload("res://scenes/objects/art/pixel_canvas.gd")
const Props = preload("res://scenes/objects/art/props.gd")

const _TOP_HEIGHT := 2     ## Tabletop height, for cast shadows.
const _RUNNER_HEIGHT := 3  ## The runner sits on the top.


## Paint a table onto `c` in `base` wood.
static func paint(c: PixelCanvas, base: Color, _material: String, opts: Dictionary) -> void:
	var t := PixelCanvas.tones(base)
	var radius: int = opts.get("corner_radius", ObjectArtConfig.table_corner_radius)
	var rim: int = opts.get("rim_px", ObjectArtConfig.table_rim_px)
	var top := PixelCanvas.rounded(Rect2i(0, 0, c.w, c.h), radius)

	c.fill(top, base, _TOP_HEIGHT)
	var seams := _planks(c, base, t, opts)
	if opts.get("inset", ObjectArtConfig.table_inset):
		_inset(c, radius, base, t, opts)
	c.bevel(top, 2, 2, t.highlight, t.shadow)
	c.bevel(top, 3, 1 + rim, t.light, t.dark)
	c.outline(top, t.outline)
	if opts.get("gaps", false):
		for a in seams:
			c.clear(PixelCanvas.rounded(Rect2i(0, a, c.w, 1) if c.w >= c.h else Rect2i(a, 0, 1, c.h), 0))
	if opts.get("runner", ObjectArtConfig.table_runner):
		_runner(c)
	Props.draw_all(c, opts.get("props", []), Rect2i(0, 0, c.w, c.h).grow(-3))
	c.cast_shadows()


## Planks along the long side: per-plank tone, grain and knots, seams between planks and
## staggered butt joints on long ones. Returns the seam positions across the planks.
static func _planks(c: PixelCanvas, base: Color, t: Dictionary, opts: Dictionary) -> Array[int]:
	var seams: Array[int] = []
	var along_x := c.w >= c.h
	var span := c.h if along_x else c.w
	var length := c.w if along_x else c.h
	var plank_px := maxi(3, int(opts.get("plank_px", ObjectArtConfig.table_plank_px)))
	var n := maxi(1, roundi(float(span) / plank_px))
	for i in n:
		var a := roundi(float(i) * span / n)
		var b := roundi(float(i + 1) * span / n)
		var r := Rect2i(0, a, length, b - a) if along_x else Rect2i(a, 0, b - a, length)
		var shift := c.rng.randf_range(-0.05, 0.05)
		var tone := base.lightened(shift) if shift > 0.0 else base.darkened(-shift)
		c.paint_over(r, tone)
		c.grain(PixelCanvas.rounded(r, 0), along_x, ObjectArtConfig.wood_grain_density,
				tone.darkened(0.12), tone.lightened(0.06))
		if c.rng.randf() < ObjectArtConfig.wood_knot_chance and b - a >= 4 and length >= 12:
			var k_along := c.rng.randi_range(5, length - 6)
			var k_across := (a + b) / 2
			var kp := Vector2i(k_along, k_across) if along_x else Vector2i(k_across, k_along)
			c.knot(kp.x, kp.y, tone.darkened(0.4), tone.darkened(0.2))
		if i > 0:
			_seam(c, along_x, a, 0, length, t.shadow)
			seams.append(a)
		# A long plank is two boards end to end; neighbours stagger their joints.
		if length >= 50:
			var joint := roundi(length * (0.3 if i % 2 == 0 else 0.65) + c.rng.randi_range(-4, 4))
			for j in range(a + (1 if i > 0 else 0), b):
				var jp := Vector2i(joint, j) if along_x else Vector2i(j, joint)
				if c.at(jp.x, jp.y).a > 0.0:
					c.px(jp.x, jp.y, t.shadow)
	return seams


## A 1px seam line at `across` running `from`..`to` along the planks (drawn pixels only).
static func _seam(c: PixelCanvas, along_x: bool, across: int, from: int, to: int, col: Color) -> void:
	for i in range(from, to):
		var p := Vector2i(i, across) if along_x else Vector2i(across, i)
		if c.at(p.x, p.y).a > 0.0:
			c.px(p.x, p.y, col)


## A recessed centre panel: a darker inlay with cross grain, framed by an inverted bevel (the
## edge nearest the light sits in shadow, the far edge catches light).
static func _inset(c: PixelCanvas, radius: int, base: Color, t: Dictionary, opts: Dictionary) -> void:
	var margin: int = opts.get("inset_margin", ObjectArtConfig.table_inset_margin)
	margin = mini(margin, mini(c.w, c.h) / 4)
	var inner_rect := Rect2i(0, 0, c.w, c.h).grow(-margin)
	if inner_rect.size.x < 4 or inner_rect.size.y < 4:
		return
	var inner := PixelCanvas.rounded(inner_rect, maxi(radius - 1, 1))
	var inlay := base.darkened(0.1)
	c.fill(inner, inlay)
	c.grain(inner, c.w >= c.h, ObjectArtConfig.wood_grain_density, inlay.darkened(0.12), inlay.lightened(0.05))
	c.bevel(inner, 1, 1, t.shadow, t.light)
	c.bevel(inner, 2, 2, t.dark, inlay)


## A cloth runner down the long axis, hanging to the rim at both ends with a fringe, a border
## stripe along each edge and a woven diamond motif down its middle.
static func _runner(c: PixelCanvas) -> void:
	var along_x := c.w >= c.h
	var length := c.w if along_x else c.h
	var span := c.h if along_x else c.w
	var width := maxi(5, roundi(span * float(ObjectArtConfig.table_runner_width)))
	var a := (span - width) / 2
	var mid := a + width / 2
	var col := ObjectArtConfig.table_runner_color
	var rt := PixelCanvas.tones(col)
	var r := Rect2i(1, a, length - 2, width) if along_x else Rect2i(a, 1, width, length - 2)
	c.fill(PixelCanvas.rounded(r, 0), col, _RUNNER_HEIGHT)
	c.speckle(r, col, ObjectArtConfig.fabric_speckle)
	for i in range(1, length - 1):
		for s in [a, a + width - 1]:
			_dot(c, along_x, i, s, rt.dark)
		if width >= 9:
			for s in [a + 2, a + width - 3]:
				_dot(c, along_x, i, s, rt.light if i % 2 == 0 else col)
		# Diamonds: |offset from the motif centre along| + |offset across| == radius.
		var motif := maxi(2, width / 2 - 3)
		var period := motif * 2 + 2
		var along_off := absi((i + period / 2) % period - period / 2)
		if i > 3 and i < length - 4 and along_off <= motif:
			for s in [mid - (motif - along_off), mid + (motif - along_off)]:
				_dot(c, along_x, i, s, rt.shadow)
	# Fringe: every other thread at each end.
	for s in range(a, a + width):
		if s % 2 == 0:
			for end in [1, length - 2]:
				_dot(c, along_x, end, s, rt.light)


## Set one pixel addressed along/across the planks.
static func _dot(c: PixelCanvas, along_x: bool, along: int, across: int, col: Color) -> void:
	if along_x:
		c.px(along, across, col)
	else:
		c.px(across, along, col)

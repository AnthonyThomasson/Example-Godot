extends RefCounted

## Small procedural props dressing a surface (Objects domain, private): monitors, keyboards,
## mugs, books, bowls, tools and the like, drawn by the table / cabinet / counter painters from a
## piece's `art_opts.props` list. Each prop is painted in the host's canonical frame (front toward
## +y), raised so it casts a shadow onto the surface, with sizes in art px scaled by
## ObjectArtConfig.pixel_size and colors from ObjectArtConfig.prop_colors.

const PixelCanvas = preload("res://scenes/objects/art/pixel_canvas.gd")

const _HEIGHT := 7  ## Props stand above the surface they sit on (cast-shadow height).


## Draw each `{ "kind": String, "at": Vector2 }` entry of `props`; `at` is relative to `area`.
static func draw_all(c: PixelCanvas, props: Array, area: Rect2i) -> void:
	for p: Dictionary in props:
		var at: Vector2 = p.get("at", Vector2(0.5, 0.5))
		draw(c, String(p.get("kind", "")), area.position + Vector2i((Vector2(area.size) * at).round()))


## Draw one prop of `kind` centred on `o`.
static func draw(c: PixelCanvas, kind: String, o: Vector2i) -> void:
	match kind:
		"monitor": _monitor(c, o)
		"keyboard": _keyboard(c, o)
		"laptop": _laptop(c, o)
		"mug": _mug(c, o)
		"papers": _papers(c, o)
		"book": _book(c, o)
		"clock": _clock(c, o)
		"bowl": _bowl(c, o, false)
		"fruit_bowl": _bowl(c, o, true)
		"vase": _vase(c, o)
		"cutting_board": _cutting_board(c, o)
		"tools": _tools(c, o)
		"vise": _vise(c, o)
		"crayons": _crayons(c, o)
		"plate": _plate(c, o)
		"lamp": _lamp(c, o)
		"toys": _toys(c, o)
		"phone": _phone(c, o)
		_:
			push_warning("Props: unknown prop '%s'" % kind)


## A size of `n` art px at the configured pixel size (never below 1).
static func _u(n: float) -> int:
	return maxi(1, _o(n))


## An offset of `n` art px at the configured pixel size (may be zero or negative).
static func _o(n: float) -> int:
	return roundi(n / maxf(ObjectArtConfig.pixel_size, 0.01))


## A prop palette color by name.
static func _col(name: String) -> Color:
	return ObjectArtConfig.prop_colors.get(name, Color.MAGENTA)


## A random entry of the prop palette list `name`.
static func _pick(c: PixelCanvas, name: String) -> Color:
	var list: Array = ObjectArtConfig.prop_colors.get(name, [Color.MAGENTA])
	return list[c.rng.randi_range(0, list.size() - 1)]


## A rect of size (sw, sh) art px centred on `o` (offset by (dx, dy)).
static func _box(o: Vector2i, sw: float, sh: float, dx: float = 0.0, dy: float = 0.0) -> Rect2i:
	var size := Vector2i(_u(sw), _u(sh))
	return Rect2i(o + Vector2i(_o(dx), _o(dy)) - size / 2, size)


## Fill + outline a rounded box in `col`, raised to the prop height.
static func _block(c: PixelCanvas, r: Rect2i, radius: int, col: Color) -> PixelCanvas.Shape:
	var s := PixelCanvas.rounded(r, radius)
	c.fill(s, col, _HEIGHT)
	c.bevel(s, 1, 1, col.lightened(0.18), col.darkened(0.2))
	return s


## A monitor: a slim screen bar with a lit front edge on a neck and oval foot.
static func _monitor(c: PixelCanvas, o: Vector2i) -> void:
	c.fill(PixelCanvas.ellipse(_box(o, 10, 6, 0, 1)), _col("metal").darkened(0.25), _HEIGHT - 2)
	c.fill(PixelCanvas.rounded(_box(o, 3, 3, 0, -1), 0), _col("metal").darkened(0.4), _HEIGHT)
	var bar := _box(o, 24, 3, 0, -3)
	var screen := _block(c, bar, 1, _col("plastic_dark"))
	c.outline(screen, _col("plastic_dark").darkened(0.4))
	c.line(Vector2i(bar.position.x + 1, bar.end.y - 1), Vector2i(bar.end.x - 2, bar.end.y - 1), _col("glow"))


## A keyboard: a pale slab dotted with keys.
static func _keyboard(c: PixelCanvas, o: Vector2i) -> void:
	var r := _box(o, 18, 6)
	var s := _block(c, r, 1, _col("plastic_light"))
	c.outline(s, _col("plastic_light").darkened(0.45))
	for y in range(r.position.y + 1, r.end.y - 1):
		for x in range(r.position.x + 1 + (y % 2), r.end.x - 1, 2):
			c.px(x, y, _col("plastic_light").darkened(0.22))


## An open laptop: a keyboard deck and trackpad, the screen's hinge bar along the back.
static func _laptop(c: PixelCanvas, o: Vector2i) -> void:
	var r := _box(o, 20, 14)
	var s := _block(c, r, 1, _col("metal"))
	c.outline(s, _col("metal").darkened(0.45))
	var keys := Rect2i(r.position.x + 2, r.position.y + _u(4), r.size.x - 4, _u(5))
	c.fill(PixelCanvas.rounded(keys, 0), _col("plastic_dark"))
	for x in range(keys.position.x, keys.end.x, 2):
		c.px(x, keys.position.y + 1, _col("plastic_dark").lightened(0.2))
		c.px(x + 1, keys.position.y + 3, _col("plastic_dark").lightened(0.2))
	c.fill(PixelCanvas.rounded(Rect2i(o.x - _u(3), r.end.y - _u(4), _u(6), _u(3)), 0), _col("metal").darkened(0.12))
	var hinge := Rect2i(r.position.x, r.position.y, r.size.x, _u(2))
	c.fill(PixelCanvas.rounded(hinge, 0), _col("plastic_dark").darkened(0.2), _HEIGHT + 1)
	c.line(Vector2i(hinge.position.x + 1, hinge.end.y - 1), Vector2i(hinge.end.x - 2, hinge.end.y - 1), _col("glow"))


## A mug of coffee with its handle.
static func _mug(c: PixelCanvas, o: Vector2i) -> void:
	c.fill(PixelCanvas.disc(o, _u(3)), _col("ceramic"), _HEIGHT)
	c.fill(PixelCanvas.disc(o, _u(2)), _col("coffee"))
	c.px(o.x + _u(4), o.y, _col("ceramic").darkened(0.15), _HEIGHT)
	c.px(o.x + _u(4), o.y + 1, _col("ceramic").darkened(0.15), _HEIGHT)


## Two offset sheets of paper, the top one lined with text.
static func _papers(c: PixelCanvas, o: Vector2i) -> void:
	for i in 2:
		var r := _box(o, 11, 14, i * 2 - 1, i - 1)
		var s := PixelCanvas.rounded(r, 0)
		c.fill(s, _col("paper").darkened(0.06 * (1 - i)), 2)
		c.outline(s, _col("paper").darkened(0.25))
		if i == 1:
			for y in range(r.position.y + 2, r.end.y - 2, 2):
				var end := r.end.x - 2 - c.rng.randi_range(0, 3)
				c.line(Vector2i(r.position.x + 2, y), Vector2i(end, y), _col("ink"))


## A closed book: a colored cover with a spine and a pale page edge.
static func _book(c: PixelCanvas, o: Vector2i) -> void:
	var r := _box(o, 12, 9)
	var cover := _pick(c, "books")
	var s := _block(c, r, 0, cover)
	c.outline(s, cover.darkened(0.45))
	c.line(Vector2i(r.position.x + 1, r.position.y), Vector2i(r.position.x + 1, r.end.y - 1), cover.darkened(0.3))
	c.line(Vector2i(r.end.x - 1, r.position.y + 1), Vector2i(r.end.x - 1, r.end.y - 2), _col("paper"))


## A small round clock face with two hands.
static func _clock(c: PixelCanvas, o: Vector2i) -> void:
	c.fill(PixelCanvas.disc(o, _u(4)), _col("plastic_dark"), _HEIGHT)
	c.fill(PixelCanvas.disc(o, _u(3)), _col("paper"), _HEIGHT)
	c.line(o, o + Vector2i(0, -_u(2)), _col("ink").darkened(0.5))
	c.line(o, o + Vector2i(_u(2), 0), _col("ink").darkened(0.5))
	c.px(o.x, o.y, _col("accent"))


## A bowl holding keys, or (`fruit`) a few pieces of fruit.
static func _bowl(c: PixelCanvas, o: Vector2i, fruit: bool) -> void:
	var rim := PixelCanvas.disc(o, _u(6))
	c.fill(rim, _col("ceramic"), _HEIGHT - 2)
	c.outline(rim, _col("ceramic").darkened(0.35))
	c.fill(PixelCanvas.disc(o, _u(4)), _col("ceramic").darkened(0.12), _HEIGHT - 3)
	if not fruit:
		c.fill(PixelCanvas.disc(o + Vector2i(-1, 0), _u(1)), _col("metal"), _HEIGHT)
		c.line(o + Vector2i(0, 0), o + Vector2i(_u(3), _u(1)), _col("metal").darkened(0.2), _HEIGHT)
		return
	for off in [Vector2i(-2, -1), Vector2i(2, -2), Vector2i(1, 2), Vector2i(-2, 2)]:
		var p: Vector2i = o + Vector2i(_o(off.x), _o(off.y))
		var col := _pick(c, "fruit")
		c.fill(PixelCanvas.disc(p, _u(2)), col, _HEIGHT)
		c.px(p.x - 1, p.y - 1, col.lightened(0.35))


## A vase of flowers with leaves.
static func _vase(c: PixelCanvas, o: Vector2i) -> void:
	c.fill(PixelCanvas.disc(o, _u(3)), _col("glaze"), _HEIGHT)
	for i in 6:
		var a := TAU * i / 6.0 + c.rng.randf_range(-0.3, 0.3)
		var p := o + Vector2i((Vector2(cos(a), sin(a)) * _u(3.5)).round())
		c.px(p.x, p.y, _col("leaf"), _HEIGHT + 1)
		var f := o + Vector2i((Vector2(cos(a + 0.5), sin(a + 0.5)) * _u(2)).round())
		c.fill(PixelCanvas.disc(f, maxi(1, _u(1))), _pick(c, "flowers"), _HEIGHT + 2)


## A grained cutting board with a knife.
static func _cutting_board(c: PixelCanvas, o: Vector2i) -> void:
	var r := _box(o, 16, 11)
	var s := _block(c, r, 2, _col("wood_light"))
	c.grain(s, true, 0.05, _col("wood_light").darkened(0.12), _col("wood_light").lightened(0.06))
	c.outline(s, _col("wood_light").darkened(0.4))
	var k := r.position + Vector2i(_u(3), r.size.y / 2)
	c.line(k, k + Vector2i(_u(7), 0), _col("metal").lightened(0.2), _HEIGHT + 1)
	c.line(k + Vector2i(_u(8), 0), k + Vector2i(_u(11), 0), _col("plastic_dark"), _HEIGHT + 1)


## A hammer, a wrench and a screwdriver.
static func _tools(c: PixelCanvas, o: Vector2i) -> void:
	# Hammer.
	var h := o + Vector2i(-_u(6), -_u(2))
	c.line(h, h + Vector2i(_u(9), 0), _col("wood_light"), _HEIGHT)
	c.fill(PixelCanvas.rounded(Rect2i(h + Vector2i(_u(8), -_u(2)), Vector2i(_u(2), _u(5))), 0), _col("metal").darkened(0.3), _HEIGHT)
	# Wrench.
	var wr := o + Vector2i(-_u(5), _u(3))
	c.line(wr, wr + Vector2i(_u(8), 0), _col("metal"), _HEIGHT)
	c.fill(PixelCanvas.disc(wr + Vector2i(_u(9), 0), _u(2)), _col("metal"), _HEIGHT)
	c.px(wr.x + _u(10), wr.y, _col("metal").darkened(0.5))
	# Screwdriver.
	var sd := o + Vector2i(_u(5), -_u(5))
	c.fill(PixelCanvas.rounded(Rect2i(sd, Vector2i(_u(2), _u(4))), 0), _col("accent"), _HEIGHT)
	c.line(sd + Vector2i(0, _u(4)), sd + Vector2i(0, _u(9)), _col("metal").lightened(0.1), _HEIGHT)


## A bench vise with its jaws and screw handle.
static func _vise(c: PixelCanvas, o: Vector2i) -> void:
	var r := _box(o, 10, 8)
	var s := _block(c, r, 1, _col("metal").darkened(0.35))
	c.outline(s, _col("metal").darkened(0.65))
	c.line(Vector2i(r.position.x + 1, o.y), Vector2i(r.end.x - 2, o.y), _col("metal").lightened(0.15))
	c.line(Vector2i(o.x, r.end.y), Vector2i(o.x, r.end.y + _u(3)), _col("metal"), _HEIGHT)
	c.line(Vector2i(o.x - _u(3), r.end.y + _u(3)), Vector2i(o.x + _u(3), r.end.y + _u(3)), _col("metal"), _HEIGHT)


## A drawing on a sheet of paper beside a row of crayons.
static func _crayons(c: PixelCanvas, o: Vector2i) -> void:
	var sheet := _box(o, 13, 10, -3, 0)
	c.fill(PixelCanvas.rounded(sheet, 0), _col("paper"), 2)
	c.outline(PixelCanvas.rounded(sheet, 0), _col("paper").darkened(0.25))
	c.line(sheet.position + Vector2i(2, 3), sheet.position + Vector2i(sheet.size.x - 3, 6), _pick(c, "flowers"))
	for i in 4:
		var p := o + Vector2i(_u(5) + i * 2, -_u(3) + i)
		c.line(p, p + Vector2i(0, _u(4)), _pick(c, "flowers"), _HEIGHT - 3)


## A plate with an inner rim.
static func _plate(c: PixelCanvas, o: Vector2i) -> void:
	var rim := PixelCanvas.disc(o, _u(5))
	c.fill(rim, _col("ceramic"), 3)
	c.outline(rim, _col("ceramic").darkened(0.3))
	c.outline(PixelCanvas.disc(o, _u(3)), _col("ceramic").darkened(0.12))


## A small lamp shade with a glowing bulb.
static func _lamp(c: PixelCanvas, o: Vector2i) -> void:
	var shade := PixelCanvas.disc(o, _u(4))
	c.fill(shade, _col("shade"), _HEIGHT + 2)
	c.outline(shade, _col("shade").darkened(0.3))
	c.fill(PixelCanvas.disc(o, _u(1)), _col("glow").lightened(0.6))


## A striped ball and a toy block.
static func _toys(c: PixelCanvas, o: Vector2i) -> void:
	var ball := o + Vector2i(-_u(3), 0)
	c.fill(PixelCanvas.disc(ball, _u(3)), _pick(c, "flowers"), _HEIGHT)
	c.line(ball + Vector2i(-_u(2), 0), ball + Vector2i(_u(2), 0), _col("paper"), _HEIGHT)
	var block := Rect2i(o + Vector2i(_u(2), -_u(2)), Vector2i(_u(4), _u(4)))
	_block(c, block, 0, _pick(c, "books"))


## A phone with a lit screen.
static func _phone(c: PixelCanvas, o: Vector2i) -> void:
	var r := _box(o, 5, 8)
	var s := _block(c, r, 1, _col("plastic_dark"))
	c.fill(PixelCanvas.rounded(r.grow(-1), 0), _col("glow").darkened(0.3))
	c.outline(s, _col("plastic_dark").darkened(0.4))

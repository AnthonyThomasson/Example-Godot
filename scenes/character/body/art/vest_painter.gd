extends RefCounted

## Top-down pixel-art VEST painter (Character domain, private; rendered through the Art domain's PixelArt as part of the
## shoulders, body_painter.gd, and the trunk, torso_painter.gd, which call it over their shirt). Two garments, from the look's
## `vest` kind (`OutfitConfig` looks): a soft tactical `vest` — a padded panel over the trunk that leaves the shoulder caps bare
## (a merc wears it as a chest rig: webbing straps, a row of pouches and one on each flank) — and a plate `carrier` — a front
## and a back panel joined by shoulder straps and a cummerbund, pouches across the front, a drag handle on the back, each panel
## bulging where a plate sits in it (a crew's panels mismatched: `front_cover`, `back_cover`). Each style marks it: the Zenitex's
## white stencil along the front and back edges with a red lamp, the Trauma Team's red cross, a borg's welded steel and rivets.
## A plate's wear shows on its panel as scuffs and cracks with the plate showing through, more of them at each wear step.
## Options (`opts`): `look` (a `style_art.gd` handle: `vest`, `vest_col`, the covers, the style) and per side (`front_` /
## `back_`) `<side>plate` (the plate's colour; absent = no plate) and `<side>wear` (0 new .. `WEAR_STEPS` spent).

const StyleArt = preload("res://scenes/character/body/art/style_art.gd")

const _VEST := 5  ## Heights for cast shadows, floor-up: over the shirt (4), under the head's ring.
const _PLATE := 6
const _POUCH := 7
const _MARK := 8
## The wear steps a plate's condition is rounded to (its marks grow with each; the art repaints only when the step changes).
const WEAR_STEPS := 4
## Scuffs and cracks added per wear step.
const _MARKS_PER_STEP := 2
const _STRAP := Color(0.10, 0.10, 0.09)  ## Buckles and webbing.


## The vest seen from above, over the shoulders ellipse `span` of a canvas centred on `o` (front toward +y).
static func paint_top(c: PixelCanvas, o: Vector2i, span: Rect2i, opts: Dictionary) -> void:
	var look := StyleArt.look_of(opts)
	var kind := String(look.get("vest", ""))
	if kind == "":
		return
	var style := String(look.get("style", ""))
	var half := roundi(c.w * 0.3)
	var col := _col(look, "vest_col")
	var t := PixelCanvas.tones(col)
	var finish := "metal" if style == "borg" else "fabric"
	if kind == "vest":
		if style == "merc":
			# A chest rig: dark webbing straps over both shoulders, a pouch on each flank and a row across the front (what shows
			# past the head from above, whatever drab top is under them).
			for side in [-1, 1]:
				for dx in [0, 1]:
					var x: int = o.x + side * (half - 3 + dx)
					c.line(Vector2i(x, span.position.y + 1), Vector2i(x, span.end.y - 2), _STRAP, _VEST)
				var flank := PixelCanvas.rounded(Rect2i(o.x + side * (half - 1) - (2 if side > 0 else 0), o.y - 2, 3, 5), 0)
				c.fill(flank, col.darkened(0.1), _POUCH)
				c.outline(flank, _STRAP)
			_pouches(c, Rect2i(o.x - half, span.end.y - 4, half * 2 + 1, 3), 4, col)
			return
		# The panel hugs the shoulders: a rounded block across the trunk, cut to the shoulders' own outline.
		var block := PixelCanvas.rounded(Rect2i(o.x - half, span.position.y, half * 2 + 1, span.size.y), 4)
		var shoulders := PixelCanvas.ellipse(span)
		var body := PixelCanvas.Shape.new(block.bounds, func(x: int, y: int) -> bool: return block.has(x, y) and shoulders.has(x, y))
		_fill(c, body, col, _VEST, finish, false, look)
		_marks_top(c, o, span, half, look, kind)
		return
	# The carrier: shoulder straps beside the neck between the panels.
	for side in [-1, 1]:
		c.line(Vector2i(o.x + side * (half - 2), span.position.y), Vector2i(o.x + side * (half - 2), span.end.y - 1), t.dark, _VEST)
	for face in ["front", "back"]:
		var front: bool = face == "front"
		var y := span.end.y - 4 if front else span.position.y - 2
		var panel := PixelCanvas.rounded(Rect2i(o.x - half, y, half * 2 + 1, 6), 2)
		var plated: bool = opts.has(face + "_plate")
		var cover := _col(look, face + "_cover")
		_fill(c, panel, cover, _PLATE if plated else _VEST, finish, plated, look)
		if plated:
			_wear(c, panel.bounds.grow(-1), face, opts, cover)
		if front:
			_pouches(c, Rect2i(o.x - half + 1, y + 3, half * 2 - 1, 3), 3, cover)
		else:
			c.line(Vector2i(o.x - 1, y + 1), Vector2i(o.x + 1, y + 1), _STRAP, _POUCH)
	_marks_top(c, o, span, half, look, kind)


## The vest on the trunk's `face` ("front" | "back" | "side"): a canvas spanning the trunk, shoulders toward −y, the shirt down
## to row `waist`.
static func paint_face(c: PixelCanvas, face: String, waist: int, opts: Dictionary) -> void:
	var look := StyleArt.look_of(opts)
	var kind := String(look.get("vest", ""))
	if kind == "":
		return
	var style := String(look.get("style", ""))
	var col := _col(look, "vest_col")
	var t := PixelCanvas.tones(col)
	var bottom := waist - 1
	var finish := "metal" if style == "borg" else "fabric"
	if face == "side":
		# The flank: the cummerbund or the vest's side panel, under the arm.
		var band := PixelCanvas.rounded(Rect2i(0, roundi(waist * 0.35), c.w, bottom - roundi(waist * 0.35)), 0)
		_fill(c, band, col, _VEST, finish, false, look)
		for y in range(band.bounds.position.y + 2, bottom, 3):
			c.line(Vector2i(1, y), Vector2i(c.w - 2, y), t.dark, _VEST)
		return
	var cx := int(c.w / 2.0)
	if kind == "vest" and style == "merc":
		# The chest rig: pouches across the front, its straps crossed over the back.
		if face == "front":
			_pouches(c, Rect2i(1, roundi(waist * 0.45), c.w - 2, 5), 4, col)
			for x in [3, c.w - 4]:
				c.line(Vector2i(x, 0), Vector2i(x, roundi(waist * 0.45)), t.dark, _VEST)
		else:
			c.line(Vector2i(2, 0), Vector2i(c.w - 3, bottom - 2), t.dark, _VEST)
			c.line(Vector2i(c.w - 3, 0), Vector2i(2, bottom - 2), t.dark, _VEST)
		return
	var inset := 1 if kind == "vest" else 2
	var top := 4 if kind == "vest" else 2
	var plated: bool = kind == "carrier" and opts.has(face + "_plate")
	var cover := col if kind == "vest" else _col(look, face + "_cover")
	var panel := PixelCanvas.rounded(Rect2i(inset, top, c.w - inset * 2, bottom - top), 2)
	_fill(c, panel, cover, _PLATE if plated else _VEST, finish, plated, look)
	for x in [inset + 2, c.w - inset - 3]:  # Straps up over the shoulders.
		c.line(Vector2i(x, 0), Vector2i(x, top), PixelCanvas.tones(cover).dark, _VEST)
	if plated:
		_wear(c, Rect2i(inset + 1, top + 1, c.w - inset * 2 - 2, roundi((bottom - top) * 0.6)), face, opts, cover)
	if kind == "carrier":
		if face == "front":
			_pouches(c, Rect2i(inset + 1, bottom - 5, c.w - inset * 2 - 2, 4), 3, cover)
		else:
			c.fill(PixelCanvas.rounded(Rect2i(cx - 2, top, 5, 2), 0), _STRAP, _POUCH)  # The drag handle.
	elif face == "front":
		c.line(Vector2i(cx, top + 1), Vector2i(cx, bottom - 1), t.shadow, _VEST)  # The zip.
	_marks_face(c, face, cx, top, bottom, look, kind)


## A panel `s` in `col`: its finish, a bevel (raised where a plate sits), the livery's edge sheen and an outline.
static func _fill(c: PixelCanvas, s: PixelCanvas.Shape, col: Color, height: int, finish: String, plated: bool,
		look: Dictionary) -> void:
	var t := PixelCanvas.tones(col)
	c.fill(s, col, height)
	c.surface(s, finish, col)
	c.bevel(s, 1, 2 if plated else 1, t.highlight if plated else t.light, t.dark)
	StyleArt.edge(c, s, look)
	c.outline(s, t.outline)


## `count` pouches side by side across `r`, a shade darker than `col`, each with its flap.
static func _pouches(c: PixelCanvas, r: Rect2i, count: int, col: Color) -> void:
	var pc := col.darkened(0.18)
	var t := PixelCanvas.tones(pc)
	var w := maxi(2, int(r.size.x / float(count)) - 1)
	for k in count:
		var pouch := PixelCanvas.rounded(Rect2i(r.position.x + k * (w + 1), r.position.y, w, r.size.y), 0)
		c.fill(pouch, pc, _POUCH)
		c.outline(pouch, t.outline)
		c.line(Vector2i(pouch.bounds.position.x, r.position.y), Vector2i(pouch.bounds.end.x - 1, r.position.y), t.light, _POUCH)


## The look's colour `key`, or a drab green.
static func _col(look: Dictionary, key: String) -> Color:
	return look.get(key, Color(0.24, 0.27, 0.22))


## The style's marks on the vest from above. The head hides the middle of the chest and back (about 6 px round `o`), so each
## sits clear of it: the Zenitex's white stencil along the front and back edges and its red lamp, the Trauma Team's cross, a
## borg's rivets.
static func _marks_top(c: PixelCanvas, o: Vector2i, span: Rect2i, half: int, look: Dictionary, kind: String) -> void:
	var trim: Color = look.get("trim", Color.WHITE)
	var chest := span.end.y - 3 if kind == "vest" else span.end.y - 5
	var front_edge := span.end.y - 2 if kind == "vest" else span.end.y + 1
	var back_edge := span.position.y + 1 if kind == "vest" else span.position.y - 1
	match String(look.get("style", "")):
		"zenitex":
			StyleArt.stencil(c, Vector2i(o.x - half + 2, front_edge), half * 2 - 3, trim, _MARK)
			StyleArt.stencil(c, Vector2i(o.x - half + 2, back_edge), half * 2 - 3, trim, _MARK)
			c.px(o.x + half - 1, chest, look.get("led", Color.RED), _MARK)
		"trauma":
			StyleArt.cross(c, Vector2i(o.x, chest), trim, _MARK)
		"borg":
			for side in [-1, 1]:
				c.px(o.x + side * (half - 1), chest, Color(0.2, 0.2, 0.2), _MARK)
				c.px(o.x + side * (half - 1), span.position.y + 2, Color(0.2, 0.2, 0.2), _MARK)


## The style's marks on the vest's front or back face: the Zenitex's stencil (and its lamps in front), the Trauma Team's cross,
## a merc carrier's patch, a borg's rivets.
static func _marks_face(c: PixelCanvas, face: String, cx: int, top: int, bottom: int, look: Dictionary, kind: String) -> void:
	var trim: Color = look.get("trim", Color.WHITE)
	var chest := top + 3
	match String(look.get("style", "")):
		"zenitex":
			StyleArt.stencil(c, Vector2i(cx - 6, chest), 13, trim, _MARK)
			if face == "front":
				c.px(cx - 6, chest + 2, look.get("led", Color.RED), _MARK)
				c.px(cx - 4, chest + 2, trim, _MARK)
		"trauma":
			StyleArt.cross(c, Vector2i(cx, chest + 2), trim, _MARK, 2)
		"merc":
			if kind == "carrier":
				c.fill(PixelCanvas.rounded(Rect2i(cx - 5, chest, 4, 3), 0), _col(look, "back_cover"), _MARK)
		"borg":
			for y in [top + 1, bottom - 2]:
				for x in [3, c.w - 4]:
					c.px(x, y, Color(0.2, 0.2, 0.2), _MARK)


## A plate's wear on its panel: `_MARKS_PER_STEP` marks per wear step inside `r`, alternating a crack (a short dark zigzag) and
## a scuff torn through to the plate. The marks come from one fixed sequence per side, so each step adds to the last step's.
static func _wear(c: PixelCanvas, r: Rect2i, face: String, opts: Dictionary, panel: Color) -> void:
	var steps := clampi(int(opts.get(face + "_wear", 0)), 0, WEAR_STEPS)
	if steps == 0 or r.size.x < 2 or r.size.y < 2:
		return
	var plate: Color = opts[face + "_plate"]
	var crack := panel.darkened(0.7)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(face)
	for k in steps * _MARKS_PER_STEP:
		var p := Vector2i(rng.randi_range(r.position.x, r.end.x - 1), rng.randi_range(r.position.y, r.end.y - 1))
		if k % 2 == 0:
			var q := p
			for i in 3:
				c.px(q.x, q.y, crack)
				q += Vector2i(1 if rng.randf() < 0.5 else -1, 1 if i % 2 == 0 else 0)
				q = q.clamp(r.position, r.end - Vector2i.ONE)
		else:
			c.px(p.x, p.y, plate.lightened(0.15))
			c.px(mini(p.x + 1, r.end.x - 1), p.y, plate)

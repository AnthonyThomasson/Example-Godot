extends RefCounted

## Top-down pixel-art VEST painter (Character domain, private; rendered through the Art domain's PixelArt as part of the
## shoulders, body_painter.gd, and the fallen trunk, torso_painter.gd, which call it over their shirt). Two kinds, from the
## outfit's vest (`OutfitConfig` look `kind`): a soft tactical `vest` — a padded panel over the trunk that leaves the shoulder
## caps bare, a velcro patch on the chest — and a plate `carrier` — a front and a back panel joined by shoulder straps and a
## cummerbund, three magazine pouches across the front, a drag handle on the back, each panel bulging where a plate sits in it.
## A plate's wear shows on its panel as scuffs and cracks with the plate showing through, more of them at each wear step.
## Options (`opts`): `vest` (&"vest" | &"carrier"; absent = none), `vest_color`, and per side (`front_` / `back_`) `<side>plate`
## (the plate's colour; absent = no plate) and `<side>wear` (0 new .. `WEAR_STEPS` spent).

const _VEST_HEIGHT := 5  ## Heights for cast shadows, floor-up: over the shirt (4), under the head's ring.
const _PLATE_HEIGHT := 6
const _POUCH_HEIGHT := 7
## The wear steps a plate's condition is rounded to (its marks grow with each; the art repaints only when the step changes).
const WEAR_STEPS := 4
## Scuffs and cracks added per wear step.
const _MARKS_PER_STEP := 2
const _STRAP := Color(0.12, 0.12, 0.11)  ## Buckles and webbing seams.


## The vest seen from above, over the shoulders ellipse `span` of a canvas centred on `o` (front toward +y).
static func paint_top(c: PixelCanvas, o: Vector2i, span: Rect2i, opts: Dictionary) -> void:
	var col: Color = opts.get("vest_color", Color(0.24, 0.27, 0.22))
	var t := PixelCanvas.tones(col)
	var half := roundi(c.w * 0.3)
	match StringName(opts.get("vest", &"")):
		&"vest":
			# The panel hugs the shoulders: a rounded block across the trunk, cut to the shoulders' own outline.
			var block := PixelCanvas.rounded(Rect2i(o.x - half, span.position.y, half * 2 + 1, span.size.y), 4)
			var shoulders := PixelCanvas.ellipse(span)
			var body := PixelCanvas.Shape.new(block.bounds, func(x: int, y: int) -> bool: return block.has(x, y) and shoulders.has(x, y))
			c.fill(body, col, _VEST_HEIGHT)
			c.surface(body, "fabric", col)
			c.bevel(body, 1, 1, t.light, t.dark)
			c.outline(body, t.outline)
			# A velcro patch on the chest and the side straps under the arms.
			c.line(Vector2i(o.x - 2, span.end.y - 2), Vector2i(o.x + 2, span.end.y - 2), t.dark, _VEST_HEIGHT)
			for side in [-1, 1]:
				c.px(o.x + side * (half - 1), o.y, _STRAP, _VEST_HEIGHT)
		&"carrier":
			# Shoulder straps between the panels, beside the neck.
			for side in [-1, 1]:
				var x: int = o.x + side * (half - 2)
				c.line(Vector2i(x, span.position.y), Vector2i(x, span.end.y - 1), t.dark, _VEST_HEIGHT)
			for face in ["front", "back"]:
				var front: bool = face == "front"
				var y := span.end.y - 4 if front else span.position.y - 2
				var panel := PixelCanvas.rounded(Rect2i(o.x - half, y, half * 2 + 1, 6), 2)
				var plated: bool = opts.has(face + "_plate")
				c.fill(panel, col, _PLATE_HEIGHT if plated else _VEST_HEIGHT)
				c.surface(panel, "fabric", col)
				c.bevel(panel, 1, 2 if plated else 1, t.highlight if plated else t.light, t.dark)
				c.outline(panel, t.outline)
				if plated:
					_wear(c, panel.bounds.grow(-1), face, opts)
				if front:
					for k in 3:
						var pouch := PixelCanvas.rounded(Rect2i(o.x - half + 1 + int(k * (half * 2 - 1) / 3.0), y + 3, 3, 3), 0)
						c.fill(pouch, t.shadow, _POUCH_HEIGHT)
						c.outline(pouch, t.outline)
						c.px(pouch.bounds.position.x + 1, y + 3, t.highlight, _POUCH_HEIGHT)
				else:
					c.line(Vector2i(o.x - 1, y + 1), Vector2i(o.x + 1, y + 1), _STRAP, _POUCH_HEIGHT)


## The vest on the fallen trunk's `face` ("front" | "back" | "side"): a canvas spanning the trunk, shoulders toward −y, the
## shirt down to row `waist`.
static func paint_face(c: PixelCanvas, face: String, waist: int, opts: Dictionary) -> void:
	var col: Color = opts.get("vest_color", Color(0.24, 0.27, 0.22))
	var t := PixelCanvas.tones(col)
	var kind := StringName(opts.get("vest", &""))
	if kind == &"":
		return
	var bottom := waist - 1
	if face == "side":
		# The flank: the cummerbund or the vest's side panel, under the arm.
		var band := PixelCanvas.rounded(Rect2i(0, roundi(waist * 0.35), c.w, bottom - roundi(waist * 0.35)), 0)
		c.fill(band, col, _VEST_HEIGHT)
		c.surface(band, "fabric", col)
		c.bevel(band, 1, 1, t.light, t.dark)
		for y in range(band.bounds.position.y + 2, bottom, 3):
			c.line(Vector2i(1, y), Vector2i(c.w - 2, y), t.dark, _VEST_HEIGHT)
		return
	var inset := 1 if kind == &"vest" else 2
	var top := 4 if kind == &"vest" else 2
	var panel := PixelCanvas.rounded(Rect2i(inset, top, c.w - inset * 2, bottom - top), 2)
	var plated: bool = kind == &"carrier" and opts.has(face + "_plate")
	c.fill(panel, col, _PLATE_HEIGHT if plated else _VEST_HEIGHT)
	c.surface(panel, "fabric", col)
	c.bevel(panel, 1, 2 if plated else 1, t.highlight if plated else t.light, t.dark)
	c.outline(panel, t.outline)
	var cx := int(c.w / 2.0)
	# Straps up over the shoulders.
	for x in [inset + 2, c.w - inset - 3]:
		c.line(Vector2i(x, 0), Vector2i(x, top), t.dark, _VEST_HEIGHT)
	if kind == &"vest":
		if face == "front":
			c.line(Vector2i(cx, top + 1), Vector2i(cx, bottom - 1), t.shadow, _VEST_HEIGHT)  # The zip.
			c.fill(PixelCanvas.rounded(Rect2i(cx + 2, top + 2, 4, 2), 0), t.dark, _VEST_HEIGHT)  # A velcro patch.
		return
	if plated:
		_wear(c, Rect2i(inset + 1, top + 1, c.w - inset * 2 - 2, roundi((bottom - top) * 0.6)), face, opts)
	if face == "front":
		var row := bottom - 5
		for k in 3:
			var pouch := PixelCanvas.rounded(Rect2i(inset + 1 + k * int((c.w - inset * 2 - 2) / 3.0), row, int((c.w - inset * 2 - 2) / 3.0) - 1, 4), 1)
			c.fill(pouch, t.dark, _POUCH_HEIGHT)
			c.bevel(pouch, 1, 1, t.light, t.shadow)
			c.outline(pouch, t.outline)
			c.line(Vector2i(pouch.bounds.position.x + 1, row + 1), Vector2i(pouch.bounds.end.x - 2, row + 1), t.highlight, _POUCH_HEIGHT)  # The flap.
	else:
		c.fill(PixelCanvas.rounded(Rect2i(cx - 2, top, 5, 2), 0), _STRAP, _POUCH_HEIGHT)  # The drag handle.


## A plate's wear on its panel: `_MARKS_PER_STEP` marks per wear step inside `r`, alternating a crack (a short dark zigzag) and
## a scuff torn through to the plate. The marks come from one fixed sequence per side, so each step adds to the last step's.
static func _wear(c: PixelCanvas, r: Rect2i, face: String, opts: Dictionary) -> void:
	var steps := clampi(int(opts.get(face + "_wear", 0)), 0, WEAR_STEPS)
	if steps == 0 or r.size.x < 2 or r.size.y < 2:
		return
	var plate: Color = opts[face + "_plate"]
	var crack := (opts.get("vest_color", Color.BLACK) as Color).darkened(0.7)
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

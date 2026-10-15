extends RefCounted

## Top-down pixel-art CHARACTER SHOULDERS painter (Character domain, private; rendered through the Art domain's PixelArt).
## Painted in the canonical frame — facing +y — and kept within the body's round footprint: the shoulders in the shirt (`base`)
## with the dark ring of the neck where the head sits (the head is its own part, head_painter.gd, drawn over this one so it can
## turn on its own). The look (`opts.look`, a `style_art.gd` handle) styles them:
## - the ends where the arms leave: a sleeve (a merc's patched one in another colour), bare skin (inked, inlaid) or chrome;
## - a police uniform: a shirt's high collar or a tee's neckband, the Zenitex's segmented shoulder plates with light edges (a
##   shirt) and two white stripes across each shoulder cap, the Trauma Team's white patch with its red cross; the sergeant's
##   chevrons (`rank` 1 or more);
## - a crew's gear: a jacket's lapels open at the throat, a tank top's straps over bare shoulders (a borg's), a stained tee;
## - then the vest (vest_painter.gd), a spine rig breaking out over the collar, cables over the shoulder, and a pack on the back
##   (the Trauma Team's white medic pack with its cross, a crew's taped bag).
## Options: `look`, and the plates' (vest_painter.gd).

const StyleArt = preload("res://scenes/character/body/art/style_art.gd")
const HeadPainter = preload("res://scenes/character/body/art/head_painter.gd")
const VestPainter = preload("res://scenes/character/body/art/vest_painter.gd")

const _SHOULDER := 4  ## Heights for cast shadows, floor-up.
const _PAD := 6
const _PACK := 6
const _RIG := 8
const _CABLE := Color(0.80, 0.32, 0.12)


## Paint the shoulders onto `c` in a `base` shirt, facing +y.
static func paint(c: PixelCanvas, base: Color, material: String, opts: Dictionary) -> void:
	var look := StyleArt.look_of(opts)
	var t := PixelCanvas.tones(base)
	var o := Vector2i(int(c.w / 2.0), int(c.h / 2.0))
	var head_r := HeadPainter.radius_for(c.w)
	var depth := roundi(c.h * CharacterConfig.art_shoulder_depth)
	var span := Rect2i(1, o.y - int(depth / 2.0) - 1, c.w - 2, depth)
	var shoulders := PixelCanvas.ellipse(span)
	c.fill(shoulders, base, _SHOULDER)
	c.surface(shoulders, material, base)
	c.bevel(shoulders, 1, 2, t.light, t.dark)
	StyleArt.edge(c, shoulders, look)
	c.outline(shoulders, t.outline)
	var long := String(look.get("body", "")) == "long_sleeves"
	_sleeve_ends(c, o, span, shoulders, look)
	if look.get("police", false):
		_uniform(c, o, span, head_r, look, long, t, shoulders)
	else:
		_street(c, o, span, head_r, look, long, t)
	VestPainter.paint_top(c, o, span, opts)
	if look.get("spine", false):
		# The spine rig breaking out over the collar at the back: vertebrae down from the neck, a glowing node.
		for y in range(o.y - head_r - 1, span.position.y - 1, -2):
			c.px(o.x, y, Color(0.07, 0.07, 0.08), _RIG)
			c.px(o.x - 1, y, Color(0.16, 0.16, 0.18), _RIG)
			c.px(o.x + 1, y, Color(0.16, 0.16, 0.18), _RIG)
		c.px(o.x, span.position.y, look.get("glow", Color.RED), _RIG)
	if look.get("cables", false):
		for k in 2:
			var x := o.x + (3 + k * 2) * (1 if int(look.get("plate_side", 0)) == 0 else -1)
			c.line(Vector2i(o.x + k, o.y - head_r + 1), Vector2i(x, span.position.y + 1), _CABLE.darkened(0.2 * k), _RIG)
	if look.get("pack", false):
		_pack(c, o, span, look)
	c.outline(PixelCanvas.disc(o, head_r + 1), t.shadow)
	c.cast_shadows()


## The ends of the shoulders where the arms leave them, per side (side 0 is −x): a sleeve in a colour of its own, bare skin
## (inked, inlaid) or chrome. A sleeve in the shirt's colour is the shoulders' own and is left as it is.
static func _sleeve_ends(c: PixelCanvas, o: Vector2i, span: Rect2i, shoulders: PixelCanvas.Shape, look: Dictionary) -> void:
	var sleeves: Array = look.get("sleeves", [null, null])
	var chrome_arms: Array = look.get("chrome_arm", [false, false])
	var skin: Color = look.get("skin", Color.WHITE)
	var reach := int(c.w * 0.2)
	for side in 2:
		var dir := -1 if side == 0 else 1
		var inner := o.x + dir * (int(c.w / 2.0) - reach)
		var area := Rect2i(mini(inner, o.x + dir * int(c.w / 2.0)), span.position.y, reach + 1, span.size.y)
		var col: Variant = sleeves[side]
		var chrome: bool = chrome_arms[side]
		if col != null and not chrome and col == look.get("shirt"):
			continue
		for y in range(area.position.y, area.end.y):
			for x in range(area.position.x, area.end.x):
				if shoulders.has(x, y):
					c.px(x, y, StyleArt.chrome(look, x + y) if chrome else skin if col == null else col, _SHOULDER)
		c.line(Vector2i(inner, span.position.y + 2), Vector2i(inner, span.end.y - 3),
			Color(0.15, 0.15, 0.17) if chrome else PixelCanvas.tones(skin if col == null else col).dark, _SHOULDER)
		if chrome:
			c.px(inner + dir * 2, o.y, look.get("glow", Color.CYAN), _SHOULDER)
		elif col == null:
			if look.get("tattoo", false):
				StyleArt.tattoo(c, area, look, 2)
			if look.get("inlays", false):
				StyleArt.inlays(c, area, 2)


## A police uniform's shoulders: the collar or neckband, the unit's marks and the sergeant's chevrons.
static func _uniform(c: PixelCanvas, o: Vector2i, span: Rect2i, head_r: int, look: Dictionary, long: bool, t: Dictionary,
		shoulders: PixelCanvas.Shape) -> void:
	var trim: Color = look.get("trim", Color.WHITE)
	var front := o.y + head_r + 1
	if long:
		for side in [-1, 1]:  # A high collar either side of the neck.
			c.line(Vector2i(o.x + side * (head_r + 1), o.y - 1), Vector2i(o.x + side * (head_r + 1), front), t.highlight, _SHOULDER + 1)
	else:
		c.line(Vector2i(o.x - head_r + 2, front + 1), Vector2i(o.x + head_r - 2, front + 1), t.dark)
	match String(look.get("style", "")):
		"zenitex":
			var edge: Color = look.get("edge", t.light)
			if long:
				# Segmented shoulder plates with light edges, and a lamp on the left one.
				for side in [-1, 1]:
					var x0: int = o.x + side * (head_r + 2) if side > 0 else 1
					var plate := PixelCanvas.rounded(Rect2i(x0, span.position.y + 1, int(c.w / 2.0) - head_r - 2, span.size.y - 2), 2)
					c.fill(plate, t.base.lightened(0.06), _PAD)
					c.bevel(plate, 1, 1, edge, edge.darkened(0.45))
					c.outline(plate, t.outline)
					c.line(Vector2i(plate.bounds.position.x + 1, o.y), Vector2i(plate.bounds.end.x - 2, o.y), t.outline, _PAD)
				c.px(o.x + head_r + 4, span.end.y - 3, trim, _PAD + 1)
			# Two white stripes across each shoulder cap (the stencil is on the vest: the head hides the chest from above).
			for side in [-1, 1]:
				for k in 2:
					var x: int = o.x + side * (int(c.w / 2.0) - 3 - k * 2)
					StyleArt.column(c, shoulders, x, span.position.y + 2, span.end.y - 2, trim if k == 0 else trim.darkened(0.2), _PAD + 1)
		"trauma":
			# A white arm patch with the red cross on the right shoulder.
			var patch := PixelCanvas.rounded(Rect2i(3, o.y - 2, 5, 5), 1)
			c.fill(patch, Color(0.92, 0.92, 0.9), _PAD)
			c.outline(patch, Color(0.5, 0.5, 0.5))
			StyleArt.cross(c, Vector2i(5, o.y), trim, _PAD + 1)
	for k in int(look.get("rank", 0)):  # Chevrons on the left shoulder.
		c.line(Vector2i(c.w - 7, o.y + 1 + k * 2), Vector2i(c.w - 5, o.y - 1 + k * 2), trim.lightened(0.2), _PAD + 2)
		c.line(Vector2i(c.w - 5, o.y - 1 + k * 2), Vector2i(c.w - 3, o.y + 1 + k * 2), trim.lightened(0.2), _PAD + 2)


## A crew's shoulders: a jacket's lapels open at the throat, a tank top's straps and scooped neck over bare skin, or a tee's
## neckband with a merc's stains.
static func _street(c: PixelCanvas, o: Vector2i, span: Rect2i, head_r: int, look: Dictionary, long: bool, t: Dictionary) -> void:
	var front := o.y + head_r + 1
	var bare := (look.get("sleeves", []) as Array).has(null)
	var skin: Color = look.get("skin", Color.WHITE)
	if long:
		for side in [-1, 1]:
			c.line(Vector2i(o.x + side * (head_r + 1), o.y + 1), Vector2i(o.x + side, front + 2), t.light, _SHOULDER + 1)
		c.line(Vector2i(o.x, front + 1), Vector2i(o.x, span.end.y - 2), skin, _SHOULDER)
	elif bare and String(look.get("style", "")) != "merc":
		c.fill(PixelCanvas.disc(Vector2i(o.x, front), 2), skin, _SHOULDER)
		for side in [-1, 1]:
			c.line(Vector2i(o.x + side * (head_r + 2), span.position.y + 1), Vector2i(o.x + side * (head_r + 2), span.end.y - 2), t.dark, _SHOULDER)
		if look.get("inlays", false):
			StyleArt.inlays(c, Rect2i(o.x - 2, front - 1, 5, 3), 1)
	else:
		c.line(Vector2i(o.x - head_r + 2, front + 1), Vector2i(o.x + head_r - 2, front + 1), t.dark)
		if String(look.get("style", "")) == "merc":
			for k in 3:
				c.px(c.rng.randi_range(4, c.w - 5), c.rng.randi_range(span.position.y + 2, span.end.y - 3), t.shadow)


## A pack on the back (toward −y) in `pack_col`, its straps over the shoulders: a medic's cross on it, or a crew's tape.
static func _pack(c: PixelCanvas, o: Vector2i, span: Rect2i, look: Dictionary) -> void:
	var col: Color = look.get("pack_col", Color(0.2, 0.2, 0.2))
	var pt := PixelCanvas.tones(col)
	var r := Rect2i(o.x - int(c.w / 4.0), span.position.y - 1, int(c.w / 2.0), roundi(c.h * 0.3))
	var pack := PixelCanvas.rounded(r, 2)
	c.fill(pack, col, _PACK)
	c.surface(pack, "fabric", col)
	c.bevel(pack, 1, 1, pt.light, pt.dark)
	c.outline(pack, pt.outline)
	if String(look.get("pack_kind", "")) == "medic":
		StyleArt.cross(c, r.get_center(), look.get("trim", Color.RED), _PACK + 1)
	elif not look.get("police", false):
		StyleArt.tape(c, Vector2i(r.position.x + 1, r.position.y + 2), Vector2i(r.end.x - 2, r.position.y + 2), _PACK + 1)
	for x in [r.position.x + 1, r.end.x - 2]:
		c.line(Vector2i(x, r.end.y), Vector2i(x, span.end.y - 3), pt.dark, _SHOULDER + 1)

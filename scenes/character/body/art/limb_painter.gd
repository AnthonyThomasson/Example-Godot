extends RefCounted

## Top-down pixel-art LIMB painter (Character domain, private; rendered through the Art domain's PixelArt): the surface of one
## segment of an arm, a leg or a shoe as a straight strip along +y in `base` — shaded light to dark across it toward the light,
## with the cloth's weave when `material` is "fabric". The caller maps it onto the limb's tapered outline, which gives it its
## shape and outline; the strip runs from the joint nearer the body (y = 0) to the far one. Without a look (the neck) it is the
## plain strip. With one (`opts.look`, a `style_art.gd` handle), by the segment's `part`:
## - an arm (`upper`, `fore`): a sleeve (the Zenitex's segmented forearm plates and white stripe, the Trauma Team's red forearm
##   guard, a plain cuff) or bare skin (`skin`: inked, inlaid);
## - a leg (`thigh`, `knee`, `shin`) by the look's `pants`: police trousers with a piping down the outer seam, or armoured
##   (`tactical`) with knee pads (the Zenitex's with a white bar), a cargo pocket and the Zenitex's segmented shins; a merc's
##   pockets and patched knees, a borg's patch and chrome knee caps;
## - a foot (`shaft`, `foot`) by the look's `feet`: polished police shoes or boots (the Trauma Team's red soles), a merc's
##   muddy laced boots, a borg's steel toe caps;
## - a chrome segment (`chrome`): joint rings, a dark seam and a borg's glowing line.
## Options: `look`, `part`, `side` (0 or 1, the body side: which edge is the outer seam), `cuff` (a sleeve's end at the wrist),
## `skin`, `chrome`.

const StyleArt = preload("res://scenes/character/body/art/style_art.gd")

const _LIMB := 3  ## Heights for cast shadows.
const _DETAIL := 4
const _LACE := Color(0.72, 0.68, 0.58)


## Paint the strip spanning `c` in `base`.
static func paint(c: PixelCanvas, base: Color, material: String, opts: Dictionary) -> void:
	var t := PixelCanvas.tones(base)
	var strip := PixelCanvas.rounded(Rect2i(0, 0, c.w, c.h), 0)
	c.fill(strip, base, _LIMB)
	if material != "":
		c.surface(strip, material, base)
	c.bevel(strip, 1, maxi(1, int(c.w / 4.0)), t.light, t.dark)
	var look := StyleArt.look_of(opts)
	if look.is_empty():
		return
	var part := String(opts.get("part", ""))
	if opts.get("chrome", false):
		_chrome(c, look, t)
		return
	if not opts.get("skin", false) and part in ["upper", "fore", "thigh", "knee", "shin"]:
		StyleArt.edge(c, strip, look)  # The livery's edge sheen on a sleeve or a trouser leg.
	if part in ["upper", "fore"]:
		_arm(c, look, opts, part, t)
		return
	var outer := c.w - 2 if int(opts.get("side", 0)) == 0 else 1
	if part in ["thigh", "knee", "shin"]:
		_leg(c, look, part, outer, t, base)
	else:
		_foot(c, look, part, t, base)


## A chrome segment: joint rings across it, a bright line down it, a dark seam down one side with a borg's glow in it.
static func _chrome(c: PixelCanvas, look: Dictionary, t: Dictionary) -> void:
	for y in c.h:
		c.px(int(c.w / 2.0) - 1, y, t.highlight)
	for y in range(2, c.h - 1, 4):
		c.line(Vector2i(0, y), Vector2i(c.w - 1, y), t.shadow, _DETAIL)
	c.line(Vector2i(c.w - 2, 1), Vector2i(c.w - 2, c.h - 2), Color(0.1, 0.1, 0.12), _DETAIL)
	if String(look.get("style", "")) == "borg":
		c.line(Vector2i(c.w - 2, 2), Vector2i(c.w - 2, c.h - 3), look.get("glow", Color.CYAN), _DETAIL)


## An arm segment: bare skin with its ink and plates, or a sleeve and its end at the wrist.
static func _arm(c: PixelCanvas, look: Dictionary, opts: Dictionary, part: String, t: Dictionary) -> void:
	if opts.get("skin", false):
		if look.get("tattoo", false):
			StyleArt.tattoo(c, Rect2i(0, 0, c.w, c.h), look, 2 if part == "fore" else 3)
		if look.get("inlays", false) and part == "upper":
			StyleArt.inlays(c, Rect2i(0, 1, c.w, c.h - 2), 1)
		return
	if part == "fore" and opts.get("cuff", false):
		match String(look.get("style", "")):
			"trauma":
				# A red armoured guard over the forearm.
				var guard := PixelCanvas.rounded(Rect2i(0, roundi(c.h * 0.3), c.w, c.h - roundi(c.h * 0.3)), 1)
				var red: Color = look.get("trim", Color.RED)
				c.fill(guard, red, _DETAIL)
				c.bevel(guard, 1, 1, red.lightened(0.25), red.darkened(0.3))
			"zenitex":
				# Segmented forearm plates with light edges, and the white stripe across them.
				var edge: Color = look.get("edge", t.light)
				for y in range(roundi(c.h * 0.35), c.h - 1, 3):
					c.line(Vector2i(0, y), Vector2i(c.w - 1, y), t.outline, _DETAIL)
					c.line(Vector2i(1, y + 1), Vector2i(c.w - 2, y + 1), edge.darkened(0.2), _DETAIL)
				c.line(Vector2i(0, roundi(c.h * 0.25)), Vector2i(c.w - 1, roundi(c.h * 0.25)), look.get("trim", Color.WHITE), _DETAIL)
			_:
				var cuff := maxi(2, roundi(c.h * 0.2))
				c.fill(PixelCanvas.rounded(Rect2i(0, c.h - cuff, c.w, cuff), 0), t.dark, _DETAIL)
	elif String(look.get("style", "")) == "merc":
		c.px(c.rng.randi_range(0, c.w - 1), c.rng.randi_range(0, c.h - 1), t.shadow)  # A stain.


## A leg segment, by what the legs wear and the style.
static func _leg(c: PixelCanvas, look: Dictionary, part: String, outer: int, t: Dictionary, base: Color) -> void:
	var style := String(look.get("style", ""))
	var armoured := String(look.get("pants", "")) == "tactical"
	if look.get("police", false):
		if armoured and part == "knee":
			var pad_col: Color = look.get("pad", base.darkened(0.5))
			var pad := PixelCanvas.rounded(Rect2i(0, 0, c.w, c.h), 2)
			c.fill(pad, pad_col, _DETAIL)
			c.bevel(pad, 1, 1, pad_col.lightened(0.25), pad_col.darkened(0.3))
			if style == "zenitex":
				c.line(Vector2i(1, int(c.h / 2.0)), Vector2i(c.w - 2, int(c.h / 2.0)), look.get("trim", Color.WHITE), _DETAIL)
		elif armoured and part == "shin" and style == "zenitex":
			for y in range(1, c.h - 1, 3):
				c.line(Vector2i(1, y), Vector2i(c.w - 2, y), t.outline, _DETAIL)
				c.line(Vector2i(1, y + 1), Vector2i(c.w - 2, y + 1), (look.get("edge", t.light) as Color).darkened(0.2), _DETAIL)
		elif armoured and part == "thigh":
			_pocket(c, outer, 0.4, base.darkened(0.1), t)
		elif not armoured:
			var piping: Color = look.get("trim", Color.WHITE)
			for y in range(0, c.h, 2):
				c.px(outer, y, piping.darkened(0.25))
		return
	match [style, armoured, part]:
		["merc", _, "thigh"]:
			_pocket(c, outer, 0.35, (look.get("patch", base) as Color) if armoured else base.darkened(0.1), t)
		["merc", _, "knee"]:
			c.fill(PixelCanvas.rounded(Rect2i(1, 1, c.w - 2, c.h - 2), 1), (look.get("patch", base) as Color).darkened(0.1), _DETAIL)
		["borg", true, "knee"]:
			var cap := PixelCanvas.rounded(Rect2i(1, 0, c.w - 2, c.h), 2)
			c.fill(cap, look.get("chrome", Color.GRAY), _DETAIL)
			c.bevel(cap, 1, 1, Color.WHITE, Color(0.3, 0.3, 0.32))
		["borg", false, "thigh"]:
			c.fill(PixelCanvas.rounded(Rect2i(1, int(c.h * 0.5), c.w - 2, 3), 0), base.lightened(0.15), _DETAIL)  # A patch.
		[_, _, "shin"]:
			c.line(Vector2i(outer, 1), Vector2i(outer, c.h - 2), t.shadow)


## A cargo pocket on the outer side of a thigh, `from` of the way down it, in `col`.
static func _pocket(c: PixelCanvas, outer: int, from: float, col: Color, t: Dictionary) -> void:
	var w := maxi(3, int(c.w / 2.0))
	var x := c.w - w - 1 if outer > int(c.w / 2.0) else 1
	var pocket := PixelCanvas.rounded(Rect2i(x, int(c.h * from), w, maxi(3, int(c.h * 0.45))), 1)
	c.fill(pocket, col, _DETAIL)
	c.outline(pocket, t.shadow)


## A foot segment: a boot's shaft up the shin (`shaft`, a padded rim on top, laces) or the shoe or boot itself (`foot`).
static func _foot(c: PixelCanvas, look: Dictionary, part: String, t: Dictionary, base: Color) -> void:
	var style := String(look.get("style", ""))
	var boots := String(look.get("feet", "")) == "boots"
	var strip := PixelCanvas.rounded(Rect2i(0, 0, c.w, c.h), 0)
	if part == "shaft":
		c.line(Vector2i(0, 0), Vector2i(c.w - 1, 0), t.highlight, _DETAIL)
		c.line(Vector2i(0, 1), Vector2i(c.w - 1, 1), t.dark, _DETAIL)
		if style != "borg":
			_laces(c, 3, c.h - 1)
		return
	c.outline(strip, t.outline)
	if look.get("police", false):
		c.px(int(c.w / 2.0), int(c.h * 0.7), t.highlight, _DETAIL)  # A polished toe.
		if style == "trauma":
			c.line(Vector2i(0, c.h - 1), Vector2i(c.w - 1, c.h - 1), look.get("trim", Color.RED), _DETAIL)  # The red sole.
		if boots:
			_laces(c, 2, int(c.h * 0.55))
		return
	if style == "merc":
		for k in 3:
			c.px(c.rng.randi_range(0, c.w - 1), c.rng.randi_range(0, c.h - 1), base.lerp(Color(0.4, 0.32, 0.2), 0.6))  # Mud.
		_laces(c, 2, int(c.h * 0.55))
		return
	var cap := PixelCanvas.rounded(Rect2i(0, int(c.h * 0.65), c.w, c.h - int(c.h * 0.65)), 1)
	c.fill(cap, look.get("chrome", Color.GRAY), _DETAIL)  # A steel toe cap.
	c.outline(cap, t.outline)


## Laces criss-crossing down the middle of a boot strip, rows `from`..`to`.
static func _laces(c: PixelCanvas, from: int, to: int) -> void:
	var cx := int(c.w / 2.0)
	for y in range(from, to, 2):
		c.px(cx - 1, y, _LACE, _DETAIL)
		c.px(cx + 1, y, _LACE, _DETAIL)
		c.px(cx, y + 1, _LACE.darkened(0.3), _DETAIL)

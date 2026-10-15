extends RefCounted

## Top-down pixel-art CHARACTER TRUNK painter (Character domain, private; rendered through the Art domain's PixelArt): the
## surface of a crouched or fallen body's trunk seen from its front, back or side, as a full strip the caller maps onto the
## trunk's rounded outline (which gives it its shape and outline). Canonical frame: shoulders toward −y, hips toward +y, across
## the body along x. The shirt (`base`) runs down to the belt and the pants cover the hips. The look (`opts.look`, a
## `style_art.gd` handle) styles it: a police uniform's collar and its unit's mark on the chest (the Zenitex's stencil, the
## Trauma Team's cross); a crew's open jacket, or a tank top with bare (inked, inlaid) skin either side; a spine rig and cables
## down the back; then the vest (vest_painter.gd) and the pack. Options: `look`, `face` ("front" | "back" | "side"), `pants`
## (the pants' colour) and the plates' (vest_painter.gd).

const StyleArt = preload("res://scenes/character/body/art/style_art.gd")
const VestPainter = preload("res://scenes/character/body/art/vest_painter.gd")

const _PANTS := 3  ## Heights for cast shadows, floor-up.
const _SHIRT := 4
const _PACK := 7
const _RIG := 8
## Share of the trunk's length the shirt covers, down to the belt.
const _WAIST := 0.8
const _BUCKLE := Color(0.75, 0.7, 0.5)
const _CABLE := Color(0.80, 0.32, 0.12)


## Paint the trunk's `face` onto `c` with a `base` shirt.
static func paint(c: PixelCanvas, base: Color, material: String, opts: Dictionary) -> void:
	var look := StyleArt.look_of(opts)
	var face := String(opts.get("face", "front"))
	var pants: Color = opts.get("pants", base)
	var t := PixelCanvas.tones(base)
	var pt := PixelCanvas.tones(pants)
	var skin: Color = look.get("skin", Color.WHITE)
	var cx := int(c.w / 2.0)
	var waist := roundi(c.h * _WAIST)
	var hips := PixelCanvas.rounded(Rect2i(0, waist, c.w, c.h - waist), 0)
	c.fill(hips, pants, _PANTS)
	c.surface(hips, "fabric", pants)
	var shirt := PixelCanvas.rounded(Rect2i(0, 0, c.w, waist), 0)
	c.fill(shirt, base, _SHIRT)
	c.surface(shirt, material, base)
	StyleArt.edge(c, shirt, look)
	var police: bool = look.get("police", false)
	var long := String(look.get("body", "")) == "long_sleeves"
	if not police and not long and (look.get("sleeves", []) as Array).has(null) and String(look.get("style", "")) != "merc":
		# A tank top: bare skin either side of it (and up to the throat at the front), inked and inlaid.
		var side_w := maxi(2, roundi(c.w * 0.18))
		for x0 in [0, c.w - side_w]:
			var bare := Rect2i(x0, 0, side_w, roundi(waist * 0.55))
			c.fill(PixelCanvas.rounded(bare, 0), skin, _SHIRT)
			if look.get("tattoo", false):
				StyleArt.tattoo(c, bare, look, 2)
			if look.get("inlays", false):
				StyleArt.inlays(c, bare, 2)
		if face == "front":
			c.fill(PixelCanvas.disc(Vector2i(cx, 0), 3), skin, _SHIRT)
	match face:
		"front":
			if long and not police:
				c.line(Vector2i(cx, 0), Vector2i(cx, waist - 1), skin, _SHIRT)  # An open jacket.
				c.line(Vector2i(cx - 1, 0), Vector2i(cx - 1, waist - 1), t.dark, _SHIRT)
			elif police:
				c.line(Vector2i(cx - 3, 1), Vector2i(cx, 4), t.shadow)
				c.line(Vector2i(cx + 3, 1), Vector2i(cx, 4), t.shadow)
				match String(look.get("style", "")):
					"zenitex":
						StyleArt.stencil(c, Vector2i(cx - 4, 6), 9, look.get("trim", Color.WHITE), _SHIRT)
					"trauma":
						StyleArt.cross(c, Vector2i(cx + 4, 6), look.get("trim", Color.RED), _SHIRT)
			else:
				c.line(Vector2i(cx - 3, 1), Vector2i(cx - 1, 3), t.dark)  # A tee's round neck.
				c.line(Vector2i(cx + 3, 1), Vector2i(cx + 1, 3), t.dark)
			c.line(Vector2i(0, waist), Vector2i(c.w - 1, waist), pt.outline, _PANTS)
			c.px(cx, waist, _BUCKLE, _PANTS)
		"back":
			c.line(Vector2i(cx, 3), Vector2i(cx, waist - 2), t.dark)
			c.line(Vector2i(0, waist), Vector2i(c.w - 1, waist), pt.outline, _PANTS)
		_:
			c.line(Vector2i(cx, 2), Vector2i(cx, waist - 2), t.dark)
	VestPainter.paint_face(c, face, waist, opts)
	if face == "back":
		if look.get("spine", false):
			# The spine rig: vertebrae down the back to the belt, a glowing node at the top.
			for y in range(1, waist - 1, 2):
				c.px(cx, y, Color(0.07, 0.07, 0.08), _RIG)
				c.px(cx - 1, y, Color(0.18, 0.18, 0.2), _RIG)
				c.px(cx + 1, y, Color(0.18, 0.18, 0.2), _RIG)
				c.px(cx - 2 if y % 4 == 1 else cx + 2, y, Color(0.12, 0.12, 0.14), _RIG)
			c.px(cx, 1, look.get("glow", Color.RED), _RIG)
		if look.get("cables", false):
			c.line(Vector2i(cx + 2, 0), Vector2i(cx + 5, waist - 3), _CABLE, _RIG)
			c.line(Vector2i(cx + 3, 0), Vector2i(cx + 7, waist - 4), _CABLE.darkened(0.25), _RIG)
		if look.get("pack", false):
			_pack(c, cx, waist, look)
	c.cast_shadows()


## A pack on the back in `pack_col`: a padded body (a medic's cross on it), straps running up over the shoulders.
static func _pack(c: PixelCanvas, cx: int, waist: int, look: Dictionary) -> void:
	var col: Color = look.get("pack_col", Color(0.2, 0.2, 0.2))
	var pt := PixelCanvas.tones(col)
	var r := Rect2i(cx - int(c.w / 4.0), 3, int(c.w / 2.0), mini(roundi(c.h * 0.45), waist - 4))
	var pack := PixelCanvas.rounded(r, 2)
	c.fill(pack, col, _PACK)
	c.surface(pack, "fabric", col)
	c.bevel(pack, 1, 1, pt.light, pt.dark)
	c.outline(pack, pt.outline)
	if String(look.get("pack_kind", "")) == "medic":
		StyleArt.cross(c, r.get_center(), look.get("trim", Color.RED), _PACK + 1, 2)
	else:
		c.px(cx, r.position.y + int(r.size.y / 3.0) + 1, _BUCKLE, _PACK)
	for x in [r.position.x + 1, r.end.x - 2]:
		c.line(Vector2i(x, r.position.y), Vector2i(x, 0), pt.dark, _SHIRT + 1)

extends RefCounted

## Top-down pixel-art CHARACTER HEAD painter (Character domain, private; rendered through the Art domain's PixelArt). Painted in
## the canonical frame — facing +y — on its own canvas, so the head can turn apart from the shoulders: skin with ears and a nose
## toward the front, under the hair or what is worn on the head, then the face's implants. All of it from the look (`opts.look`,
## a `style_art.gd` handle; `character_style.gd` resolves it):
## - the hair (`hair_style`: `short`, `long`, `buzz`, `bald`, `mohawk`) in `hair`, a tattoo on a bare scalp;
## - a cap (`head` `cap`): the police units' peaked duty cap (the Zenitex's white band, the Trauma Team's cross), a merc's watch
##   cap, a borg's bandana;
## - a helmet (`head` `helmet`): the Zenitex's faceless shell, light rimmed, a visor with a white glint, rails and ear pods; the
##   Trauma Team's white shell with its red crown and blue lamp; a merc's scuffed army helmet with goggles pushed up; a borg's
##   welded skull cap; the lead's stripe across the brow (`rank` 2);
## - the face (`eyes`: `glow`, `multi` lenses; `face`: `respirator`, a chrome `plate`, `goggles`; a `headset`).

const StyleArt = preload("res://scenes/character/body/art/style_art.gd")

const _HAIR := 7  ## Heights for cast shadows, floor-up.
const _HEAD := 9
const _BRIM := 10
const _SHELL := 11
const _VISOR := 12
## Canvas margin around the head (px) for the ears, long hair, a brim and a headset.
const MARGIN := 5


## Head radius (art px) for a body `width` px across.
static func radius_for(width: int) -> int:
	return maxi(3, roundi(width * CharacterConfig.art_head_size))


## Canvas side (art px) for a head of radius `r`.
static func canvas_for(r: int) -> int:
	return (r + MARGIN) * 2


## Paint a head onto `c`, centred, facing +y. `base` is unused: the head takes its colours from the look.
static func paint(c: PixelCanvas, _base: Color, _material: String, opts: Dictionary) -> void:
	var look := StyleArt.look_of(opts)
	var o := Vector2i(int(c.w / 2.0), int(c.h / 2.0))
	var r := int(c.w / 2.0) - MARGIN
	var skin: Color = look.get("skin", Color(0.80, 0.62, 0.48))
	var st := PixelCanvas.tones(skin)
	var style := String(look.get("hair_style", "short"))
	var worn := String(look.get("head", ""))
	if worn == "" and style == "long":
		_long_hair(c, o, r, look.get("hair", Color.BLACK))
	for side in [-1, 1]:
		c.px(o.x + side * (r + 1), o.y + 1, st.dark, _HEAD)
	c.px(o.x, o.y + r + 1, skin, _HEAD)
	var head := PixelCanvas.disc(o, r)
	c.fill(head, skin, _HEAD)
	match worn:
		"helmet":
			_helmet(c, o, r, look)
		"cap":
			_cap(c, o, r, look, head)
			_shade(c, head)
		_:
			_hair(c, o, r, look, skin, head)
			_shade(c, head)
	_face(c, o, r, look)
	c.cast_shadows()


## One shared bevel and outline over the skin and what covers it.
static func _shade(c: PixelCanvas, head: PixelCanvas.Shape) -> void:
	c.bevel_relative(head, 1, 2, 0.16, 0.22)
	c.outline_relative(head, 0.45)


## Whether a pixel of the head lies behind the face (the face is the head's front cap): what hair and a cap cover.
static func _covered(o: Vector2i, r: int, head: PixelCanvas.Shape) -> Callable:
	var face_o := Vector2(o.x, o.y + r * 0.9)
	var face_r := r * 0.85
	return func(x: int, y: int) -> bool: return head.has(x, y) and Vector2(x, y).distance_to(face_o) > face_r


# --- Hair --------------------------------------------------------------------------------------------

## Long hair falling behind the head, under it.
static func _long_hair(c: PixelCanvas, o: Vector2i, r: int, hair: Color) -> void:
	var ht := PixelCanvas.tones(hair)
	var fall := PixelCanvas.ellipse(Rect2i(o.x - r - 1, o.y - r - 4, r * 2 + 3, r + 6))
	c.fill(fall, hair, _HAIR)
	c.outline(fall, ht.outline)
	for dx in [-2, 0, 2]:
		c.line(Vector2i(o.x + dx, o.y - r - 2), Vector2i(o.x + dx, o.y - 2), ht.dark)


## The hair over the crown: cropped, buzzed (stubble over skin), shaved bald, a mohawk's crest over stubble, or full; a glyph
## inked beside the crest on a tattooed bare scalp.
static func _hair(c: PixelCanvas, o: Vector2i, r: int, look: Dictionary, skin: Color, head: PixelCanvas.Shape) -> void:
	var hair: Color = look.get("hair", Color.BLACK)
	var ht := PixelCanvas.tones(hair)
	var covered := _covered(o, r, head)
	var style := String(look.get("hair_style", "short"))
	for y in range(o.y - r, o.y + r + 1):
		for x in range(o.x - r, o.x + r + 1):
			if not covered.call(x, y):
				continue
			match style:
				"bald":
					pass
				"buzz":
					if c.rng.randf() < 0.6:
						c.px(x, y, hair.lerp(skin, 0.4))
				"mohawk":
					if absi(x - o.x) <= 1:
						c.px(x, y, ht.light if x == o.x else hair, _HAIR + 2)
					elif c.rng.randf() < 0.25:
						c.px(x, y, skin.darkened(0.12))  # Shaved sides: stubble.
				_:
					c.px(x, y, hair)
	match style:
		"mohawk":
			c.px(o.x, o.y + r - 1, ht.highlight, _HAIR + 2)  # The crest's tip over the brow.
		"short", "long":
			c.line(Vector2i(o.x, o.y - int(r / 3.0)), Vector2i(o.x - r + 1, o.y - 1), ht.light)
	if look.get("tattoo", false) and style in ["bald", "buzz", "mohawk"]:
		var ink: Color = look.get("ink", Color.BLACK)
		var at := Vector2i(o.x - 3 if c.rng.randf() < 0.5 else o.x + 2, o.y - 2)
		c.px(at.x, at.y, ink)
		c.px(at.x + 1, at.y + 1, ink)
		c.px(at.x, at.y + 2, ink)


# --- Caps --------------------------------------------------------------------------------------------

## A cap over the crown in `helm`: the police units' peaked duty cap (a crown seam, a brim to the front, the Zenitex's white
## band or the Trauma Team's cross), a merc's ribbed watch cap with its knot, a borg's bandana tied at the back.
static func _cap(c: PixelCanvas, o: Vector2i, r: int, look: Dictionary, head: PixelCanvas.Shape) -> void:
	var col: Color = look.get("helm", Color.BLACK)
	var t := PixelCanvas.tones(col)
	var trim: Color = look.get("trim", Color.WHITE)
	var covered := _covered(o, r, head)
	var style := String(look.get("style", ""))
	for y in range(o.y - r, o.y + r + 1):
		for x in range(o.x - r, o.x + r + 1):
			if covered.call(x, y):
				var rib := style == "merc" and (x - o.x) % 2 == 0
				c.px(x, y, t.dark if rib else col)
	match style:
		"zenitex", "trauma":
			c.line(Vector2i(o.x, o.y - r + 1), Vector2i(o.x, o.y + int(r / 2.0)), t.dark)
			var brim := PixelCanvas.ellipse(Rect2i(o.x - r + 1, o.y + int(r / 2.0), r * 2 - 1, r))
			c.fill(brim, t.shadow, _BRIM)
			c.outline(brim, t.outline)
			if style == "zenitex":
				for x in range(o.x - r + 1, o.x + r):
					if (x - o.x) % 3 != 0:
						c.px(x, o.y + int(r / 2.0) - 1, trim, _BRIM)
			else:
				StyleArt.cross(c, Vector2i(o.x, o.y - 1), trim, _BRIM)
		"merc":
			c.fill(PixelCanvas.disc(Vector2i(o.x, o.y - int(r / 3.0)), 1), t.light, _HEAD + 1)
		_:
			c.px(o.x, o.y - r, t.dark, _BRIM)
			c.px(o.x - 1, o.y - r - 1, col, _BRIM)
			c.px(o.x + 1, o.y - r - 2, col, _BRIM)


# --- Helmets -----------------------------------------------------------------------------------------

## A helmet shell over the head in `helm`, a style's own on it, and the lead's stripe across the brow.
static func _helmet(c: PixelCanvas, o: Vector2i, r: int, look: Dictionary) -> void:
	var col: Color = look.get("helm", Color.GRAY)
	var t := PixelCanvas.tones(col)
	var trim: Color = look.get("trim", Color.WHITE)
	var visor: Color = look.get("visor", Color.BLACK)
	var style := String(look.get("style", ""))
	var at := o + Vector2i(0, -1)
	var grow := 2 if style in ["zenitex", "borg"] else 1
	var shell := PixelCanvas.disc(at, r + grow)
	c.fill(shell, col, _SHELL)
	c.surface(shell, "metal" if style == "borg" else "plastic", col)
	c.bevel(shell, 2, 3, t.light, t.dark)
	StyleArt.edge(c, shell, look)  # The Zenitex's light rim round its charcoal shell.
	c.outline(shell, t.outline)
	var front := at.y + r + grow  # The shell's front edge row.
	match style:
		"zenitex":
			# Faceless: a glossy visor wrapping the front with a white glint across it, ridge rails down each side, ear pods.
			_visor(c, shell, front - 3, visor, visor.lightened(0.45))
			c.px(at.x - 3, front - 2, Color(0.92, 0.95, 1.0), _VISOR)
			c.px(at.x - 2, front - 2, Color(0.80, 0.86, 0.94), _VISOR)
			c.px(at.x - 1, front - 1, visor.lightened(0.5), _VISOR)
			for side in [-1, 1]:
				c.line(Vector2i(at.x + side * (r - 1), at.y - r + 1), Vector2i(at.x + side * (r - 1), front - 4), t.highlight, _SHELL)
				c.px(at.x + side * (r + 2), at.y + 1, t.light, _SHELL)
		"trauma":
			# A white shell, red over the crown, a dark visor and a blue lamp on one side.
			for y in range(at.y - r - grow, at.y - 1):
				for x in range(at.x - r - grow, at.x + r + grow + 1):
					if shell.has(x, y) and c.covered(x, y) and absi(x - at.x) < r:
						c.px(x, y, trim)
			_visor(c, shell, front - 2, visor, visor.lightened(0.3))
			var led: Color = look.get("led", Color.CYAN)
			c.px(at.x + r + 1, at.y + 1, led, _VISOR)
			c.px(at.x + r, at.y, led.darkened(0.3), _VISOR)
		"merc":
			# An old army helmet, scuffed, with goggles pushed up on the brow.
			for k in 4:
				c.px(at.x + c.rng.randi_range(-r + 1, r - 1), at.y + c.rng.randi_range(-r + 1, 0), t.shadow)
			for side in [-1, 1]:
				c.line(Vector2i(at.x + side * (r + 1), at.y), Vector2i(at.x + side * 2, front - 2), Color(0.15, 0.14, 0.12), _VISOR)
				c.fill(PixelCanvas.disc(Vector2i(at.x + side * 2, front - 2), 1), Color(0.55, 0.45, 0.2), _VISOR)
		_:
			# A welded skull cap: a seam over the crown and a ring of rivets.
			c.line(Vector2i(at.x, at.y - r - 1), Vector2i(at.x, front - 1), t.shadow, _SHELL)
			for k in 8:
				var p := Vector2(at) + Vector2.from_angle(TAU * k / 8.0) * (r - 0.5)
				c.px(roundi(p.x), roundi(p.y), t.highlight, _SHELL + 1)
	if int(look.get("rank", 0)) >= 2:
		c.line(Vector2i(at.x - r + 1, at.y - 1), Vector2i(at.x + r - 1, at.y - 1), trim.lightened(0.2), _SHELL + 1)


## A visor over the shell's front rows from `row` on, rimmed along its top edge.
static func _visor(c: PixelCanvas, shell: PixelCanvas.Shape, row: int, col: Color, rim: Color) -> void:
	var b := shell.bounds
	for y in range(row, b.end.y):
		for x in range(b.position.x, b.end.x):
			if shell.has(x, y):
				c.px(x, y, col if y > row else rim, _VISOR)


# --- Face implants -----------------------------------------------------------------------------------

## The face: a respirator, a chrome plate over one side, or goggles; glowing eyes or multi-lens optics; a headset's band.
static func _face(c: PixelCanvas, o: Vector2i, r: int, look: Dictionary) -> void:
	var glow: Color = look.get("glow", Color.RED)
	var eye_y := o.y + r - 1
	match String(look.get("face", "")):
		"respirator":
			var mask := PixelCanvas.rounded(Rect2i(o.x - 2, o.y + r - 1, 5, 3), 1)
			c.fill(mask, Color(0.09, 0.09, 0.10), _VISOR)
			c.outline(mask, Color(0.03, 0.03, 0.04))
			c.px(o.x - 1, o.y + r, Color(0.3, 0.3, 0.32), _VISOR)
			c.px(o.x + 1, o.y + r, Color(0.3, 0.3, 0.32), _VISOR)
			eye_y -= 1
		"plate":
			var side := 1 if int(look.get("plate_side", 0)) == 1 else -1
			for y in range(o.y, o.y + r + 1):
				for x in range(o.x, o.x + side * (r + 1), side):
					if Vector2(x, y).distance_to(Vector2(o)) <= r:
						c.px(x, y, StyleArt.chrome(look, x + y), _HEAD + 1)
			c.px(o.x + side * (r - 1), o.y + 1, Color(0.2, 0.2, 0.22), _HEAD + 1)  # A bolt.
		"goggles":
			for side in [-1, 1]:
				c.line(Vector2i(o.x + side * r, o.y), Vector2i(o.x + side * 2, eye_y), Color(0.12, 0.11, 0.10), _VISOR)
				c.fill(PixelCanvas.disc(Vector2i(o.x + side * 2, eye_y), 1), Color(0.75, 0.55, 0.12), _VISOR)
				c.px(o.x + side * 2, eye_y, Color(0.95, 0.85, 0.45), _VISOR)
	match String(look.get("eyes", "")):
		"glow":
			for side in [-1, 1]:
				c.px(o.x + side * 2, eye_y, glow.lightened(0.35), _VISOR + 1)
				var halo := glow
				halo.a = 0.55
				c.px(o.x + side * 2, eye_y + 1, halo, _VISOR + 1)
		"multi":
			for p in [Vector2i(-2, 0), Vector2i(-1, 1), Vector2i(1, 1), Vector2i(2, 0), Vector2i(0, -1)]:
				c.px(o.x + p.x, eye_y + p.y, glow.lightened(0.2) if p.y == 1 else glow, _VISOR + 1)
	if look.get("headset", false):
		var band := Color(0.12, 0.12, 0.12)
		c.line(Vector2i(o.x - r, o.y), Vector2i(o.x + r, o.y), band, _VISOR)
		for side in [-1, 1]:
			c.fill(PixelCanvas.disc(Vector2i(o.x + side * (r + 1), o.y + 1), 1), Color(0.18, 0.18, 0.17), _VISOR)

extends RefCounted

## Top-down pixel-art CHARACTER HEAD painter (Character domain, private; rendered through the Art
## domain's PixelArt). Painted in the canonical frame — facing +y — on its own canvas, so the head
## can turn apart from the shoulders: skin with ears and a nose toward the front, under a
## hairstyle or headwear. Options (`opts`, defaulting to CharacterConfig.art_*): `skin`, `hair`
## (the hair or headwear color), `hair_style` ("short" | "long" | "buzz" | "beanie" | "cap").

const _HAIR_HEIGHT := 7  ## Heights for cast shadows, floor-up.
const _HEAD_HEIGHT := 9
const _BRIM_HEIGHT := 10
## Canvas margin around the head (px) for the ears, long hair and a cap's brim.
const MARGIN := 5


## Head radius (art px) for a body `width` px across.
static func radius_for(width: int) -> int:
	return maxi(3, roundi(width * CharacterConfig.art_head_size))


## Canvas side (art px) for a head of radius `r`.
static func canvas_for(r: int) -> int:
	return (r + MARGIN) * 2


## Paint a head onto `c`, centered, facing +y. `base` is unused: the head takes its colors from
## `opts`.
static func paint(c: PixelCanvas, _base: Color, _material: String, opts: Dictionary) -> void:
	var o := Vector2i(int(c.w / 2.0), int(c.h / 2.0))
	_head(c, o, int(c.w / 2.0) - MARGIN, opts.get("skin", CharacterConfig.art_skin_color),
			opts.get("hair", CharacterConfig.art_hair_color), String(opts.get("hair_style", "short")))
	c.cast_shadows()


## The head: skin with ears and a nose at the front, then the hairstyle or headwear in `hair`, and
## one shared bevel and outline over both.
static func _head(c: PixelCanvas, o: Vector2i, r: int, skin: Color, hair: Color, style: String) -> void:
	var st := PixelCanvas.tones(skin)
	var ht := PixelCanvas.tones(hair)
	if style == "long":
		var fall := PixelCanvas.ellipse(Rect2i(o.x - r - 1, o.y - r - 4, r * 2 + 3, r + 6))
		c.fill(fall, hair, _HAIR_HEIGHT)
		c.outline(fall, ht.outline)
		for dx in [int(-r / 2.0), 0, int(r / 2.0)]:
			c.line(Vector2i(o.x + dx, o.y - r - 2), Vector2i(o.x + dx, o.y - 2), ht.light)
	for side in [-1, 1]:
		c.px(o.x + side * (r + 1), o.y + 1, st.dark, _HEAD_HEIGHT)
	c.px(o.x, o.y + r + 1, skin, _HEAD_HEIGHT)
	var head := PixelCanvas.disc(o, r)
	c.fill(head, skin, _HEAD_HEIGHT)
	# The face is the front cap of the head; hair or headwear covers the rest.
	var face_o := Vector2(o.x, o.y + r * 0.9)
	var face_r := r * 0.85
	var covered := func(x: int, y: int) -> bool:
		return head.has(x, y) and Vector2(x, y).distance_to(face_o) > face_r
	match style:
		"buzz":
			for y in range(o.y - r, o.y + r + 1):
				for x in range(o.x - r, o.x + r + 1):
					if covered.call(x, y) and c.rng.randf() < 0.55:
						c.px(x, y, hair.lerp(skin, 0.35))
		"beanie", "cap":
			for y in range(o.y - r, o.y + r + 1):
				for x in range(o.x - r, o.x + r + 1):
					if covered.call(x, y):
						var rib := style == "beanie" and (x - o.x) % 2 == 0
						c.px(x, y, ht.dark if rib else hair)
			if style == "beanie":
				c.fill(PixelCanvas.disc(Vector2i(o.x, o.y - int(r / 3.0)), maxi(1, int(r / 3.0))), ht.light, _HEAD_HEIGHT + 1)
			else:
				c.line(Vector2i(o.x, o.y - r + 1), Vector2i(o.x, o.y + int(r / 2.0)), ht.dark)
				var brim := PixelCanvas.ellipse(Rect2i(o.x - r + 1, o.y + int(r / 2.0), r * 2 - 1, r))
				c.fill(brim, ht.dark, _BRIM_HEIGHT)
				c.outline(brim, ht.outline)
		_:
			for y in range(o.y - r, o.y + r + 1):
				for x in range(o.x - r, o.x + r + 1):
					if covered.call(x, y):
						c.px(x, y, hair)
			# A few lighter strands sweeping from the crown toward the sides and back.
			var crown := Vector2i(o.x, o.y - int(r / 3.0))
			for d in [Vector2i(-r + 1, int(-r / 2.0)), Vector2i(r - 1, int(-r / 2.0)), Vector2i(int(-r / 2.0), -r + 1), Vector2i(int(r / 2.0), -r + 1)]:
				var tip: Vector2i = crown + d
				if covered.call(tip.x, tip.y):
					c.line(crown, tip, ht.light)
			c.px(crown.x, crown.y, ht.dark)
	c.bevel_relative(head, 1, 2, 0.16, 0.22)
	c.outline_relative(head, 0.45)

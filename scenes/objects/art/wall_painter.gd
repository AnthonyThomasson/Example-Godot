extends RefCounted

## Top-down pixel-art WALL tile painter (Objects domain, private). Paints one tile of a wall's top
## cap that the wall visuals repeat along every segment: x runs along the wall, y across its
## thickness. `plaster`: a stuccoed cap with streaks that wrap along the wall, framed at both faces
## by a lit trim and a dark edge. `brick`: running-bond courses with mortar joints. The tile is
## symmetric across the thickness, so it reads the same whichever side of a wall faces a room.
## Options (`art_opts`, defaulting to ObjectArtConfig.wall_*): `pattern` ("plaster" | "brick").

const PixelCanvas = preload("res://scenes/objects/art/pixel_canvas.gd")


## Paint one wall tile onto `c` in `base` (x along the wall, y across it).
static func paint(c: PixelCanvas, base: Color, _material: String, opts: Dictionary) -> void:
	var t := PixelCanvas.tones(base)
	var cap := PixelCanvas.rounded(Rect2i(0, 0, c.w, c.h), 0)
	c.fill(cap, base)
	if String(opts.get("pattern", ObjectArtConfig.wall_pattern)) == "brick":
		_brick(c, base, t)
	else:
		c.speckle(Rect2i(0, 0, c.w, c.h), base, 0.18, 0.04)
		c.grain(cap, true, 0.004, base.darkened(0.05), base.lightened(0.04), true)
	for y in [1, c.h - 2]:
		c.line(Vector2i(0, y), Vector2i(c.w - 1, y), t.light)
	for y in [0, c.h - 1]:
		c.line(Vector2i(0, y), Vector2i(c.w - 1, y), t.outline)


## Running-bond brick courses across the thickness, each brick a slightly different tone.
static func _brick(c: PixelCanvas, base: Color, t: Dictionary) -> void:
	var courses := maxi(2, c.h / 8)
	var brick := c.w / 2
	var mortar := base.lightened(0.35)
	for row in courses:
		var y0 := 2 + row * (c.h - 4) / courses
		var y1 := 2 + (row + 1) * (c.h - 4) / courses
		var offset := (brick / 2) * (row % 2)
		for b in 3:
			var x0 := b * brick - offset
			var shift := c.rng.randf_range(-0.08, 0.08)
			var tone := base.lightened(shift) if shift > 0.0 else base.darkened(-shift)
			for x in range(maxi(0, x0), mini(c.w, x0 + brick)):
				c.line(Vector2i(x, y0), Vector2i(x, y1 - 1), tone)
			if x0 >= 0 and x0 < c.w:
				c.line(Vector2i(x0, y0), Vector2i(x0, y1 - 1), mortar)
		c.line(Vector2i(0, y0), Vector2i(c.w - 1, y0), mortar)
	c.speckle(Rect2i(0, 0, c.w, c.h), base, 0.1, 0.06)
	c.line(Vector2i(0, c.h - 3), Vector2i(c.w - 1, c.h - 3), t.dark)

extends RefCounted

## Top-down pixel-art FLOOR tile painter (Objects domain, private). Paints one seamless tile that
## the floor visuals repeat across a room: staggered wooden `planks`, basket-weave `parquet`,
## glazed `tiles`, a two-tone `checker`, small `mosaic` tiles, speckled `carpet` pile or `concrete`
## slabs with joints and hairline cracks. Every pattern's period divides the tile, and grain and
## cracks wrap at its edges, so repeats never show a seam. Options (`art_opts`): `pattern`, `alt`
## (the checker's second color); sizes come from ObjectArtConfig.floor_*.

const PixelCanvas = preload("res://scenes/objects/art/pixel_canvas.gd")


## The tile size (world px) for the `pattern` in `opts`.
static func tile_size(opts: Dictionary) -> Vector2:
	var cell := float(ObjectArtConfig.floor_tile_px)
	match String(opts.get("pattern", "planks")):
		"planks":
			return Vector2(ObjectArtConfig.floor_plank_length * 2, ObjectArtConfig.floor_plank_px * 8)
		"parquet":
			return Vector2(ObjectArtConfig.floor_parquet_px * 2, ObjectArtConfig.floor_parquet_px * 2)
		"checker":
			return Vector2(cell * 2, cell * 2)
		"mosaic":
			return Vector2(ObjectArtConfig.floor_mosaic_px * 6, ObjectArtConfig.floor_mosaic_px * 6)
		"carpet":
			return Vector2(64, 64)
		"concrete":
			return Vector2(ObjectArtConfig.floor_slab_px, ObjectArtConfig.floor_slab_px)
	# Plain tiles: a 4×4 block, so per-tile tone and glare repeat less visibly.
	return Vector2(cell * 4, cell * 4)


## Paint one tile of the floor `pattern` onto `c` in `base`.
static func paint(c: PixelCanvas, base: Color, material: String, opts: Dictionary) -> void:
	var t := PixelCanvas.tones(base)
	c.fill(PixelCanvas.rounded(Rect2i(0, 0, c.w, c.h), 0), base)
	match String(opts.get("pattern", "planks")):
		"planks":
			_planks(c, base, t)
		"parquet":
			_parquet(c, base, t)
		"tiles":
			_tiles(c, base, t, material, ObjectArtConfig.floor_tile_px, false, base)
		"checker":
			_tiles(c, base, t, material, ObjectArtConfig.floor_tile_px, true, opts.get("alt", base.darkened(0.65)))
		"mosaic":
			_mosaic(c, base)
		"carpet":
			_carpet(c, base)
		"concrete":
			_concrete(c, base, t)


## Rows of planks with per-plank tones, wrapped grain, seams between rows and staggered butt joints.
static func _planks(c: PixelCanvas, base: Color, t: Dictionary) -> void:
	var row_h := maxi(3, roundi(ObjectArtConfig.floor_plank_px / ObjectArtConfig.pixel_size))
	var rows := c.h / row_h
	for row in rows:
		var y := row * row_h
		var joint := (row * c.w * 3 / 8 + c.rng.randi_range(0, c.w / 8)) % c.w
		# Each row is two boards meeting at `joint` (and again at the tile edge, which wraps).
		for board in 2:
			var x0 := joint if board == 0 else (joint + c.w / 2) % c.w
			var shift := c.rng.randf_range(-0.06, 0.06)
			var tone := base.lightened(shift) if shift > 0.0 else base.darkened(-shift)
			for x in c.w / 2:
				c.line(Vector2i((x0 + x) % c.w, y), Vector2i((x0 + x) % c.w, y + row_h - 1), tone)
			c.line(Vector2i(x0, y), Vector2i(x0, y + row_h - 1), t.shadow)
		var plank := PixelCanvas.rounded(Rect2i(0, y + 1, c.w, row_h - 1), 0)
		c.grain(plank, true, ObjectArtConfig.wood_grain_density, base.darkened(0.13), base.lightened(0.06), true)
		c.line(Vector2i(0, y), Vector2i(c.w - 1, y), t.shadow)
		if c.rng.randf() < ObjectArtConfig.wood_knot_chance:
			c.knot(c.rng.randi_range(2, c.w - 3), y + row_h / 2, base.darkened(0.4), base.darkened(0.2))


## Basket-weave parquet: a 2×2 grid of squares, each three or four strips laid alternately across
## and along, with darker borders.
static func _parquet(c: PixelCanvas, base: Color, t: Dictionary) -> void:
	var cell := c.w / 2
	var strips := maxi(2, cell / 4)
	for gy in 2:
		for gx in 2:
			var along_x := (gx + gy) % 2 == 0
			for s in strips:
				var a := s * cell / strips
				var b := (s + 1) * cell / strips
				var r := Rect2i(gx * cell, gy * cell + a, cell, b - a) if along_x else Rect2i(gx * cell + a, gy * cell, b - a, cell)
				var shift := c.rng.randf_range(-0.07, 0.07)
				var tone := base.lightened(shift) if shift > 0.0 else base.darkened(-shift)
				var strip := PixelCanvas.rounded(r, 0)
				c.fill(strip, tone)
				c.grain(strip, along_x, ObjectArtConfig.wood_grain_density, tone.darkened(0.12), tone.lightened(0.05))
				c.outline(strip, tone.darkened(0.16))
			c.outline(PixelCanvas.rounded(Rect2i(gx * cell, gy * cell, cell, cell), 0), t.shadow)


## Square tiles with grout lines (on the tile's top and left edges, so they wrap), a bevelled glaze
## per tile and a little glare; `checker` alternates `alt` with `base`.
static func _tiles(c: PixelCanvas, base: Color, t: Dictionary, material: String, size: int, checker: bool, alt: Color) -> void:
	var cell := maxi(4, roundi(size / ObjectArtConfig.pixel_size))
	var grout := base.darkened(0.25) if base.get_luminance() > 0.35 else base.lightened(0.3)
	for gy in c.h / cell:
		for gx in c.w / cell:
			var col := alt if checker and (gx + gy) % 2 == 1 else base
			var shift := c.rng.randf_range(-0.03, 0.03)
			col = col.lightened(shift) if shift > 0.0 else col.darkened(-shift)
			var tile := PixelCanvas.rounded(Rect2i(gx * cell + 1, gy * cell + 1, cell - 1, cell - 1), 1)
			c.fill(tile, col)
			if material == "ceramic" or material == "glass":
				c.speckle(tile.bounds, col, 0.03, 0.03)
				if c.rng.randf() < ObjectArtConfig.floor_glare_chance:
					c.glare(tile, col.lightened(0.4), 1)
			else:
				c.surface(tile, material, col)
			c.bevel(tile, 1, 1, col.lightened(0.12), col.darkened(0.12))
	for g in range(0, c.w, cell):
		c.line(Vector2i(g, 0), Vector2i(g, c.h - 1), grout)
	for g in range(0, c.h, cell):
		c.line(Vector2i(0, g), Vector2i(c.w - 1, g), grout)


## Small square tiles in four mixed tones of `base`, with light grout.
static func _mosaic(c: PixelCanvas, base: Color) -> void:
	var cell := maxi(3, roundi(ObjectArtConfig.floor_mosaic_px / ObjectArtConfig.pixel_size))
	var tones := [base, base.lightened(0.1), base.darkened(0.1), base.lightened(0.22)]
	for gy in c.h / cell:
		for gx in c.w / cell:
			var col: Color = tones[c.rng.randi_range(0, tones.size() - 1)]
			c.fill(PixelCanvas.rounded(Rect2i(gx * cell + 1, gy * cell + 1, cell - 1, cell - 1), 0), col)
	var grout := base.lightened(0.45)
	for g in range(0, c.w, cell):
		c.line(Vector2i(g, 0), Vector2i(g, c.h - 1), grout)
	for g in range(0, c.h, cell):
		c.line(Vector2i(0, g), Vector2i(c.w - 1, g), grout)


## Carpet pile: dense two-strength speckle over the whole tile.
static func _carpet(c: PixelCanvas, base: Color) -> void:
	var r := Rect2i(0, 0, c.w, c.h)
	c.speckle(r, base, 0.5, 0.05)
	c.speckle(r, base, 0.25, 0.1)


## Concrete: speckle, a few faint stains, a control joint along the tile's top and left edges
## (a slab grid once repeated) and a hairline crack that wraps at the edges.
static func _concrete(c: PixelCanvas, base: Color, t: Dictionary) -> void:
	var r := Rect2i(0, 0, c.w, c.h)
	c.speckle(r, base, 0.25, 0.05)
	for _i in 3:
		var o := Vector2i(c.rng.randi_range(8, c.w - 9), c.rng.randi_range(8, c.h - 9))
		var stain := base.darkened(0.04)
		for y in range(-6, 7):
			for x in range(-9, 10):
				if (x * x) / 81.0 + (y * y) / 36.0 <= 1.0 and c.rng.randf() < 0.7:
					c.px(o.x + x, o.y + y, stain)
	c.line(Vector2i(0, 0), Vector2i(c.w - 1, 0), t.dark)
	c.line(Vector2i(0, 0), Vector2i(0, c.h - 1), t.dark)
	var p := Vector2i(c.rng.randi_range(0, c.w - 1), c.rng.randi_range(0, c.h - 1))
	for _s in c.w / 2:
		c.px(posmod(p.x, c.w), posmod(p.y, c.h), t.dark)
		p += Vector2i(1, c.rng.randi_range(-1, 1))

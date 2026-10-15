extends RefCounted

## Top-down pixel-art WEAR painter (Objects domain, private): the damage of a run-down house and its street, one mark per
## canvas, transparent round it, placed in the world (room_wear.gd over a room's floor and walls, street_marks.gd over the
## street), never part of a repeating tile, so no mark shows up twice. Options (`art_opts`): `kind`, `v` (varies the random
## detail, so two marks of a kind and size differ) and, for the grid-bound marks, the floor's grid in art px:
##   floor: `plank_gap` (boards broken out of one or two plank rows down to the dark subfloor, splintered ends; `row_h`,
##     `rows`), `missing_cells` (tiles knocked out of a block of the tile or mosaic grid, the screed under them, a cracked
##     neighbour; `cell`, `nx`, `ny`), `strip_gap` (a parquet strip or two prised out: the subfloor and dried glue), `crack` (a
##     jagged line with a branch), `stain` (a lobed tide-marked blot), `oil` (a dark slick), `worn` (pile or finish worn pale,
##     `base` the floor's tone), `burns` (a few cigarette burns), `scuffs` (a cluster of pale strokes);
##   wall cap (x along the wall, y across its thickness, symmetric across it like the cap tile): `peel` (plaster fallen to
##     the brick), `wall_stain` (a water stain), `wall_crack` (a hairline crack), `cable` (a cable stapled along the cap, a
##     frayed end);
##   street: `patch` (a patched rectangle of newer asphalt, `base` the asphalt), `gum` (gum and grit spots), `weeds` (tufts out
##     of a crack), the floor's `crack`, `stain` and `oil`, `dash` (one worn lane dash in `base`, the paint; `fade` 1-10, how
##     much of it is left), `slab` (one sidewalk slab of another shade, `base` its tone), `chip` (a slab's broken corner).

const SUBFLOOR := Color(0.07, 0.06, 0.05)
const SCREED := Color(0.2, 0.19, 0.17)
const BRICK := Color(0.46, 0.22, 0.14)
const MORTAR := Color(0.62, 0.56, 0.46)


## Paint the mark `kind` onto `c` (`base`: the surface's own tone, for the marks that tint it).
static func paint(c: PixelCanvas, base: Color, _material: String, opts: Dictionary) -> void:
	match String(opts.get("kind", "")):
		"plank_gap":
			_plank_gap(c, base, int(opts.get("row_h", 8)), int(opts.get("rows", 1)))
		"strip_gap":
			_strip_gap(c, base)
		"missing_cells":
			_missing_cells(c, int(opts.get("cell", 24)), int(opts.get("nx", 1)), int(opts.get("ny", 1)))
		"crack":
			_crack(c, Color(0.03, 0.03, 0.03), 0.8)
		"stain":
			_blot(c, Color(0.24, 0.15, 0.06), 0.42, true)
		"oil":
			_blot(c, Color(0.03, 0.03, 0.04), 0.6, false)
			for _i in 2:  # A rainbow glint on the slick.
				var p := Vector2i(c.rng.randi_range(2, c.w - 3), c.rng.randi_range(2, c.h - 3))
				if c.at(p.x, p.y).a > 0.0:
					c.img.set_pixel(p.x, p.y, Color(0.35, 0.3, 0.5, 0.6))
		"worn":
			_blot(c, base.lightened(0.14), 0.5, false)
		"burns":
			_burns(c)
		"scuffs":
			_scuffs(c)
		"peel":
			_peel(c)
		"wall_stain":
			_mirror(c, func() -> void: _blot(c, Color(0.22, 0.15, 0.07), 0.38, true))
		"wall_crack":
			_mirror(c, func() -> void: _crack(c, Color(0.1, 0.08, 0.06), 0.55))
		"cable":
			_cable(c)
		"patch":
			_patch(c, base)
		"gum":
			_gum(c)
		"weeds":
			_crack(c, Color(0.04, 0.04, 0.04), 0.7)
			_weeds(c)
		"dash":
			_dash(c, base, int(opts.get("fade", 10)) / 10.0)
		"slab":
			_slab(c, base)
		"chip":
			_chip(c)


# --- Floor --------------------------------------------------------------------------------------------------

## Boards broken out of `rows` plank rows (each `row_h` art px with its seam on top; the canvas starts on the first board's first row
## and ends on the last's last), each row's break of its own length, splintered at both ends, the dark subfloor and a joist under it.
static func _plank_gap(c: PixelCanvas, base: Color, row_h: int, rows: int) -> void:
	var joist := c.rng.randi_range(int(c.w * 0.25), int(c.w * 0.75))
	var spans: Array[Vector2i] = []
	for r in rows:  # One row spans the canvas; another breaks shorter, over the same joist.
		var full := r == 0
		var x0 := 0 if full else c.rng.randi_range(0, maxi(0, joist - 6))
		var x1 := c.w if full else c.rng.randi_range(mini(c.w, joist + 6), c.w)
		spans.append(Vector2i(x0, x1))
		var y0 := r * row_h
		for y in range(y0, mini(c.h, y0 + row_h - 1)):
			var a := x0 + c.rng.randi_range(0, 2)
			var b := x1 - c.rng.randi_range(0, 2)
			for x in range(a, b):
				c.img.set_pixel(x, y, SUBFLOOR if absi(x - joist) > 1 else SUBFLOOR.lightened(0.12))
			for x in [a - 1, b]:  # Splinters: the board's pale broken end.
				if x >= 0 and x < c.w and c.rng.randf() < 0.7:
					c.img.set_pixel(x, y, base.lightened(0.25))
	for r in rows - 1:  # The seam between two broken rows is gone where both are.
		var y := r * row_h + row_h - 1
		for x in range(maxi(spans[r].x, spans[r + 1].x) + 2, mini(spans[r].y, spans[r + 1].y) - 2):
			if c.rng.randf() < 0.8:
				c.img.set_pixel(x, y, SUBFLOOR.lightened(0.05))


## Parquet strips prised out (the canvas is the strips' rect): the dark subfloor, smears of dried glue, a splintered pale edge.
static func _strip_gap(c: PixelCanvas, base: Color) -> void:
	for y in c.h:
		for x in c.w:
			var edge := x == 0 or y == 0 or x == c.w - 1 or y == c.h - 1
			if edge and c.rng.randf() < 0.35:
				c.img.set_pixel(x, y, base.lightened(0.22))  # What is left of the strip's edge.
				continue
			c.img.set_pixel(x, y, SUBFLOOR if c.rng.randf() < 0.8 else Color(0.36, 0.3, 0.18))


## Tiles knocked out of an `nx` x `ny` block of a `cell` grid (the canvas starts on a grout line): the first always, the others at
## random; the screed under each with crumbs, and a crack across one tile left in place.
static func _missing_cells(c: PixelCanvas, cell: int, nx: int, ny: int) -> void:
	var gone: Array[Vector2i] = [Vector2i(c.rng.randi_range(0, nx - 1), c.rng.randi_range(0, ny - 1))]
	for gy in ny:
		for gx in nx:
			if Vector2i(gx, gy) != gone[0] and c.rng.randf() < 0.45:
				gone.append(Vector2i(gx, gy))
	for g in gone:
		var r := Rect2i(g.x * cell + 1, g.y * cell + 1, cell - 1, cell - 1)
		for y in range(r.position.y, r.end.y):
			for x in range(r.position.x, r.end.x):
				var edge := x == r.position.x or y == r.position.y or x == r.end.x - 1 or y == r.end.y - 1
				if edge and c.rng.randf() < 0.3:
					continue  # A chip of tile still stuck at the edge.
				c.img.set_pixel(x, y, SCREED if c.rng.randf() < 0.82 else SCREED.lightened(0.18))
	if gone.size() < nx * ny:
		for gy in ny:
			for gx in nx:
				if not gone.has(Vector2i(gx, gy)):
					var a := Vector2i(gx * cell + 2, gy * cell + c.rng.randi_range(2, cell - 2))
					var p := a
					for _k in cell - 3:
						c.img.set_pixel(p.x, p.y, Color(0.03, 0.03, 0.03, 0.75))
						p += Vector2i(1, c.rng.randi_range(-1, 1))
						p.y = clampi(p.y, gy * cell + 1, gy * cell + cell - 1)
					return


## A crack: a jagged line wandering along the canvas's long side, with one short branch.
static func _crack(c: PixelCanvas, col: Color, alpha: float) -> void:
	var horizontal := c.w >= c.h
	var p := Vector2i(0, c.rng.randi_range(int(c.h * 0.3), int(c.h * 0.7))) if horizontal \
			else Vector2i(c.rng.randi_range(int(c.w * 0.3), int(c.w * 0.7)), 0)
	var length := c.w if horizontal else c.h
	var branch_at := c.rng.randi_range(int(length * 0.3), int(length * 0.7))
	for k in length:
		if c.has(p.x, p.y):
			c.img.set_pixel(p.x, p.y, Color(col, alpha))
		if k == branch_at:
			var q := p
			var turn := Vector2i(1, c.rng.randi_range(0, 1) * 2 - 1) if horizontal else Vector2i(c.rng.randi_range(0, 1) * 2 - 1, 1)
			for _j in c.rng.randi_range(4, maxi(5, int(length / 4.0))):
				q += turn if c.rng.randf() < 0.6 else (Vector2i(1, 0) if horizontal else Vector2i(0, 1))
				if c.has(q.x, q.y):
					c.img.set_pixel(q.x, q.y, Color(col, alpha * 0.8))
		p += Vector2i(1, c.rng.randi_range(-1, 1)) if horizontal else Vector2i(c.rng.randi_range(-1, 1), 1)
		p = p.clamp(Vector2i.ZERO, Vector2i(c.w - 1, c.h - 1))


## A lobed, dithered blot of `col` fading out from its middle, filling the canvas's oval; `tide` adds a darker tide mark at its rim.
static func _blot(c: PixelCanvas, col: Color, alpha: float, tide: bool) -> void:
	var centre := Vector2(c.w, c.h) * 0.5
	var lobes: Array = []
	for _i in c.rng.randi_range(2, 4):
		lobes.append([Vector2(c.rng.randf_range(-0.25, 0.25) * c.w, c.rng.randf_range(-0.25, 0.25) * c.h), c.rng.randf_range(0.28, 0.48)])
	for y in c.h:
		for x in c.w:
			var d := 9.0
			for lobe in lobes:
				var offset: Vector2 = lobe[0]
				var reach: float = lobe[1]
				d = minf(d, ((Vector2(x, y) - centre - offset) / (Vector2(c.w, c.h) * reach)).length())
			if d > 1.0 or c.rng.randf() > 0.95 - d * 0.45:
				continue
			var a := alpha * (1.0 - d * 0.55)
			if tide and d > 0.82:
				a = alpha * 1.15
			c.img.set_pixel(x, y, Color(col.darkened(0.2) if tide and d > 0.82 else col, clampf(a, 0.0, 1.0)))


## A few cigarette burns: black dots in brown scorch.
static func _burns(c: PixelCanvas) -> void:
	for _i in c.rng.randi_range(2, 4):
		var o := Vector2i(c.rng.randi_range(2, c.w - 3), c.rng.randi_range(2, c.h - 3))
		for d in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			c.img.set_pixel(o.x + d.x, o.y + d.y, Color(0.2, 0.12, 0.05, 0.6))
		c.img.set_pixel(o.x, o.y, Color(0.04, 0.03, 0.02, 0.95))


## A cluster of short pale scuff strokes, each its own way.
static func _scuffs(c: PixelCanvas) -> void:
	for _i in c.rng.randi_range(4, 9):
		var p := Vector2(c.rng.randi_range(1, c.w - 2), c.rng.randi_range(1, c.h - 2))
		var dir := Vector2.RIGHT.rotated(c.rng.randf_range(-0.6, 0.6) + (PI * 0.5 if c.rng.randf() < 0.25 else 0.0))
		for k in c.rng.randi_range(3, 8):
			var q := Vector2i((p + dir * k).round())
			if c.has(q.x, q.y):
				c.img.set_pixel(q.x, q.y, Color(0.82, 0.74, 0.6, 0.3))


# --- Wall cap -----------------------------------------------------------------------------------------------

## Run `mark`, then make the canvas symmetric across the thickness (each pixel and its mirror take the more opaque of the two), as
## the game's wall tile is, so the cap reads the same from either room.
static func _mirror(c: PixelCanvas, mark: Callable) -> void:
	mark.call()
	_symmetric(c)


## Mirror the marks across the canvas' middle row, so both faces of the wall show them (the more opaque pixel of each pair).
static func _symmetric(c: PixelCanvas) -> void:
	for y in int(c.h / 2.0):
		for x in c.w:
			var top := c.at(x, y)
			var bottom := c.at(x, c.h - 1 - y)
			var keep := top if top.a >= bottom.a else bottom
			c.img.set_pixel(x, y, keep)
			c.img.set_pixel(x, c.h - 1 - y, keep)


## Plaster fallen away to the brick: a ragged patch from one face in, brick courses and mortar showing, a pale lip of broken plaster
## round it, mirrored onto the other face.
static func _peel(c: PixelCanvas) -> void:
	var half := int(c.h / 2.0)
	var depth := c.rng.randi_range(maxi(2, int(half * 0.5)), maxi(2, half))
	var mid := c.w * 0.5
	var hole := {}
	for y in range(0, half + 1):
		if y > depth:
			break
		var reach := mid * (1.0 - pow(float(y) / float(maxi(1, depth)), 1.6))
		for x in c.w:
			if absf(x + 0.5 - mid) <= reach + c.rng.randf_range(-1.5, 1.5):
				hole[Vector2i(x, y)] = true
	var lip := Color(0.82, 0.76, 0.6, 0.9)
	for y in range(0, half + 1):
		for x in c.w:
			var p := Vector2i(x, y)
			if hole.has(p):
				var mortar := y % 3 == 0 or (x + 3 * int(y / 3.0)) % 7 == 0
				c.img.set_pixel(x, y, MORTAR if mortar else BRICK.lightened(c.rng.randf_range(0.0, 0.08)))
			elif hole.has(p + Vector2i.LEFT) or hole.has(p + Vector2i.RIGHT) or hole.has(p + Vector2i.UP):
				c.img.set_pixel(x, y, lip)
	_symmetric(c)


## A cable stapled along the cap, a pixel off the middle, staples at uneven gaps, a frayed end where it stops.
static func _cable(c: PixelCanvas) -> void:
	var y := int(c.h / 2.0) + c.rng.randi_range(-1, 1)
	var next := c.rng.randi_range(4, 10)
	for x in range(0, c.w - 2):
		c.img.set_pixel(x, y, Color(0.08, 0.08, 0.08))
		if x == next:
			c.img.set_pixel(x, y - 1, Color(0.6, 0.6, 0.58))
			c.img.set_pixel(x, y + 1, Color(0.6, 0.6, 0.58))
			next += c.rng.randi_range(9, 22)
		if c.rng.randf() < 0.08:
			y = clampi(y + c.rng.randi_range(-1, 1), 1, c.h - 2)
	c.img.set_pixel(c.w - 2, y - 1, Color(0.75, 0.45, 0.2))  # Copper showing at the frayed end.
	c.img.set_pixel(c.w - 1, y + 1, Color(0.75, 0.45, 0.2))


# --- Street -------------------------------------------------------------------------------------------------

## A patch of newer asphalt: a slightly lighter, speckled rectangle with a dark tar seam round it.
static func _patch(c: PixelCanvas, base: Color) -> void:
	var tone := base.lightened(0.06)
	for y in c.h:
		for x in c.w:
			var edge := x == 0 or y == 0 or x == c.w - 1 or y == c.h - 1
			var col := Color(0.04, 0.04, 0.04) if edge else (tone if c.rng.randf() < 0.8 else tone.darkened(0.12))
			c.img.set_pixel(x, y, col)


## Gum and grit: a handful of pale and black spots.
static func _gum(c: PixelCanvas) -> void:
	for _i in c.rng.randi_range(5, 10):
		var p := Vector2i(c.rng.randi_range(0, c.w - 2), c.rng.randi_range(0, c.h - 2))
		var col := Color(0.62, 0.6, 0.55, 0.85) if c.rng.randf() < 0.5 else Color(0.08, 0.08, 0.08, 0.8)
		c.img.set_pixel(p.x, p.y, col)
		if c.rng.randf() < 0.5:
			c.img.set_pixel(p.x + 1, p.y, col.darkened(0.15))


## Tufts of weeds along a crack.
static func _weeds(c: PixelCanvas) -> void:
	for _i in c.rng.randi_range(2, 4):
		var o := Vector2i(c.rng.randi_range(2, c.w - 3), c.rng.randi_range(1, c.h - 2))
		for d in [Vector2i(0, 0), Vector2i(-1, -1), Vector2i(1, -1), Vector2i(0, 1)]:
			if c.has(o.x + d.x, o.y + d.y):
				c.img.set_pixel(o.x + d.x, o.y + d.y, Color(0.3, 0.42, 0.16) if d != Vector2i.ZERO else Color(0.42, 0.55, 0.2))


## One lane dash of `ink` (the paint): worn through to the asphalt in specks (more of them as `left` falls), its ends chipped unevenly.
static func _dash(c: PixelCanvas, ink: Color, left: float) -> void:
	var cut_a := c.rng.randi_range(0, 2)
	var cut_b := c.rng.randi_range(0, 2)
	for y in c.h:
		for x in c.w:
			if x < cut_a and c.rng.randf() < 0.6 or x >= c.w - cut_b and c.rng.randf() < 0.6:
				continue
			if c.rng.randf() > left * 0.92 + 0.05:
				continue  # Worn through.
			c.img.set_pixel(x, y, Color(ink, ink.a * c.rng.randf_range(0.75, 1.0)))


## One sidewalk slab of its own shade (`tone`: a newer or a dirtier slab than the rest), its grain, and grime along an edge.
static func _slab(c: PixelCanvas, tone: Color) -> void:
	var grimy := c.rng.randi_range(0, 3)
	for y in c.h:
		for x in c.w:
			var col := tone if c.rng.randf() < 0.85 else (tone.lightened(0.04) if c.rng.randf() < 0.5 else tone.darkened(0.05))
			var edge := [y, c.w - 1 - x, c.h - 1 - y, x][grimy] as int
			if edge < 3 and c.rng.randf() < 0.5:
				col = col.darkened(0.12)
			c.img.set_pixel(x, y, col)


## A slab's broken corner: a ragged wedge of dark grit from one corner of the canvas.
static func _chip(c: PixelCanvas) -> void:
	var corner := Vector2i(0 if c.rng.randf() < 0.5 else c.w - 1, 0 if c.rng.randf() < 0.5 else c.h - 1)
	var reach := float(mini(c.w, c.h))
	for y in c.h:
		for x in c.w:
			var d := absf(x - corner.x) + absf(y - corner.y)
			if d < reach * 0.8 + c.rng.randf_range(-1.5, 1.5):
				c.img.set_pixel(x, y, Color(0.12, 0.11, 0.1, 0.9) if c.rng.randf() < 0.8 else Color(0.3, 0.28, 0.25, 0.9))

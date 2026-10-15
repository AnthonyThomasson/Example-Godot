extends RefCounted

## The run-down look every Objects painter draws in (Objects domain, private): rust & grime, with a share of neon. A painter
## draws its piece's shape as before, in the colours ObjectArt hands it (`grade`: any catalogue colour washed toward dun, rust
## and nicotine yellow) and the ObjectArtConfig colour knobs, then finishes it here: grime blotches, stains, tears and tape on
## upholstery, scratches, cup rings and burns on wood, rust and stickers on metal, cracks in porcelain and glass. A piece the
## factory gave a `neon` option (`ObjectArt.neon_for`: a share of the light-giving pieces) takes a cyan or magenta trim or
## screen. No light is painted in: what gives light (a screen's face, a tube, a bulb, an LED) is drawn bright and `glowing`
## (PixelCanvas), so it can be drawn unshaded later, and nothing round it is lit. Every mark is per piece, never in a
## repeating floor or wall tile (their wear is placed in the world: wear_painter.gd). Tuning: ObjectArtConfig.grade_*,
## decay_*, neon_*.

const STAIN := Color(0.3, 0.2, 0.1)  ## Brown: coffee, water, worse.
const GREASE := Color(0.24, 0.18, 0.08)
const FOOD := Color(0.4, 0.36, 0.14)
const LIMESCALE := Color(0.45, 0.3, 0.12)
const RUST_DARK := Color(0.52, 0.26, 0.12)
const RUST_LIGHT := Color(0.66, 0.36, 0.16)
const SCRATCH := Color(0.85, 0.8, 0.7)
const STUFFING := Color(0.82, 0.76, 0.56)
const HOLE := Color(0.12, 0.09, 0.07)
const TAPE := Color(0.62, 0.62, 0.6)
const BURN := Color(0.06, 0.05, 0.04)
const PRIMER := Color(0.5, 0.5, 0.48)
const STICKERS: Array[Color] = [Color(0.85, 0.2, 0.2), Color(0.95, 0.8, 0.2), Color(0.2, 0.6, 0.85), Color(0.9, 0.9, 0.86)]


# --- Colour ----------------------------------------------------------------------------------------------------

## `col` in the run-down palette: its hue pulled toward rust and dun (a grey taking a dun hue), its saturation and value
## squeezed toward a dull middle (ObjectArtConfig.grade_*). ObjectArt grades every piece's, floor's and wall's colour.
static func grade(col: Color) -> Color:
	var grey := col.s <= ObjectArtConfig.grade_grey_saturation
	var hue := ObjectArtConfig.grade_grey_hue if grey else lerpf(col.h, ObjectArtConfig.grade_hue, ObjectArtConfig.grade_hue_pull)
	var sat := col.s * ObjectArtConfig.grade_saturation.x + ObjectArtConfig.grade_saturation.y
	var val := col.v * ObjectArtConfig.grade_value.x + ObjectArtConfig.grade_value.y
	return Color.from_hsv(hue, clampf(sat, 0.0, 1.0), clampf(val, 0.0, 1.0), col.a)


## The neon colour a piece's `neon` option names (`cyan` / `magenta`), or transparent for a piece without one.
static func neon(opts: Dictionary) -> Color:
	match String(opts.get("neon", "")):
		"cyan":
			return ObjectArtConfig.neon_cyan
		"magenta":
			return ObjectArtConfig.neon_magenta
	return Color(0, 0, 0, 0)


## The glow of a screen in the piece (a monitor, a TV, an appliance's display): its neon when it has one, else the sick
## green of a cheap screen.
static func screen_color(opts: Dictionary) -> Color:
	var lit := neon(opts)
	return lit if lit.a > 0.0 else ObjectArtConfig.decay_screen_color


# --- Grime over a drawn piece --------------------------------------------------------------------------------

## Grime blotches over the whole piece, about one per `ObjectArtConfig.decay_grime_area` art px² (at least two): darker,
## dithered pixels fading out from each blotch's middle.
static func grime(c: PixelCanvas, amount := -1.0, radius := 5) -> void:
	var strength := ObjectArtConfig.decay_grime_amount if amount < 0.0 else amount
	blotches(c, maxi(2, int(c.w * c.h / ObjectArtConfig.decay_grime_area)), strength, radius)


## `count` grime blotches of up to `radius` px, `amount` darker at their middle.
static func blotches(c: PixelCanvas, count: int, amount: float, radius: int) -> void:
	for _i in count:
		var o := Vector2i(c.rng.randi_range(0, c.w - 1), c.rng.randi_range(0, c.h - 1))
		var r := c.rng.randi_range(maxi(1, int(radius / 2.0)), radius)
		for y in range(-r, r + 1):
			for x in range(-r, r + 1):
				var d := sqrt(x * x + y * y) / float(r)
				if d > 1.0 or c.rng.randf() > 0.75 - d * 0.4:
					continue
				var p := o + Vector2i(x, y)
				if c.covered(p.x, p.y):
					c.img.set_pixel(p.x, p.y, c.at(p.x, p.y).darkened(amount * (1.0 - d * 0.6)))


## A stain ring at a random drawn spot: a rim of `col` round a faintly tinted middle.
static func stain(c: PixelCanvas, col: Color, radius := 4) -> void:
	var o := Vector2i(c.rng.randi_range(radius, maxi(radius, c.w - radius - 1)), c.rng.randi_range(radius, maxi(radius, c.h - radius - 1)))
	for y in range(-radius, radius + 1):
		for x in range(-radius, radius + 1):
			var d := sqrt(x * x + y * y)
			var p := o + Vector2i(x, y)
			if d > radius + 0.5 or not c.covered(p.x, p.y):
				continue
			c.img.set_pixel(p.x, p.y, c.at(p.x, p.y).lerp(col, 0.55 if d > radius - 1.2 else 0.18))


## `count` small orange-brown rust clusters over drawn pixels.
static func rust(c: PixelCanvas, count: int) -> void:
	for _i in count:
		var p := Vector2i(c.rng.randi_range(0, c.w - 1), c.rng.randi_range(0, c.h - 1))
		for _k in c.rng.randi_range(2, 6):
			if c.covered(p.x, p.y):
				c.img.set_pixel(p.x, p.y, c.at(p.x, p.y).lerp(RUST_DARK if c.rng.randf() < 0.6 else RUST_LIGHT, 0.7))
			p += Vector2i(c.rng.randi_range(-1, 1), c.rng.randi_range(-1, 1))


## `count` short pale scratches over drawn pixels.
static func scratches(c: PixelCanvas, count: int) -> void:
	for _i in count:
		var a := Vector2i(c.rng.randi_range(0, c.w - 1), c.rng.randi_range(0, c.h - 1))
		var b := a + Vector2i(c.rng.randi_range(-6, 6), c.rng.randi_range(-3, 3))
		for p in points(a, b):
			if c.covered(p.x, p.y):
				c.img.set_pixel(p.x, p.y, c.at(p.x, p.y).lerp(SCRATCH, 0.35))


## A tear in upholstery at a random drawn spot: a dark hole rimmed with pale stuffing.
static func tear(c: PixelCanvas, size := 3) -> void:
	var o := Vector2i(c.rng.randi_range(size + 2, maxi(size + 2, c.w - size - 3)), c.rng.randi_range(size + 2, maxi(size + 2, c.h - size - 3)))
	if not c.covered(o.x, o.y):
		return
	for y in range(-size, size + 1):
		for x in range(-size - 1, size + 2):
			var d := absf(x) / (size + 1.0) + absf(y) / float(size)
			var p := o + Vector2i(x, y)
			if d <= 1.0 and c.covered(p.x, p.y):
				c.img.set_pixel(p.x, p.y, HOLE if d < 0.45 else STUFFING)


## A strip of grey duct tape across a random drawn spot.
static func tape(c: PixelCanvas) -> void:
	var o := Vector2i(c.rng.randi_range(2, maxi(2, c.w - 3)), c.rng.randi_range(2, maxi(2, c.h - 3)))
	var length := c.rng.randi_range(5, 9)
	var dir := Vector2i(1, 0) if c.rng.randf() < 0.5 else Vector2i(1, 1)
	for k in length:
		for s in 2:
			var p := o + dir * (k - int(length / 2.0)) + Vector2i(0, s)
			if c.covered(p.x, p.y):
				c.img.set_pixel(p.x, p.y, TAPE if s == 0 else TAPE.darkened(0.2))


## `count` cigarette burns: a black spot ringed with scorch.
static func burns(c: PixelCanvas, count: int) -> void:
	for _i in count:
		var p := Vector2i(c.rng.randi_range(2, maxi(2, c.w - 3)), c.rng.randi_range(2, maxi(2, c.h - 3)))
		if not c.covered(p.x, p.y):
			continue
		c.img.set_pixel(p.x, p.y, BURN)
		for d in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			if c.covered(p.x + d.x, p.y + d.y):
				c.img.set_pixel(p.x + d.x, p.y + d.y, c.at(p.x + d.x, p.y + d.y).darkened(0.4))


## `count` stickers (band logos, gang tags): small bright rectangles slapped on drawn spots.
static func stickers(c: PixelCanvas, count: int) -> void:
	for _i in count:
		var p := Vector2i(c.rng.randi_range(2, maxi(2, c.w - 6)), c.rng.randi_range(2, maxi(2, c.h - 5)))
		var col: Color = STICKERS[c.rng.randi_range(0, STICKERS.size() - 1)].darkened(0.25)
		for y in 3:
			for x in 4:
				if c.covered(p.x + x, p.y + y):
					c.img.set_pixel(p.x + x, p.y + y, col if (x + y) % 3 != 0 else col.darkened(0.3))


## A jagged dark crack across a drawn part.
static func crack(c: PixelCanvas) -> void:
	var p := Vector2i(c.rng.randi_range(2, maxi(2, c.w - 3)), c.rng.randi_range(2, maxi(2, c.h - 3)))
	for _k in maxi(4, int(mini(c.w, c.h) / 3.0)):
		if c.covered(p.x, p.y):
			c.img.set_pixel(p.x, p.y, c.at(p.x, p.y).darkened(0.55))
		p += Vector2i(1, c.rng.randi_range(-1, 1))


## `count` moth holes cut through to the floor.
static func holes(c: PixelCanvas, count: int) -> void:
	for _i in count:
		var o := Vector2i(c.rng.randi_range(4, maxi(4, c.w - 5)), c.rng.randi_range(4, maxi(4, c.h - 5)))
		c.clear(PixelCanvas.disc(o, c.rng.randi_range(1, 2)))


## A primer-grey panel (a replaced door) over part of a body.
static func primer(c: PixelCanvas) -> void:
	var r := Rect2i(int(c.w * 0.1), int(c.h * 0.4), int(c.w * 0.3), int(c.h * 0.2))
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			if c.covered(x, y):
				c.img.set_pixel(x, y, c.at(x, y).lerp(PRIMER, 0.65))


# --- Trims and screens (what gives light: drawn `glowing`) -----------------------------------------------------

## A strip set `depth` px in from the silhouette's edge, blended `amount` toward `col`, drawn glowing (a neon strip round a
## desk, a shelf, a mattress, a mirror's frame).
static func neon_ring(c: PixelCanvas, depth: int, col: Color, amount: float) -> void:
	c.glowing(func() -> void: _ring(c, depth, col, amount))


## The strip: each drawn pixel whose four neighbours `depth` px off along the axes are drawn but not all four `depth` + 1 px
## off (off the canvas counts as not drawn), read from the canvas's coverage bytes.
static func _ring(c: PixelCanvas, depth: int, col: Color, amount: float) -> void:
	var cov := c.coverage()
	var w := c.w
	var h := c.h
	var far := depth + 1
	var dw := depth * w
	var fw := far * w
	var lit: Array[Vector2i] = []
	var i := 0
	for y in h:
		var rows_in := y >= depth and y + depth < h  # The rows `depth` px up and down are on the canvas.
		var rows_far := y >= far and y + far < h
		for x in w:
			if cov[i] != 0 and rows_in and x >= depth and x + depth < w and cov[i - depth] != 0 and cov[i + depth] != 0 \
					and cov[i - dw] != 0 and cov[i + dw] != 0:
				if not (rows_far and x >= far and x + far < w and cov[i - far] != 0 and cov[i + far] != 0 and cov[i - fw] != 0
						and cov[i + fw] != 0):
					lit.append(Vector2i(x, y))
			i += 1
	for p in lit:
		c.img.set_pixel(p.x, p.y, c.at(p.x, p.y).lerp(col, amount))


## A neon under-glow along the piece's front edge (the canonical +y side), drawn glowing.
static func neon_front(c: PixelCanvas, col: Color, amount: float) -> void:
	c.glowing(func() -> void:
		for x in c.w:
			for y in range(c.h - 1, -1, -1):
				if c.covered(x, y):
					c.img.set_pixel(x, y, c.at(x, y).lerp(col, amount))
					break)


## A lit display: a short line from `a` to `b` in `col`, drawn glowing.
static func display(c: PixelCanvas, a: Vector2i, b: Vector2i, col: Color) -> void:
	c.glowing(func() -> void: line(c, a, b, col, 1.0))


## A glowing screen over `r`: `col` with a brighter top line and dark scanlines every other row.
static func screen(c: PixelCanvas, r: Rect2i, col: Color) -> void:
	c.glowing(func() -> void:
		for y in range(r.position.y, r.end.y):
			for x in range(r.position.x, r.end.x):
				if c.has(x, y):
					var top := y == r.position.y
					c.px(x, y, col.lightened(0.35) if top else (col.darkened(0.35) if (y - r.position.y) % 2 == 1 else col))
	, r)


# --- Shared bits --------------------------------------------------------------------------------------------------

## A line from `a` to `b`, each pixel blended `amount` toward `col` over what is drawn (set outright where nothing is).
static func line(c: PixelCanvas, a: Vector2i, b: Vector2i, col: Color, amount: float) -> void:
	for p in points(a, b):
		if c.has(p.x, p.y):
			var here := c.at(p.x, p.y)
			c.px(p.x, p.y, here.lerp(col, amount) if here.a > 0.0 else col)


## The points of a 1 px line from `a` to `b` (Bresenham).
static func points(a: Vector2i, b: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var d := (b - a).abs()
	var sx := 1 if a.x < b.x else -1
	var sy := 1 if a.y < b.y else -1
	var err := d.x - d.y
	var p := a
	while true:
		out.append(p)
		if p == b:
			break
		var e2 := err * 2
		if e2 > -d.y:
			err -= d.y
			p.x += sx
		if e2 < d.x:
			err += d.x
			p.y += sy
	return out

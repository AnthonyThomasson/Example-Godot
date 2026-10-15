extends RefCounted

## What the character painters share (Character domain, private): the resolved looks they draw by handle, and the marks of
## the styles (`CharacterConfig.styles`: the Zenitex and Trauma Team police units, the merc and borg crew) drawn on a
## PixelCanvas: chrome, tattoo ink, black plates set in the skin, a livery's edge sheen, stripes, crosses, stencils, tape and a
## plate's wear.
##
## A painter's options carry the look as an int handle (`opts.look`, from `register`), never the look itself: PixelArt keys its
## caches by the options (`render_turned` hashes them on every call), and the look is some fifty entries, so carrying it would
## cost that for every part of every body every frame. The handle is the look's hash, so the same look always has the same one
## and a cached texture keyed by it is always that look's.

## The resolved looks (`character_style.gd`'s `resolve`) by handle.
static var _looks := {}


## The handle of `look`, registered for `look_of`.
static func register(look: Dictionary) -> int:
	var id := hash(look)
	_looks[id] = look
	return id


## The look a painter's `opts` name (`opts.look`), or {} for none (the plain strip of a neck).
static func look_of(opts: Dictionary) -> Dictionary:
	return _looks.get(opts.get("look", 0), {})


## The chrome tone at pixel index `k`: cool metal with a bright glint every few pixels.
static func chrome(look: Dictionary, k: int) -> Color:
	var base: Color = look.get("chrome", Color(0.7, 0.74, 0.78))
	return base.lightened(0.35) if k % 5 == 0 else base if k % 2 == 0 else base.darkened(0.14)


## Tattoo ink over the drawn pixels of `r`: `strokes` short seeded strokes in the body's ink.
static func tattoo(c: PixelCanvas, r: Rect2i, look: Dictionary, strokes := 3) -> void:
	var ink: Color = look.get("ink", Color.BLACK)
	for k in strokes:
		var p := Vector2i(c.rng.randi_range(r.position.x, r.end.x - 1), c.rng.randi_range(r.position.y, r.end.y - 1))
		for i in 3:
			if c.covered(p.x, p.y):
				c.px(p.x, p.y, ink)
			p += Vector2i(c.rng.randi_range(-1, 1), 1)


## `count` black cyber plates set into the skin of `r`: 2 px slivers with a bright edge.
static func inlays(c: PixelCanvas, r: Rect2i, count := 2) -> void:
	for k in count:
		var p := Vector2i(c.rng.randi_range(r.position.x, r.end.x - 2), c.rng.randi_range(r.position.y, r.end.y - 1))
		if not (c.covered(p.x, p.y) and c.covered(p.x + 1, p.y)):
			continue
		c.px(p.x, p.y, Color(0.07, 0.07, 0.08))
		c.px(p.x + 1, p.y, Color(0.12, 0.12, 0.14))
		if c.covered(p.x, p.y + 1):
			c.px(p.x, p.y + 1, Color(0.04, 0.04, 0.05))


## The livery's edge sheen on `shape` (the Zenitex's light grey plate edges): its rim lit all round, brighter toward the
## light, so a near-black garment still reads as a shape on the floor. Nothing for a style without an `edge`.
static func edge(c: PixelCanvas, shape: PixelCanvas.Shape, look: Dictionary) -> void:
	var col: Color = look.get("edge", Color(0, 0, 0, 0))
	if col.a > 0.0:
		c.bevel(shape, 1, 1, col, col.darkened(0.4))


## A vertical line at column `x` from row `y0` to `y1` (exclusive), only where `shape` is: a stripe kept on the garment.
static func column(c: PixelCanvas, shape: PixelCanvas.Shape, x: int, y0: int, y1: int, col: Color, height: int) -> void:
	for y in range(y0, y1):
		if shape.has(x, y):
			c.px(x, y, col, height)


## A plus-shaped cross (a medic's) centred at `at`, arms `arm` px long.
static func cross(c: PixelCanvas, at: Vector2i, col: Color, height: int, arm := 1) -> void:
	c.line(at - Vector2i(arm, 0), at + Vector2i(arm, 0), col, height)
	c.line(at - Vector2i(0, arm), at + Vector2i(0, arm), col, height)


## A stencilled word: a row of letter blocks with gaps, from `from` along x for `length` px.
static func stencil(c: PixelCanvas, from: Vector2i, length: int, col: Color, height: int) -> void:
	for x in range(from.x, from.x + length):
		if (x - from.x) % 3 != 2:
			c.px(x, from.y, col, height)


## A strip of grey duct tape from `a` to `b` (a scavenged patch).
static func tape(c: PixelCanvas, a: Vector2i, b: Vector2i, height: int) -> void:
	c.line(a, b, Color(0.62, 0.62, 0.6), height)

extends RefCounted

## Top-down pixel-art DECOR painter (Objects domain, private): the walk-over clutter of a run-down house and the neon on its
## walls, all non-solid catalogue pieces (no collider, never carved), and the litter the street's marks strew. Painted in
## the canonical frame, along the canvas's length. Options (`art_opts`): `kind` —
##   `trash` (black bags, crushed cans, papers and a bottle, heaped), `cables` (a loose run of cables), `cable_nest` (a
##   tangle of them), `cardboard` (a flattened, taped box with a blanket on it: someone sleeps here), `puddle` (standing
##   water), `neon_tube` (a neon tube at the foot of a wall: a white-hot core and its `tone`, `cyan` or `magenta`, drawn
##   glowing: it gives light);
## and `v`, which only varies the random detail, so two pieces of a kind are not one cached picture. No light is painted
## round anything: a tube is its tube, a puddle its water.

const Decay = preload("res://scenes/objects/art/decay.gd")

const BAG := Color(0.1, 0.1, 0.11)
const CANS: Array[Color] = [Color(0.75, 0.15, 0.15), Color(0.2, 0.5, 0.75), Color(0.8, 0.8, 0.82)]
const PAPER := Color(0.86, 0.84, 0.76)
const BOTTLE := Color(0.25, 0.45, 0.22)
const CABLES: Array[Color] = [Color(0.08, 0.08, 0.08), Color(0.12, 0.12, 0.14), Color(0.55, 0.14, 0.12), Color(0.85, 0.65, 0.15)]
const CARD := Color(0.62, 0.48, 0.3)
const BLANKET := Color(0.3, 0.32, 0.22)
const WATER := Color(0.14, 0.12, 0.08, 0.72)
const TUBE_END := Color(0.2, 0.2, 0.22)


## Paint the decor `kind` onto `c`.
static func paint(c: PixelCanvas, _base: Color, _material: String, opts: Dictionary) -> void:
	match String(opts.get("kind", "")):
		"trash":
			_trash(c)
		"cables":
			_cables(c, 3, false)
		"cable_nest":
			_cables(c, 7, true)
		"cardboard":
			_cardboard(c)
		"puddle":
			_puddle(c)
		"neon_tube":
			_tube(c, Decay.neon({ "neon": opts.get("tone", "cyan") }))


## Three black bags with their knots, and cans, papers and a bottle round them.
static func _trash(c: PixelCanvas) -> void:
	for _i in 3:
		var r := c.rng.randi_range(4, 7)
		var o := Vector2i(c.rng.randi_range(r, maxi(r, c.w - r - 1)), c.rng.randi_range(r, maxi(r, c.h - r - 1)))
		var bag := PixelCanvas.disc(o, r)
		c.fill(bag, BAG, 3)
		c.bevel(bag, 1, 1, BAG.lightened(0.25), BAG.darkened(0.4))
		c.px(o.x, o.y - r + 1, BAG.lightened(0.35))  # The knot.
	for _i in 6:
		var p := Vector2i(c.rng.randi_range(1, maxi(1, c.w - 4)), c.rng.randi_range(1, maxi(1, c.h - 3)))
		match c.rng.randi_range(0, 2):
			0:
				var can: Color = CANS[c.rng.randi_range(0, CANS.size() - 1)]
				c.fill(PixelCanvas.rounded(Rect2i(p, Vector2i(3, 2)), 0), can, 2)
				c.px(p.x, p.y, can.lightened(0.4), 2)
			1:
				c.fill(PixelCanvas.rounded(Rect2i(p, Vector2i(3, 3)), 0), PAPER, 1)
				c.px(p.x + 1, p.y + 1, Color(0.5, 0.5, 0.5), 1)
			_:
				c.line(p, p + Vector2i(3, 1), BOTTLE, 2)
	c.cast_shadows()


## Loose cables snaking along the canvas (`count` of them), or (`nest`) a tangle of them looping round on itself.
static func _cables(c: PixelCanvas, count: int, nest: bool) -> void:
	for i in count:
		var col: Color = CABLES[i % CABLES.size()]
		var p := Vector2(0, c.rng.randf_range(2, c.h - 3)) if not nest else Vector2(c.rng.randf_range(4, c.w - 5), c.rng.randf_range(4, c.h - 5))
		var heading := 0.0 if not nest else c.rng.randf() * TAU
		for _k in (c.w * 2 if not nest else c.w * 3):
			heading += c.rng.randf_range(-0.35, 0.35) if not nest else c.rng.randf_range(-0.15, 0.6)
			if not nest:
				heading = clampf(heading, -0.6, 0.6)
			p += Vector2(cos(heading), sin(heading)) * 0.6
			if nest:
				p = Vector2(clampf(p.x, 1, c.w - 2), clampf(p.y, 1, c.h - 2))
			var q := Vector2i(p.round())
			if c.has(q.x, q.y):
				c.px(q.x, q.y, col, 1)


## A flattened cardboard box, creased and taped, stained where it got wet, a blanket over half of it.
static func _cardboard(c: PixelCanvas) -> void:
	var box := PixelCanvas.rounded(Rect2i(0, 0, c.w, c.h), 0)
	c.fill(box, CARD, 1)
	c.speckle(Rect2i(0, 0, c.w, c.h), CARD, 0.2, 0.05)
	c.line(Vector2i(0, int(c.h / 2.0)), Vector2i(c.w - 1, int(c.h / 2.0)), CARD.darkened(0.3))
	c.line(Vector2i(int(c.w / 3.0), 0), Vector2i(int(c.w / 3.0), c.h - 1), CARD.lightened(0.18))
	Decay.stain(c, CARD.darkened(0.35), 5)
	var blanket := PixelCanvas.bowed(Rect2i(int(c.w * 0.4), 2, int(c.w * 0.55), c.h - 4), 3, 2)
	c.fill(blanket, BLANKET, 2)
	c.outline(blanket, BLANKET.darkened(0.45))
	c.outline(box, CARD.darkened(0.45))


## Standing water: a dark, irregular pool of a few lobes.
static func _puddle(c: PixelCanvas) -> void:
	var o := Vector2(c.w, c.h) * 0.5
	var lobes: Array = []
	for _i in 4:
		lobes.append([Vector2(c.rng.randf_range(-0.3, 0.3) * c.w, c.rng.randf_range(-0.25, 0.25) * c.h), c.rng.randf_range(0.3, 0.5)])
	for y in c.h:
		for x in c.w:
			for lobe: Array in lobes:
				if ((Vector2(x, y) - o - (lobe[0] as Vector2)) / (Vector2(c.w, c.h) * float(lobe[1]))).length() <= 1.0:
					c.px(x, y, WATER, 0)
					break


## A neon tube along the canvas: a white-hot core between two rows of `col` (glowing), dark end caps.
static func _tube(c: PixelCanvas, col: Color) -> void:
	var mid := int(c.h / 2.0)
	c.glowing(func() -> void:
		for x in range(1, c.w - 1):
			c.px(x, mid, Color.WHITE, 1)
			c.px(x, mid - 1, col, 1)
			c.px(x, mid + 1, col, 1))
	for x in [0, c.w - 1]:
		c.line(Vector2i(x, mid - 1), Vector2i(x, mid + 1), TUBE_END, 1)

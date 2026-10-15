extends GameTest

## A piece's neon strip (the run-down finish's `neon_ring`: a mattress, a desk, a shelf, a mirror's frame) lights the drawn
## pixels whose four neighbours `depth` px off along the axes are drawn but not all four one pixel further, reading the
## canvas's coverage bytes. This pins its drawing and its emissive marks to the plain scan that asks the canvas `covered`
## for every one of those neighbours, over silhouettes of every kind (rounded, round, bowed, holed, at the canvas's edge)
## and strip depths.

const Decay := preload("res://scenes/objects/art/decay.gd")
const SEED := 7171


func describe() -> Dictionary:
	return {
		"name": "A neon strip lights the same pixels as the plain scan",
		"description": "Decay.neon_ring draws and marks emissive the same strip as the per-pixel covered() scan.",
		"tags": ["art", "neon", "scripted"],
		"timeout": 20.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 200, 200))


func run(t: TestContext) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED
	var differing := 0
	for n in 30:
		var size := Vector2i(rng.randi_range(3, 90), rng.randi_range(3, 90))
		var seed_value := rng.randi()
		var depth := rng.randi_range(1, 3)
		var col := Color(rng.randf(), rng.randf(), rng.randf())
		var a := _silhouette(n, size, seed_value)
		var b := _silhouette(n, size, seed_value)
		Decay.neon_ring(a, depth, col, 0.55)
		b.glowing(func() -> void: _plain_ring(b, depth, col, 0.55))
		var ea := a.emissive()
		var eb := b.emissive()
		var same := a.img.get_data() == b.img.get_data() and (ea == null) == (eb == null) \
			and (ea == null or ea.get_data() == eb.get_data())
		if not same:
			differing += 1
			if differing <= 3:
				t.check(false, "silhouette %d (%v, depth %d) lights a different strip" % [n, size, depth])
	t.check(differing == 0, "%d of 30 silhouettes light the plain scan's strip" % (30 - differing))


## Silhouette `n` on a canvas of `size`: a rounded rect, an ellipse, a bowed bar or a holed slab, some running off the
## canvas's edge.
func _silhouette(n: int, size: Vector2i, seed_value: int) -> PixelCanvas:
	var c := PixelCanvas.new(size.x, size.y, seed_value, ArtConfig.light_from)
	var r := Rect2i(c.rng.randi_range(-2, 3), c.rng.randi_range(-2, 3), size.x - c.rng.randi_range(-2, 4), size.y - c.rng.randi_range(-2, 4))
	match n % 4:
		0:
			c.fill(PixelCanvas.rounded(r, c.rng.randi_range(0, 6)), Color(0.4, 0.3, 0.3), 2)
		1:
			c.fill(PixelCanvas.ellipse(r), Color(0.3, 0.4, 0.3), 2)
		2:
			c.fill(PixelCanvas.bowed(r, c.rng.randi_range(0, 5), c.rng.randi_range(0, 4)), Color(0.3, 0.3, 0.4), 2)
		3:
			c.fill(PixelCanvas.rounded(r, 2), Color(0.5, 0.4, 0.3), 2)
			for _k in c.rng.randi_range(1, 4):
				c.clear(PixelCanvas.disc(Vector2i(c.rng.randi_range(0, size.x - 1), c.rng.randi_range(0, size.y - 1)), c.rng.randi_range(1, 4)))
	return c


## The plain scan: every pixel, asking `covered` for each neighbour.
func _plain_ring(c: PixelCanvas, depth: int, col: Color, amount: float) -> void:
	var lit: Array[Vector2i] = []
	for y in c.h:
		for x in c.w:
			if not c.covered(x, y):
				continue
			var deeper := c.covered(x - depth, y) and c.covered(x + depth, y) and c.covered(x, y - depth) and c.covered(x, y + depth)
			if deeper and not (c.covered(x - depth - 1, y) and c.covered(x + depth + 1, y)
					and c.covered(x, y - depth - 1) and c.covered(x, y + depth + 1)):
				lit.append(Vector2i(x, y))
	for p in lit:
		c.img.set_pixel(p.x, p.y, c.at(p.x, p.y).lerp(col, amount))

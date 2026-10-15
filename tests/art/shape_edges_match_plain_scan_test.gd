extends GameTest

## A shape rasterized from a point test (`PixelCanvas.Shape`: `bowed`, and any other shape that is not convex along both
## axes) learns per pixel how far in from its edge it sits and the outward normal there by sweeping its mask along the eight
## steps, and hands `bevel` / `outline` only the pixels within reach of the edge. This pins its depths, normals and edge
## bands to the plain scan (every pixel, every step, the band as every inside pixel), and the bevels and outlines drawn
## through them to the same drawings, over shapes of every kind: bowed bars, blobs, rings with holes, scattered noise.

const SEED := 6161


func describe() -> Dictionary:
	return {
		"name": "Shape edges are the same as the plain scan finds",
		"description": "A point-test shape's depth, normal and edge band, and the bevel and outline drawn through them, match the plain per-pixel scan.",
		"tags": ["art", "shape", "scripted"],
		"timeout": 30.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 200, 200))


func run(t: TestContext) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED
	var shapes := 0
	var differing := 0
	for n in 48:
		var shape := _shape(n, rng)
		var plain := _plain_edges(shape)
		shapes += 1
		if not _same_edges(shape, plain) or not _same_drawings(shape, plain, rng.randi()):
			differing += 1
			if differing <= 3:
				t.check(false, "shape %d (%s, %v) differs from the plain scan" % [n, ["bowed", "blob", "ring", "noise"][n % 4], shape.bounds])
	t.check(differing == 0, "%d of %d shapes match the plain scan" % [shapes - differing, shapes])


## Shape `n`: a bowed bar, a blob of discs, a ring with a hole or scattered noise, at a random place and size.
func _shape(n: int, rng: RandomNumberGenerator) -> PixelCanvas.Shape:
	var r := Rect2i(rng.randi_range(-3, 10), rng.randi_range(-3, 10), rng.randi_range(3, 90), rng.randi_range(3, 70))
	match n % 4:
		0:
			return PixelCanvas.bowed(r, rng.randi_range(0, 6), rng.randi_range(0, 5))
		1:
			var discs: Array[Vector3i] = []
			for _k in rng.randi_range(1, 5):
				discs.append(Vector3i(rng.randi_range(r.position.x, r.end.x), rng.randi_range(r.position.y, r.end.y), rng.randi_range(2, 20)))
			return PixelCanvas.Shape.new(r, func(x: int, y: int) -> bool:
				for d in discs:
					if (x - d.x) * (x - d.x) + (y - d.y) * (y - d.y) <= d.z * d.z:
						return true
				return false)
		2:
			var c := Vector2(r.get_center())
			var outer := minf(r.size.x, r.size.y) * 0.5
			var inner := outer * rng.randf_range(0.2, 0.7)
			return PixelCanvas.Shape.new(r, func(x: int, y: int) -> bool:
				var d := Vector2(x, y).distance_to(c)
				return d <= outer and d >= inner)
	var seed_value := rng.randi()
	return PixelCanvas.Shape.new(r, func(x: int, y: int) -> bool: return hash([seed_value, x, y]) % 3 != 0)


## The plain scan: per step, how many inside pixels run on from each pixel that way (every pixel of the bounds); per
## inside pixel the nearest exit over the straight steps (diagonals where strictly sooner) and the sum of the steps
## exiting there. `{ depth, normal }` by mask index.
func _plain_edges(shape: PixelCanvas.Shape) -> Dictionary:
	var bw := shape.bounds.size.x
	var bh := shape.bounds.size.y
	var n := bw * bh
	var inside := PackedByteArray()
	inside.resize(n)
	for y in bh:
		for x in bw:
			inside[y * bw + x] = 1 if shape.has(shape.bounds.position.x + x, shape.bounds.position.y + y) else 0
	var runs: Array[PackedInt32Array] = []
	for d in PixelCanvas.Shape.STEPS:
		var walk := PackedInt32Array()
		walk.resize(n)
		var ys := range(bh - 1, -1, -1) if d.y > 0 else range(bh)
		var xs := range(bw - 1, -1, -1) if d.x > 0 else range(bw)
		for y in ys:
			for x in xs:
				var qx: int = x + d.x
				var qy: int = y + d.y
				if qx >= 0 and qy >= 0 and qx < bw and qy < bh and inside[qy * bw + qx] == 1:
					walk[y * bw + x] = walk[qy * bw + qx] + 1
		runs.append(walk)
	var depth := PackedInt32Array()
	depth.resize(n)
	var normal := PackedVector2Array()
	normal.resize(n)
	for i in n:
		if inside[i] == 0:
			continue
		var k := 1 << 30
		for s in 4:
			k = mini(k, runs[s][i] + 1)
		var first := 0
		var k_diag := 1 << 30
		for s in range(4, 8):
			k_diag = mini(k_diag, runs[s][i] + 1)
		if k_diag < k:
			k = k_diag
			first = 4
		var sum := Vector2.ZERO
		for s in range(first, first + 4):
			if runs[s][i] + 1 == k:
				sum += Vector2(PixelCanvas.Shape.STEPS[s])
		depth[i] = mini(k, 255)
		normal[i] = sum.normalized()
	return { "depth": depth, "normal": normal }


## Whether every pixel of the bounds (and a ring round them) has the plain depth and normal, and each edge band (1 to 4 px)
## lists exactly the inside pixels the plain depth puts within it, each once.
func _same_edges(shape: PixelCanvas.Shape, plain: Dictionary) -> bool:
	var b := shape.bounds
	for y in range(b.position.y - 1, b.end.y + 1):
		for x in range(b.position.x - 1, b.end.x + 1):
			var inside := b.has_point(Vector2i(x, y))
			var i := (y - b.position.y) * b.size.x + (x - b.position.x)
			var want_depth: int = plain["depth"][i] if inside else 0
			var want_normal: Vector2 = plain["normal"][i] if inside else Vector2.ZERO
			if shape.depth(x, y) != want_depth or not shape.normal(x, y).is_equal_approx(want_normal):
				return false
	for k in range(1, 5):
		var listed := {}
		var pts := shape.edge_pixels(k)
		for j in range(0, pts.size(), 2):
			var p := Vector2i(pts[j], pts[j + 1])
			if listed.has(p):
				return false
			listed[p] = true
		var want := 0
		for i in (plain["depth"] as PackedInt32Array).size():
			var d: int = plain["depth"][i]
			if d != 0 and d <= k:
				want += 1
				var p := Vector2i(b.position.x + i % b.size.x, b.position.y + int(i / float(b.size.x)))
				if not listed.has(p):
					return false
		if want != listed.size():
			return false
	return true


## Whether `bevel`, `bevel_relative`, `outline` and `outline_relative` through the shape paint what the plain scan's depths
## and normals paint, every inside pixel visited, on a canvas filled with noise.
func _same_drawings(shape: PixelCanvas.Shape, plain: Dictionary, seed_value: int) -> bool:
	var size := shape.bounds.end + Vector2i(4, 4)
	var a := _noise_canvas(size, seed_value)
	var b := _noise_canvas(size, seed_value)
	a.bevel(shape, 1, 2, Color.WHITE, Color.BLACK)
	a.bevel_relative(shape, 1, 3, 0.2, 0.3)
	a.outline_relative(shape, 0.25)
	a.outline(shape, Color.RED)
	_plain_draw(b, shape, plain)
	return a.img.get_data() == b.img.get_data()


func _noise_canvas(size: Vector2i, seed_value: int) -> PixelCanvas:
	var c := PixelCanvas.new(size.x, size.y, seed_value, ArtConfig.light_from)
	for y in c.h:
		for x in c.w:
			c.img.set_pixel(x, y, Color(c.rng.randf(), c.rng.randf(), c.rng.randf(), 1.0))
	return c


## The four drawings, each over every inside pixel with the plain depth and normal.
func _plain_draw(c: PixelCanvas, shape: PixelCanvas.Shape, plain: Dictionary) -> void:
	var b := shape.bounds
	var steps: Array[Callable] = [
		func(x: int, y: int, k: int, d: float) -> void:
			if k >= 1 and k <= 2:
				if d > 0.3:
					c.img.set_pixel(x, y, Color.WHITE)
				elif d < -0.3:
					c.img.set_pixel(x, y, Color.BLACK),
		func(x: int, y: int, k: int, d: float) -> void:
			if k >= 1 and k <= 3:
				if d > 0.3:
					c.img.set_pixel(x, y, c.img.get_pixel(x, y).lightened(0.2))
				elif d < -0.3:
					c.img.set_pixel(x, y, c.img.get_pixel(x, y).darkened(0.3)),
		func(x: int, y: int, k: int, _d: float) -> void:
			if k == 1:
				c.img.set_pixel(x, y, c.img.get_pixel(x, y).darkened(0.25)),
		func(x: int, y: int, k: int, _d: float) -> void:
			if k == 1:
				c.img.set_pixel(x, y, Color.RED),
	]
	for step in steps:
		for ly in b.size.y:
			for lx in b.size.x:
				var i := ly * b.size.x + lx
				var k: int = plain["depth"][i]
				var x := b.position.x + lx
				var y := b.position.y + ly
				if k == 0 or not c.has(x, y):
					continue
				step.call(x, y, k, (plain["normal"][i] as Vector2).dot(c.light))

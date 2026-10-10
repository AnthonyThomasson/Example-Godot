extends RefCounted

## Pixel-art drawing surface for the furniture painters (Objects domain, private): an RGBA8
## Image at art resolution plus a per-pixel height map, and the primitives the painters compose —
## filled shapes, light-aware bevels, outlines, cast shadows, fabric speckle and wood grain.
## Coordinates are integer art pixels; writes outside the image are ignored. Rect-based texture
## primitives touch only pixels already drawn, so texture never spills past a piece's silhouette.

const CLEAR := Color(0.0, 0.0, 0.0, 0.0)


## A pixel region: its bounding rect and a point test, rasterized once into a mask. Built by
## rounded() / bowed(). Also answers, per inside pixel, how far in from the edge it sits and
## the outward edge normal there (computed once, on first use, for the bevel/outline passes).
class Shape:
	## Straight steps first, then diagonals: a diagonal only decides the edge where no straight
	## step reaches it as soon (the rounded corners).
	const STEPS: Array[Vector2i] = [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN,
			Vector2i(-1, -1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(1, 1)]

	var bounds: Rect2i
	var _mask := PackedByteArray()
	var _depth := PackedByteArray()      ## Steps to the first outside pixel (1 = edge ring); 0 outside.
	var _normal := PackedVector2Array()  ## Outward edge normal at that depth.

	func _init(rect: Rect2i, test: Callable) -> void:
		bounds = rect
		_mask.resize(maxi(rect.get_area(), 0))
		for y in rect.size.y:
			for x in rect.size.x:
				_mask[y * rect.size.x + x] = 1 if test.call(rect.position.x + x, rect.position.y + y) else 0

	## True if (x, y) is inside the shape.
	func has(x: int, y: int) -> bool:
		var lx := x - bounds.position.x
		var ly := y - bounds.position.y
		if lx < 0 or ly < 0 or lx >= bounds.size.x or ly >= bounds.size.y:
			return false
		return _mask[ly * bounds.size.x + lx] == 1

	## How many steps in from the edge (x, y) sits (1 = the edge ring), or 0 if outside.
	func depth(x: int, y: int) -> int:
		if _depth.is_empty():
			_build_edges()
		return _depth[_index(x, y)] if has(x, y) else 0

	## The outward edge normal nearest (x, y) (unit; ZERO outside).
	func normal(x: int, y: int) -> Vector2:
		if _depth.is_empty():
			_build_edges()
		return _normal[_index(x, y)] if has(x, y) else Vector2.ZERO

	## Mask index of (x, y), which must lie inside the bounds.
	func _index(x: int, y: int) -> int:
		return (y - bounds.position.y) * bounds.size.x + (x - bounds.position.x)

	## For each step direction, sweep the mask so each pixel learns how many inside pixels run
	## on from it in that direction; the first outside pixel is one past that run. A pixel's
	## depth is the nearest such exit over the straight steps (diagonals only where they reach
	## the edge strictly sooner), and its normal is the sum of the directions exiting there.
	func _build_edges() -> void:
		var bw := bounds.size.x
		var bh := bounds.size.y
		var n := bw * bh
		var runs: Array[PackedInt32Array] = []
		for d in STEPS:
			var run := PackedInt32Array()
			run.resize(n)
			var ys := range(bh - 1, -1, -1) if d.y > 0 else range(bh)
			var xs := range(bw - 1, -1, -1) if d.x > 0 else range(bw)
			for y in ys:
				for x in xs:
					var qx: int = x + d.x
					var qy: int = y + d.y
					if qx >= 0 and qy >= 0 and qx < bw and qy < bh and _mask[qy * bw + qx] == 1:
						run[y * bw + x] = run[qy * bw + qx] + 1
			runs.append(run)
		_depth.resize(n)
		_normal.resize(n)
		for i in n:
			if _mask[i] == 0:
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
					sum += Vector2(STEPS[s])
			_depth[i] = mini(k, 255)
			_normal[i] = sum.normalized()


var img: Image  ## The art, at art resolution.
var w: int  ## Image width (art px).
var h: int  ## Image height (art px).
var rng := RandomNumberGenerator.new()  ## Seeded per texture, so a piece paints identically every time.
## Direction the light comes FROM, in this canvas's frame (normalized).
var light: Vector2
## Height above the floor per pixel, set by the painters; drives cast_shadows().
var _height := PackedByteArray()


func _init(width: int, height: int, seed_value: int, light_from: Vector2) -> void:
	w = maxi(width, 1)
	h = maxi(height, 1)
	img = Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(CLEAR)
	_height.resize(w * h)
	rng.seed = seed_value
	light = light_from.normalized()


## Shade ramp around a base color, from the outline (darkest) to the highlight.
static func tones(base: Color) -> Dictionary:
	return {
		"outline": base.darkened(ObjectArtConfig.tone_outline),
		"shadow": base.darkened(ObjectArtConfig.tone_shadow),
		"dark": base.darkened(ObjectArtConfig.tone_dark),
		"base": base,
		"light": base.lightened(ObjectArtConfig.tone_light),
		"highlight": base.lightened(ObjectArtConfig.tone_highlight),
	}


## `r` with its corners rounded to `radius`.
static func rounded(r: Rect2i, radius: int) -> Shape:
	return Shape.new(r, func(x: int, y: int) -> bool: return _in_rounded(r, radius, x, y))


## A rounded bar across `r` whose ends sag `bow` px toward +y (a curved chair rail); its
## thickness is r.size.y - bow.
static func bowed(r: Rect2i, radius: int, bow: int) -> Shape:
	var bar := Rect2i(r.position, Vector2i(r.size.x, maxi(1, r.size.y - bow)))
	var half := maxf(1.0, (r.size.x - 1) * 0.5)
	var test := func(x: int, y: int) -> bool:
		var t := (x - r.position.x - half) / half
		return _in_rounded(bar, radius, x, y - roundi(bow * t * t))
	return Shape.new(r, test)


## True if (x, y) lies inside `r` with its corners rounded to `radius`.
static func _in_rounded(r: Rect2i, radius: int, x: int, y: int) -> bool:
	if x < r.position.x or y < r.position.y or x >= r.end.x or y >= r.end.y:
		return false
	var rad := mini(radius, mini(r.size.x, r.size.y) / 2)
	if rad <= 0:
		return true
	var dx := x - clampi(x, r.position.x + rad, r.end.x - 1 - rad)
	var dy := y - clampi(y, r.position.y + rad, r.end.y - 1 - rad)
	return dx * dx + dy * dy <= rad * rad + rad


## True if (x, y) is on the image.
func has(x: int, y: int) -> bool:
	return x >= 0 and y >= 0 and x < w and y < h


## The pixel at (x, y), or CLEAR off the image.
func at(x: int, y: int) -> Color:
	return img.get_pixel(x, y) if has(x, y) else CLEAR


## Set the pixel at (x, y) (ignored off the image).
func px(x: int, y: int, c: Color) -> void:
	if has(x, y):
		img.set_pixel(x, y, c)


## Fill a shape; a non-negative `height` also raises those pixels.
func fill(s: Shape, c: Color, height: int = -1) -> void:
	for y in range(s.bounds.position.y, s.bounds.end.y):
		for x in range(s.bounds.position.x, s.bounds.end.x):
			if has(x, y) and s.has(x, y):
				img.set_pixel(x, y, c)
				if height >= 0:
					_height[y * w + x] = height


## Recolor the already-drawn pixels of `r`.
func paint_over(r: Rect2i, c: Color) -> void:
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			if at(x, y).a > 0.0:
				img.set_pixel(x, y, c)


## Shade the rings `from_k`..`to_k` in from a shape's edge: edges facing the light take `lit`,
## edges facing away take `unlit` (swap them for a recess). Side-on edges are left alone.
func bevel(s: Shape, from_k: int, to_k: int, lit: Color, unlit: Color) -> void:
	for y in range(s.bounds.position.y, s.bounds.end.y):
		for x in range(s.bounds.position.x, s.bounds.end.x):
			var k := s.depth(x, y)
			if k < from_k or k > to_k or not has(x, y):
				continue
			var d := s.normal(x, y).dot(light)
			if d > 0.3:
				img.set_pixel(x, y, lit)
			elif d < -0.3:
				img.set_pixel(x, y, unlit)


## A 1px ring just inside a shape's edge.
func outline(s: Shape, c: Color) -> void:
	for y in range(s.bounds.position.y, s.bounds.end.y):
		for x in range(s.bounds.position.x, s.bounds.end.x):
			if s.depth(x, y) == 1 and has(x, y):
				img.set_pixel(x, y, c)


## Nudge a fraction of the pixels of exactly color `base` a shade lighter or darker.
func speckle(r: Rect2i, base: Color, density: float, amount: float = 0.07) -> void:
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			if rng.randf() < density and at(x, y).is_equal_approx(base):
				img.set_pixel(x, y, base.lightened(amount) if rng.randf() < 0.5 else base.darkened(amount))


## Wood grain over the drawn pixels of shape `s`: long, gently wandering streaks running along x
## (or y), each a dark line with the odd pale fleck beside it.
func grain(s: Shape, along_x: bool, density: float, dark: Color, pale: Color) -> void:
	var r := s.bounds
	var length := r.size.x if along_x else r.size.y
	var across := r.size.y if along_x else r.size.x
	if length < 2 or across < 1:
		return
	var streaks := maxi(1, roundi(r.get_area() * density))
	for _s in streaks:
		var a := rng.randi_range(0, across - 1)
		var run := rng.randi_range(maxi(2, length * 4 / 10), maxi(2, length))
		var start := rng.randi_range(0, maxi(0, length - run))
		for i in run:
			if rng.randf() < 0.05:
				a = clampi(a + (1 if rng.randf() < 0.5 else -1), 0, across - 1)
			var p := _grain_point(r, along_x, start + i, a)
			if s.has(p.x, p.y) and at(p.x, p.y).a > 0.0:
				img.set_pixel(p.x, p.y, dark)
			if a + 1 < across and rng.randf() < 0.08:
				var q := _grain_point(r, along_x, start + i, a + 1)
				if s.has(q.x, q.y) and at(q.x, q.y).a > 0.0:
					img.set_pixel(q.x, q.y, pale)


## Image point `along`/`across` a grain rect's axes.
static func _grain_point(r: Rect2i, along_x: bool, along: int, across: int) -> Vector2i:
	return r.position + (Vector2i(along, across) if along_x else Vector2i(across, along))


## A wood knot centred on (x, y): a dark heart in a ring of grain.
func knot(x: int, y: int, heart: Color, ring: Color) -> void:
	for p in [Vector2i(-2, 0), Vector2i(2, 0), Vector2i(-1, -1), Vector2i(0, -1), Vector2i(1, -1),
			Vector2i(-1, 1), Vector2i(0, 1), Vector2i(1, 1)]:
		if at(x + p.x, y + p.y).a > 0.0:
			img.set_pixel(x + p.x, y + p.y, ring)
	for dx in [-1, 0, 1]:
		if at(x + dx, y).a > 0.0:
			img.set_pixel(x + dx, y, heart)


## Darken each drawn pixel that a taller neighbour, toward the light, overshadows: a part `k` px
## toward the light that stands at least `k` higher shades it (up to cast_shadow_px away).
func cast_shadows() -> void:
	var step := Vector2i(roundi(light.x), roundi(light.y))
	if step == Vector2i.ZERO:
		return
	var reach := maxi(0, ObjectArtConfig.cast_shadow_px)
	var shaded := PackedByteArray()
	shaded.resize(w * h)
	for y in h:
		for x in w:
			var own := _height[y * w + x]
			for k in range(1, reach + 1):
				var q := Vector2i(x, y) + step * k
				if has(q.x, q.y) and at(q.x, q.y).a > 0.0 and _height[q.y * w + q.x] >= own + k:
					shaded[y * w + x] = 1
					break
	for y in h:
		for x in w:
			if shaded[y * w + x] == 1 and at(x, y).a > 0.0:
				img.set_pixel(x, y, at(x, y).darkened(ObjectArtConfig.cast_shadow_darken))

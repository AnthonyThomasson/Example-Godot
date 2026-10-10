extends RefCounted

## Pixel-art drawing surface for the object painters (Objects domain, private): an RGBA8 Image at
## art resolution plus coverage and height layers, and the primitives the painters compose —
## filled shapes, light-aware bevels, outlines, lines, cast shadows and material surface finishes
## (wood grain, brushed metal, stone flecks, glaze glare, fabric weave). Coordinates are integer
## art pixels; writes outside the image are ignored. Texture primitives touch only drawn pixels,
## so they never spill past a piece's silhouette. Fills run as native row spans and bevels visit
## only a shape's edge band, so large pieces stay cheap to paint.

const CLEAR := Color(0.0, 0.0, 0.0, 0.0)
const _ON := Color(1.0, 0.0, 0.0)  ## Coverage-layer value for a drawn pixel.


## A pixel region rasterized from a point test into a mask (any shape, e.g. bowed()). Answers
## membership, its row spans (for filling), and per pixel how far in from the edge it sits and the
## outward normal there — from run lengths along the axes and diagonals, built on first use.
class Shape:
	## Straight steps first, then diagonals: a diagonal only decides the edge where no straight
	## step reaches it as soon (rounded corners).
	const STEPS: Array[Vector2i] = [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN,
			Vector2i(-1, -1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(1, 1)]

	var bounds: Rect2i  ## Bounding rect (absolute art px).
	var _mask := PackedByteArray()       ## 1 per inside pixel of `bounds`.
	var _depth := PackedByteArray()      ## Steps to the first outside pixel (1 = edge ring); 0 outside.
	var _normal := PackedVector2Array()  ## Outward edge normal at that depth.

	func _init(rect: Rect2i, test: Callable = Callable()) -> void:
		bounds = rect
		if not test.is_valid():
			return
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

	## The inside runs of each row, as flat [y, x0, x1) triples.
	func spans() -> PackedInt32Array:
		var out := PackedInt32Array()
		var bw := bounds.size.x
		for ly in bounds.size.y:
			var x := 0
			while x < bw:
				if _mask[ly * bw + x] == 0:
					x += 1
					continue
				var x0 := x
				while x < bw and _mask[ly * bw + x] == 1:
					x += 1
				out.append_array([bounds.position.y + ly, bounds.position.x + x0, bounds.position.x + x])
		return out

	## Candidate pixels within `k` of the edge, as flat [x, y] pairs (every inside pixel here;
	## callers re-check depth).
	func edge_pixels(_k: int) -> PackedInt32Array:
		var out := PackedInt32Array()
		var sp := spans()
		for i in range(0, sp.size(), 3):
			for x in range(sp[i + 1], sp[i + 2]):
				out.append_array([x, sp[i]])
		return out

	## Mask index of (x, y), which must lie inside the bounds.
	func _index(x: int, y: int) -> int:
		return (y - bounds.position.y) * bounds.size.x + (x - bounds.position.x)

	## Per step direction, sweep the mask so each pixel learns how many inside pixels run on from
	## it that way; the first outside pixel is one past that run. Depth is the nearest exit over
	## the straight steps (diagonals only where strictly sooner); the normal sums the exiting steps.
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


## A shape convex along both axes (rounded rects, ellipses), kept as one span per row and per
## column. Membership, depth (the nearest of the four axis exits) and normal are O(1), and the
## edge band is enumerated directly from the span ends.
class ConvexShape extends Shape:
	var _x0 := PackedInt32Array()  ## Per row: first inside x (absolute); an empty row has x1 <= x0.
	var _x1 := PackedInt32Array()  ## Per row: one past the last inside x.
	var _y0 := PackedInt32Array()  ## Per column: first inside y (absolute).
	var _y1 := PackedInt32Array()  ## Per column: one past the last inside y.

	func _init(rect: Rect2i, x0: PackedInt32Array, x1: PackedInt32Array, y0: PackedInt32Array,
			y1: PackedInt32Array) -> void:
		super(rect)
		_x0 = x0
		_x1 = x1
		_y0 = y0
		_y1 = y1

	## True if (x, y) is inside the shape.
	func has(x: int, y: int) -> bool:
		var ly := y - bounds.position.y
		if ly < 0 or ly >= bounds.size.y:
			return false
		return x >= _x0[ly] and x < _x1[ly]

	## How many steps in from the edge (x, y) sits (1 = the edge ring), or 0 if outside.
	func depth(x: int, y: int) -> int:
		if not has(x, y):
			return 0
		var ly := y - bounds.position.y
		var lx := x - bounds.position.x
		var m := mini(mini(x - _x0[ly], _x1[ly] - 1 - x), mini(y - _y0[lx], _y1[lx] - 1 - y))
		return maxi(1, m + 1)

	## The outward edge normal nearest (x, y): the sum of the axis directions exiting soonest.
	func normal(x: int, y: int) -> Vector2:
		if not has(x, y):
			return Vector2.ZERO
		var ly := y - bounds.position.y
		var lx := x - bounds.position.x
		var d := [x - _x0[ly], _x1[ly] - 1 - x, y - _y0[lx], _y1[lx] - 1 - y]
		var m: int = mini(mini(d[0], d[1]), mini(d[2], d[3]))
		var sum := Vector2.ZERO
		for i in 4:
			if d[i] == m:
				sum += Vector2(STEPS[i])
		return sum.normalized()

	## The inside run of each row, as flat [y, x0, x1) triples.
	func spans() -> PackedInt32Array:
		var out := PackedInt32Array()
		for ly in bounds.size.y:
			if _x1[ly] > _x0[ly]:
				out.append_array([bounds.position.y + ly, _x0[ly], _x1[ly]])
		return out

	## Pixels within `k` of a row end or a column end (each listed once), as flat [x, y] pairs.
	func edge_pixels(k: int) -> PackedInt32Array:
		var out := PackedInt32Array()
		for ly in bounds.size.y:
			var a := _x0[ly]
			var b := _x1[ly]
			if b <= a:
				continue
			var y := bounds.position.y + ly
			var left_end := mini(a + k, b)
			for x in range(a, left_end):
				out.append_array([x, y])
			for x in range(maxi(b - k, left_end), b):
				out.append_array([x, y])
		for lx in bounds.size.x:
			var a := _y0[lx]
			var b := _y1[lx]
			if b <= a:
				continue
			var x := bounds.position.x + lx
			var top_end := mini(a + k, b)
			for y in range(a, top_end) + range(maxi(b - k, top_end), b):
				if not has(x, y):
					continue
				var ly: int = y - bounds.position.y
				if x - _x0[ly] < k or _x1[ly] - 1 - x < k:
					continue  # The row pass already listed it.
				out.append_array([x, y])
		return out


var img: Image  ## The art, at art resolution.
var w: int  ## Image width (art px).
var h: int  ## Image height (art px).
var rng := RandomNumberGenerator.new()  ## Seeded per texture, so a piece paints identically every time.
## Direction the light comes FROM, in this canvas's frame (normalized).
var light: Vector2
var _cov: Image  ## Coverage layer (R8): non-zero where something is drawn.
var _hgt: Image  ## Height layer (R8): height above the floor per pixel; drives cast_shadows().
var _cov_bytes := PackedByteArray()  ## Snapshot of _cov for fast reads; refreshed when stale.
var _cov_stale := true  ## Whether _cov changed since the snapshot.


func _init(width: int, height: int, seed_value: int, light_from: Vector2) -> void:
	w = maxi(width, 1)
	h = maxi(height, 1)
	img = Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(CLEAR)
	_cov = Image.create(w, h, false, Image.FORMAT_R8)
	_hgt = Image.create(w, h, false, Image.FORMAT_R8)
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


# --- Shapes ----------------------------------------------------------------------------

## `r` with its corners rounded to `radius` (0 = a plain rect).
static func rounded(r: Rect2i, radius: int) -> Shape:
	var rad := clampi(radius, 0, mini(r.size.x, r.size.y) / 2)
	var x0 := PackedInt32Array()
	var x1 := PackedInt32Array()
	var y0 := PackedInt32Array()
	var y1 := PackedInt32Array()
	for ly in r.size.y:
		var cut := _corner_cut(ly, r.size.y, rad)
		x0.append(r.position.x + cut if cut >= 0 else 0)
		x1.append(r.end.x - cut if cut >= 0 else 0)
	for lx in r.size.x:
		var cut := _corner_cut(lx, r.size.x, rad)
		y0.append(r.position.y + cut if cut >= 0 else 0)
		y1.append(r.end.y - cut if cut >= 0 else 0)
	return ConvexShape.new(r, x0, x1, y0, y1)


## How many px a rounded corner trims from each end of line `i` of `n` (rows or columns), or -1
## if the line is wholly outside. Inside means dx² + dy² ≤ rad² + rad from the corner centre.
static func _corner_cut(i: int, n: int, rad: int) -> int:
	if rad <= 0:
		return 0
	var d := i - clampi(i, rad, n - 1 - rad)
	if d == 0:
		return 0
	var allowance := rad * rad + rad - d * d
	if allowance < 0:
		return -1
	return maxi(0, rad - floori(sqrt(float(allowance))))


## The ellipse inscribed in `r`.
static func ellipse(r: Rect2i) -> Shape:
	var x0 := PackedInt32Array()
	var x1 := PackedInt32Array()
	var y0 := PackedInt32Array()
	var y1 := PackedInt32Array()
	for ly in r.size.y:
		var half := _ellipse_half(ly, r.size.y, r.size.x)
		x0.append(r.position.x + roundi(r.size.x * 0.5 - half))
		x1.append(r.position.x + roundi(r.size.x * 0.5 + half))
	for lx in r.size.x:
		var half := _ellipse_half(lx, r.size.x, r.size.y)
		y0.append(r.position.y + roundi(r.size.y * 0.5 - half))
		y1.append(r.position.y + roundi(r.size.y * 0.5 + half))
	return ConvexShape.new(r, x0, x1, y0, y1)


## Half the chord of an ellipse (`span` across, `n` lines along) through line `i`'s centre.
static func _ellipse_half(i: int, n: int, span: int) -> float:
	var v := (i + 0.5 - n * 0.5) / (n * 0.5)
	return 0.0 if absf(v) >= 1.0 else span * 0.5 * sqrt(1.0 - v * v)


## A circle of `radius` centred on `c`.
static func disc(c: Vector2i, radius: int) -> Shape:
	return ellipse(Rect2i(c - Vector2i(radius, radius), Vector2i(radius * 2 + 1, radius * 2 + 1)))


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


# --- Pixels ----------------------------------------------------------------------------

## True if (x, y) is on the image.
func has(x: int, y: int) -> bool:
	return x >= 0 and y >= 0 and x < w and y < h


## The pixel at (x, y), or CLEAR off the image.
func at(x: int, y: int) -> Color:
	return img.get_pixel(x, y) if has(x, y) else CLEAR


## True if something is drawn at (x, y).
func covered(x: int, y: int) -> bool:
	if not has(x, y):
		return false
	if _cov_stale:
		_cov_bytes = _cov.get_data()
		_cov_stale = false
	return _cov_bytes[y * w + x] != 0


## Set the pixel at (x, y) (ignored off the image); a non-negative `height` also raises it.
func px(x: int, y: int, c: Color, height: int = -1) -> void:
	if not has(x, y):
		return
	img.set_pixel(x, y, c)
	_cov.set_pixel(x, y, _ON if c.a > 0.0 else CLEAR)
	_cov_stale = true
	if height >= 0:
		_hgt.set_pixel(x, y, _height_color(height))


## Fill a shape; a non-negative `height` also raises those pixels.
func fill(s: Shape, c: Color, height: int = -1) -> void:
	var sp := s.spans()
	var image := Rect2i(0, 0, w, h)
	var hc := _height_color(height)
	for i in range(0, sp.size(), 3):
		var r := Rect2i(sp[i + 1], sp[i], sp[i + 2] - sp[i + 1], 1).intersection(image)
		if r.size.x <= 0 or r.size.y <= 0:
			continue
		img.fill_rect(r, c)
		_cov.fill_rect(r, _ON if c.a > 0.0 else CLEAR)
		if height >= 0:
			_hgt.fill_rect(r, hc)
	_cov_stale = true


## Erase a shape back to transparent floor (gaps between slats, cut-outs).
func clear(s: Shape) -> void:
	fill(s, CLEAR, 0)


## Recolor the already-drawn pixels of `r`.
func paint_over(r: Rect2i, c: Color) -> void:
	var rr := r.intersection(Rect2i(0, 0, w, h))
	if rr.size.x <= 0 or rr.size.y <= 0:
		return
	var solid := Image.create(rr.size.x, rr.size.y, false, Image.FORMAT_RGBA8)
	solid.fill(c)
	img.blit_rect_mask(solid, img.get_region(rr), Rect2i(Vector2i.ZERO, rr.size), rr.position)


## A 1px line from `a` to `b` (Bresenham).
func line(a: Vector2i, b: Vector2i, c: Color, height: int = -1) -> void:
	var d := (b - a).abs()
	var sx := 1 if a.x < b.x else -1
	var sy := 1 if a.y < b.y else -1
	var err := d.x - d.y
	var p := a
	while true:
		px(p.x, p.y, c, height)
		if p == b:
			break
		var e2 := err * 2
		if e2 > -d.y:
			err -= d.y
			p.x += sx
		if e2 < d.x:
			err += d.x
			p.y += sy


# --- Shading ---------------------------------------------------------------------------

## Shade the rings `from_k`..`to_k` in from a shape's edge: edges facing the light take `lit`,
## edges facing away take `unlit` (swap them for a recess). Side-on edges are left alone.
func bevel(s: Shape, from_k: int, to_k: int, lit: Color, unlit: Color) -> void:
	var pts := s.edge_pixels(to_k)
	for i in range(0, pts.size(), 2):
		var x := pts[i]
		var y := pts[i + 1]
		if not has(x, y):
			continue
		var k := s.depth(x, y)
		if k < from_k or k > to_k:
			continue
		var d := s.normal(x, y).dot(light)
		if d > 0.3:
			img.set_pixel(x, y, lit)
		elif d < -0.3:
			img.set_pixel(x, y, unlit)


## A 1px ring just inside a shape's edge.
func outline(s: Shape, c: Color) -> void:
	var pts := s.edge_pixels(1)
	for i in range(0, pts.size(), 2):
		var x := pts[i]
		var y := pts[i + 1]
		if has(x, y) and s.depth(x, y) == 1:
			img.set_pixel(x, y, c)


## Darken each drawn pixel that a taller neighbour, toward the light, overshadows: a part `k` px
## toward the light that stands at least `k` higher shades it (up to cast_shadow_px away).
func cast_shadows() -> void:
	var step := Vector2i(roundi(light.x), roundi(light.y))
	var reach := maxi(0, ObjectArtConfig.cast_shadow_px)
	if step == Vector2i.ZERO or reach == 0:
		return
	var hb := _hgt.get_data()
	covered(0, 0)  # Refresh the coverage snapshot.
	var shade := ObjectArtConfig.cast_shadow_darken
	for y in h:
		for x in w:
			var i := y * w + x
			if _cov_bytes[i] == 0:
				continue
			var own := hb[i]
			for k in range(1, reach + 1):
				var qx := x + step.x * k
				var qy := y + step.y * k
				if qx < 0 or qy < 0 or qx >= w or qy >= h:
					break
				var j := qy * w + qx
				if _cov_bytes[j] != 0 and hb[j] >= own + k:
					img.set_pixel(x, y, img.get_pixel(x, y).darkened(shade))
					break


## A soft glare: short diagonal streaks of `glint` near the lit corner of `s` (glaze, glass).
func glare(s: Shape, glint: Color, streaks: int = 2) -> void:
	var r := s.bounds
	var corner := Vector2(r.position) + Vector2(r.size) * (Vector2(0.5, 0.5) + light * 0.32)
	var along := Vector2(light.y, -light.x)  # Across the light: streaks run perpendicular to it.
	var length := mini(r.size.x, r.size.y) * 0.35
	for i in streaks:
		var off := -light * (i * 3.0)
		var a := Vector2i((corner + off - along * length * 0.5).round())
		var b := Vector2i((corner + off + along * length * (0.5 - i * 0.2)).round())
		_line_inside(s, a, b, glint)


## A line clipped to shape `s`.
func _line_inside(s: Shape, a: Vector2i, b: Vector2i, c: Color) -> void:
	var d := (b - a).abs()
	var sx := 1 if a.x < b.x else -1
	var sy := 1 if a.y < b.y else -1
	var err := d.x - d.y
	var p := a
	while true:
		if s.has(p.x, p.y) and has(p.x, p.y):
			img.set_pixel(p.x, p.y, c)
		if p == b:
			break
		var e2 := err * 2
		if e2 > -d.y:
			err -= d.y
			p.x += sx
		if e2 < d.x:
			err += d.x
			p.y += sy


# --- Surface finishes ------------------------------------------------------------------

## Texture a freshly filled shape (still in `base`) by its material: wood grain, brushed metal,
## stone flecks, glaze or glass glare, fabric weave or a faint plastic grain. `along_x` runs grain
## and brushing along x; `wrap` makes them wrap at the image edges (seamless tiles).
func surface(s: Shape, material: String, base: Color, along_x: bool = true, wrap: bool = false) -> void:
	match material:
		"wood":
			grain(s, along_x, ObjectArtConfig.wood_grain_density, base.darkened(0.12), base.lightened(0.07), wrap)
		"metal":
			grain(s, along_x, ObjectArtConfig.metal_brush_density, base.lightened(0.07), base.darkened(0.05), wrap)
		"stone":
			speckle(s.bounds, base, ObjectArtConfig.stone_fleck_density, 0.16)
			speckle(s.bounds, base, ObjectArtConfig.stone_fleck_density * 0.5, 0.3)
		"ceramic":
			speckle(s.bounds, base, 0.02, 0.03)
			glare(s, base.lightened(0.45), 2)
		"glass":
			glare(s, base.lightened(0.55), 3)
		"fabric":
			speckle(s.bounds, base, ObjectArtConfig.fabric_speckle)
		"plastic", "electronics":
			speckle(s.bounds, base, 0.04, 0.04)


## Nudge a sample of the pixels of exactly color `base` in `r` a shade lighter or darker.
func speckle(r: Rect2i, base: Color, density: float, amount: float = 0.07) -> void:
	var rr := r.intersection(Rect2i(0, 0, w, h))
	if rr.size.x <= 0 or rr.size.y <= 0:
		return
	for _i in roundi(rr.get_area() * density):
		var x := rr.position.x + rng.randi_range(0, rr.size.x - 1)
		var y := rr.position.y + rng.randi_range(0, rr.size.y - 1)
		if _same(img.get_pixel(x, y), base):
			img.set_pixel(x, y, base.lightened(amount) if rng.randf() < 0.5 else base.darkened(amount))


## True if a stored (8-bit) pixel holds `col`, allowing for the rounding the image applied.
static func _same(stored: Color, col: Color) -> bool:
	const TOLERANCE := 1.5 / 255.0
	return absf(stored.r - col.r) < TOLERANCE and absf(stored.g - col.g) < TOLERANCE \
			and absf(stored.b - col.b) < TOLERANCE and absf(stored.a - col.a) < TOLERANCE


## Wood grain over the drawn pixels of shape `s`: long, gently wandering streaks running along x
## (or y), each a dark line with the odd pale fleck beside it. `wrap` continues a streak past the
## far end back at the near end, so a tile repeats seamlessly.
func grain(s: Shape, along_x: bool, density: float, dark: Color, pale: Color, wrap: bool = false) -> void:
	var r := s.bounds
	var length := r.size.x if along_x else r.size.y
	var across := r.size.y if along_x else r.size.x
	if length < 2 or across < 1:
		return
	covered(0, 0)  # Refresh the coverage snapshot.
	var streaks := maxi(1, roundi(r.get_area() * density))
	for _s in streaks:
		var a := rng.randi_range(0, across - 1)
		var run := rng.randi_range(maxi(2, length * 4 / 10), maxi(2, length))
		var start := rng.randi_range(0, length - 1) if wrap else rng.randi_range(0, maxi(0, length - run))
		for i in run:
			if rng.randf() < 0.05:
				a = clampi(a + (1 if rng.randf() < 0.5 else -1), 0, across - 1)
			var along := (start + i) % length if wrap else start + i
			var p := _grain_point(r, along_x, along, a)
			if s.has(p.x, p.y) and _drawn(p):
				img.set_pixel(p.x, p.y, dark)
			if a + 1 < across and rng.randf() < 0.08:
				var q := _grain_point(r, along_x, along, a + 1)
				if s.has(q.x, q.y) and _drawn(q):
					img.set_pixel(q.x, q.y, pale)


## Image point `along`/`across` a grain rect's axes.
static func _grain_point(r: Rect2i, along_x: bool, along: int, across: int) -> Vector2i:
	return r.position + (Vector2i(along, across) if along_x else Vector2i(across, along))


## Coverage at `p` from the current snapshot (callers refresh it first).
func _drawn(p: Vector2i) -> bool:
	return p.x >= 0 and p.y >= 0 and p.x < w and p.y < h and _cov_bytes[p.y * w + p.x] != 0


## A wood knot centred on (x, y): a dark heart in a ring of grain.
func knot(x: int, y: int, heart: Color, ring: Color) -> void:
	for p in [Vector2i(-2, 0), Vector2i(2, 0), Vector2i(-1, -1), Vector2i(0, -1), Vector2i(1, -1),
			Vector2i(-1, 1), Vector2i(0, 1), Vector2i(1, 1)]:
		if covered(x + p.x, y + p.y):
			img.set_pixel(x + p.x, y + p.y, ring)
	for dx in [-1, 0, 1]:
		if covered(x + dx, y):
			img.set_pixel(x + dx, y, heart)


## The height layer's encoding of `height` (rounded up so the byte reads back exactly).
static func _height_color(height: int) -> Color:
	return Color((clampi(height, 0, 255) + 0.5) / 255.0, 0.0, 0.0)

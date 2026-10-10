class_name Deformation

## Stateless damage-deformation geometry + rendering, shared by furniture, walls and
## characters (their visuals and, for furniture/walls, collider rebuilds), so the drawn
## silhouette and any collider come from the same deformed polygon. The caller owns the
## impact list. Tuning lives in PhysicsConfig.deform_* (and, for a character, CharacterConfig).
##
## An "impact" is a Dictionary in the drawer's local space:
##   pos:    Vector2  contact point
##   inward: Vector2  unit direction INTO the surface (dents push points this way)
##   depth:  float    dent depth in px (from dealt damage)
##   chunk:  bool     true = carve a jagged missing piece instead of a shallow dent
##   seed:   int      stable RNG seed so a hit's jitter/cracks don't shimmer each frame

## Sentinel for an unset color argument: callers pass it to accept the default derived from
## the shape's own colors (an intentional mark color always has non-zero alpha).
const NO_COLOR := Color(0.0, 0.0, 0.0, 0.0)
## Default near-black bullet-hole color when a caller supplies no override.
const HOLE_COLOR := Color(0.05, 0.05, 0.06)


## Closed perimeter sample ring for a primitive shape, centered on the origin.
static func base_ring(shape: String, size: Vector2) -> PackedVector2Array:
	var ring := PackedVector2Array()
	match shape:
		"circle":
			var radius := size.x * 0.5
			var n: int = maxi(3, PhysicsConfig.deform_circle_points)
			for i in n:
				var a := TAU * float(i) / float(n)
				ring.append(Vector2(cos(a), sin(a)) * radius)
		_:  # "square" / "rect"
			var half := size * 0.5
			var corners := [
				Vector2(-half.x, -half.y), Vector2(half.x, -half.y),
				Vector2(half.x, half.y), Vector2(-half.x, half.y),
			]
			var per: int = maxi(1, PhysicsConfig.deform_rect_points_per_edge)
			for c in 4:
				var a: Vector2 = corners[c]
				var b: Vector2 = corners[(c + 1) % 4]
				for i in per:
					ring.append(a.lerp(b, float(i) / float(per)))
	return ring


## Displace ring points near each impact: shallow smooth dents, or a deep jagged notch
## for `chunk` impacts (a "missing piece"). Points are clamped so they can't cross the
## shape center (which would fold the polygon inside out).
static func deform(ring: PackedVector2Array, impacts: Array, radius: float,
		core: float = PhysicsConfig.deform_back_margin) -> PackedVector2Array:
	if impacts.is_empty():
		return ring
	var center := _centroid(ring)
	var out := PackedVector2Array()
	out.resize(ring.size())
	for i in ring.size():
		var p: Vector2 = ring[i]
		var offset := Vector2.ZERO
		for impact in impacts:
			var d: float = p.distance_to(impact["pos"])
			var reach: float = radius * (PhysicsConfig.deform_chunk_reach_scale if impact["chunk"] else 1.0)
			if d >= reach:
				continue
			var t := 1.0 - d / reach  # 1 at the impact, 0 at the edge of reach
			if impact["chunk"]:
				# Deep carve + seeded jitter so the bite looks torn, not smooth.
				var rng := RandomNumberGenerator.new()
				rng.seed = int(impact["seed"]) + i * 7
				var jag := 1.0 + rng.randf_range(-PhysicsConfig.deform_chunk_jitter, PhysicsConfig.deform_chunk_jitter)
				offset += impact["inward"] * impact["depth"] * PhysicsConfig.deform_chunk_depth * smoothstep(0.0, 1.0, t) * jag
			else:
				offset += impact["inward"] * impact["depth"] * (t * t)
		# Clamp the displacement so a dent can't push the point past the object's opposite
		# face (which would grow the silhouette out the back on repeated hits).
		out[i] = _clamp_inside(ring, center, p, offset, core)
	return out


## Centroid (average) of a ring of points, used as the interior limit a dent can't pass.
static func _centroid(ring: PackedVector2Array) -> Vector2:
	if ring.is_empty():
		return Vector2.ZERO
	var sum := Vector2.ZERO
	for pt in ring:
		sum += pt
	return sum / float(ring.size())


## A displaced boundary point kept inside the base outline. A dent may only cave the point
## INWARD: an offset that points out of the solid (e.g. an impact reaching a far-face point)
## leaves it put, and an inward offset is capped so it can't travel past the opposite face
## minus a thin margin, nor into the solid `core` around the shape's center (so opposite
## dents can't meet and fold a small silhouette inside out). Returns `p` unmoved or a point
## that stays inside.
static func _clamp_inside(ring: PackedVector2Array, center: Vector2, p: Vector2, offset: Vector2,
		core: float) -> Vector2:
	if offset == Vector2.ZERO:
		return p
	var dir := offset.normalized()
	# A step along the offset that leaves the outline means the dent would bulge outward.
	if not Geometry2D.is_point_in_polygon(p + dir * 0.05, ring):
		return p
	var span := _exit_distance(ring, p, dir)
	var limit := maxf(span - PhysicsConfig.deform_back_margin, 0.0)
	# Stop the point at the edge of the central core, so it keeps its distance from the
	# center. On big furniture this is slack (dents are far shallower); on a small body (a
	# character) it is what lets dents go deep without opposite edges crossing.
	var to_center := maxf(p.distance_to(center) - core, 0.0)
	limit = minf(limit, to_center)
	return p + dir * minf(offset.length(), limit)


## Distance from boundary point `p` along `dir` to where it exits `ring` again (the far
## face), or INF if the ray leaves without re-crossing. `p` is a vertex of `ring`, so
## intersections closer than a hair are its own adjacent edges and are ignored.
static func _exit_distance(ring: PackedVector2Array, p: Vector2, dir: Vector2) -> float:
	var start := p + dir * 0.05
	var far := p + dir * 100000.0
	var best := INF
	var n := ring.size()
	for i in n:
		var hit = Geometry2D.segment_intersects_segment(start, far, ring[i], ring[(i + 1) % n])
		if hit != null:
			var dist: float = p.distance_to(hit)
			if dist > 0.1 and dist < best:
				best = dist
	return best


## Deformed perimeter polygon for a furniture shape — the single source both the visuals
## and the collider use. The central core scales with the shape, so a small body dents
## deeply without folding while big furniture (whose dents never reach the core) is unchanged.
static func shape_polygon(shape: String, size: Vector2, impacts: Array) -> PackedVector2Array:
	var core := minf(size.x, size.y) * 0.5 * PhysicsConfig.deform_core_fraction
	return deform(base_ring(shape, size), impacts, PhysicsConfig.deform_radius, core)


## Deformed polygon for one wall segment: a thick rectangle (quad) along the centerline
## a→b, ends extended by half-thickness (like the collider), long edges subdivided so
## dents have resolution. Shared by the wall visuals and the wall collider rebuild.
static func wall_polygon(a: Vector2, b: Vector2, thickness: float, impacts: Array) -> PackedVector2Array:
	var dir := (b - a).normalized()
	var half_n := dir.orthogonal() * (thickness * 0.5)
	var s := a - dir * (thickness * 0.5)
	var e := b + dir * (thickness * 0.5)
	var ring := PackedVector2Array()
	var steps := 16
	for i in steps + 1:  # near edge (+half_n): s -> e
		ring.append(s.lerp(e, float(i) / float(steps)) + half_n)
	for i in steps + 1:  # far edge (-half_n): e -> s
		ring.append(e.lerp(s, float(i) / float(steps)) - half_n)
	return deform(ring, impacts, PhysicsConfig.deform_radius)


## True when `poly` is a valid simple polygon the engine can triangulate. A silhouette
## deformed by many overlapping dents on a small body can pinch itself into a degenerate
## (self-touching) polygon; both `draw_colored_polygon` and `decompose_polygon_in_convex`
## reject those, so callers check this first and skip the deformed polygon that frame.
static func is_valid_polygon(poly: PackedVector2Array) -> bool:
	return poly.size() >= 3 and not Geometry2D.triangulate_polygon(poly).is_empty()


## Decompose a (possibly concave) polygon into convex ConvexPolygonShape2D pieces for a
## static collider. Returns [] for a degenerate polygon or if decomposition fails (caller
## keeps the old collider).
static func convex_shapes(polygon: PackedVector2Array) -> Array:
	var shapes: Array = []
	if not is_valid_polygon(polygon):
		return shapes
	for piece in Geometry2D.decompose_polygon_in_convex(polygon):
		if piece.size() >= 3:
			var shape := ConvexPolygonShape2D.new()
			shape.points = piece
			shapes.append(shape)
	return shapes


## Draw a deformed primitive shape (furniture, characters): filled polygon (darkened by
## accumulated damage), outline, then crack/hole marks. `crack_color`/`hole_color` override
## the mark colors (e.g. red cracks on flesh); left as NO_COLOR they derive from `outline`.
## With a `texture` (spanning the `size` footprint) the polygon is drawn textured instead of
## filled and unoutlined: the dents cut into the image rather than squash it.
static func draw_shape(canvas: CanvasItem, shape: String, size: Vector2, fill: Color,
		outline: Color, impacts: Array, damage_total: float,
		crack_color: Color = NO_COLOR, hole_color: Color = NO_COLOR, scorch_color: Color = NO_COLOR,
		texture: Texture2D = null) -> void:
	var poly := shape_polygon(shape, size, impacts)
	# Fall back to the intact outline if the dents pinched the silhouette into a polygon the
	# renderer can't triangulate; the hit marks below still show the damage.
	if not is_valid_polygon(poly):
		poly = base_ring(shape, size)
	var darken := 0.0
	if damage_total > 0.0 and PhysicsConfig.deform_darken_full > 0.0:
		darken = clampf(damage_total / PhysicsConfig.deform_darken_full, 0.0, 1.0) * PhysicsConfig.deform_darken_max
	if texture:
		var uvs := PackedVector2Array()
		for p in poly:
			uvs.append(p / size + Vector2(0.5, 0.5))
		canvas.draw_colored_polygon(poly, Color.WHITE.darkened(darken), uvs, texture)
	else:
		canvas.draw_colored_polygon(poly, fill.darkened(darken))
		_draw_outline(canvas, poly, outline)
	var cc := crack_color if crack_color.a > 0.0 else outline.darkened(0.3)
	var hc := hole_color if hole_color.a > 0.0 else HOLE_COLOR
	var sc := scorch_color if scorch_color.a > 0.0 else Color.BLACK
	draw_marks(canvas, impacts, cc, hc, sc)


## Draw one deformed wall segment (fill + outline + marks). With a `texture` (a repeating tile
## `tile_length` px long, x along the wall and y across its thickness) the polygon is drawn
## textured in the segment's own frame instead of filled and outlined, so the tile runs along the
## wall whichever way it points and dents cut into it (the canvas item must repeat textures).
static func draw_wall(canvas: CanvasItem, a: Vector2, b: Vector2, thickness: float,
		color: Color, impacts: Array, texture: Texture2D = null, tile_length: float = 0.0) -> void:
	var poly := wall_polygon(a, b, thickness, impacts)
	if texture and tile_length > 0.0:
		var dir := (b - a).normalized()
		var across := dir.orthogonal()
		var uvs := PackedVector2Array()
		for p in poly:
			uvs.append(Vector2((p - a).dot(dir) / tile_length, (p - a).dot(across) / thickness + 0.5))
		canvas.draw_colored_polygon(poly, Color.WHITE, uvs, texture)
	else:
		canvas.draw_colored_polygon(poly, color)
		_draw_outline(canvas, poly, color.darkened(0.25))
	draw_marks(canvas, impacts, color.darkened(0.4).darkened(0.3), HOLE_COLOR, Color.BLACK)


## Local position of an impact's dent apex: the contact point pushed inward by its dent
## depth (deeper for a carved chunk), mirroring the t=1 displacement in deform(). Marks are
## drawn here so they sit in the deformed notch instead of on the original surface line.
static func _impact_apex(impact: Dictionary) -> Vector2:
	var pos: Vector2 = impact["pos"]
	var inward: Vector2 = impact["inward"]
	var d: float = impact["depth"]
	if impact["chunk"]:
		d *= PhysicsConfig.deform_chunk_depth
	var apex := pos + inward * d
	# Same guard deform() uses: never let the point cross the shape center.
	if apex.dot(pos) < 0.0:
		return pos * 0.02
	return apex


## Bullet holes + radiating cracks + faint scorch for each impact, seated in its dent.
## `crack_color` tints the radiating cracks, `hole_color` the central hole, `scorch_color`
## the faint halo (its alpha comes from PhysicsConfig, so only its RGB matters).
static func draw_marks(canvas: CanvasItem, impacts: Array, crack_color: Color, hole_color: Color,
		scorch_color: Color) -> void:
	var scorch := scorch_color
	scorch.a = PhysicsConfig.deform_scorch_alpha
	for impact in impacts:
		var p := _impact_apex(impact)
		var depth: float = impact["depth"]
		canvas.draw_circle(p, PhysicsConfig.deform_scorch_radius + depth, scorch)
		canvas.draw_circle(p, maxf(1.5, depth * PhysicsConfig.deform_hole_radius_scale), hole_color)
		var rng := RandomNumberGenerator.new()
		rng.seed = int(impact["seed"])
		var count := 2 + int(clampf(depth * PhysicsConfig.deform_crack_count, 0.0, 5.0))
		for _c in count:
			var ang := rng.randf_range(0.0, TAU)
			var length := PhysicsConfig.deform_crack_length * rng.randf_range(0.5, 1.0) * (1.0 + depth * 0.15)
			var jitter := Vector2(cos(ang), sin(ang)).orthogonal() * rng.randf_range(-2.0, 2.0)
			canvas.draw_line(p, p + Vector2(cos(ang), sin(ang)) * length + jitter, crack_color, PhysicsConfig.deform_crack_width)


## Closed outline around a ring of points.
static func _draw_outline(canvas: CanvasItem, ring: PackedVector2Array, color: Color) -> void:
	if ring.size() < 2:
		return
	var closed := ring.duplicate()
	closed.append(ring[0])
	canvas.draw_polyline(closed, color, 1.5, true)

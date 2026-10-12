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
## Multiplier that packs two piece ids into one dictionary key in `_convex_pieces` (ids stay far below it).
const PIECE_PAIR_STRIDE := 65536


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
## (self-touching) polygon; `draw_colored_polygon` rejects those, so callers check this first
## and skip the deformed polygon that frame.
static func is_valid_polygon(poly: PackedVector2Array) -> bool:
	return poly.size() >= 3 and not Geometry2D.triangulate_polygon(poly).is_empty()


## Decompose a (possibly concave) polygon into convex ConvexPolygonShape2D pieces for a
## static collider. Returns [] for a degenerate polygon (caller keeps the old collider).
## Merges the triangulation itself rather than calling `Geometry2D.decompose_polygon_in_convex`,
## which logs "Convex decomposing failed!" on some near-degenerate polygons that do triangulate.
static func convex_shapes(polygon: PackedVector2Array) -> Array:
	var shapes: Array = []
	if not is_valid_polygon(polygon):
		return shapes
	for piece in _convex_pieces(polygon):
		var points := PackedVector2Array()
		for i in piece:
			points.append(polygon[i])
		var shape := ConvexPolygonShape2D.new()
		shape.points = points
		shapes.append(shape)
	return shapes


## Convex pieces of `polygon` as vertex-index loops (Hertel-Mehlhorn): start from its
## triangulation, wound like the polygon, and keep merging two pieces across a shared edge
## while the union stays convex. Needs `is_valid_polygon(polygon)`.
static func _convex_pieces(polygon: PackedVector2Array) -> Array:
	var sign_ := -1.0 if Geometry2D.is_polygon_clockwise(polygon) else 1.0
	var tris := Geometry2D.triangulate_polygon(polygon)
	var pieces: Array = []
	for t in range(0, tris.size(), 3):
		var tri := [tris[t], tris[t + 1], tris[t + 2]]
		if _turn(polygon, tri[0], tri[1], tri[2]) * sign_ < 0.0:
			tri = [tri[0], tri[2], tri[1]]
		pieces.append(tri)
	# The scan restarts after every merge and takes the first pair, in piece order, that is neighbours across an edge and
	# whose union is convex. Only neighbours can merge, so they are found through a map of who owns each directed edge
	# (a piece's edge i -> j meets its neighbour's j -> i), and a neighbouring pair that failed is remembered by the
	# pieces' ids (the failure holds until one of them changes). The same merges happen in the same order.
	var count := polygon.size()
	var ids: Array = range(pieces.size())
	var next_id := pieces.size()
	var owner := {}
	for p in pieces.size():
		_own_edges(owner, pieces[p], ids[p], count, true)
	var failed := {}
	while true:
		var position_of := {}
		for p in pieces.size():
			position_of[ids[p]] = p
		var found := false
		for a in pieces.size():
			var loop: Array = pieces[a]
			var neighbours: Array = []
			for k in loop.size():
				var other = owner.get(int(loop[(k + 1) % loop.size()]) * count + int(loop[k]))
				if other != null and position_of[other] > a:
					neighbours.append(position_of[other])
			neighbours.sort()
			for b in neighbours:
				var pair: int = mini(ids[a], ids[b]) * PIECE_PAIR_STRIDE + maxi(ids[a], ids[b])
				if failed.has(pair):
					continue
				var union := _merge_across_edge(pieces[a], pieces[b])
				# Both pieces are convex already, so only the two corners where they now join can turn the wrong way:
				# the union's first vertex and the one ending piece a's run (see _merge_across_edge).
				if union.is_empty() or not (_turns_right_at(polygon, union, 0, sign_)
						and _turns_right_at(polygon, union, pieces[a].size() - 1, sign_)):
					failed[pair] = true
					continue
				_own_edges(owner, pieces[a], ids[a], count, false)
				_own_edges(owner, pieces[b], ids[b], count, false)
				pieces[a] = union
				ids[a] = next_id
				next_id += 1
				_own_edges(owner, union, ids[a], count, true)
				pieces.remove_at(b)
				ids.remove_at(b)
				found = true
				break
			if found:
				break
		if not found:
			break
	return pieces


## Record (`add`) or forget the directed edges of piece `loop` in `owner`, keyed `from * count + to`, as piece `id`'s.
static func _own_edges(owner: Dictionary, loop: Array, id: int, count: int, add: bool) -> void:
	for k in loop.size():
		var key: int = int(loop[k]) * count + int(loop[(k + 1) % loop.size()])
		if add:
			owner[key] = id
		else:
			owner.erase(key)


## Cross product of the turn at `b` on the way a -> b -> c (positive = counter-clockwise).
static func _turn(polygon: PackedVector2Array, a: int, b: int, c: int) -> float:
	return (polygon[b] - polygon[a]).cross(polygon[c] - polygon[b])


## The loop `a` + `b` form when they share an edge (a runs i -> j, b runs j -> i), or [] when
## they share none.
static func _merge_across_edge(a: Array, b: Array) -> Array:
	for k in a.size():
		var i: int = a[k]
		var j: int = a[(k + 1) % a.size()]
		var m := b.find(j)
		if m == -1 or b[(m + 1) % b.size()] != i:
			continue
		var out: Array = []
		for n in a.size():  # a rotated to start at j and end at i
			out.append(a[(k + 1 + n) % a.size()])
		for n in range(2, b.size()):  # b's vertices strictly between i and j
			out.append(b[(m + n) % b.size()])
		return out
	return []


## True when `loop` turns the polygon's way (`sign_` = +1 / -1, straight allowed) at its vertex number `at`.
static func _turns_right_at(polygon: PackedVector2Array, loop: Array, at: int, sign_: float) -> bool:
	var n := loop.size()
	var a: Vector2 = polygon[loop[(at - 1 + n) % n]]
	var b: Vector2 = polygon[loop[at]]
	var c: Vector2 = polygon[loop[(at + 1) % n]]
	return not ((b - a).cross(c - b) * sign_ < 0.0)


## Draw a deformed primitive shape (furniture, characters): filled polygon (darkened by
## accumulated damage), outline, then crack/hole marks. `crack_color`/`hole_color` override
## the mark colors (e.g. red cracks on flesh); left as NO_COLOR they derive from `outline`.
## With a `texture` (spanning the `size` footprint) the polygon is drawn textured instead of
## filled and unoutlined: the dents cut into the image rather than squash it. `texture_angle`
## turns the image within the (unturned) silhouette — a round body facing any way. Without
## `marks` the hit marks are left to the caller (draw_marks), to draw over parts layered on top.
static func draw_shape(canvas: CanvasItem, shape: String, size: Vector2, fill: Color,
		outline: Color, impacts: Array, damage_total: float,
		crack_color: Color = NO_COLOR, hole_color: Color = NO_COLOR, scorch_color: Color = NO_COLOR,
		texture: Texture2D = null, texture_angle: float = 0.0, marks: bool = true) -> void:
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
			uvs.append(p.rotated(-texture_angle) / size + Vector2(0.5, 0.5))
		canvas.draw_colored_polygon(poly, Color.WHITE.darkened(darken), uvs, texture)
	else:
		canvas.draw_colored_polygon(poly, fill.darkened(darken))
		_draw_outline(canvas, poly, outline)
	if not marks:
		return
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
	# Many dents can pinch the segment into a polygon the renderer can't triangulate; draw it
	# undented that frame (the hit marks below still show the damage).
	if not is_valid_polygon(poly):
		poly = wall_polygon(a, b, thickness, [])
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
		var blood: float = impact.get("blood", 0.0)
		if blood > 0.0:
			_draw_blood_mark(canvas, p, blood, int(impact["seed"]))
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


## Blood a bullet carried onto an object, drawn under the hole: a lumpy red blot with a few flecks around
## it, scaled and faded by how much blood arrived (`blood` 0..1). Seeded per impact so it never shimmers.
static func _draw_blood_mark(canvas: CanvasItem, at: Vector2, blood: float, seed_value: int) -> void:
	var color := PhysicsConfig.blood_mark_color
	color.a = clampf(0.45 + blood * 0.5, 0.0, 1.0)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value + 7
	var radius := PhysicsConfig.blood_mark_radius * (0.6 + blood * 0.6)
	canvas.draw_circle(at, radius, color)
	for _i in 3 + int(blood * 4.0):
		var ang := rng.randf_range(0.0, TAU)
		var off := Vector2(cos(ang), sin(ang)) * radius * rng.randf_range(0.6, 1.6)
		canvas.draw_circle(at + off, radius * rng.randf_range(0.25, 0.55), color)


## Closed outline around a ring of points.
static func _draw_outline(canvas: CanvasItem, ring: PackedVector2Array, color: Color) -> void:
	if ring.size() < 2:
		return
	var closed := ring.duplicate()
	closed.append(ring[0])
	canvas.draw_polyline(closed, color, 1.5, true)

class_name Deformation

## Stateless damage-deformation geometry + rendering, shared by furniture and walls (their
## visuals and collider rebuilds), so the drawn silhouette and the collider come from the
## same deformed polygon. The caller owns the impact list. Tuning lives in PhysicsConfig.deform_*.
##
## An "impact" is a Dictionary in the drawer's local space:
##   pos:    Vector2  contact point
##   inward: Vector2  unit direction INTO the surface (dents push points this way)
##   depth:  float    dent depth in px (from dealt damage)
##   chunk:  bool     true = carve a jagged missing piece instead of a shallow dent
##   seed:   int      stable RNG seed so a hit's jitter/cracks don't shimmer each frame


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
static func deform(ring: PackedVector2Array, impacts: Array, radius: float) -> PackedVector2Array:
	if impacts.is_empty():
		return ring
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
		# Clamp so the point cannot pass the center along its own radius.
		var moved := p + offset
		if moved.dot(p) < 0.0:
			moved = p * 0.02
		out[i] = moved
	return out


## Deformed perimeter polygon for a furniture shape — the single source both the visuals
## and the collider use.
static func shape_polygon(shape: String, size: Vector2, impacts: Array) -> PackedVector2Array:
	return deform(base_ring(shape, size), impacts, PhysicsConfig.deform_radius)


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


## Decompose a (possibly concave) polygon into convex ConvexPolygonShape2D pieces for a
## static collider. Returns [] if decomposition fails (caller keeps the old collider).
static func convex_shapes(polygon: PackedVector2Array) -> Array:
	var shapes: Array = []
	if polygon.size() < 3:
		return shapes
	for piece in Geometry2D.decompose_polygon_in_convex(polygon):
		if piece.size() >= 3:
			var shape := ConvexPolygonShape2D.new()
			shape.points = piece
			shapes.append(shape)
	return shapes


## Draw a deformed primitive shape (furniture): filled polygon (darkened by accumulated
## damage), outline, then crack/hole marks.
static func draw_shape(canvas: CanvasItem, shape: String, size: Vector2, fill: Color,
		outline: Color, impacts: Array, damage_total: float) -> void:
	var poly := shape_polygon(shape, size, impacts)
	var body_color := fill
	if damage_total > 0.0 and PhysicsConfig.deform_darken_full > 0.0:
		var k := clampf(damage_total / PhysicsConfig.deform_darken_full, 0.0, 1.0) * PhysicsConfig.deform_darken_max
		body_color = fill.darkened(k)
	canvas.draw_colored_polygon(poly, body_color)
	_draw_outline(canvas, poly, outline)
	draw_marks(canvas, impacts, outline)


## Draw one deformed wall segment (fill + outline + marks).
static func draw_wall(canvas: CanvasItem, a: Vector2, b: Vector2, thickness: float,
		color: Color, impacts: Array) -> void:
	var poly := wall_polygon(a, b, thickness, impacts)
	canvas.draw_colored_polygon(poly, color)
	_draw_outline(canvas, poly, color.darkened(0.25))
	draw_marks(canvas, impacts, color.darkened(0.4))


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
static func draw_marks(canvas: CanvasItem, impacts: Array, ink: Color) -> void:
	var hole := Color(0.05, 0.05, 0.06)
	var crack := ink.darkened(0.3)
	for impact in impacts:
		var p := _impact_apex(impact)
		var depth: float = impact["depth"]
		canvas.draw_circle(p, PhysicsConfig.deform_scorch_radius + depth, Color(0.0, 0.0, 0.0, PhysicsConfig.deform_scorch_alpha))
		canvas.draw_circle(p, maxf(1.5, depth * PhysicsConfig.deform_hole_radius_scale), hole)
		var rng := RandomNumberGenerator.new()
		rng.seed = int(impact["seed"])
		var count := 2 + int(clampf(depth * PhysicsConfig.deform_crack_count, 0.0, 5.0))
		for _c in count:
			var ang := rng.randf_range(0.0, TAU)
			var length := PhysicsConfig.deform_crack_length * rng.randf_range(0.5, 1.0) * (1.0 + depth * 0.15)
			var jitter := Vector2(cos(ang), sin(ang)).orthogonal() * rng.randf_range(-2.0, 2.0)
			canvas.draw_line(p, p + Vector2(cos(ang), sin(ang)) * length + jitter, crack, PhysicsConfig.deform_crack_width)


## Closed outline around a ring of points.
static func _draw_outline(canvas: CanvasItem, ring: PackedVector2Array, color: Color) -> void:
	if ring.size() < 2:
		return
	var closed := ring.duplicate()
	closed.append(ring[0])
	canvas.draw_polyline(closed, color, 1.5, true)

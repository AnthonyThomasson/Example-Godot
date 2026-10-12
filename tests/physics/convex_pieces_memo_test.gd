extends GameTest

## `Deformation.convex_shapes` cuts a dented silhouette into convex collider pieces by merging triangles
## (Hertel-Mehlhorn), restarting its scan after every merge. It now remembers the pairs that failed to merge instead
## of trying them again after each restart. This pins its pieces to the plain restart-everything scan over
## silhouettes of every shape with up to the most dents a piece keeps.

const SEED := 4242
const SHAPES := ["circle", "square", "rect"]


func describe() -> Dictionary:
	return {
		"name": "Convex collider pieces are the same with failed merges remembered",
		"description": "Deformation cuts dented silhouettes into the same convex pieces as the scan that retries every pair after each merge.",
		"tags": ["deformation", "collider"],
		"timeout": 30.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 400, 300))


func run(t: TestContext) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED
	var checked := 0
	var differing := 0
	for n in 120:
		var shape: String = SHAPES[n % SHAPES.size()]
		var size := Vector2(rng.randf_range(24.0, 90.0), rng.randf_range(24.0, 90.0))
		var impacts: Array = []
		for k in rng.randi_range(0, PhysicsConfig.deform_max_impacts):
			var at := Vector2.from_angle(rng.randf() * TAU) * size.x * 0.5
			impacts.append({
				"pos": at, "inward": -at.normalized(), "depth": rng.randf_range(1.0, PhysicsConfig.deform_max_depth),
				"chunk": rng.randf() < 0.3, "seed": rng.randi(), "blood": 0.0,
			})
		var poly := Deformation.shape_polygon(shape, size, impacts)
		if not Deformation.is_valid_polygon(poly):
			continue
		checked += 1
		if Deformation._convex_pieces(poly) != _every_pair(poly):
			differing += 1
	t.check(checked >= 100, "silhouettes cut (%d)" % checked)
	t.check(differing == 0, "%d of %d silhouettes are cut differently" % [differing, checked])


## `_convex_pieces` as it was: the scan restarts after every merge and tries every pair again.
func _every_pair(polygon: PackedVector2Array) -> Array:
	var sign_ := -1.0 if Geometry2D.is_polygon_clockwise(polygon) else 1.0
	var tris := Geometry2D.triangulate_polygon(polygon)
	var pieces: Array = []
	for i in range(0, tris.size(), 3):
		var tri := [tris[i], tris[i + 1], tris[i + 2]]
		if Deformation._turn(polygon, tri[0], tri[1], tri[2]) * sign_ < 0.0:
			tri = [tri[0], tri[2], tri[1]]
		pieces.append(tri)
	var merged := true
	while merged:
		merged = false
		for a in pieces.size():
			for b in range(a + 1, pieces.size()):
				var union := Deformation._merge_across_edge(pieces[a], pieces[b])
				if union.is_empty() or not Deformation._is_convex_loop(polygon, union, sign_):
					continue
				pieces[a] = union
				pieces.remove_at(b)
				merged = true
				break
			if merged:
				break
	return pieces

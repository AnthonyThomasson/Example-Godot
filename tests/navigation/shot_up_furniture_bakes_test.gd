extends GameTest

## A shot-up piece of furniture has a many-sided hull, and snapped to the 1 px grid it is a run of steps and notches
## a pixel deep. Baked as it is, the engine logs "polygon convex partition failed" and produces NO navmesh (every
## path in the house gone until the next re-bake). `NavBuilder._simplified` drops the vertices that sit on the line
## between their neighbours; the outlines below are real ones (a kitchen island shot up in a firefight) that the raw
## bake could not make a mesh of.

const ARENA := Rect2(0, 0, 1000, 700)
const OUTLINES := [
	[Vector2(827, 193), Vector2(843, 187), Vector2(857, 186), Vector2(937, 190), Vector2(937, 204), Vector2(938, 236),
			Vector2(938, 245), Vector2(917, 252), Vector2(902, 252), Vector2(901, 252), Vector2(886, 251), Vector2(829, 248),
			Vector2(827, 235), Vector2(827, 229)],
	[Vector2(829, 191), Vector2(832, 186), Vector2(841, 184), Vector2(850, 183), Vector2(945, 183), Vector2(948, 220),
			Vector2(950, 238), Vector2(938, 245), Vector2(913, 247), Vector2(886, 249), Vector2(839, 253), Vector2(835, 246)],
]


func describe() -> Dictionary:
	return {
		"name": "A shot-up piece of furniture bakes a navmesh",
		"description": "Two hulls of a shot-up island, snapped to the grid, still bake once their near-collinear vertices are dropped; the outline moves by under the tolerance.",
		"tags": ["navigation", "bake", "deformation", "furniture"],
		"timeout": 10.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 400, 300))


func _bake(outline: PackedVector2Array) -> int:
	var nav_poly := NavigationPolygon.new()
	nav_poly.agent_radius = 18.0
	var source := NavigationMeshSourceGeometryData2D.new()
	source.add_traversable_outline(PackedVector2Array([ARENA.position, Vector2(ARENA.end.x, ARENA.position.y), ARENA.end, Vector2(ARENA.position.x, ARENA.end.y)]))
	source.add_obstruction_outline(outline)
	NavigationServer2D.bake_from_source_geometry_data(nav_poly, source)
	return nav_poly.get_polygon_count()


func run(t: TestContext) -> void:
	for i in OUTLINES.size():
		var raw := PackedVector2Array(OUTLINES[i])
		var simplified := NavBuilder._simplified(raw)
		t.check(simplified.size() < raw.size(), "outline %d loses its near-collinear vertices (%d -> %d)" % [i, raw.size(), simplified.size()])
		var drift := 0.0
		for p in raw:
			drift = maxf(drift, _distance_to_ring(p, simplified))
		t.check(drift <= NavBuilder.SIMPLIFY_TOLERANCE * 2.0, "outline %d moves by under the tolerance (%.2f px)" % [i, drift])
		t.check(_bake(simplified) > 0, "outline %d bakes a navmesh" % i)


## Distance from `p` to the closed ring `ring`.
func _distance_to_ring(p: Vector2, ring: PackedVector2Array) -> float:
	var best := INF
	for i in ring.size():
		best = minf(best, p.distance_to(Geometry2D.get_closest_point_to_segment(p, ring[i], ring[(i + 1) % ring.size()])))
	return best

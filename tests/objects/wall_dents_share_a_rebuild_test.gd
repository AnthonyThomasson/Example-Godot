extends GameTest

## A wall struck several times in one frame (a frag's fragments) rebuilds each struck segment's collider once, from the dents
## as they stand when the deferred rebuild runs, as a piece of furniture does (wall.gd); and the dented segment polygon is kept
## between asks (`Deformation.wall_polygon`), as a wall repaints every segment whenever one is struck. This checks that after
## volleys of hits landing in one frame each segment's collider is exactly the convex cut of its dented polygon, that the kept
## polygon is the one a fresh computation gives (and a fresh array each ask), and that a further dent gives a new one.

const SHOTS := 5


func describe() -> Dictionary:
	return {
		"name": "A wall's dents in one frame share one collider rebuild",
		"description": "Hits landing on a wall in one frame leave each segment's collider the convex cut of its dented polygon; a kept dented polygon equals a fresh one.",
		"tags": ["deformation", "collider", "wall", "cache"],
		"timeout": 6.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 600, 400))
	s.switch(&"physics.debris", false)
	s.switch(&"nav.rebake", false)


func run(t: TestContext) -> void:
	var wall: Node = null
	for node in t.world.find_children("*", "StaticBody2D", true, false):
		if node.has_method("wall_segments"):
			wall = node
			break
	if not t.require(wall != null, "the arena has a wall"):
		return
	await t.frames(1)
	var rng := RandomNumberGenerator.new()
	rng.seed = 31
	for volley in 3:
		for k in SHOTS:  # one frame's worth of hits, along the top wall
			var hit := HitInfo.new()
			hit.position = wall.to_global(Vector2(rng.randf_range(80.0, 520.0), 0.0))
			hit.normal = Vector2.DOWN
			hit.direction = Vector2.UP
			hit.damage = rng.randf_range(10.0, 40.0)
			hit.speed_factor = 1.0
			wall.take_hit(hit)
		await t.frames(2)
	var segs: Array = wall.wall_segments()
	var checked := 0
	var differing: Array = []
	for i in segs.size():
		var impacts: Array = wall._seg_impacts.get(i, [])
		if impacts.is_empty():
			continue
		checked += 1
		var seg: PackedVector2Array = segs[i]
		var poly := Deformation.wall_polygon(seg[0], seg[1], wall.wall_thickness, impacts)
		var fresh := Deformation._wall_polygon(seg[0], seg[1], wall.wall_thickness, impacts)
		if poly != fresh:
			differing.append("segment %d: the kept polygon is not a fresh one's" % i)
		poly.append(Vector2(9999.0, 9999.0))  # the caller's own copy: changing it must change nothing kept
		if Deformation.wall_polygon(seg[0], seg[1], wall.wall_thickness, impacts) != fresh:
			differing.append("segment %d: a caller's change reached the kept polygon" % i)
		var want := Deformation.convex_shapes(fresh)
		var have: Array = []
		for col in wall._seg_colliders.get(i, []):
			if is_instance_valid(col) and not col.is_queued_for_deletion():
				have.append(col.shape)
		var same := want.size() == have.size()
		for k in mini(want.size(), have.size()):
			same = same and (want[k] as ConvexPolygonShape2D).points == (have[k] as ConvexPolygonShape2D).points
		if not same:
			differing.append("segment %d: collider %d pieces, its cut %d" % [i, have.size(), want.size()])
		var more: Array = impacts.duplicate(true)
		more.append({ "pos": (seg[0] + seg[1]) * 0.5, "inward": Vector2.DOWN, "depth": 6.0, "chunk": true, "seed": 5, "blood": 0.0 })
		if Deformation.wall_polygon(seg[0], seg[1], wall.wall_thickness, more) != Deformation._wall_polygon(seg[0], seg[1], wall.wall_thickness, more):
			differing.append("segment %d: a further dent was answered with an old polygon" % i)
	t.check(checked >= 1, "the hits dented the wall (%d segments)" % checked)
	t.check(differing.is_empty(), "%s" % str(differing))

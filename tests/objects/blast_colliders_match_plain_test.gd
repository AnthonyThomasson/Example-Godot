extends GameTest

## A frag dents a room's worth of furniture in one frame, and each dented piece rebuilds its collider from convex pieces of its
## silhouette in a deferred call (environment_object.gd). The first rebuild of a flush cuts every waiting piece's silhouette
## together on the worker threads (`ColliderCuts`); each piece still swaps its own colliders in its own call. This checks that after a frag and
## its fragments every piece's collider is exactly what cutting its own silhouette alone gives (`Deformation.convex_shapes`),
## piece by piece and point by point.

const Probe := preload("res://tests/_ai/grenade_probe.gd")

const CENTRE := Vector2(500, 350)
const PIECES := [
	["sofa", Vector2(0, -110)], ["armchair", Vector2(-120, -70)], ["armchair", Vector2(120, -70)], ["bookshelf", Vector2(-150, 60)],
	["wardrobe", Vector2(150, 70)], ["desk", Vector2(0, 120)], ["coffee_table", Vector2(-60, 40)], ["side_table", Vector2(70, 30)],
]


func describe() -> Dictionary:
	return {
		"name": "Furniture dented by a blast gets the colliders it would alone",
		"description": "After a frag among eight pieces, every dented piece's collider is the convex cut of its own silhouette, the same pieces and points.",
		"tags": ["deformation", "collider", "frag", "grenade"],
		"timeout": 12.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 1000, 700))
	s.switch(&"physics.blood", false)
	s.switch(&"nav.rebake", false)
	for i in PIECES.size():
		s.object(StringName("piece%d" % i), PIECES[i][0], CENTRE + PIECES[i][1])
	s.actor(&"thrower", &"puppet", Vector2(120, 350), { "max_health": 1000000.0, "aim_point": CENTRE })


func run(t: TestContext) -> void:
	var started := ColliderCuts.started
	Probe.arm(t.actor(&"thrower"), 0, 1)
	await Probe.throw_at(t, &"thrower", Probe.FRAG, CENTRE)
	if not t.require(await t.until(func() -> bool: return not Probe.booms(t).is_empty(), 6.0), "the frag went off"):
		return
	await t.seconds(1.0)  # the fragments land and every rebuild has run
	var dented := 0
	var differing: Array = []
	for i in PIECES.size():
		var piece := t.object(StringName("piece%d" % i))
		var impacts: Array = piece._deformable.impacts
		if impacts.is_empty():
			continue
		dented += 1
		var want := Deformation.convex_shapes(Deformation.shape_polygon(piece.shape_type, piece.size, impacts))
		var have: Array = []
		for child in piece.get_children():
			if child is CollisionShape2D and not child.is_queued_for_deletion():
				have.append(child.shape)
		var same := want.size() == have.size()
		for k in mini(want.size(), have.size()):
			same = same and (want[k] as ConvexPolygonShape2D).points == (have[k] as ConvexPolygonShape2D).points
		if not same:
			differing.append("piece%d (%d pieces, want %d)" % [i, have.size(), want.size()])
	t.check(dented >= 4, "the blast dented the furniture (%d of %d pieces)" % [dented, PIECES.size()])
	t.check(ColliderCuts.started > started, "the pieces were cut beside one another (%d on workers)" % (ColliderCuts.started - started))
	t.check(differing.is_empty(), "every dented piece's collider is its own cut: %s differ" % str(differing))

extends GameTest

## Blood dragged out of a settled pool (BloodPool.drag_out, what a smear does) grows the pool's own
## outline: the spot just beyond the rim becomes wet and covered, far-off floor stays dry, and the trail
## never grows past BloodConfig.pool_trail_max cells.


func describe() -> Dictionary:
	return {
		"name": "Dragging blood out of a pool extends the pool",
		"description": "drag_out beyond a settled pool's rim makes that spot wet and covered by the pool, leaves distant floor dry and is not dragged past pool_trail_length and respects the trail cap.",
		"tags": ["blood", "pool", "smear"],
		"timeout": 30.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 900, 500))
	s.switch(&"physics.blood", true)
	s.set_static(BloodConfig, &"pool_trail_max", 40)


func run(t: TestContext) -> void:
	var anchor := Node2D.new()
	t.world.add_child(anchor)
	anchor.global_position = Vector2(300, 250)
	var pool := BloodSpawner.bleed(t.world, anchor, [])
	if not t.require(await t.until(func(): return pool.flow.settled(), 20.0, "the pool fills"), "pool settles"):
		return

	# The pool's cell farthest to the right, and a spot a few cells beyond it.
	var edge := Vector2i(-1000000, 0)
	for c in pool.flow.cells:
		if c.x > edge.x:
			edge = c
	var beyond: Vector2 = pool.global_position + (Vector2(edge) + Vector2(0.5, 0.5)) * BloodConfig.flow_cell_size + Vector2(12.0, 0.0)
	t.expect_eq(BloodField.wetness_at(beyond), 0.0, "beyond the rim is bare floor before the drag")
	t.check(BloodField.pool_near(beyond, BloodConfig.smear_trail_reach) == pool, "the pool is near enough to feed")

	pool.drag_out(beyond, 1.0)
	t.check(BloodField.wetness_at(beyond) > 0.5, "dragged-out blood is wet (%.2f)" % BloodField.wetness_at(beyond))
	t.check(pool.flow.covers(Vector2i(((beyond - pool.global_position) / BloodConfig.flow_cell_size).floor())), "the pool covers the dragged cell")
	t.expect_eq(BloodField.wetness_at(beyond + Vector2(0, 150)), 0.0, "distant floor stays dry")
	t.check(BloodField.pool_near(beyond + Vector2(0, 150), BloodConfig.smear_trail_reach) == null, "no pool near distant floor")

	var far := beyond + Vector2(BloodConfig.pool_trail_length + 10.0, 0.0)
	pool.drag_out(far, 1.0)
	t.expect_eq(BloodField.wetness_at(far), 0.0, "blood is not dragged past pool_trail_length")

	for i in 30:
		pool.drag_out(beyond + Vector2(i * 4.0, 0), 1.0)
	t.check(pool.flow.trail.size() <= BloodConfig.pool_trail_max, "the trail is capped (%d)" % pool.flow.trail.size())

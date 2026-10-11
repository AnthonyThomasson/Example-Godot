extends GameTest

## A chair pushed out of a bleed-out pool drags blood with it and the streak grows out of the pool's soft
## rim without a hard edge: ribbons ease in from nothing and their opacity never steps sharply.


func describe() -> Dictionary:
	return {
		"name": "A smear flows out of a pool without an edge",
		"description": "A chair pushed through a settled pool stretches the pool's outline into a tongue and leaves ribbons beyond it that start faint and never jump up in opacity.",
		"tags": ["blood", "smear", "pool"],
		"timeout": 30.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 900, 400))
	s.switch(&"physics.blood", true)
	s.switch(&"nav.rebake", false)
	s.object(&"chair", "chair", Vector2(215, 200))
	s.actor(&"pusher", &"puppet", Vector2(160, 200))
	s.camera_follow([&"chair"])


func run(t: TestContext) -> void:
	var anchor := Node2D.new()  # where the pool's blood leaves: nothing solid in the chair's way
	t.world.add_child(anchor)
	anchor.global_position = Vector2(300, 200)
	var pool := BloodSpawner.bleed(t.world, anchor, [])
	if not t.require(await t.until(func(): return pool.flow.settled(), 20.0, "the pool fills"), "pool settles"):
		return
	var rim := 0.0
	for c in pool.flow.cells:
		rim = maxf(rim, pool.global_position.x + (c.x + 1) * BloodConfig.flow_cell_size)
	t.expect_eq(pool.flow.trail.size(), 0, "nothing dragged out yet")
	t.puppet(&"pusher").walk(Vector2.RIGHT)
	await t.until(func(): return t.object(&"chair").global_position.x > 400.0, 10.0, "the chair is pushed out of the pool")
	t.screenshot("chair_smear_pool")
	await t.until(func(): return t.object(&"chair").global_position.x > 520.0, 10.0, "the chair is well clear of the pool")
	t.screenshot("chair_smear_pool_clear")
	await t.until(func(): return t.object(&"chair").global_position.x > 650.0, 10.0, "the chair is pushed across")
	t.puppet(&"pusher").stop()
	var layer := BloodDecals.find(t.object(&"chair").get_parent())
	if not t.require(layer != null and layer.ribbon_count() > 0, "the chair left streaks"):
		return
	var reach := 0.0
	for c in pool.flow.trail:
		reach = maxf(reach, pool.global_position.x + c.x * BloodConfig.flow_cell_size)
	t.check(reach > rim + 20.0, "the pool's own outline was pulled out past its old rim (%.0f vs %.0f)" % [reach, rim])
	var jump := 0.0
	var start := 1.0
	var beyond := 0
	for m in layer.items():
		if m["kind"] != "ribbon":
			continue
		var a: PackedFloat32Array = m["alphas"]
		start = minf(start, a[0])
		for i in range(1, a.size()):
			jump = maxf(jump, a[i] - a[i - 1])  # rises only
		if (m["points"] as PackedVector2Array)[-1].x > 360.0:
			beyond += 1
	t.check(beyond > 0, "streaks reach past the pool (%d)" % beyond)
	t.check(start < 0.02, "a streak starts from nothing (%.2f)" % start)
	t.check(jump < 0.2, "opacity rises gradually across the pool's rim, no hard edge (%.2f)" % jump)

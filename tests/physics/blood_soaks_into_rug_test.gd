extends GameTest

## A rug is a surface blood sinks into, like carpet: a bleed-out pool on the rug sinks in without shrinking and is
## no longer wet, one on the bare floor beside it does not, and the rug draws beneath blood so the pool
## shows on it. Once the rug is gone the spot is plain floor again.


func describe() -> Dictionary:
	return {
		"name": "Blood soaks into a rug",
		"description": "A bleed-out pool on a rug soaks in and is no longer wet; a pool beside it stays wet; the rug draws below blood and stops soaking once removed.",
		"tags": ["blood", "pool", "rug", "surface"],
		"timeout": 120.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 900, 500))
	s.switch(&"physics.blood", true)
	s.set_static(BloodConfig, &"soak_time", 2.0)
	s.object(&"rug", "rug", Vector2(250, 250))


func run(t: TestContext) -> void:
	var rug := t.object(&"rug")
	t.check(rug.z_index < BloodConfig.z_index, "the rug draws beneath blood (%d < %d)" % [rug.z_index, BloodConfig.z_index])
	var on_rug := _pool(t, Vector2(250, 250))
	var on_floor := _pool(t, Vector2(650, 250))
	if not t.require(await t.until(func(): return on_rug.flow.settled() and on_floor.flow.settled(), 80.0, "both pools fill"), "pools settle"):
		return
	t.check(on_rug.flow.cells.size() < on_floor.flow.cells.size() * 0.6, "rug blood does not travel as far (%d cells vs %d on bare floor)" % [on_rug.flow.cells.size(), on_floor.flow.cells.size()])
	var covered_before := _covered(on_rug)
	if not t.require(await t.until(func(): return not on_rug.flow.soaking(), 6.0, "the rug blood finishes soaking in"), "soaking ends"):
		return
	t.screenshot("rug_soaked")
	t.expect_near(on_rug.flow.soak_level(Vector2i.ZERO), 1.0, 0.01, "rug blood has sunk in")
	t.expect_near(on_rug.flow.fill(Vector2i.ZERO), 1.0, 0.01, "rug blood still fully covers its spot")
	t.expect_eq(_covered(on_rug), covered_before, "soaking does not shrink the pool's outline")
	t.check(BloodField.wetness_at(on_rug.global_position) < 0.05, "soaked blood is not wet enough to pick up")
	t.expect_near(on_floor.flow.fill(Vector2i.ZERO), 1.0, 0.01, "blood on bare floor stays fully filled")
	t.check(BloodField.wetness_at(on_floor.global_position) > 0.8, "blood on bare floor stays wet")

	t.check(BloodSurface.is_porous(Vector2(250, 250)), "the rug is a porous surface")
	rug.queue_free()
	await t.frames(2)
	t.check(not BloodSurface.is_porous(Vector2(250, 250)), "the spot is plain floor once the rug is gone")


## How many cells of `pool` are filled more than half (the outline the shader draws).
func _covered(pool: Node) -> int:
	var n := 0
	for c in pool.flow.cells:
		if pool.flow.fill(c) > 0.5:
			n += 1
	return n


## A bleed-out pool started at `at`.
func _pool(t: TestContext, at: Vector2) -> Node:
	var anchor := Node2D.new()
	t.world.add_child(anchor)
	anchor.global_position = at
	return BloodSpawner.bleed(t.world, anchor, [])

extends GameTest

## Two bleed-out pools in one room, one on a carpet floor and one on glazed tile. Once the front has swept
## out and BloodConfig.soak_time has passed, the carpet's blood has sunk in: it covers exactly the floor it
## covered (no shrinking, no holes; it is only translucent) but is no longer wet enough to leave prints or
## smears. The pool on tile is unchanged.


func describe() -> Dictionary:
	return {
		"name": "Blood soaks into carpet",
		"description": "A bleed-out pool on carpet soaks in without shrinking and is no longer wet; the same pool on tile stays fully filled and wet.",
		"tags": ["blood", "pool", "floor", "surface", "carpet"],
		"timeout": 120.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 900, 500))
	s.switch(&"physics.blood", true)
	s.set_static(BloodConfig, &"soak_time", 2.0)


func run(t: TestContext) -> void:
	FloorFactory.spawn(Rect2(40, 40, 380, 420), {
		"art": "floor", "color": Color(0.76, 0.7, 0.6), "material": "fabric", "art_opts": { "pattern": "carpet" },
	}, "TestCarpet", t.world)
	FloorFactory.spawn(Rect2(480, 40, 380, 420), {
		"art": "floor", "color": Color(0.8, 0.8, 0.8), "material": "ceramic", "art_opts": { "pattern": "tiles" },
	}, "TestTiles", t.world)
	var on_carpet := _pool(t, Vector2(230, 250))
	var on_tile := _pool(t, Vector2(670, 250))
	# Blood creeps slower over carpet: the tile pool has finished spreading while the carpet one still goes.
	if not t.require(await t.until(func(): return on_tile.flow.settled(), 20.0, "the pool on tile fills"), "tile pool settles"):
		return
	t.check(not on_carpet.flow.settled(), "the pool on carpet is still spreading when the tile one has finished")
	t.screenshot("carpet_soaking")
	if not t.require(await t.until(func(): return on_carpet.flow.settled(), 60.0, "the pool on carpet fills"), "carpet pool settles"):
		return
	t.check(on_carpet.flow.cells.size() < on_tile.flow.cells.size() * 0.6, "carpet blood does not travel as far (%d cells vs %d on tile)" % [on_carpet.flow.cells.size(), on_tile.flow.cells.size()])
	var covered_before := _covered(on_carpet)
	if not t.require(await t.until(func(): return not on_carpet.flow.soaking(), 6.0, "the carpet blood finishes soaking in"), "soaking ends"):
		return

	t.expect_near(on_carpet.flow.soak_level(Vector2i.ZERO), 1.0, 0.01, "carpet blood has sunk in")
	t.expect_near(on_carpet.flow.fill(Vector2i.ZERO), 1.0, 0.01, "carpet blood still fully covers its spot")
	t.expect_eq(_covered(on_carpet), covered_before, "soaking does not shrink the pool's outline")
	t.check(BloodField.wetness_at(on_carpet.global_position) < 0.05, "soaked blood is not wet enough to pick up (%.2f)" % BloodField.wetness_at(on_carpet.global_position))

	t.expect_near(on_tile.flow.fill(Vector2i.ZERO), 1.0, 0.01, "blood on tile stays fully filled")
	t.check(not on_tile.flow.soaking(), "blood on tile never soaks")
	t.check(BloodField.wetness_at(on_tile.global_position) > 0.8, "blood on tile stays wet (%.2f)" % BloodField.wetness_at(on_tile.global_position))
	t.screenshot("carpet_soaked")


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

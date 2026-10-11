extends GameTest

## BloodField answers where wet blood lies: wet inside a fresh splatter, dry outside it, drying to
## nothing with the splatter, and following a bleed-out pool's fill.


func describe() -> Dictionary:
	return {
		"name": "BloodField reports wet blood only where it lies",
		"description": "wetness_at is high inside a fresh splatter, 0 away from it and after it dries, and high at the middle of a settled bleed-out pool.",
		"tags": ["blood", "field"],
		"timeout": 25.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 900, 500))
	s.switch(&"physics.blood", true)
	s.set_static(BloodConfig, &"splat_dry_time", 3.0)
	s.actor(&"body", &"puppet", Vector2(650, 300))


func run(t: TestContext) -> void:
	var at := Vector2(200, 200)
	BloodSpawner.splat(t.world, at, 30.0, Vector2.RIGHT, 0.0, [])
	await t.frames(2)
	t.check(BloodField.wetness_at(at) > 0.5, "wet at the heart of a fresh splatter (%.2f)" % BloodField.wetness_at(at))
	t.expect_eq(BloodField.wetness_at(at + Vector2(0, 150)), 0.0, "bare floor away from it is dry")
	await t.seconds(3.5)
	t.expect_eq(BloodField.wetness_at(at), 0.0, "the splatter has dried to nothing")

	var pool := BloodSpawner.bleed(t.world, t.actor(&"body"), [])
	if not t.require(await t.until(func(): return pool.flow.settled(), 15.0, "the pool fills"), "pool settles"):
		return
	t.check(BloodField.wetness_at(pool.global_position) > 0.5, "wet at the middle of the pool (%.2f)" % BloodField.wetness_at(pool.global_position))

extends GameTest

## The same one-hit kill as death_bleeds_out, with the `physics.blood` switch off: the target still
## dies and falls, but no blood pool appears at all — the switch reaches the Physics domain.


func describe() -> Dictionary:
	return {
		"name": "No blood with the blood switch off",
		"description": "physics.blood off: a 1 hp target is shot dead and rests, with no wound pool and no bleed-out.",
		"tags": ["death", "blood", "switch"],
		"timeout": 12.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 800, 500))
	s.switch(&"projectile.flyover", false)
	s.switch(&"physics.blood", false)
	s.actor(&"shooter", &"puppet", Vector2(200, 250), { "start_slot": 3 })
	s.actor(&"target", &"puppet", Vector2(560, 250), { "max_health": 1.0 })


func run(t: TestContext) -> void:
	var shooter := t.puppet(&"shooter")
	shooter.aim_at(t.actor(&"target"))
	await t.seconds(0.4)
	shooter.shoot()
	if not t.require(await t.until(func(): return t.happened(&"died", func(d): return d["actor"] == &"target"), 2.0), "the target dies"):
		return
	await t.seconds(6.0)  # past the ragdoll settling, when a bleed-out would start
	t.expect_eq(t.spawned("BloodPool").size(), 0, "no blood pool was spawned")

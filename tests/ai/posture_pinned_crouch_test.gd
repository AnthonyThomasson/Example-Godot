extends GameTest

## A defender under fire in the open, with nothing between it and the shooter, crouches; a hit-free defender
## in the same arena does not. Shot at from the side it cannot see, the defender still gets low (it knows it is
## being shot).


func describe() -> Dictionary:
	return {
		"name": "A pinned defender crouches",
		"description": "Shot at in the open with the server down, the defender crouches; its twin out of the fire stays on its feet.",
		"tags": ["ai", "posture", "crouch", "under fire"],
		"timeout": 20.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 1000, 600))
	s.von_down()
	s.switch(&"ai.callouts", false)
	s.switch(&"ai.territory", false)
	s.switch(&"ai.hostile_on_sight", false)
	s.switch(&"ai.hostile_on_trespass", false)
	s.switch(&"nav.rebake", false)
	s.switch(&"projectile.flyover", false)  # every shot that arrives lands
	s.actor(&"pinned", &"defender", Vector2(700, 150))
	s.actor(&"bystander", &"defender", Vector2(700, 480))
	s.actor(&"gunman", &"puppet", Vector2(200, 150), { "start_slot": 3, "faction": &"invader", "max_health": 400.0 })


func run(t: TestContext) -> void:
	var pinned := t.actor(&"pinned")
	var bystander := t.actor(&"bystander")
	var gunman := t.puppet(&"gunman")
	await t.seconds(0.5)
	t.expect_eq(pinned.posture(), &"stand", "the defender starts standing")
	gunman.aim_at(pinned)
	await t.seconds(0.5)
	gunman.shoot()
	t.check(await t.until(func(): return pinned.is_crouching(), 5.0), "shot at in the open, the defender crouches (%s)" % pinned.posture())
	t.expect_eq(bystander.posture(), &"stand", "the defender out of the fire stays on its feet")

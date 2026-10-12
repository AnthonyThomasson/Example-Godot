extends GameTest

## With the `ai.posture` switch off an NPC always stands, however hard it is pressed: the same pinned defender that
## goes prone in `posture_pinned_prone_test` stays on its feet.


func describe() -> Dictionary:
	return {
		"name": "The posture switch keeps NPCs standing",
		"description": "Shot at in the open with the posture switch off, the defender never crouches or goes prone.",
		"tags": ["ai", "posture", "switch", "under fire"],
		"timeout": 15.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 1000, 400))
	s.von_down()
	s.switch(&"ai.posture", false)
	s.switch(&"ai.callouts", false)
	s.switch(&"ai.territory", false)
	s.switch(&"ai.hostile_on_sight", false)
	s.switch(&"ai.hostile_on_trespass", false)
	s.switch(&"nav.rebake", false)
	s.switch(&"projectile.flyover", false)
	s.actor(&"defender", &"defender", Vector2(700, 150))
	s.actor(&"gunman", &"puppet", Vector2(200, 150), { "start_slot": 3, "faction": &"invader", "max_health": 400.0 })


func run(t: TestContext) -> void:
	var defender := t.actor(&"defender")
	var gunman := t.puppet(&"gunman")
	gunman.aim_at(defender)
	await t.seconds(0.6)
	gunman.shoot()
	t.check(await t.until(func(): return defender.health < defender.max_health, 3.0), "the defender was shot")
	await t.seconds(4.0)
	t.expect_eq(defender.posture(), &"stand", "with the switch off it stays standing")

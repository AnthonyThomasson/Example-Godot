extends GameTest

## With every decision failing (server down), a defender that is shot at never leaves its idle hold and
## nothing is logged as an error: the fallback is quiet.


func describe() -> Dictionary:
	return {
		"name": "Server down: the defender holds steady",
		"description": "Every Von decision fails; the NPC keeps holding and the game logs no errors.",
		"tags": ["ai", "decision", "scripted", "fallback"],
		"timeout": 12.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 900, 600))
	s.von_down()
	s.switch(&"projectile.flyover", false)
	s.actor(&"defender", &"defender", Vector2(650, 300))
	s.actor(&"attacker", &"puppet", Vector2(200, 300), { "start_slot": 3, "faction": &"invader", "max_health": 400.0 })


func run(t: TestContext) -> void:
	var gunman := t.puppet(&"attacker")
	gunman.aim_at(t.actor(&"defender"))
	await t.seconds(0.6)
	gunman.shoot()
	await t.seconds(5.0)
	var brain := t.controller(&"defender", &"current_act")
	t.check(not t.von_requests().is_empty(), "the NPC did ask for a decision")
	t.check(t.von_requests().all(func(r): return r["pick"] == ""), "every ask failed")
	t.expect_eq(String(brain.current_act()), "hold", "the NPC is still holding")

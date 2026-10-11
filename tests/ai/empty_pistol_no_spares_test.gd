extends GameTest

## An NPC with an empty pistol and no spare magazine neither dry-fires forever nor is offered a reload.


func describe() -> Dictionary:
	return {
		"name": "An empty pistol with no spares is not offered a reload",
		"description": "The shot-at defender has an empty pistol and no spares: no reload is offered, it fires nothing, and it is not stuck.",
		"tags": ["ai", "reload", "ammo", "scripted", "combat"],
		"timeout": 20.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 900, 600))
	s.von_script([{ "pick": "combat" }])
	s.switch(&"ai.callouts", false)
	s.switch(&"ai.hostile_on_trespass", false)
	s.switch(&"projectile.flyover", false)
	s.actor(&"defender", &"defender", Vector2(650, 300), { "start_rounds": 0, "spare_magazine_types": [], "max_health": 400.0 })
	s.actor(&"attacker", &"puppet", Vector2(200, 300), { "start_slot": 3, "faction": &"invader", "max_health": 400.0 })


func run(t: TestContext) -> void:
	var gunman := t.puppet(&"attacker")
	gunman.aim_at(t.actor(&"defender"))
	await t.seconds(0.6)
	gunman.shoot()
	await t.seconds(0.3)
	var shots := t.spawned("Projectile").size()
	var brain := t.controller(&"defender", &"current_act")
	t.check(await t.until(func(): return String(brain.current_act()).begins_with("combat"), 8.0), "the defender enters combat")
	await t.seconds(4.0)
	t.check(not t.von_requests().is_empty(), "the NPC asked for decisions")
	t.check(t.von_requests().all(func(r): return not str(r["options"]).contains("reload")), "no level offered reload")
	t.check(t.von_requests().all(func(r): return not str(r["options"]).contains("engage")), "an empty pistol is never offered a clear shot")
	t.expect_eq(t.spawned("Projectile").size(), shots, "the empty pistol fired nothing")

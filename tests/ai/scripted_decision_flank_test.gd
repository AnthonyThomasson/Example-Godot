extends GameTest

## With Von scripted to answer combat → flank, a defender that is shot at ends up on a flank path: the
## decision wiring (snapshot → planner → behaviour) works without a server.


func describe() -> Dictionary:
	return {
		"name": "Scripted Von drives the defender into a flank",
		"description": "Von is scripted (combat, then flank); the shot-at defender's decision path follows the script and Von was asked about flanking.",
		"tags": ["ai", "decision", "scripted", "flank"],
		"timeout": 20.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 900, 600))
	s.von_script([{ "pick": "combat" }, { "pick": "flank" }])
	s.switch(&"ai.callouts", false)
	s.switch(&"ai.hostile_on_trespass", false)
	s.switch(&"projectile.flyover", false)
	s.actor(&"defender", &"defender", Vector2(650, 300))
	s.actor(&"attacker", &"puppet", Vector2(200, 300), { "start_slot": 3, "faction": &"invader", "max_health": 400.0 })


func run(t: TestContext) -> void:
	var gunman := t.puppet(&"attacker")
	gunman.aim_at(t.actor(&"defender"))
	await t.seconds(0.6)
	gunman.shoot()
	var brain := t.controller(&"defender", &"current_act")
	t.check(await t.until(func(): return String(brain.current_act()).begins_with("combat"), 8.0), "the defender enters combat")
	t.check(await t.until(func(): return String(brain.current_act()).contains("flank"), 8.0), "its decision path goes through flank (%s)" % brain.current_act())
	t.check(t.von_requests().any(func(r): return r["pick"] == "flank"), "a tactic level offered flank and the script picked it")

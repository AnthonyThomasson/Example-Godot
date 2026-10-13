extends GameTest

## In a fight, an NPC with a nearly empty pistol and spare magazines is told so (the loadout in the Von
## state), is offered a RELOAD tactic next to the shooting ones, runs it when Von picks it, and radios that
## it is reloading.


func describe() -> Dictionary:
	return {
		"name": "Scripted Von sends a dry defender to reload mid-fight",
		"description": "A hostile is in sight and the defender's pistol is nearly empty; Von sees that, picks combat then reload, and the pistol ends up full.",
		"tags": ["ai", "decision", "scripted", "reload", "callout", "ammo"],
		"timeout": 20.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 900, 600))
	s.von_script([{ "pick": "combat" }, { "pick": "reload" }])
	s.switch(&"ai.callouts", true)
	s.switch(&"ai.hostile_on_sight", true)
	s.switch(&"projectile.flyover", false)
	# The defender faces east at spawn, toward the (unarmed) stranger standing in plain sight.
	s.actor(&"defender", &"defender", Vector2(200, 300), { "start_rounds": 2, "max_health": 400.0, "spare_magazine_types": [&"standard", &"standard"] })
	s.actor(&"stranger", &"puppet", Vector2(600, 300), { "start_slot": 1, "faction": &"invader", "max_health": 400.0 })


func run(t: TestContext) -> void:
	var defender := t.actor(&"defender")
	var brain := t.controller(&"defender", &"current_act")
	t.check(await t.until(func(): return String(brain.current_act()).begins_with("combat/") and String(brain.current_act()).ends_with("/reload"), 8.0), "the defender's decision path goes through combat then reload (%s)" % brain.current_act())
	var asked := t.von_requests().filter(func(r): return str(r["options"]).contains("reload"))
	t.check(not asked.is_empty(), "a tactic level offered reload")
	t.check(asked.any(func(r): return String(r["state"]).contains("Your pistol is nearly empty. You carry spare magazines.")), "Von was told the pistol is nearly empty and spares are carried")
	t.check(t.happened(&"callout", func(d): return String(d.get("status", "")).contains("reloading")), "the defender radioed that it is reloading")
	t.check(await t.until(func(): return defender.ammo(3) == 12, 6.0), "the pistol is full again (%d)" % defender.ammo(3))
	t.expect_eq(defender.spare_magazines(), 2, "the old magazine was kept as a spare")

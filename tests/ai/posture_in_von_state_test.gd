extends GameTest

## What Von is told about postures: a hostile seen crouching is "crouched low" in its contact line, a
## hostile standing says nothing of the kind, and the defender's own state says "You are crouching." only once
## it has taken a crouch — a standing defender's text carries no posture words at all.


func describe() -> Dictionary:
	return {
		"name": "Von is told about postures only when someone is not standing",
		"description": "A standing defender and a standing hostile leave posture words out of Von's state; once the hostile crouches it is crouched low, and the fighting defender is crouching.",
		"tags": ["ai", "posture", "decision", "scripted", "snapshot"],
		"timeout": 30.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 900, 600))
	s.von_script([{ "pick": "combat" }, { "pick": "engage" }])
	s.switch(&"ai.callouts", false)
	s.switch(&"ai.territory", false)
	s.switch(&"ai.hostile_on_sight", true)
	s.switch(&"projectile.flyover", false)
	s.set_static(CharacterConfig, &"posture_change_time", 0.0)
	s.actor(&"defender", &"defender", Vector2(200, 300), { "max_health": 400.0 })
	s.actor(&"stranger", &"puppet", Vector2(600, 300), { "start_slot": 1, "faction": &"invader", "max_health": 400.0 })


func run(t: TestContext) -> void:
	var defender := t.actor(&"defender")
	defender.aim_point = t.actor(&"stranger").global_position
	t.check(await t.until(func(): return not t.von_requests().is_empty(), 8.0), "the defender asked Von")
	var first: String = String(t.von_requests()[0]["state"])
	t.check(first.contains("holding a"), "the state has the usual situation line")
	for word in ["crouch"]:
		t.check(not first.contains(word), "a standing defender and a standing hostile leave '%s' out of the state" % word)

	# The hostile crouches; later asks mention it.
	var asked := t.von_requests().size()
	t.puppet(&"stranger").set_posture(&"crouch")
	t.check(await t.until(func(): return t.von_requests().slice(asked).any(
		func(r): return String(r["state"]).contains("crouched low")), 15.0), "a hostile seen crouching is crouched low")
	# The defender fights in place, crouched, and says so.
	t.check(await t.until(func(): return t.von_requests().slice(asked).any(
		func(r): return String(r["state"]).contains("You are crouching.")), 15.0), "the crouching defender tells Von it is crouching")

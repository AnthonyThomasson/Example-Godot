extends GameTest

## The NPC presets' goal says "your {gun}", filled in with the gun each one carries: Von is told "your pistol", "your SMG"
## or "your assault rifle", never the raw placeholder, and the HUD's `goal_text()` reads the same. A pistol carrier's
## text is the original one.


func describe() -> Dictionary:
	return {
		"name": "The goal names the NPC's own gun",
		"description": "Defenders carrying a pistol, an SMG and a rifle are each told to shoot with their own gun; no placeholder reaches Von or the HUD.",
		"tags": ["ai", "gun", "goal", "prompt", "scripted"],
		"timeout": 10.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 900, 700))
	s.von_script([])
	s.switch(&"ai.callouts", false)
	# Three lanes, each a defender facing a hostile across open floor, its gun nearly empty with a spare carried, so
	# each has a real choice to put to Von (a lone option is taken without asking).
	var lanes := [
		[&"with_pistol", 3, &"standard", 120.0],
		[&"with_smg", 5, &"smg_standard", 350.0],
		[&"with_rifle", 6, &"rifle_standard", 580.0],
	]
	for lane in lanes:
		s.actor(lane[0], &"defender", Vector2(150, lane[3]), { "start_slot": lane[1], "start_rounds": 2,
			"spare_magazine_types": [lane[2]], "max_health": 400.0 })
		s.actor(StringName("%s_target" % lane[0]), &"puppet", Vector2(650, lane[3]),
			{ "start_slot": 1, "faction": &"invader", "max_health": 4000.0 })


func run(t: TestContext) -> void:
	var expect := {
		&"with_pistol": "your pistol",
		&"with_smg": "your SMG",
		&"with_rifle": "your assault rifle",
	}
	# Every NPC asks Von once it has decided; what each was told lives in the request's state text.
	t.check(await t.until(func(): return t.von_requests().size() >= 3, 8.0), "the NPCs ask Von (%d requests)" % t.von_requests().size())
	await t.seconds(0.5)
	for id: StringName in expect:
		var goal := String(t.controller(id, &"goal_text").goal_text())
		t.check(goal.contains(expect[id]), "%s: goal_text() says '%s' (%s)" % [id, expect[id], goal.left(90)])
		t.check(not goal.contains("{gun}"), "%s: no placeholder left in goal_text()" % id)
		t.check(t.von_requests().any(func(r): return String(r["state"]).contains(expect[id] + " to stop")),
			"%s: Von was told '%s'" % [id, expect[id]])
	t.check(not t.von_requests().any(func(r): return String(r["state"]).contains("{gun}")), "no request carries the raw placeholder")

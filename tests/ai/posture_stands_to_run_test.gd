extends GameTest

## Only a standing body runs, so an NPC that is crouched in a fight and then sent across the arena (combat →
## advance, a `run` leaf) stands up to do it: it is never crouched or prone while running, it does run, and
## it keeps low again when it is back to fighting in place.


func describe() -> Dictionary:
	return {
		"name": "An NPC stands up to run",
		"description": "A crouched defender told to advance on a far hostile stands, runs, and never runs while crouched.",
		"tags": ["ai", "posture", "run", "scripted"],
		"timeout": 30.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 3000, 600))
	s.von_script([{ "pick": "combat" }, { "pick": "advance" }])
	s.switch(&"ai.callouts", false)
	s.switch(&"ai.territory", false)
	s.switch(&"ai.hostile_on_sight", true)
	s.switch(&"nav.rebake", false)
	s.actor(&"runner", &"defender", Vector2(200, 300))
	s.set_props(&"runner", "GoalController", { "shoot_range": 1600.0 })
	s.actor(&"far", &"puppet", Vector2(1500, 300), { "faction": &"invader", "max_health": 400.0 })


func run(t: TestContext) -> void:
	var runner := t.actor(&"runner")
	var brain := t.controller(&"runner", &"current_act")
	runner.aim_point = t.actor(&"far").global_position
	t.check(await t.until(func(): return String(brain.current_act()).contains("advance"), 10.0), "the runner advances (%s)" % brain.current_act())
	var ran := false
	var ran_low := 0
	for i in 600:
		await t.frames(1)
		if runner.is_running():
			ran = true
			if runner.posture() != &"stand":
				ran_low += 1
	t.check(ran, "the runner ran")
	t.expect_eq(ran_low, 0, "never while crouched or prone")

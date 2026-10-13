extends GameTest

## Desired (the wiring): gunfire heard outside the house reaches Von worded as outside, and the
## INVESTIGATE level offers a way to decline the lead (STAY: hold your ground inside the house) next to the
## lead itself. Nothing removes the lead: Von decides, here scripted to decline, and the NPC then stays put.
## What a real Von picks for a defender is `defender_stays_in_house_von`.

const Probe := preload("res://tests/_ai/investigate_probe.gd")


func describe() -> Dictionary:
	return {
		"name": "An outside lead is worded as outside and can be declined",
		"description": "Gunfire is heard in the garden: Von is asked, told it is outside the house, offered the lead and STAY; scripted to stay, the NPC holds inside.",
		"tags": ["ai", "territory", "investigate", "decision", "scripted"],
		"timeout": 20.0,
	}


func configure(s: TestSetup) -> void:
	Probe.world(s, &"defender")
	s.von_script([{ "pick": "investigate" }, { "pick": "stay" }])


func run(t: TestContext) -> void:
	var npc := t.actor(&"npc")
	var brain := t.controller(&"npc", &"current_act")
	await t.seconds(1.0)
	Probe.gunfire(Probe.OUTSIDE)
	if not t.require(await t.until(func(): return String(brain.current_act()) == "investigate/stay", 6.0), "the decision path is investigate, then stay (%s)" % brain.current_act()):
		return
	var asked: Array = t.von_requests().filter(func(r): return String(r["question"]).begins_with("What should you check first"))
	if not t.require(not asked.is_empty(), "Von was asked what to check first"):
		return
	var level: Dictionary = asked[-1]
	t.check(level["options"].has("stay"), "STAY is offered at that level (%s)" % [level["options"]])
	t.check(level["options"].any(func(id): return String(id).begins_with("lead_gunfire")), "and so is the gunfire lead (%s)" % [level["options"]])
	t.check(String(level["state"]).contains("outside the house, "), "the state says the gunfire is outside the house (%s)" % level["state"])
	await t.seconds(4.0)
	t.check(npc.global_position.x > Probe.OUTSIDE_X, "the NPC stayed inside (at %s)" % npc.global_position.round())

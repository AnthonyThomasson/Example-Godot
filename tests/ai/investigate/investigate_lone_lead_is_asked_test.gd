extends GameTest

## Desired: Von is always asked about an investigation, even with a lone lead (INVESTIGATE's `ask` field):
## the planner never takes it for him. Gunfire heard INSIDE the house offers just the lead (no STAY), and the
## INVESTIGATE level is still a question Von answers.

const Probe := preload("res://tests/_ai/investigate_probe.gd")


func describe() -> Dictionary:
	return {
		"name": "A lone investigation lead is still asked of Von",
		"description": "Gunfire is heard in the kitchen: the INVESTIGATE level has one option and is asked rather than taken, and STAY is not offered for a lead inside.",
		"tags": ["ai", "investigate", "decision", "scripted"],
		"timeout": 15.0,
	}


func configure(s: TestSetup) -> void:
	Probe.world(s, &"defender")
	s.von_script([{ "pick": "investigate" }])


func run(t: TestContext) -> void:
	var brain := t.controller(&"npc", &"current_act")
	await t.seconds(1.0)
	Probe.gunfire(Probe.INSIDE)
	if not t.require(await t.until(func(): return String(brain.current_act()).begins_with("investigate/lead_gunfire"), 6.0), "the NPC investigates the lead (%s)" % brain.current_act()):
		return
	var asked: Array = t.von_requests().filter(func(r): return String(r["question"]).begins_with("What should you check first"))
	if not t.require(not asked.is_empty(), "Von was asked what to check first although there was a single lead"):
		return
	t.expect_eq(asked[-1]["options"].size(), 1, "the lead was the only option on offer")
	t.check(not Probe.levels(brain).any(func(l): return l.get("node") == "investigate" and l.get("auto", false)), "the INVESTIGATE level was not taken without asking")

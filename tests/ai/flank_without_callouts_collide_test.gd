extends GameTest

## The counterpart of flank_two_invaders_split_sides with the radio off: nothing tells the second invader
## the first has claimed left, and neither stands on the other's side of the target, so both are offered it
## and both take it (the contrast to B4: this is why the callouts exist).

const Flank := preload("res://tests/_ai/flank_probe.gd")
const Maps := preload("res://tests/_ai/flank_maps.gd")
const A_POS := Vector2(120, 350)
const B_POS := Vector2(120, 430)
const TARGET_POS := Vector2(620, 330)


func describe() -> Dictionary:
	return {
		"name": "Without the radio two invaders take the same flank side",
		"description": "Callouts off in the warehouse: both invaders prefer the left side and both end up flanking from it.",
		"tags": ["ai", "flank", "callout", "scripted"],
		"timeout": 20.0,
	}


func configure(s: TestSetup) -> void:
	Maps.warehouse(s)
	Flank.rules(s)
	s.switch(&"ai.callouts", false)
	Flank.npc(s, &"a", A_POS, {}, &"invader", TARGET_POS)
	Flank.npc(s, &"b", B_POS, { "max_commit_time": 0.55, "tactic_interval": 0.55, "decide_interval": 0.55 }, &"invader", TARGET_POS)
	Flank.target(s, &"target", TARGET_POS, A_POS)


func run(t: TestContext) -> void:
	t.puppet(&"target").aim_at(A_POS)
	var a := t.controller(&"a", &"current_act")
	var b := t.controller(&"b", &"current_act")
	await t.seconds(3.0)
	t.expect_eq(Flank.side_of_act(a), "left", "the first invader flanks from the left (%s)" % a.current_act())
	t.expect_eq(Flank.side_of_act(b), "left", "so does the second (%s)" % b.current_act())
	t.expect_eq(Flank.sides_claimed(t), 0, "nothing was radioed")

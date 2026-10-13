extends GameTest

## Desired (B4, B3): two invaders against one target split the flank. Von is scripted to prefer left, then
## right, then rear: the first to decide claims left over the radio, so the second is not offered it and
## takes right. They end on different sides (whichever decides first), each radioed its side, and each
## stays put on it.

const Flank := preload("res://tests/_ai/flank_probe.gd")
const Maps := preload("res://tests/_ai/flank_maps.gd")
const A_POS := Vector2(120, 350)
const B_POS := Vector2(120, 430)
const TARGET_POS := Vector2(620, 330)


func describe() -> Dictionary:
	return {
		"name": "Two invaders flank from different sides",
		"description": "Side by side in the warehouse both prefer the left side; the radio claim of the first sends the second to the right.",
		"tags": ["ai", "flank", "callout", "scripted"],
		"timeout": 20.0,
	}


func configure(s: TestSetup) -> void:
	Maps.warehouse(s)
	Flank.rules(s)
	# Different cadences so the two never decide on the same frame (a tie would claim the same side twice).
	Flank.npc(s, &"a", A_POS, {}, &"invader", TARGET_POS)
	Flank.npc(s, &"b", B_POS, { "max_commit_time": 0.55, "tactic_interval": 0.55, "decide_interval": 0.55 }, &"invader", TARGET_POS)
	Flank.target(s, &"target", TARGET_POS, A_POS)


func run(t: TestContext) -> void:
	t.puppet(&"target").aim_at(A_POS)
	var a := t.controller(&"a", &"current_act")
	var b := t.controller(&"b", &"current_act")
	await t.seconds(3.0)
	var sa := Flank.side_of_act(a)
	var sb := Flank.side_of_act(b)
	t.check(sa != "" and sb != "", "both ended up flanking (%s / %s)" % [a.current_act(), b.current_act()])
	t.check(sa != sb, "on different sides (%s / %s)" % [sa, sb])
	t.check(Flank.sides_claimed(t) >= 2, "each radioed its side")

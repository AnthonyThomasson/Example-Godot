extends GameTest

## Desired (B6): a spot with no shot is not a flank. A row of shelving stands between the target and the
## whole south side, so every point there has the line blocked and cover (the shelves) in the way: the NPC
## is told 'line blocked from there' with that cover, and the side is not offered; the open sides are.

const Flank := preload("res://tests/_ai/flank_probe.gd")
const Maps := preload("res://tests/_ai/flank_maps.gd")
const NPC_POS := Vector2(120, 350)
const TARGET_POS := Vector2(620, 330)


func describe() -> Dictionary:
	return {
		"name": "A flank point behind a shelf reads 'line blocked' with cover",
		"description": "A row of shelving screens the target's south side; that side reads 'line blocked from there' with cover and is not offered, the open sides are.",
		"tags": ["ai", "flank", "scripted"],
		"timeout": 15.0,
	}


func configure(s: TestSetup) -> void:
	Maps.warehouse(s)
	for i in 4:
		s.object(StringName("screen_%d" % i), "shelving", Vector2(500 + i * 90, 440))   # a screen south of the target
	Flank.rules(s)
	Flank.npc(s, &"npc", NPC_POS, {}, &"invader", TARGET_POS)
	Flank.target(s, &"target", TARGET_POS, NPC_POS)


func run(t: TestContext) -> void:
	t.puppet(&"target").aim_at(NPC_POS)
	var brain := t.controller(&"npc", &"current_act")
	if not await Flank.settle(t, brain):
		return
	var zones := Flank.zones(brain)
	if not t.require(zones.has("left"), "the south side was weighed (%s)" % Flank.dump(brain)):
		return
	var left: Dictionary = zones["left"]
	t.expect_eq(left["tags"]["clear_shot"], false, "the shot from there is blocked")
	t.expect_eq(left["tags"]["cover"], "shelves", "the shelves are in the way")
	t.check(String(left["desc"]).contains("line blocked from there"), "its description says the line is blocked (%s)" % left["desc"])
	var sides := Flank.offered_sides(brain)
	t.check(not sides.has("left"), "a side with no shot is not offered (%s)" % [sides])
	t.check(sides.has("right"), "the open north side is (%s | %s)" % [sides, Flank.dump(brain)])

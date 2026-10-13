extends GameTest

## Desired (B6): the flank spot is a firing position. A pillar stands just off the line between the
## target and its south flank point: the point still has a clear shot, and the NPC is told it has cover
## close by (the pillar), so a flank that ends behind cover is distinguishable from one in the open.

const Flank := preload("res://tests/_ai/flank_probe.gd")
const Maps := preload("res://tests/_ai/flank_maps.gd")
const NPC_POS := Vector2(120, 350)
const TARGET_POS := Vector2(620, 330)
const PILLAR_POS := Vector2(668, 500)    # beside the south point, off the line of fire


func describe() -> Dictionary:
	return {
		"name": "A flank point with cover beside it keeps its clear shot",
		"description": "A pillar stands beside the target's south flank point; it reads 'clear shot from there' and 'cover close by (the pillar)'.",
		"tags": ["ai", "flank", "scripted"],
		"timeout": 15.0,
	}


func configure(s: TestSetup) -> void:
	Maps.warehouse(s)
	s.object(&"pillar_south", Maps.PILLAR, PILLAR_POS)
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
	t.expect_eq(left["tags"]["clear_shot"], true, "the point has a clear shot")
	t.expect_eq(left["tags"]["cover"], "pillar", "the pillar is the cover beside it")
	t.check(String(left["desc"]).contains("clear shot from there"), "its description says clear shot (%s)" % left["desc"])
	t.check(String(left["desc"]).contains("cover close by (the pillar)"), "and cover close by (%s)" % left["desc"])
	t.check(Flank.offered_sides(brain).has("left"), "it is offered")

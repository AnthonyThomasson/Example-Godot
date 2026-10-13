extends GameTest

## Desired (B2): never walk a flank route past the target itself. A target holds the living room facing the
## hall door where the NPC watches it: its right (west) side and its rear are only reachable by walking
## across its field of view and right past it, so both are dropped as `crosses`; the open east side is the
## one flank left.

const Flank := preload("res://tests/_ai/flank_probe.gd")
const Maps := preload("res://tests/_ai/flank_maps.gd")
const NPC_POS := Vector2(150, 410)       # in the hall
const TARGET_POS := Vector2(150, 190)    # in the living room, facing the hall door


func describe() -> Dictionary:
	return {
		"name": "A flank whose route passes the target is dropped",
		"description": "The target guards the living room facing the hall door; the sides behind and west of it are tagged 'route passes target' and not offered, the east side is.",
		"tags": ["ai", "flank", "scripted"],
		"timeout": 15.0,
	}


func configure(s: TestSetup) -> void:
	Maps.house(s)
	Flank.rules(s)
	Flank.npc(s, &"npc", NPC_POS, {}, &"invader", TARGET_POS)  # starts looking at the target, as a held NPC must
	Flank.target(s, &"target", TARGET_POS, NPC_POS)


func run(t: TestContext) -> void:
	t.puppet(&"target").aim_at(NPC_POS)
	var brain := t.controller(&"npc", &"current_act")
	if not await Flank.settle(t, brain):
		return
	var zones := Flank.zones(brain)
	for side in ["rear", "right"]:
		if not t.check(zones.has(side), "the %s side was weighed (%s)" % [side, Flank.dump(brain)]):
			continue
		t.expect_eq(zones[side]["tags"]["crosses"], true, "the %s route is tagged crosses" % side)
		t.expect_eq(zones[side]["tags"]["crosses_name"], "target", "naming the target it passes")
		t.check(String(zones[side]["desc"]).contains("route passes target"), "the %s description says so (%s)" % [side, zones[side]["desc"]])
	var sides := Flank.offered_sides(brain)
	t.check(not sides.has("rear") and not sides.has("right"), "neither is offered (%s)" % [sides])
	t.check(sides.has("left"), "the east side, clear of the target, is offered (%s)" % [sides])

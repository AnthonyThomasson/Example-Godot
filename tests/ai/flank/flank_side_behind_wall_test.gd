extends GameTest

## Desired (B5, B6): a spot you cannot shoot from is not a flank. The target stands against the living
## room's north wall: its rear point is out in the front garden, behind that wall, and the shot from there
## is blocked by it. The NPC is told so, and the rear is not offered; the sides inside the room are.

const Flank := preload("res://tests/_ai/flank_probe.gd")
const Maps := preload("res://tests/_ai/flank_maps.gd")
const NPC_POS := Vector2(150, 410)       # in the hall, looking up through the living-room door
const TARGET_POS := Vector2(200, 50)     # against the living room's north wall, facing the door


func describe() -> Dictionary:
	return {
		"name": "A flank point behind a wall is weighed as outside, shot blocked",
		"description": "The target stands against the living room's north wall; its rear point is outside the house with the wall in the line of fire, and is not offered, while the sides inside the room are.",
		"tags": ["ai", "flank", "scripted"],
		"timeout": 15.0,
	}


func configure(s: TestSetup) -> void:
	Maps.house(s)
	Flank.rules(s)
	Flank.npc(s, &"npc", NPC_POS, {}, &"invader", TARGET_POS)
	Flank.target(s, &"target", TARGET_POS, NPC_POS)


func run(t: TestContext) -> void:
	t.puppet(&"target").aim_at(NPC_POS)
	var brain := t.controller(&"npc", &"current_act")
	if not await Flank.settle(t, brain):
		return
	var zones := Flank.zones(brain)
	if not t.require(zones.has("rear"), "the rear side was weighed (%s)" % Flank.dump(brain)):
		return
	var rear: Dictionary = zones["rear"]
	t.check(not Maps.HOUSE_BOUNDS.has_point(rear["point"]), "the rear point is outside the house (%s)" % [rear["point"]])
	t.expect_eq(rear["tags"]["inside"], false, "it is tagged outside")
	t.expect_eq(rear["tags"]["clear_shot"], false, "the shot from there is blocked")
	t.expect_eq(rear["tags"]["cover"], "wall", "the wall is in the way")
	t.check(String(rear["desc"]).contains("outside the house"), "its description says outside (%s)" % rear["desc"])
	t.check(String(rear["desc"]).contains("line blocked from there"), "its description says the line is blocked")
	var sides := Flank.offered_sides(brain)
	t.check(not sides.has("rear"), "a point with no shot is not offered as a flank (%s)" % [sides])
	for side in ["left", "right"]:
		t.check(sides.has(side) and zones[side]["tags"]["inside"], "the %s side, inside the room, is offered (%s)" % [side, Flank.dump(brain)])

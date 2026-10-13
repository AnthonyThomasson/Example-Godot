extends GameTest

## Desired (B8): a territorial defender does not leave its house to flank. An intruder stands by the
## kitchen's back door, facing into the house, so its rear is the garden beyond the open door, with a
## clear shot through it. The defender weighs that side, the description says outside the house, and it is
## not offered; the sides inside the kitchen are.

const Flank := preload("res://tests/_ai/flank_probe.gd")
const Maps := preload("res://tests/_ai/flank_maps.gd")
const NPC_POS := Vector2(780, 110)       # the kitchen's north-east corner, clear of the route to the back door
const TARGET_POS := Vector2(720, 260)    # south of the back door, facing into the house
const LOOKING_AT := Vector2(400, 190)


func describe() -> Dictionary:
	return {
		"name": "A territorial NPC is not offered a flank outside the house",
		"description": "A defender in the kitchen vs an intruder at the back door: the rear point is out in the garden with a clear shot and is not offered, the inside sides are.",
		"tags": ["ai", "flank", "territory", "scripted"],
		"timeout": 15.0,
	}


func configure(s: TestSetup) -> void:
	Maps.house(s)
	Flank.rules(s)
	s.switch(&"ai.hostile_on_trespass", true)  # the intruder is hostile for standing in the house
	Flank.npc(s, &"npc", NPC_POS, {}, &"defender", TARGET_POS)
	Flank.target(s, &"target", TARGET_POS, LOOKING_AT, { "faction": &"invader" })


func run(t: TestContext) -> void:
	t.puppet(&"target").aim_at(LOOKING_AT)
	var brain := t.controller(&"npc", &"current_act")
	if not await Flank.settle(t, brain):
		return
	var zones := Flank.zones(brain)
	if not t.require(zones.has("rear"), "the rear side was weighed (%s)" % Flank.dump(brain)):
		return
	t.expect_eq(zones["rear"]["tags"]["inside"], false, "the rear point is outside the house")
	t.expect_eq(zones["rear"]["tags"]["clear_shot"], true, "with a clear shot through the open back door")
	var sides := Flank.offered_sides(brain)
	t.check(not sides.has("rear"), "the outside side is not offered to a territorial NPC (%s)" % [sides])
	for side in sides:
		t.check(zones[side]["tags"]["inside"], "the offered %s side is inside the house" % side)

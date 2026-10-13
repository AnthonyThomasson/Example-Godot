extends GameTest

## Desired (B3): never flank across a friend's line of fire. An ally holds the east end of a warehouse and
## shoots west at the target; the NPC comes up from the south-east. Walking round to the target's north
## side would cut across the ally's line of fire, so that side is not offered; the south and west sides,
## whose routes stay clear of the line, are. The NPC stands where the ally is inside its view cone (110°,
## so the ally must bear within 55° of its line to the target): it only weighs allies it can see.

const Flank := preload("res://tests/_ai/flank_probe.gd")
const Maps := preload("res://tests/_ai/flank_maps.gd")
const NPC_POS := Vector2(900, 420)
const TARGET_POS := Vector2(620, 330)
const BUDDY_POS := Vector2(860, 330)     # shooting west along the target's row


func describe() -> Dictionary:
	return {
		"name": "A flank across an ally's line of fire is not offered",
		"description": "An ally shoots at the target from the east; the NPC's route to the target's north side crosses that line of fire, so the side is dropped.",
		"tags": ["ai", "flank", "scripted"],
		"timeout": 15.0,
	}


func configure(s: TestSetup) -> void:
	Maps.warehouse(s, false)
	s.object(&"shelf_nw", "shelving", Vector2(200, 150))     # cover well away from the fight
	s.object(&"bench_sw", "workbench", Vector2(160, 600))
	s.object(&"chest_ne", "tool_chest", Vector2(900, 90))
	Flank.rules(s)
	Flank.npc(s, &"npc", NPC_POS, { "route_clearance": 40.0 }, &"invader", TARGET_POS)   # only the lane rule is under test, not the target-clearance rule
	Flank.target(s, &"target", TARGET_POS, BUDDY_POS)
	Flank.ally(s, &"buddy", BUDDY_POS, { "aim_point": TARGET_POS })


func run(t: TestContext) -> void:
	t.puppet(&"target").aim_at(BUDDY_POS)
	t.puppet(&"buddy").aim_at(TARGET_POS)
	var brain := t.controller(&"npc", &"current_act")
	if not await Flank.settle(t, brain):
		return
	var zones := Flank.zones(brain)
	var north_cuts_the_line := false
	for side in zones:
		if Flank.crosses_fire_line(t, NPC_POS, zones[side]["point"], BUDDY_POS, TARGET_POS):
			north_cuts_the_line = true
	if not t.require(north_cuts_the_line, "one weighed side has a route across the ally's line of fire (%s)" % Flank.dump(brain)):
		return
	var sides := Flank.offered_sides(brain)
	for side in sides:
		t.check(not Flank.crosses_fire_line(t, NPC_POS, zones[side]["point"], BUDDY_POS, TARGET_POS),
			"the offered %s side does not make the NPC cross the ally's line of fire (%s)" % [side, Flank.dump(brain)])
	t.check(not sides.is_empty(), "a safe side is still offered (%s)" % [sides])

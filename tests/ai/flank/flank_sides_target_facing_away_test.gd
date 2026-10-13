extends GameTest

## A target with its back to the NPC: the NPC already stands on its rear, so only the left and right are
## offered. Desired (B1): the target cannot see the approach, so neither route is described as exposed to
## it; a target's view is its facing cone, not a line to its position.

const Flank := preload("res://tests/_ai/flank_probe.gd")
const Maps := preload("res://tests/_ai/flank_maps.gd")
const NPC_POS := Vector2(150, 330)       # just inside the living room, by the hall door
const TARGET_POS := Vector2(330, 170)    # mid-room
const LOOKING_AT := Vector2(550, 20)     # away from the NPC, toward the kitchen archway


func describe() -> Dictionary:
	return {
		"name": "Flank sides of a target that faces away from the NPC",
		"description": "In the living room the target looks away; the NPC is on its rear, so only left and right are offered, and neither route is exposed to a target that cannot see it.",
		"tags": ["ai", "flank", "scripted"],
		"timeout": 15.0,
	}


func configure(s: TestSetup) -> void:
	Maps.house(s)
	Flank.rules(s)
	Flank.npc(s, &"npc", NPC_POS, {}, &"invader", TARGET_POS)
	Flank.target(s, &"target", TARGET_POS, LOOKING_AT)


func run(t: TestContext) -> void:
	t.puppet(&"target").aim_at(LOOKING_AT)
	var brain := t.controller(&"npc", &"current_act")
	if not await Flank.settle(t, brain):
		return
	var facing := (LOOKING_AT - TARGET_POS).normalized()
	t.expect_eq(Flank.side_of(TARGET_POS, facing, NPC_POS), "rear", "the NPC stands on the target's rear")
	var zones := Flank.zones(brain)
	t.check(not zones.has("rear"), "the NPC's own side is not weighed (%s)" % Flank.dump(brain))
	for side in ["left", "right"]:
		if not t.check(zones.has(side), "the %s side was weighed (%s)" % [side, Flank.dump(brain)]):
			continue
		t.expect_eq(Flank.side_of(TARGET_POS, facing, zones[side]["point"]), side, "the %s point lies on the target's %s" % [side, side])
		t.expect_eq(zones[side]["tags"]["route_exposed"], false, "the route to the %s side is not in the view of a target looking away" % side)
	var sides := Flank.offered_sides(brain)
	t.check(sides.has("left") and sides.has("right") and not sides.has("rear"), "left and right are offered, rear is not (%s)" % [sides])

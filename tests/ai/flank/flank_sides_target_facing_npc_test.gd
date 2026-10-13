extends GameTest

## Desired (F): a target facing the NPC across a warehouse: the NPC stands on its front, so its left,
## right and rear are all open. Each flank point lies on that side of the target's own frame, within flank range, with a clear
## shot, and none of the routes there passes the target (B1, B2): the whole fan is on offer.

const Flank := preload("res://tests/_ai/flank_probe.gd")
const Maps := preload("res://tests/_ai/flank_maps.gd")
const NPC_POS := Vector2(120, 350)
const TARGET_POS := Vector2(620, 330)


func describe() -> Dictionary:
	return {
		"name": "Flank sides of a target that faces the NPC",
		"description": "In the warehouse the target looks at the NPC; left, right and rear are all offered, lie on the right side of the target's frame with a clear shot.",
		"tags": ["ai", "flank", "scripted"],
		"timeout": 15.0,
	}


func configure(s: TestSetup) -> void:
	Maps.warehouse(s)
	Flank.rules(s)
	Flank.npc(s, &"npc", NPC_POS, {}, &"invader", TARGET_POS)
	Flank.target(s, &"target", TARGET_POS, NPC_POS)


func run(t: TestContext) -> void:
	t.puppet(&"target").aim_at(NPC_POS)  # keep looking at the NPC
	var brain := t.controller(&"npc", &"current_act")
	if not await Flank.settle(t, brain):
		return
	var facing := (NPC_POS - TARGET_POS).normalized()
	var zones := Flank.zones(brain)
	t.expect_eq(zones.keys().size(), 3, "all three sides were weighed (%s)" % Flank.dump(brain))
	for side in ["left", "right", "rear"]:
		if not t.check(zones.has(side), "the %s side exists" % side):
			continue
		var p: Vector2 = zones[side]["point"]
		t.expect_eq(Flank.side_of(TARGET_POS, facing, p), side, "the %s point lies on the target's %s" % [side, side])
		t.check(p.distance_to(TARGET_POS) <= 240.0, "the %s point is within flank range of the target (%.0f px)" % [side, p.distance_to(TARGET_POS)])
		t.expect_eq(zones[side]["tags"]["clear_shot"], true, "there is a clear shot at the target from the %s point" % side)
		t.expect_eq(zones[side]["tags"]["crosses"], false, "the route to the %s point passes no hostile" % side)
	var sides := Flank.offered_sides(brain)
	t.check(sides.has("left") and sides.has("right") and sides.has("rear"), "the flank level offers every side (%s)" % [sides])

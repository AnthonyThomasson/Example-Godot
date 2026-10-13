extends GameTest

## Desired (F): sides are the target's own. A target looking across the NPC's line (north, with the NPC
## due west of it): the NPC stands on the target's own left, so left is not offered; the right (east) and the rear (south) are, on the right side
## of the target's frame.

const Flank := preload("res://tests/_ai/flank_probe.gd")
const Maps := preload("res://tests/_ai/flank_maps.gd")
const NPC_POS := Vector2(120, 350)
const TARGET_POS := Vector2(620, 330)
const LOOKING_AT := Vector2(620, 100)    # north, across the NPC's line


func describe() -> Dictionary:
	return {
		"name": "Flank sides of a target that looks across the NPC's line",
		"description": "In the warehouse the target looks north with the NPC on its left; right and rear are offered, left (the NPC's own side) is not.",
		"tags": ["ai", "flank", "scripted"],
		"timeout": 15.0,
	}


func configure(s: TestSetup) -> void:
	Maps.warehouse(s)
	Flank.rules(s)
	Flank.npc(s, &"npc", NPC_POS, {}, &"invader", TARGET_POS)
	Flank.target(s, &"target", TARGET_POS, LOOKING_AT)


func run(t: TestContext) -> void:
	t.puppet(&"target").aim_at(LOOKING_AT)
	var brain := t.controller(&"npc", &"current_act")
	if not await Flank.settle(t, brain):
		return
	var facing := (LOOKING_AT - TARGET_POS).normalized()
	t.expect_eq(Flank.side_of(TARGET_POS, facing, NPC_POS), "left", "the NPC stands on the target's left")
	var zones := Flank.zones(brain)
	t.check(not zones.has("left"), "the NPC's own side is not weighed (%s)" % Flank.dump(brain))
	for side in ["right", "rear"]:
		if not t.check(zones.has(side), "the %s side was weighed (%s)" % [side, Flank.dump(brain)]):
			continue
		t.expect_eq(Flank.side_of(TARGET_POS, facing, zones[side]["point"]), side, "the %s point lies on the target's %s" % [side, side])
	var sides := Flank.offered_sides(brain)
	t.check(sides.has("right") and sides.has("rear") and not sides.has("left"), "right and rear are offered, left is not (%s)" % [sides])

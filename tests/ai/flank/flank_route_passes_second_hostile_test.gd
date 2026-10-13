extends GameTest

## Desired (B2): a flank route never passes another hostile. The NPC and the target face off across a
## warehouse and a guard stands in the south: the walks to the target's south and east sides both pass it
## and are dropped as 'route passes guard', while the north side, whose route is clear of both hostiles,
## is offered.

const Flank := preload("res://tests/_ai/flank_probe.gd")
const Maps := preload("res://tests/_ai/flank_maps.gd")
const NPC_POS := Vector2(120, 350)
const TARGET_POS := Vector2(620, 330)
const GUARD_POS := Vector2(330, 470)     # on the way to the south side


func describe() -> Dictionary:
	return {
		"name": "A flank route that passes another hostile is dropped",
		"description": "A second hostile stands in the south of the warehouse; the south and east walks read 'route passes guard' and are not offered, the north side is.",
		"tags": ["ai", "flank", "scripted"],
		"timeout": 15.0,
	}


func configure(s: TestSetup) -> void:
	Maps.warehouse(s)
	Flank.rules(s)
	Flank.npc(s, &"npc", NPC_POS, {}, &"invader", TARGET_POS)
	Flank.target(s, &"target", TARGET_POS, NPC_POS)
	Flank.target(s, &"guard", GUARD_POS, NPC_POS)


func run(t: TestContext) -> void:
	t.puppet(&"target").aim_at(NPC_POS)
	t.puppet(&"guard").aim_at(NPC_POS)
	var brain := t.controller(&"npc", &"current_act")
	Flank.prefer_target(t, &"target")   # read the flanks of the target, not of the guard
	if not await Flank.settle(t, brain):
		return
	var zones := Flank.zones(brain, TARGET_POS)
	var facing := (NPC_POS - TARGET_POS).normalized()
	var south := Flank.side_point(TARGET_POS, facing, "left")
	var left := {}
	for side in zones:
		if (zones[side]["point"] as Vector2).distance_to(south) < 60.0:
			left = zones[side]
	if not t.require(not left.is_empty(), "the south side was weighed (%s)" % Flank.dump(brain, TARGET_POS)):
		return
	t.expect_eq(left["tags"]["crosses"], true, "its route is tagged crosses")
	t.expect_eq(left["tags"]["crosses_name"], "guard", "naming the hostile it passes")
	t.check(String(left["desc"]).contains("route passes guard"), "its description says so (%s)" % left["desc"])
	var sides := Flank.offered_sides(brain)
	t.check(not sides.has("left"), "the south side is not offered (%s)" % [sides])
	var rear: Dictionary = zones.get("rear", {})
	t.expect_eq(rear.get("tags", {}).get("crosses_name"), "guard", "the long walk east passes the guard too")
	t.check(not sides.has("rear"), "so the east side is not offered (%s)" % [sides])
	t.check(sides.has("right"), "the north side is (%s | %s)" % [sides, Flank.dump(brain, TARGET_POS)])

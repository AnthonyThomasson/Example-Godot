extends GameTest

## Desired (B4): a side an ally has radioed is its own. An ally in the kitchen, out of the NPC's sight,
## radios that it is going to the target's left; the NPC in the living room is told the side is 'taken by
## … (radio)' and is not offered it, while the right side is. (The call's lapse after `callout_ttl` is not
## tested: memory ages in wall-clock ms, which a headless fixed-fps run outruns.)

const Flank := preload("res://tests/_ai/flank_probe.gd")
const Maps := preload("res://tests/_ai/flank_maps.gd")
const NPC_POS := Vector2(150, 330)       # just inside the living room, by the hall door
const TARGET_POS := Vector2(330, 170)    # mid-room, facing the NPC


func describe() -> Dictionary:
	return {
		"name": "A flank side claimed over the radio is not offered",
		"description": "An ally in the kitchen radios the target's left; in the living room left reads 'taken by … (radio)' and is dropped, right is offered.",
		"tags": ["ai", "flank", "callout", "scripted"],
		"timeout": 15.0,
	}


func configure(s: TestSetup) -> void:
	Maps.house(s)
	Flank.rules(s)
	Flank.npc(s, &"npc", NPC_POS, {}, &"invader", TARGET_POS)
	Flank.target(s, &"target", TARGET_POS, NPC_POS)
	Flank.ally(s, &"radio_ally", Vector2(700, 110))   # in the kitchen, behind the wall


func run(t: TestContext) -> void:
	t.puppet(&"target").aim_at(NPC_POS)
	var brain := t.controller(&"npc", &"current_act")
	var facing := (NPC_POS - TARGET_POS).normalized()
	Flank.radio(t, &"radio_ally", Flank.side_point(TARGET_POS, facing, "left"))
	if not await Flank.settle(t, brain):
		return
	var zones := Flank.zones(brain)
	if not t.require(zones.has("left"), "the left side was weighed (%s)" % Flank.dump(brain)):
		return
	t.expect_eq(zones["left"]["tags"]["held_by"], "radio_ally (radio)", "the left side is held over the radio")
	t.check(String(zones["left"]["desc"]).contains("taken by radio_ally (radio)"), "its description says so (%s)" % zones["left"]["desc"])
	var sides := Flank.offered_sides(brain)
	t.check(not sides.has("left"), "left is dropped (%s)" % [sides])
	t.check(sides.has("right"), "right is offered (%s)" % [sides])

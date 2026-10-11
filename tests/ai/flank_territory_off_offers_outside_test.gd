extends GameTest

## The contrast to B8, the counterpart of flank_territory_confines_sides: the same kitchen, the same intruder at the back
## door, but the defender is not territorial, so the garden side is offered like any other.

const Flank := preload("res://tests/_ai/flank_probe.gd")
const Maps := preload("res://tests/_ai/flank_maps.gd")
const NPC_POS := Vector2(780, 110)
const TARGET_POS := Vector2(720, 260)
const LOOKING_AT := Vector2(400, 190)


func describe() -> Dictionary:
	return {
		"name": "Without territory the outside flank side is offered",
		"description": "The same defender and intruder with defend_territory off: the rear point in the garden, through the back door, is offered.",
		"tags": ["ai", "flank", "territory", "scripted"],
		"timeout": 15.0,
	}


func configure(s: TestSetup) -> void:
	Maps.house(s)
	Flank.rules(s)
	s.switch(&"ai.hostile_on_trespass", true)
	s.switch(&"ai.territory", false)
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
	t.check(Flank.offered_sides(brain).has("rear"), "the outside side is offered (%s)" % [Flank.offered_sides(brain)])

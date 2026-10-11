extends GameTest

## Desired (C): `disabled_nodes = [flank]` takes the FLANK tactic away from that NPC however open the sides are.
## Two invaders stand shoulder to shoulder in the hall watching a target through the living-room door: the
## one with the node disabled is never offered a flank, while its neighbour (the control) is, so it is the
## switch and not the geometry that removed it.

const Flank := preload("res://tests/_ai/flank_probe.gd")
const Maps := preload("res://tests/_ai/flank_maps.gd")
const DISABLED_POS := Vector2(130, 420)
const CONTROL_POS := Vector2(170, 420)
const TARGET_POS := Vector2(150, 200)    # in the living room, facing the hall door


func describe() -> Dictionary:
	return {
		"name": "A disabled flank node is never offered",
		"description": "Two invaders watch a target through the living-room door; the one with the flank node disabled is offered engage/advance only, the other is offered flank.",
		"tags": ["ai", "flank", "decision", "scripted"],
		"timeout": 15.0,
	}


func configure(s: TestSetup) -> void:
	Maps.house(s)
	Flank.rules(s)
	var disabled: Array[StringName] = [&"flank"]
	Flank.npc(s, &"disabled", DISABLED_POS, { "disabled_nodes": disabled })
	Flank.npc(s, &"control", CONTROL_POS)
	Flank.target(s, &"target", TARGET_POS, Vector2(150, 415))


func run(t: TestContext) -> void:
	t.puppet(&"target").aim_at(Vector2(150, 415))
	var off := t.controller(&"disabled", &"current_act")
	var on := t.controller(&"control", &"current_act")
	if not await Flank.settle(t, off) or not await Flank.settle(t, on):
		return
	t.check(Flank.offered(on, "combat").has("flank"), "the control is offered flank (%s)" % [Flank.offered(on, "combat")])
	t.check(not Flank.offered(off, "combat").has("flank"), "the disabled NPC is not (%s)" % [Flank.offered(off, "combat")])
	t.check(not String(off.current_act()).contains("flank"), "it is not flanking (%s)" % off.current_act())
	t.check(not Flank.zones(off).is_empty(), "the sides are still weighed: the tree, not the geometry, removed flank")

extends GameTest

## Desired (B4): a target already boxed in by the squad gets no flank. Three allies in the kitchen radio the
## target's left, right and rear while the NPC watches it from the hall through the living-room door; every
## side is held, so combat offers no FLANK and the NPC fights directly (engage or advance), never idle.

const Flank := preload("res://tests/_ai/flank_probe.gd")
const Maps := preload("res://tests/_ai/flank_maps.gd")
const NPC_POS := Vector2(150, 410)       # in the hall, looking up through the living-room door
const TARGET_POS := Vector2(230, 190)    # in the living room, facing the door


func describe() -> Dictionary:
	return {
		"name": "With every side taken there is no FLANK tactic",
		"description": "In the terrace house three allies in the kitchen radio the target's left, right and rear; the NPC in the hall is offered no flank and fights directly.",
		"tags": ["ai", "flank", "callout", "scripted"],
		"timeout": 15.0,
	}


func configure(s: TestSetup) -> void:
	Maps.house(s)
	Flank.rules(s)
	Flank.npc(s, &"npc", NPC_POS)
	Flank.target(s, &"target", TARGET_POS, NPC_POS)
	Flank.ally(s, &"radio_a", Vector2(600, 110))
	Flank.ally(s, &"radio_b", Vector2(720, 260))
	Flank.ally(s, &"radio_c", Vector2(590, 300))


func run(t: TestContext) -> void:
	t.puppet(&"target").aim_at(NPC_POS)
	var brain := t.controller(&"npc", &"current_act")
	var facing := (NPC_POS - TARGET_POS).normalized()
	Flank.radio(t, &"radio_a", Flank.side_point(TARGET_POS, facing, "left"))
	Flank.radio(t, &"radio_b", Flank.side_point(TARGET_POS, facing, "right"))
	Flank.radio(t, &"radio_c", Flank.side_point(TARGET_POS, facing, "rear"))
	if not await Flank.settle(t, brain):
		return
	var zones := Flank.zones(brain)
	t.check(not zones.is_empty(), "the sides were still weighed (%s)" % Flank.dump(brain))
	for side in zones:
		t.expect_eq(zones[side]["tags"]["held"], true, "the %s side is held (%s)" % [side, Flank.dump(brain)])
	var tactics := Flank.offered(brain, "combat")
	t.check(not tactics.has("flank"), "combat offers no flank (%s)" % [tactics])
	t.check(tactics.has("engage") or tactics.has("advance"), "it still has a direct way to fight (%s)" % [tactics])
	t.check(String(brain.current_act()).begins_with("combat/"), "the NPC is fighting, not idle (%s)" % brain.current_act())
	var state := String(Flank.level(brain, "combat").get("state", ""))
	for caller in ["radio_a", "radio_b"]:   # the rear is also tagged 'route passes target', which the wording puts first
		t.check(state.contains("taken by %s (radio)" % caller), "the state says %s holds a side (%s)" % [caller, state.replace("\n", " ")])

extends GameTest

## Desired (B5): where the terrain denies a flank there is none. A target holds the dead end of a long
## corridor facing the NPC: its left and rear are walls and the garden beyond them, and its right is a
## side room it can only be shot at through the wall. No side has a shot, so none is offered and combat
## has no FLANK; the NPC fights directly.

const Flank := preload("res://tests/_ai/flank_probe.gd")
const Maps := preload("res://tests/_ai/flank_maps.gd")
const NPC_POS := Vector2(420, 250)
const TARGET_POS := Maps.CORRIDOR_DEAD_END


func describe() -> Dictionary:
	return {
		"name": "A target at a corridor's dead end cannot be flanked",
		"description": "The target holds the dead end of a corridor; every flank point is behind a wall, so combat offers no flank and the NPC engages directly.",
		"tags": ["ai", "flank", "scripted", "gap"],
		"timeout": 15.0,
	}


func configure(s: TestSetup) -> void:
	Maps.spine(s)
	Flank.rules(s)
	Flank.npc(s, &"npc", NPC_POS, {}, &"invader", TARGET_POS)
	Flank.target(s, &"target", TARGET_POS, NPC_POS)


func run(t: TestContext) -> void:
	t.puppet(&"target").aim_at(NPC_POS)
	var brain := t.controller(&"npc", &"current_act")
	if not await Flank.settle(t, brain):
		return
	var zones := Flank.zones(brain)
	t.check(not zones.is_empty(), "sides were weighed (%s)" % Flank.dump(brain))
	for side in zones:
		t.expect_eq(zones[side]["tags"]["clear_shot"], false, "there is no shot at the target from the %s point" % side)
	var tactics := Flank.offered(brain, "combat")
	t.check(not tactics.has("flank"), "combat offers no flank (%s | %s)" % [tactics, Flank.dump(brain)])
	t.check(tactics.has("engage") or tactics.has("advance"), "the NPC still has a direct way to fight (%s)" % [tactics])

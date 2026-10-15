extends GameTest

## G18 as amended (issue #51, R6): footsteps heard in a room make it suspect, as gunfire heard there does. The stack of two invaders,
## both carrying a stun, in the back garden by the kitchen's back door hears someone walking about the kitchen's north-east corner,
## behind the wall and out of their sight: it goes in by STUN ENTRY, not the quiet ENTER. The whole pipeline runs with real Von; a
## `require` that the stack went for the kitchen by its back door comes first. (`quiet_entry_unsuspected_room` is the control: nothing
## heard, ENTER.)
##
## It judges the entry the stack WENT IN WITH, not its first decision (`Suspect.check_stun_entry_gone_in`, issue #51 R11): the invaders
## decide on their first frames, and the first of them can decide before the walker's first step reaches it, so it may take the quiet
## ENTER and hear the steps while it lines up. A late reason turns a quiet entry into a bang before anyone crosses
## (`docs/tactical-entry.md` E17), so the check is that each member heard the steps before it took STUN ENTRY, that every member went in
## under STUN ENTRY, and that a bang was radioed and a stun went off in the kitchen before anyone went in or stood in it.
##
## Premise: the walker is a household puppet (the thing to be heard) pacing a short lane in the corner, 150 to 240 px from the stack
## through the wall and hidden from every spot outside the back door; unkillable, it never shoots. Both invaders are armed with a stun
## at the start of `run`, the way Main arms a spawn.

const Suspect := preload("res://tests/_ai/suspect_probe.gd")
const LANE := [Vector2(810, 45), Vector2(750, 45)]


func describe() -> Dictionary:
	return {
		"name": "A stack takes a stun entry into a room where footsteps were heard",
		"description": "Two invaders with a stun at the kitchen's back door hear someone walking about the kitchen behind the wall: STUN ENTRY, not the quiet ENTER.",
		"tags": ["ai", "grenade", "entry", "stun", "hearing", "von"],
		"requires_von": true,
		"timeout": 80.0,
	}


func configure(s: TestSetup) -> void:
	Suspect.world(s)
	s.actor(&"walker", &"puppet", LANE[0], { "faction": &"household", "max_health": 1000000.0 })


func run(t: TestContext) -> void:
	if not t.require(Suspect.arm(t), "both invaders carry a stun grenade (Character.item_count(7))"):
		return
	var walker := t.puppet(&"walker")
	var leg := [0]
	walker.walk_to(LANE[1])
	var pace := func(_now: float) -> void:
		if walker.has_arrived():
			leg[0] = (leg[0] + 1) % 2
			walker.walk_to(LANE[leg[0]])
	var result: Dictionary = await Suspect.watch_in(t, 60.0, pace)
	Suspect.check_stun_entry_gone_in(t, result, "footsteps heard in the kitchen")

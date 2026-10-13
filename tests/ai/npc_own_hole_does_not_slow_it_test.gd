extends GameTest

## A character is a hole in the steering map and so is the NPC itself, standing inside its own hole when it sets
## off. Its path starts at the nearest open ground, which must not send it off the wrong way or make it
## re-plan every frame: with nobody else around, an NPC advancing across an open arena covers the ground as
## fast as its pace allows and never stalls.

const PAST_X := 700.0
const RUN_SPEED := 150.0 * 1.7


func describe() -> Dictionary:
	return {
		"name": "An NPC's own nav hole does not slow it",
		"description": "A lone defender advances on a far hostile across an open arena: it reaches the halfway mark in about the time its pace needs, in a straight line, without a stall.",
		"tags": ["ai", "navigation", "character", "scripted"],
		"timeout": 30.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 1500, 520))
	s.von_script([{ "pick": "combat" }, { "pick": "advance" }])
	s.switch(&"nav.rebake", true)
	s.switch(&"ai.callouts", false)
	s.switch(&"ai.territory", false)
	s.switch(&"ai.hostile_on_sight", false)
	s.actor(&"npc", &"defender", Vector2(100, 260))
	s.actor(&"far", &"puppet", Vector2(1400, 260), { "faction": &"invader", "max_health": 1.0e6 })


func run(t: TestContext) -> void:
	var npc := t.actor(&"npc")
	var brain := t.controller(&"npc", &"current_act")
	var stalled := 0.0
	var off_line := 0.0
	var start := t.time
	while npc.global_position.x < PAST_X and t.time - start < 20.0:
		await t.frames(1)
		off_line = maxf(off_line, absf(npc.global_position.y - 260.0))
		stalled = maxf(stalled, float(brain.debug_progress().get("stalled_for", 0.0)))
	var took := t.time - start
	t.trace("took", took)
	t.trace("off_line", off_line)
	t.check(npc.global_position.x >= PAST_X, "the NPC crosses the arena (x=%.0f, %s)" % [npc.global_position.x, brain.current_act()])
	t.check(took < (PAST_X - 100.0) / RUN_SPEED + 1.5, "at its pace (%.2f s for %.0f px)" % [took, PAST_X - 100.0])
	t.check(off_line < 12.0, "in a straight line (strayed %.1f px)" % off_line)
	t.check(stalled < 1.0, "without a stall (longest %.2f s without progress)" % stalled)

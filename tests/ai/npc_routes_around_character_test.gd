extends GameTest

## An NPC advancing on a far hostile goes AROUND a friendly character standing on its line instead of into it,
## and does not stall on the way. The standing character is a hole in the steering map the NPC walks.

const PAST_X := 700.0
const BLOCKER := Vector2(400, 260)


func describe() -> Dictionary:
	return {
		"name": "An NPC routes around a standing character",
		"description": "A defender advances on a far hostile along a lane with a friendly puppet standing on it. It passes the puppet without touching it and without a stall.",
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
	s.actor(&"npc", &"defender", Vector2(100, BLOCKER.y))
	s.actor(&"blocker", &"puppet", BLOCKER, { "faction": &"household", "max_health": 1.0e6 })
	s.actor(&"far", &"puppet", Vector2(1400, BLOCKER.y), { "faction": &"invader", "max_health": 1.0e6 })


func run(t: TestContext) -> void:
	var npc := t.actor(&"npc")
	var blocker := t.actor(&"blocker")
	var brain := t.controller(&"npc", &"current_act")
	var closest := INF
	var stalled := 0.0
	var start := t.time
	while npc.global_position.x < PAST_X and t.time - start < 20.0:
		await t.frames(1)
		closest = minf(closest, npc.global_position.distance_to(blocker.global_position))
		stalled = maxf(stalled, float(brain.debug_progress().get("stalled_for", 0.0)))
	var took := t.time - start
	t.trace("closest_to_blocker", closest)
	t.trace("took", took)
	t.check(npc.global_position.x >= PAST_X, "the NPC gets past the standing character (x=%.0f after %.1f s, %s)" % [npc.global_position.x, took, brain.current_act()])
	t.check(closest >= 30.0, "without touching it (closest %.1f px; 28 is contact)" % closest)
	t.check(stalled < 1.0, "and without a stall (longest %.2f s without progress)" % stalled)

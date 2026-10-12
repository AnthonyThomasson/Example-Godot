extends GameTest

## Desired (docs/gaze-and-fire.md W3): an NPC with an empty gun and a spare magazine reloads it when a hostile is in
## view, whatever it is doing (an advance included), instead of walking on with a dead gun. Walking at a hostile in
## plain view it fires its last two rounds; with the gun dry it must reload at once.

const START := Vector2(100, 300)
const HOSTILE_AT := Vector2(800, 300)


func describe() -> Dictionary:
	return {
		"name": "A gun that runs dry on the way to a hostile is reloaded",
		"description": "A defender with two rounds and two spare magazines rushes a visible hostile, fires them off and reloads within 2 s of the gun going dry.",
		"tags": ["ai", "gaze", "reload", "scripted", "combat"],
		"timeout": 30.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 900, 600))
	s.von_script([{ "pick": "combat" }, { "pick": "advance" }, { "pick": "rush" }])
	s.switch(&"ai.callouts", false)
	s.switch(&"ai.territory", false)
	s.switch(&"ai.hostile_on_sight", true)
	s.switch(&"projectile.flyover", false)
	s.actor(&"npc", &"defender", START, { "start_rounds": 2, "facing": Vector2.RIGHT, "aim_point": HOSTILE_AT })
	s.set_props(&"npc", "GoalController", { "run_enabled": false, "shoot_range": 1000.0 })  # walks, so the shots are not refused
	s.actor(&"hostile", &"puppet", HOSTILE_AT, { "faction": &"invader", "max_health": 1000000.0, "facing": Vector2.LEFT, "aim_point": START })


func run(t: TestContext) -> void:
	var npc := t.actor(&"npc")
	var brain := t.controller(&"npc", &"debug_state")
	if not t.require(await t.until(func(): return npc.ammo() == 0, 10.0), "the NPC fired its last round (%d left, act %s)" % [npc.ammo(), brain.debug_state().get("act")]):
		return
	var dry := t.time
	var reloaded := func(): return t.events.any(func(e):
		return e["topic"] == &"reload" and e["data"].get("stage") == &"start" and e["data"].get("character") == npc)
	t.check(await t.until(reloaded, 2.0), "it started reloading within 2 s of the gun going dry at %.1f s (act %s, %d rounds)" \
		% [dry, brain.debug_state().get("act"), npc.ammo()])

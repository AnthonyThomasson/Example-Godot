extends GameTest

## Desired (docs/gaze-and-fire.md W6, the exception): an NPC stops sprinting to shoot, but not when it is retreating. Falling
## back from a defender it can see through the living room's door (in range, a clear line, a loaded gun) the invader keeps
## running: a retreat is about getting out of the line, not about trading shots.

const Entry := preload("res://tests/_ai/entry_probe.gd")
const Maps := preload("res://tests/_ai/flank_maps.gd")
const START := Vector2(150, 440)    # in the hall, south of the living room's door
const TARGET := Vector2(150, 200)   # in the living room, in line with that door, 240 px away
const WALK_SPEED := 150.0


func describe() -> Dictionary:
	return {
		"name": "A retreating NPC keeps sprinting with a shot available",
		"description": "Falling back to the kitchen from a defender in view and in range, the invader runs rather than stopping to shoot.",
		"tags": ["ai", "run", "retreat", "scripted"],
		"timeout": 40.0,
	}


func configure(s: TestSetup) -> void:
	Maps.house(s, false)
	Entry.guard_rules(s, ["combat", "retreat", "fall_kitchen"])
	Entry.npc(s, &"inv", START, 0.4, {}, { "facing": Vector2.UP })
	s.set_props(&"inv", "GoalController", { "familiar_with_house": true })
	Entry.target(s, &"tgt", TARGET, Vector2(150, 0))


func run(t: TestContext) -> void:
	var inv := t.actor(&"inv")
	var brain := Entry.brain(t, &"inv")
	if not t.require(await t.until(func(): return String(brain.current_act()).contains("retreat"), 15.0), "the invader retreats (act %s)" % brain.current_act()):
		return
	var top := 0.0
	var run_frames := 0
	for i in 60:
		await t.frames(1)
		top = maxf(top, (inv.get_real_velocity() as Vector2).length())
		if inv.is_running():
			run_frames += 1
	t.trace("retreat_top_speed", top)
	t.check(top > WALK_SPEED * 1.3, "it sprints while it falls back (%.0f px/s)" % top)
	t.check(run_frames > 20, "it was running for most of that second (%d of 60 frames)" % run_frames)

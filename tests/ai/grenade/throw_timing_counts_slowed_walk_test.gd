extends GameTest

## G16: the speed an NPC counts on to reach a safe spot before the fuse runs out (`AgentThrow.run_speed`) is, once its stamina is low,
## its walk as the body is now (`Character.walk_speed()`), not its tuned `speed`: a stunned body walks at `CharacterConfig.stun_speed` of
## it and a full plated kit about 8% slower, so both count on less. Three bodies with the same `speed` and an empty stamina bar: one
## bare, one stunned, one in the plated kit.

const OutfitProbe := preload("res://tests/_outfit/outfit_probe.gd")
const AgentThrow := preload("res://scenes/ai/perception/agent_throw.gd")
const LANES := { &"bare": 150.0, &"stunned": 300.0, &"plated": 450.0 }


func describe() -> Dictionary:
	return {
		"name": "A stunned or heavily armoured NPC counts on a slower walk to get clear",
		"description": "With its stamina low, AgentThrow.run_speed is the body's walk_speed(): the bare body's tuned speed, under half of it stunned, about 8% less in the plated kit.",
		"tags": ["ai", "grenade", "stun", "outfit", "unit"],
		"timeout": 10.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 800, 600))
	s.switch(&"nav.rebake", false)
	for id: StringName in LANES:
		s.actor(id, &"puppet", Vector2(100, LANES[id]))


func run(t: TestContext) -> void:
	var plated := t.actor(&"plated")
	if not OutfitProbe.require_api(t, plated):
		return
	OutfitProbe.wear(plated, OutfitProbe.PLATED_KIT)
	var stunned := t.actor(&"stunned")
	stunned.take_stun(4.0, 0.0)
	var throw := AgentThrow.new()
	var counted := {}
	for id: StringName in LANES:
		var c := t.actor(id)
		c.stamina = 0.0  # below RUN_STAMINA: it is taken to walk
		counted[id] = throw.run_speed(c)
	var bare := t.actor(&"bare")
	t.check(is_equal_approx(counted[&"bare"], bare.speed), "the bare body counts on its tuned walk (%.0f px/s of %.0f)" % [counted[&"bare"], bare.speed])
	t.check(is_equal_approx(counted[&"stunned"], bare.speed * CharacterConfig.stun_speed),
		"the stunned one on stun_speed of it (%.0f px/s against %.0f), though its tuned speed is the same (%.0f)" % [counted[&"stunned"], bare.speed * CharacterConfig.stun_speed, stunned.speed])
	var share: float = counted[&"plated"] / counted[&"bare"]
	t.check(share > 0.85 and share < 0.97, "the plated one on about 8%% less (%.0f px/s: %.0f%%)" % [counted[&"plated"], share * 100.0])
	t.check(is_equal_approx(counted[&"plated"], plated.walk_speed()), "each is the body's walk_speed()")

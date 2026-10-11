extends GameTest

## A defender whose scripted decision is combat → advance (a `run` node) sprints across the open arena
## toward a visible hostile; with `run_enabled` off it only walks. In shooting range but still running it holds
## its fire (no shot, cooldown unspent) and shoots once the run is over.

const WALK_SPEED := 150.0
const SHOOT_RANGE := 1600.0


func describe() -> Dictionary:
	return {
		"name": "AI runs to a far destination",
		"description": "Von is scripted (combat, then advance); the defender runs toward the far hostile, spends stamina, holds its fire while running in range, shoots once it stops, and walks when running is disabled.",
		"tags": ["ai", "run", "stamina", "scripted"],
		"timeout": 25.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 3000, 600))
	s.von_script([{ "pick": "combat" }, { "pick": "advance" }])
	s.switch(&"ai.callouts", false)
	s.switch(&"ai.territory", false)
	s.switch(&"ai.hostile_on_sight", true)
	s.actor(&"runner", &"defender", Vector2(200, 300))
	s.actor(&"walker", &"defender", Vector2(200, 100))
	s.set_props(&"walker", "GoalController", { "run_enabled": false })
	s.set_props(&"runner", "GoalController", { "shoot_range": SHOOT_RANGE })  # In range of the far hostiles from the start.
	s.actor(&"far_a", &"puppet", Vector2(1500, 300), { "faction": &"invader", "max_health": 400.0 })
	s.actor(&"far_b", &"puppet", Vector2(1500, 100), { "faction": &"invader", "max_health": 400.0 })


func run(t: TestContext) -> void:
	var runner := t.actor(&"runner")
	var walker := t.actor(&"walker")
	var brain := t.controller(&"runner", &"current_act")
	t.check(await t.until(func(): return String(brain.current_act()).contains("advance"), 10.0), "the runner advances (%s)" % brain.current_act())
	var top_runner := 0.0
	var top_walker := 0.0
	for i in 90:
		await t.frames(1)
		top_runner = maxf(top_runner, runner.get_real_velocity().length())
		top_walker = maxf(top_walker, walker.get_real_velocity().length())
	t.trace("runner_top_speed", top_runner)
	t.trace("walker_top_speed", top_walker)
	t.check(top_runner > WALK_SPEED * 1.3, "the runner exceeds walking speed (%.0f)" % top_runner)
	t.check(top_walker <= WALK_SPEED * 1.05, "with run_enabled off the walker never exceeds walk speed (%.0f)" % top_walker)
	t.check(runner.stamina_fraction() < 1.0, "running spent stamina (%.2f)" % runner.stamina_fraction())

	# In range but still running: no shot leaves and the fire cooldown is not spent on one.
	var hostile := t.actor(&"far_a")
	var shots: int = t.spawned("Projectile").size()
	var held := 0
	var spent := 0
	var fired_running := 0
	var fired := false
	for i in 900:
		await t.frames(1)
		var running: bool = runner.is_running()
		if running and runner.global_position.distance_to(hostile.global_position) < SHOOT_RANGE:
			held += 1
			if float(brain.debug_state()["timers"]["fire"]) > 0.0:
				spent += 1
		var now: int = t.spawned("Projectile").size()
		if now > shots:
			if running:
				fired_running += 1
			else:
				fired = true
				break
			shots = now
	t.check(held > 0, "the runner was still running within shooting range (%d frames)" % held)
	t.expect_eq(fired_running, 0, "no shot leaves while the runner is running")
	t.expect_eq(spent, 0, "a held shot does not spend the fire cooldown")
	t.check(fired, "it shoots once the run is over")

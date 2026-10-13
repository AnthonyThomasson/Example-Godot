extends GameTest

## A defender whose scripted decision is combat → advance → rush (a `run` node) sprints across the open arena
## toward a hostile far out of shooting range; with `run_enabled` off it only walks. A running character cannot shoot, so
## the moment a shot is available (a visible hostile in range on a clear line, gun loaded) it drops to a walk and shoots
## (docs/gaze-and-fire.md W6) instead of sprinting on past its range with the gun lowered.

const WALK_SPEED := 150.0
const SHOOT_RANGE := 500.0  ## The controller's default.
## Frames of grace between crossing into range and the run actually ending (the controller drops it on its next tick).
const GRACE_FRAMES := 6
## It must have fired by the time it is this near the hostile (the run's own cut-off is 150 px from its destination).
const FIRED_BY := 250.0


func describe() -> Dictionary:
	return {
		"name": "AI runs to a far destination",
		"description": "Von is scripted (combat, then advance); the defender runs toward the far hostile and spends stamina, drops to a walk and shoots once the hostile is in range, and walks all the way when running is disabled.",
		"tags": ["ai", "run", "stamina", "scripted"],
		"timeout": 25.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 3000, 600))
	s.von_script([{ "pick": "combat" }, { "pick": "advance" }, { "pick": "rush" }])
	s.switch(&"ai.callouts", false)
	s.switch(&"ai.territory", false)
	s.switch(&"ai.hostile_on_sight", true)
	s.actor(&"runner", &"defender", Vector2(200, 300))
	s.actor(&"walker", &"defender", Vector2(200, 100))
	s.set_props(&"walker", "GoalController", { "run_enabled": false })
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

	# Into range: the shot is available, so the run ends and the shots come while it is still closing in.
	var hostile := t.actor(&"far_a")
	var shots: int = t.spawned("Projectile").size()
	var running_in_range := 0
	var fired_running := 0
	var fired_at := INF
	for i in 900:
		await t.frames(1)
		var running: bool = runner.is_running()
		var dist: float = runner.global_position.distance_to(hostile.global_position)
		if running and dist < SHOOT_RANGE:
			running_in_range += 1
		var now: int = t.spawned("Projectile").size()
		if now > shots:
			if running:
				fired_running += 1
			elif fired_at == INF:
				fired_at = dist
				break
			shots = now
	t.trace("running_in_range_frames", running_in_range)
	t.expect_eq(fired_running, 0, "no shot leaves while the runner is running")
	t.check(running_in_range <= GRACE_FRAMES, "it stops running once the hostile is in range (%d frames of running in range)" % running_in_range)
	t.check(fired_at < INF, "it shoots the hostile")
	t.check(fired_at > FIRED_BY, "it shoots while still closing in, not only after the sprint ends (first shot from %.0f px)" % fired_at)

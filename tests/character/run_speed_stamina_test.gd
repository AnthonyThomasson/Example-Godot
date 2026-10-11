extends GameTest

## Holding run speeds a moving character up by `run_speed_mult` and spends stamina; running dry drops
## it back to a walk until stamina refills to `run_resume_fraction`; standing still spends nothing.

const WALK_SPEED := 150.0


func describe() -> Dictionary:
	return {
		"name": "Running is faster and spends stamina",
		"description": "A puppet holding run moves at run speed while stamina lasts, walks once dry until it refills, and spends nothing standing still.",
		"tags": ["run", "stamina", "locomotion"],
		"timeout": 20.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 4000, 600))
	s.set_static(CharacterConfig, &"run_stamina_seconds", 1.0)
	s.set_static(CharacterConfig, &"stamina_regen_per_sec", 0.5)
	s.set_static(CharacterConfig, &"run_resume_fraction", 0.3)
	s.actor(&"runner", &"puppet", Vector2(100, 300), { "start_slot": 2 })


func run(t: TestContext) -> void:
	var puppet := t.puppet(&"runner")
	var body := t.actor(&"runner")

	# Standing still while holding run spends nothing.
	puppet.set_run(true)
	await t.seconds(0.3)
	t.expect_near(body.stamina_fraction(), 1.0, 0.001, "holding run while standing still keeps a full bar")
	t.check(not body.is_running(), "not running while standing still")

	# Walking is walk speed.
	puppet.set_run(false)
	puppet.walk(Vector2.RIGHT)
	await t.seconds(0.3)
	t.expect_near(body.get_real_velocity().length(), WALK_SPEED, 5.0, "walks at walk speed")

	# Running is faster and drains the bar.
	puppet.set_run(true)
	await t.seconds(0.2)
	t.check(body.is_running(), "running while holding run and moving")
	t.expect_near(body.get_real_velocity().length(), WALK_SPEED * CharacterConfig.run_speed_mult, 5.0, "runs at run speed")
	t.check(body.stamina_fraction() < 1.0, "running spends stamina")

	# Running dry: back to a walk even though run is still held.
	t.require(await t.until(func(): return not body.is_running(), 3.0), "runs dry")
	await t.frames(3)
	t.expect_near(body.stamina_fraction(), 0.0, 0.2, "the bar is spent")
	t.expect_near(body.get_real_velocity().length(), WALK_SPEED, 5.0, "walks again once out of stamina")

	# It resumes once stamina refills to the resume fraction.
	t.check(await t.until(func(): return body.is_running(), 3.0), "runs again after stamina refills")
	t.check(body.stamina_fraction() >= CharacterConfig.run_resume_fraction - 0.05, "not before the resume fraction")

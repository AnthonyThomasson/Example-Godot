extends GameTest

## A crouching character walks slower than a standing one (the posture's `speed` row). Only a standing
## character can run: holding run while crouched does nothing and spends no
## stamina, and the run is there again on standing back up.

const WALK_SPEED := 150.0


func describe() -> Dictionary:
	return {
		"name": "Crouching is slower, and only standing runs",
		"description": "A puppet walks at each posture's speed; run is ignored (and free) while crouched, and works again standing.",
		"tags": ["posture", "crouch", "run", "locomotion"],
		"timeout": 20.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 8000, 600))
	s.set_static(CharacterConfig, &"posture_change_time", 0.0)
	s.actor(&"walker", &"puppet", Vector2(100, 300), { "start_slot": 2 })


func run(t: TestContext) -> void:
	var puppet := t.puppet(&"walker")
	var body := t.actor(&"walker")
	t.expect_eq(body.posture(), &"stand", "a character starts standing")

	puppet.walk(Vector2.RIGHT)
	await t.seconds(0.3)
	t.expect_near(body.get_real_velocity().length(), WALK_SPEED, 5.0, "standing walks at the walk speed")

	puppet.set_posture(&"crouch")
	await t.seconds(0.3)
	t.check(body.is_crouching(), "the puppet crouches")
	var crouch_speed: float = WALK_SPEED * float(CharacterConfig.postures[&"crouch"]["speed"])
	t.expect_near(body.get_real_velocity().length(), crouch_speed, 5.0, "crouching walks at the crouch speed")

	t.check(crouch_speed < WALK_SPEED, "a crouch is slower than standing")

	# Holding run while crouched: no run, no stamina spent.
	puppet.set_run(true)
	await t.seconds(0.4)
	t.check(not body.is_running(), "run is ignored while crouched")
	t.expect_near(body.get_real_velocity().length(), crouch_speed, 5.0, "still creeping with run held")
	t.expect_near(body.stamina_fraction(), 1.0, 0.001, "a refused run spends no stamina")

	# Standing up gives the run back.
	puppet.set_posture(&"stand")
	await t.seconds(0.4)
	t.check(body.is_running(), "standing with run held runs")
	t.expect_near(body.get_real_velocity().length(), WALK_SPEED * CharacterConfig.run_speed_mult, 5.0, "at run speed")

extends GameTest

## A crouching character walks slower than a standing one and a prone one slower still (each posture's `speed`
## row). Only a standing character can run: holding run while crouched or prone does nothing and spends no
## stamina, and the run is there again on standing back up.

const WALK_SPEED := 150.0


func describe() -> Dictionary:
	return {
		"name": "Crouching and prone are slower, and only standing runs",
		"description": "A puppet walks at each posture's speed; run is ignored (and free) while crouched or prone, and works again standing.",
		"tags": ["posture", "crouch", "prone", "run", "locomotion"],
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

	puppet.set_posture(&"prone")
	await t.seconds(0.3)
	t.check(body.is_prone(), "the puppet goes prone")
	var prone_speed: float = WALK_SPEED * float(CharacterConfig.postures[&"prone"]["speed"])
	t.expect_near(body.get_real_velocity().length(), prone_speed, 5.0, "prone crawls at the prone speed")
	t.check(prone_speed < crouch_speed and crouch_speed < WALK_SPEED, "each lower posture is slower")

	# Holding run while prone: no run, no stamina spent.
	puppet.set_run(true)
	await t.seconds(0.4)
	t.check(not body.is_running(), "run is ignored while prone")
	t.expect_near(body.get_real_velocity().length(), prone_speed, 5.0, "still crawling with run held")
	t.expect_near(body.stamina_fraction(), 1.0, 0.001, "a refused run spends no stamina")

	puppet.set_posture(&"crouch")
	await t.seconds(0.4)
	t.check(not body.is_running(), "run is ignored while crouched")
	t.expect_near(body.stamina_fraction(), 1.0, 0.001, "nor does it while crouched")

	# Standing up gives the run back.
	puppet.set_posture(&"stand")
	await t.seconds(0.4)
	t.check(body.is_running(), "standing with run held runs")
	t.expect_near(body.get_real_velocity().length(), WALK_SPEED * CharacterConfig.run_speed_mult, 5.0, "at run speed")

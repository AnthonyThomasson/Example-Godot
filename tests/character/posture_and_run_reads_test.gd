extends GameTest

## Interface 7: what a controller may ask of a character about its own body, instead of keeping a copy of the numbers: `posture_coverage(posture)` (the height
## of the body in a posture, on the coverage scale `get_surface()` answers for the posture it is in) and `run_speed()` (px/s, running standing: what the
## character really covers, so a controller can tell whether it gets somewhere in time). Pinned against what the body does.

const SPEED_SLACK := 0.06
const STAND_COVERAGE := 60.0
const CROUCH_COVERAGE := 35.0


func describe() -> Dictionary:
	return {
		"name": "A character tells its posture heights and its running speed",
		"description": "posture_coverage answers the height of standing and crouching (what get_surface says in them); run_speed is the speed the character really covers running, and falls while it is stunned.",
		"tags": ["character", "posture", "run"],
		"timeout": 10.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 1400, 500))
	s.actor(&"c", &"puppet", Vector2(100, 250), { "max_health": 100000.0 })


func run(t: TestContext) -> void:
	var c := t.actor(&"c")
	t.expect_eq(c.posture_coverage(&"stand"), STAND_COVERAGE, "standing is 60 tall on the coverage scale")
	t.expect_eq(c.posture_coverage(&"crouch"), CROUCH_COVERAGE, "crouching 35")
	t.expect_eq(c.get_surface()["coverage"], c.posture_coverage(&"stand"), "get_surface answers the same while standing")
	t.puppet(&"c").set_posture(&"crouch")
	await t.seconds(0.5)
	t.expect_eq(c.get_surface()["coverage"], c.posture_coverage(&"crouch"), "and while crouched")
	t.puppet(&"c").set_posture(&"stand")
	await t.seconds(0.5)

	# Run along the arena and measure the speed it covers.
	var puppet := t.puppet(&"c")
	puppet.set_run(true)
	puppet.walk(Vector2.RIGHT)
	await t.seconds(0.3)
	var from: Vector2 = c.global_position
	var start := t.time
	await t.seconds(0.6)
	var measured: float = from.distance_to(c.global_position) / (t.time - start)
	t.check(c.is_running(), "set-up: it is running")
	t.check(absf(c.run_speed() - measured) <= c.run_speed() * SPEED_SLACK, "run_speed() %.0f px/s is what it covers running (%.0f measured)" % [c.run_speed(), measured])
	t.check(c.run_speed() > c.speed * 1.3, "faster than its walk (%.0f px/s)" % c.speed)
	puppet.stop()
	var free: float = c.run_speed()
	c.take_stun(2.0, 0.0, c.global_position + Vector2.LEFT * 100.0)
	t.check(c.run_speed() < free, "and slower while stunned (%.0f against %.0f)" % [c.run_speed(), free])

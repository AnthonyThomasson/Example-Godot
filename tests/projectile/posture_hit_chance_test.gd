extends GameTest

## In the open a lower posture is a smaller target: a bullet strikes a body of coverage C when it flies below C,
## so at a pinned height each posture is struck or missed by the numbers alone, and over random heights the hit
## rates follow the postures' coverage (standing most, then crouched).

const LANES := { &"stand": 200.0, &"crouch": 400.0 }
const TARGET_X := 560.0
const SHOOT_X := 150.0


func describe() -> Dictionary:
	return {
		"name": "A lower posture is hit by fewer shots",
		"description": "Bullets pinned to a height strike the postures it is below (10 and 20: both, 40: standing, 70: none); random shots hit standing most, crouched less.",
		"tags": ["projectile", "posture", "crouch", "coverage", "ballistics"],
		"timeout": 20.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 1200, 600))
	s.switch(&"nav.rebake", false)
	s.switch(&"physics.debris", false)
	s.set_static(BloodConfig, &"enabled", false)
	s.set_static(BallisticsConfig, &"bullet_height", -1.0)
	for lane: StringName in LANES:
		s.actor(StringName("body_%s" % lane), &"puppet", Vector2(TARGET_X, LANES[lane]), { "max_health": 1000000.0 })


func run(t: TestContext) -> void:
	for lane: StringName in LANES:
		t.check(t.actor(StringName("body_%s" % lane)).set_posture(lane), "the %s body takes its posture" % lane)
	await t.frames(2)

	await _volley(t, 10.0, 1)
	for lane: StringName in LANES:
		t.expect_eq(_hits(t, lane), 1, "a shot at 10 strikes the %s body" % lane)
	await _volley(t, 20.0, 1)
	t.expect_eq(_hits(t, &"stand"), 2, "a shot at 20 strikes the standing body")
	t.expect_eq(_hits(t, &"crouch"), 2, "...and the crouched one")
	await _volley(t, 40.0, 1)
	t.expect_eq(_hits(t, &"stand"), 3, "a shot at 40 strikes only the standing body")
	t.expect_eq(_hits(t, &"crouch"), 2, "...over the crouched one")
	await _volley(t, 70.0, 1)
	t.expect_eq(_hits(t, &"stand"), 3, "a shot at 70 misses everyone")
	t.expect_eq(_hits(t, &"crouch"), 2, "...including the crouched")

	var before := {}
	for lane: StringName in LANES:
		before[lane] = _hits(t, lane)
	var shots := 200
	await _volley(t, -1.0, shots)
	var rate := {}
	for lane: StringName in LANES:
		rate[lane] = float(_hits(t, lane) - before[lane]) / shots
		var want: float = float(CharacterConfig.postures[lane]["coverage"]) / 100.0
		t.expect_near(rate[lane], want, 0.12, "a %s body is hit by about %.0f%% of random shots (%.2f)" % [lane, want * 100.0, rate[lane]])
	t.check(rate[&"stand"] > rate[&"crouch"], "standing is hit more than crouched")


## Fire `count` bullets down every lane at `height` (negative = random) and let them land.
func _volley(t: TestContext, height: float, count: int) -> void:
	BallisticsConfig.bullet_height = height
	for lane: StringName in LANES:
		for i in count:
			ProjectileSpawner.spawn(Vector2(SHOOT_X, LANES[lane]), Vector2.RIGHT, t.world, null)
	await t.seconds(0.6)


func _hits(t: TestContext, lane: StringName) -> int:
	var victim := t.actor(StringName("body_%s" % lane))
	return t.events_of(&"hit", func(d): return d["victim"] == victim).size()

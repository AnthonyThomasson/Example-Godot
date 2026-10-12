extends GameTest

## Coverage is a height, and a bullet flies at one height for its whole flight: it strikes cover taller than it
## is and clears the rest, and whatever it clears it clears for every body behind. Behind cover of 50, a standing
## body (60) is struck only by shots between 50 and 60 (the 10 that clear the cover but not the body); a crouched
## body (35) is never reached by a shot that cleared the cover, and the cover (which
## stops what it meets) keeps the rest from them.

const LANES := { &"stand": 200.0, &"crouch": 400.0 }
const COVER_X := 500.0
const TARGET_X := 580.0
const SHOOT_X := 150.0


func describe() -> Dictionary:
	return {
		"name": "A bullet's one height meets cover and the body behind it",
		"description": "Bullets pinned to a height strike the cover (30), only the standing body behind it (55) or nothing (70); at random heights about half meet the cover, a tenth reach the standing body, none reach the crouched one.",
		"tags": ["projectile", "cover", "coverage", "posture", "ballistics"],
		"timeout": 20.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 1200, 600))
	s.switch(&"nav.rebake", false)
	s.switch(&"physics.debris", false)
	s.set_static(BloodConfig, &"enabled", false)
	s.set_static(BallisticsConfig, &"bullet_height", -1.0)
	var cover := {
		"name": "Cover", "shape": "rect", "size": Vector2(24, 120), "color": Color(0.5, 0.4, 0.3),
		"material": "wood", "coverage": 50.0, "penetration": 100.0, "weight": 5000.0,
	}
	for lane: StringName in LANES:
		s.object(StringName("cover_%s" % lane), cover, Vector2(COVER_X, LANES[lane]))
		s.actor(StringName("body_%s" % lane), &"puppet", Vector2(TARGET_X, LANES[lane]), { "max_health": 1000000.0 })


func run(t: TestContext) -> void:
	for lane: StringName in LANES:
		t.check(t.actor(StringName("body_%s" % lane)).set_posture(lane), "the %s body takes its posture" % lane)
	var coverage := {}
	for lane: StringName in LANES:
		coverage[lane] = t.actor(StringName("body_%s" % lane)).get_surface()["coverage"]
	t.expect_near(coverage[&"stand"], 60.0, 0.01, "a standing body is 60")
	t.check(coverage[&"crouch"] < 50.0, "the crouched body stands lower than the cover")
	await t.frames(2)

	# Pinned heights: each outcome is decided by the numbers alone.
	await _volley(t, 30.0, 1)
	for lane: StringName in LANES:
		t.expect_eq(_hits(t, _cover(t, lane)), 1, "a shot at 30 meets the %s lane's cover" % lane)
		t.expect_eq(_hits(t, _body(t, lane)), 0, "...and the cover stops it before the %s body" % lane)

	await _volley(t, 55.0, 1)
	t.expect_eq(_hits(t, _cover(t, &"stand")), 1, "a shot at 55 clears the cover")
	t.expect_eq(_hits(t, _body(t, &"stand")), 1, "...and strikes the standing body, which stands to 60")
	t.expect_eq(_hits(t, _body(t, &"crouch")), 0, "...and passes over the crouched body")

	await _volley(t, 70.0, 1)
	t.expect_eq(_hits(t, _body(t, &"stand")), 1, "a shot at 70 clears even the standing body (no new hit)")
	t.expect_eq(_hits(t, _cover(t, &"stand")), 1, "...and the cover (no new hit)")

	# Random heights: the 50 / 60 split.
	var covers_before := _hits(t, _cover(t, &"stand"))
	var bodies_before := _hits(t, _body(t, &"stand"))
	var shots := 300
	BallisticsConfig.bullet_height = -1.0
	await _volley(t, -1.0, shots)
	var on_cover := float(_hits(t, _cover(t, &"stand")) - covers_before) / shots
	var on_body := float(_hits(t, _body(t, &"stand")) - bodies_before) / shots
	t.expect_near(on_cover, 0.5, 0.12, "about half the shots meet cover of 50 (%.2f)" % on_cover)
	t.expect_near(on_body, 0.1, 0.07, "about a tenth reach the standing body behind it alone (%.2f)" % on_body)
	t.expect_eq(_hits(t, _body(t, &"crouch")), 0, "no random shot ever reaches the crouched body behind the cover")


## Fire `count` bullets down every lane at `height` (negative = random) and let them land.
func _volley(t: TestContext, height: float, count: int) -> void:
	BallisticsConfig.bullet_height = height
	for lane: StringName in LANES:
		for i in count:
			ProjectileSpawner.spawn(Vector2(SHOOT_X, LANES[lane]), Vector2.RIGHT, t.world, null)
	await t.seconds(0.6)


func _cover(t: TestContext, lane: StringName) -> Node:
	return t.object(StringName("cover_%s" % lane))


func _body(t: TestContext, lane: StringName) -> Node:
	return t.actor(StringName("body_%s" % lane))


func _hits(t: TestContext, victim: Node) -> int:
	return t.events_of(&"hit", func(d): return d["victim"] == victim).size()

extends GameTest

## A defender holding its ground with a hostile in view crouches: behind a table (45), which hides a crouching
## body, and in the open with no shots landing alike. With the posture switch off it stays on its feet.

const LANES := { &"table": 150.0, &"open": 350.0, &"off": 550.0 }


func describe() -> Dictionary:
	return {
		"name": "A defender crouches while holding its ground",
		"description": "Holding with a hostile in view (server down): crouched behind a table or in the open, standing with the switch off.",
		"tags": ["ai", "posture", "crouch", "cover"],
		"timeout": 20.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 1000, 700))
	s.von_down()
	s.switch(&"ai.callouts", false)
	s.switch(&"ai.territory", false)
	s.switch(&"ai.hostile_on_sight", true)
	s.switch(&"nav.rebake", false)
	for lane: StringName in LANES:
		var y: float = LANES[lane]
		s.actor(StringName("def_%s" % lane), &"defender", Vector2(300, y))
		s.actor(StringName("foe_%s" % lane), &"puppet", Vector2(750, y), { "faction": &"invader", "max_health": 400.0 })
	s.object(&"table", { "name": "Table", "shape": "rect", "size": Vector2(24, 90), "color": Color(0.5, 0.4, 0.3),
		"material": "wood", "coverage": 45.0, "penetration": 60.0, "weight": 5000.0 }, Vector2(350, LANES[&"table"]))
	s.set_props(&"def_off", "GoalController", { "posture_enabled": false })


func run(t: TestContext) -> void:
	for lane: StringName in LANES:
		var body: Node = t.actor(StringName("def_%s" % lane))
		body.aim_point = t.actor(StringName("foe_%s" % lane)).global_position
		t.check(body.posture() == &"stand", "the %s defender starts standing" % lane)

	var table: Node = t.actor(&"def_table")
	var open: Node = t.actor(&"def_open")
	var off: Node = t.actor(&"def_off")
	t.check(await t.until(func(): return table.posture() == &"crouch", 6.0), "behind a table (45) it crouches (%s)" % table.posture())
	t.check(await t.until(func(): return open.posture() == &"crouch", 6.0), "in the open, unshot, it crouches (%s)" % open.posture())
	await t.seconds(2.0)
	t.expect_eq(table.posture(), &"crouch", "the table defender stays crouched")
	t.expect_eq(open.posture(), &"crouch", "the open defender stays crouched")
	t.expect_eq(off.posture(), &"stand", "with the posture switch off the defender stays standing")

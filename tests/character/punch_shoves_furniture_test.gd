extends GameTest

## A puppet with bare fists punches a chair right in front of it: the punch lands (hit_landed with a
## melee hand) and shoves the chair away along the punch (the "pushable" contract).


func describe() -> Dictionary:
	return {
		"name": "Punch shoves a chair",
		"description": "A fists-wielding puppet punches a chair; the punch lands and the chair slides away.",
		"tags": ["punch", "melee", "pushable", "fists"],
		"timeout": 5.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 600, 400))
	s.switch(&"nav.rebake", false)
	s.actor(&"boxer", &"puppet", Vector2(250, 200), { "start_slot": 2 })
	s.object(&"chair", "chair", Vector2(292, 200))


func run(t: TestContext) -> void:
	var boxer := t.puppet(&"boxer")
	var chair: Node2D = t.object(&"chair")
	boxer.aim_at(chair.global_position)
	await t.seconds(0.3)
	var start := chair.global_position
	boxer.punch()
	var landed := func(d): return d["actor"] == &"boxer" and d["body"] == chair and d["hand"] >= 0
	if not t.require(await t.until(func(): return t.happened(&"hit_landed", landed), 1.5), "the punch lands on the chair"):
		return
	await t.seconds(0.8)
	var moved := chair.global_position - start
	t.check(moved.length() > 3.0, "the chair was shoved (moved %.1f px)" % moved.length())
	t.check(moved.x > 0.0, "the chair moved away from the boxer (dx %.1f)" % moved.x)

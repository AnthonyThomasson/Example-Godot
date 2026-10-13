extends GameTest

## A puppet kicks a chair right in front of it: the kick lands (hit_landed with the kick hand code) and shoves the
## chair away along the kick, harder than a punch shoves an identical chair. The kicker holds a pistol the whole
## time: a kick works with whatever is held.


func describe() -> Dictionary:
	return {
		"name": "Kick shoves a chair harder than a punch",
		"description": "An armed puppet kicks a chair and a fists puppet punches an identical one; the kick lands as hand code 2 and the kicked chair slides further.",
		"tags": ["kick", "melee", "pushable", "legs"],
		"timeout": 8.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 600, 400))
	s.switch(&"nav.rebake", false)
	s.actor(&"kicker", &"puppet", Vector2(250, 300), { "start_slot": 3 })
	s.object(&"kicked", "chair", Vector2(292, 300))
	s.actor(&"boxer", &"puppet", Vector2(250, 100), { "start_slot": 2 })
	s.object(&"punched", "chair", Vector2(292, 100))


func run(t: TestContext) -> void:
	var kicker := t.puppet(&"kicker")
	var boxer := t.puppet(&"boxer")
	var kicked: Node2D = t.object(&"kicked")
	var punched: Node2D = t.object(&"punched")
	kicker.aim_at(kicked.global_position)
	boxer.aim_at(punched.global_position)
	await t.seconds(0.3)
	var kicked_start := kicked.global_position
	var punched_start := punched.global_position
	kicker.kick()
	boxer.punch()
	var kick_landed := func(d): return d["actor"] == &"kicker" and d["body"] == kicked and d["hand"] == 2
	if not t.require(await t.until(func(): return t.happened(&"hit_landed", kick_landed), 1.5), "the kick lands on the chair as hand code 2"):
		return
	await t.seconds(1.0)
	var kick_moved := kicked.global_position - kicked_start
	var punch_moved := punched.global_position - punched_start
	t.check(kick_moved.x > 3.0, "the kicked chair moved away from the kicker (dx %.1f)" % kick_moved.x)
	t.check(kick_moved.length() > punch_moved.length(), "the kick shoves further than a punch (%.1f vs %.1f px)" % [kick_moved.length(), punch_moved.length()])
	t.expect_eq(t.actor(&"kicker").current_slot(), 3, "the kicker kept its pistol in hand")

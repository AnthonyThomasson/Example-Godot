extends GameTest

## A low body takes longer to come round to a new aim: standing faces it at once, crouched at no more than its
## posture's `turn` rate (rad/s), prone slower still. The aim point itself is never held back, and a body that
## stands up catches up at once.

const AIM_EAST := Vector2(2000.0, 300.0)
const AIM_WEST := Vector2(-2000.0, 300.0)


func describe() -> Dictionary:
	return {
		"name": "Crouching and prone turn more slowly",
		"description": "Turned 180 degrees, a standing puppet faces the aim at once, a crouched one takes about PI / turn seconds, a prone one longer; standing up catches up.",
		"tags": ["posture", "crouch", "prone", "turn", "facing"],
		"timeout": 20.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 1000, 600))
	s.set_static(CharacterConfig, &"posture_change_time", 0.0)
	s.switch(&"nav.rebake", false)
	s.actor(&"stand", &"puppet", Vector2(200, 100), { "start_slot": 1 })
	s.actor(&"crouch", &"puppet", Vector2(200, 300), { "start_slot": 1 })
	s.actor(&"prone", &"puppet", Vector2(200, 500), { "start_slot": 1 })


func run(t: TestContext) -> void:
	for id in [&"stand", &"crouch", &"prone"]:
		t.puppet(id).aim_at(AIM_EAST)
	t.puppet(&"crouch").set_posture(&"crouch")
	t.puppet(&"prone").set_posture(&"prone")
	await t.seconds(0.8)
	for id in [&"stand", &"crouch", &"prone"]:
		t.check(t.actor(id).facing.dot(Vector2.RIGHT) > 0.99, "the %s puppet faces east" % id)

	# Swing every aim 180 degrees at once and time how long each body takes to face it.
	var started := t.time
	var took := {}
	for id in [&"stand", &"crouch", &"prone"]:
		t.puppet(id).aim_at(AIM_WEST)
	var aim_before: Vector2 = t.actor(&"prone").aim_point
	await t.frames(2)
	t.expect_eq(t.actor(&"prone").aim_point, AIM_WEST, "the aim point is the new one at once (the cursor is never held back)")
	t.check(aim_before != t.actor(&"prone").aim_point, "the aim point moved")
	for _i in 400:
		for id in [&"stand", &"crouch", &"prone"]:
			if not took.has(id) and t.actor(id).facing.dot(Vector2.LEFT) > 0.99:
				took[id] = t.time - started
		if took.size() == 3:
			break
		await t.frames(1)
	t.check(took.size() == 3, "every body came round (%s)" % [took])
	t.check(took[&"stand"] < 0.1, "standing faces the new aim at once (%.2f s)" % took[&"stand"])
	var crouch_turn: float = CharacterConfig.postures[&"crouch"]["turn"]
	var prone_turn: float = CharacterConfig.postures[&"prone"]["turn"]
	t.expect_near(took[&"crouch"], PI / crouch_turn, 0.15, "a crouched body takes about PI / %.1f s (%.2f s)" % [crouch_turn, took[&"crouch"]])
	t.expect_near(took[&"prone"], PI / prone_turn, 0.2, "a prone body takes about PI / %.1f s (%.2f s)" % [prone_turn, took[&"prone"]])
	t.check(took[&"stand"] < took[&"crouch"] and took[&"crouch"] < took[&"prone"], "the lower the body, the longer it takes")

	# Standing back up: the body catches up with the aim at once.
	t.puppet(&"crouch").aim_at(AIM_EAST)
	await t.frames(3)
	t.check(t.actor(&"crouch").facing.dot(Vector2.LEFT) > 0.5, "mid-turn, still part of the way round")
	t.puppet(&"crouch").set_posture(&"stand")
	await t.frames(3)
	t.check(t.actor(&"crouch").facing.dot(Vector2.RIGHT) > 0.99, "standing up, the body is on the aim at once")

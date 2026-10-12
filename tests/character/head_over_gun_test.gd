extends GameTest

## The head is the highest part of the body, so it is painted over the gun and the fists, never under them,
## and the gun's butt is tucked under the torso (character_visuals.gd): standing and crouched, with each gun.

const GUNS := { &"pistol": 3, &"smg": 5, &"rifle": 6 }


func describe() -> Dictionary:
	return {
		"name": "The head is over the gun and the butt is under the torso",
		"description": "Standing and crouched with a pistol, SMG and rifle, a living body paints the weapon, then its torso over the gun's butt, then the fists, and last its head.",
		"tags": ["draw", "gun", "head", "crouch"],
		"timeout": 12.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 800, 800))
	s.set_static(CharacterConfig, &"posture_change_time", 0.0)
	s.switch(&"nav.rebake", false)
	var y := 100.0
	for gun: StringName in GUNS:
		s.actor(StringName("stand_%s" % gun), &"puppet", Vector2(200, y), { "start_slot": GUNS[gun] })
		s.actor(StringName("crouch_%s" % gun), &"puppet", Vector2(500, y), { "start_slot": GUNS[gun] })
		y += 200.0


func run(t: TestContext) -> void:
	for gun: StringName in GUNS:
		for stance in [&"stand", &"crouch"]:
			var id := StringName("%s_%s" % [stance, gun])
			t.puppet(id).aim_at(t.actor(id).global_position + Vector2(2000, 0))
			if stance == &"crouch":
				t.puppet(id).set_posture(&"crouch")
	await t.seconds(1.5)
	for gun: StringName in GUNS:
		for stance in [&"stand", &"crouch"]:
			var c = t.actor(StringName("%s_%s" % [stance, gun]))
			var visuals = c.get_node("Visuals")
			t.check(visuals.draws_laid_out() == (stance == &"crouch"), "%s %s: drawn the %s way" % [stance, gun, stance])
			t.expect_eq(visuals.draw_order, [&"weapon", &"torso", &"hands", &"head"] as Array[StringName],
				"%s %s: gun under the torso, fists over it, head last" % [stance, gun])

extends GameTest

## The same scene as `blocked_gun_steps_back`, with the pistol: its barrel is short enough to fire point-blank, so the
## chair against it does not stop it. The defender, pinned in place, shoots the intruder and never backs off — the AI
## has no special case for any weapon, it only reacts when its gun reports it cannot fire.

const PISTOL_SLOT := 3


func describe() -> Dictionary:
	return {
		"name": "An AI with a pistol fires against an object",
		"description": "A chair against a defender's pistol barrel does not stop it: the defender shoots the intruder and never steps back.",
		"tags": ["ai", "gun", "pistol", "back off", "scripted"],
		"timeout": 20.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 900, 600))
	s.von_script([{ "pick": "combat" }, { "pick": "engage" }])
	s.switch(&"ai.callouts", false)
	s.switch(&"projectile.flyover", false)
	s.actor(&"defender", &"defender", Vector2(300, 250), { "start_slot": PISTOL_SLOT, "speed": 0.0, "max_health": 400.0 })
	s.object(&"chair", "chair", Vector2(336, 232))
	s.actor(&"intruder", &"puppet", Vector2(750, 250), { "start_slot": 1, "faction": &"invader", "max_health": 400.0 })


func run(t: TestContext) -> void:
	var defender := t.actor(&"defender")
	var intruder := t.actor(&"intruder")
	var backed_off := [false]  # an Array, because a lambda cannot reassign a captured local
	var fired := await t.until(func():
		if defender.weapon_blocked() or defender.move_input.dot(defender.facing) < -0.5:
			backed_off[0] = true
		return intruder.health < intruder.max_health, 14.0)
	t.check(fired, "the defender's pistol shoots the intruder from against the chair (%.0f / %.0f)" % [intruder.health, intruder.max_health])
	t.check(not backed_off[0], "and it never reports a blocked gun or steps back")
	t.check(defender.weapon_raise() == 0.0, "the pistol is never raised")

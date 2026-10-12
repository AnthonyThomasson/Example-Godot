extends GameTest

## The human's posture keys, pressed through the real input actions: C crouches (and stands back up), Z goes prone
## (and stands back up), and from prone C comes up to a crouch. A posture change has to wait out
## `posture_change_time`, and a prone character cannot punch.


func describe() -> Dictionary:
	return {
		"name": "C crouches, Z goes prone, and both toggle back",
		"description": "The crouch and prone actions toggle the player's posture; changes are paced and prone cannot punch.",
		"tags": ["posture", "crouch", "prone", "player", "input"],
		"timeout": 15.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 800, 500))
	s.switch(&"nav.rebake", false)
	s.actor(&"you", &"player", Vector2(400, 250), { "start_slot": 2 })


func run(t: TestContext) -> void:
	var you := t.actor(&"you")
	await t.seconds(0.3)
	t.expect_eq(you.posture(), &"stand", "the player starts standing")

	await _tap(t, Keybinds.CROUCH)
	t.expect_eq(you.posture(), &"crouch", "C crouches")
	await _tap(t, Keybinds.CROUCH)
	t.expect_eq(you.posture(), &"stand", "C again stands")
	await _tap(t, Keybinds.PRONE)
	t.expect_eq(you.posture(), &"prone", "Z goes prone")
	await _tap(t, Keybinds.CROUCH)
	t.expect_eq(you.posture(), &"crouch", "C from prone comes up to a crouch")
	await _tap(t, Keybinds.PRONE)
	t.expect_eq(you.posture(), &"prone", "Z from a crouch goes prone")
	await _tap(t, Keybinds.PRONE)
	t.expect_eq(you.posture(), &"stand", "Z again stands")

	# Changes are paced: a second press inside the change time is ignored.
	Input.action_press(Keybinds.CROUCH)
	await t.frames(2)
	Input.action_release(Keybinds.CROUCH)
	await t.frames(1)
	t.expect_eq(you.posture(), &"crouch", "C crouches")
	Input.action_press(Keybinds.PRONE)
	await t.frames(2)
	Input.action_release(Keybinds.PRONE)
	t.expect_eq(you.posture(), &"crouch", "a press inside the change time is ignored")
	await t.seconds(CharacterConfig.posture_change_time + 0.1)
	t.check(you.set_posture(&"prone"), "a controller's request is taken once the change time is up")

	# Prone: no punch (crouched and standing can).
	await t.seconds(CharacterConfig.posture_change_time + 0.1)
	you.melee()
	await t.frames(3)
	t.check(not you.is_attacking(), "a prone character cannot punch")
	t.check(you.set_posture(&"stand"), "stands up")
	await t.seconds(CharacterConfig.posture_change_time + 0.1)
	you.melee()
	await t.frames(3)
	t.check(you.is_attacking(), "a standing character can")
	await t.seconds(1.0)


## Press `action` for a few frames, release, and wait out the change time so the next press is not paced away.
func _tap(t: TestContext, action: String) -> void:
	Input.action_press(action)
	await t.frames(2)
	Input.action_release(action)
	await t.seconds(CharacterConfig.posture_change_time + 0.1)

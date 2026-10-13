extends GameTest

## The human's kick key, pressed through the real input action: it throws a kick whatever is held, but not while
## crouched.


func describe() -> Dictionary:
	return {
		"name": "Kick key kicks standing, not crouched",
		"description": "The kick action starts a kick for the player holding a pistol; a crouched player cannot kick.",
		"tags": ["kick", "player", "input", "legs"],
		"timeout": 10.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 800, 500))
	s.switch(&"nav.rebake", false)
	s.actor(&"you", &"player", Vector2(400, 250), { "start_slot": 3 })


func run(t: TestContext) -> void:
	var you := t.actor(&"you")
	await t.seconds(0.3)
	t.check(not you.is_kicking(), "not kicking before the key")

	await _tap(t)
	t.check(you.is_kicking(), "the kick key starts a kick")
	t.expect_eq(you.current_slot(), 3, "the pistol stays in hand")
	await t.seconds(CharacterConfig.kick_strike_time + CharacterConfig.kick_recover_time + 0.2)
	t.check(not you.is_kicking(), "the kick ends")

	t.check(you.set_posture(&"crouch"), "crouches")
	await t.seconds(CharacterConfig.posture_change_time + 0.1)
	await _tap(t)
	t.check(not you.is_kicking(), "a crouched character cannot kick")
	await t.seconds(1.0)


## Press the kick action for a few frames, then release.
func _tap(t: TestContext) -> void:
	Input.action_press(Keybinds.KICK)
	await t.frames(2)
	Input.action_release(Keybinds.KICK)
	await t.frames(1)

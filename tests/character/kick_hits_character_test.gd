extends GameTest

## A kick wounds the character it reaches for `kick_damage`, once per kick, and posts the same world `hit` event a
## punch does (outcome `punch`, so it sounds like one) with the kicker as attacker. A second kick is refused while
## one is under way.


func describe() -> Dictionary:
	return {
		"name": "Kick wounds a character once",
		"description": "A kick deals kick_damage to the target once, posts a punch-outcome hit event attributed to the kicker, and is refused mid-kick.",
		"tags": ["kick", "melee", "legs", "damage"],
		"timeout": 8.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 600, 400))
	s.switch(&"nav.rebake", false)
	s.switch(&"physics.blood", false)
	s.actor(&"kicker", &"puppet", Vector2(250, 200), { "start_slot": 3 })
	s.actor(&"victim", &"puppet", Vector2(288, 200), { "start_slot": 1, "max_health": 100.0, "faction": &"invader" })


func run(t: TestContext) -> void:
	var kicker := t.puppet(&"kicker")
	var you := t.actor(&"kicker")
	var victim := t.actor(&"victim")
	kicker.aim_at(victim.global_position)
	await t.seconds(0.3)
	t.check(not you.is_kicking(), "not kicking before V")
	kicker.kick()
	await t.frames(2)
	t.check(you.is_kicking(), "a kick is under way")
	t.check(not you.leg_kick(), "a second kick is refused mid-kick")
	var landed := func(d): return d["actor"] == &"kicker" and d["body"] == victim and d["hand"] == 2
	if not t.require(await t.until(func(): return t.happened(&"hit_landed", landed), 1.0), "the kick lands on the victim"):
		return
	await t.seconds(CharacterConfig.kick_recover_time + 0.3)
	t.check(not you.is_kicking(), "the kick is over")
	t.expect_near(victim.health, 100.0 - CharacterConfig.kick_damage, 0.01, "the victim lost exactly kick_damage (once)")
	var hit := func(d): return d["attacker"] == you and d["victim"] == victim and d["outcome"] == &"punch"
	t.check(t.happened(&"hit", hit), "a punch-outcome hit event names the kicker as attacker")
	t.check(you.leg_kick_amount(1) == 0.0, "the left leg never kicks")

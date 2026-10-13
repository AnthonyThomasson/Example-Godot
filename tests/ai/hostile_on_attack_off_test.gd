extends GameTest

## With the `ai.hostile_on_attack` switch off an NPC that is shot does not turn on its attacker: it registers the
## attack (it is under fire) but keeps the shooter as a known, non-hostile contact.


func describe() -> Dictionary:
	return {
		"name": "No hostility toward an attacker with hostile_on_attack off",
		"description": "ai.hostile_on_attack off: a puppet shoots a defender that sees it; the defender is under fire yet still regards the puppet as not hostile.",
		"tags": ["ai", "hostility", "switch"],
		"timeout": 15.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 800, 500))
	s.von_down()
	s.switch(&"projectile.flyover", false)
	s.switch(&"ai.hostile_on_sight", false)
	s.switch(&"ai.hostile_on_trespass", false)
	s.switch(&"ai.hostile_on_attack", false)
	s.actor(&"shooter", &"puppet", Vector2(200, 250), { "start_slot": 3, "max_health": 1000000.0 })
	s.actor(&"def", &"defender", Vector2(560, 250), { "max_health": 1000000.0, "facing": Vector2.LEFT, "aim_point": Vector2(200, 250) })


func run(t: TestContext) -> void:
	var shooter := t.puppet(&"shooter")
	var shooter_body := t.actor(&"shooter")
	var brain := t.controller(&"def", &"known_contacts_for_display")
	var contact := func() -> Dictionary:
		for c in brain.known_contacts_for_display():
			if c["node"] == shooter_body:
				return c
		return {}
	if not t.require(await t.until(func(): return not contact.call().is_empty(), 3.0), "the defender sees the puppet"):
		return
	shooter.aim_at(t.actor(&"def"))
	await t.seconds(0.4)
	shooter.shoot()
	if not t.require(await t.until(func(): return t.happened(&"hit", func(d): return d.get("victim") == t.actor(&"def")), 2.0), "the shot hits the defender"):
		return
	await t.frames(5)
	t.check(brain.debug_state().get("under_fire", false), "the defender registers the attack (under fire)")
	var c: Dictionary = contact.call()
	t.check(not c.is_empty() and not c.get("hostile", true), "yet it does not regard the shooter as hostile")

extends GameTest

## In melee range an NPC with its fists out (and a dry gun with no spares in the pack) punches rather than kicks.


func describe() -> Dictionary:
	return {
		"name": "Unarmed NPC punches in melee",
		"description": "A hostile stands point-blank; Von picks combat then melee; a defender with its fists out and no ammo punches it.",
		"tags": ["ai", "melee", "punch", "scripted"],
		"timeout": 15.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 900, 600))
	s.von_script([{ "pick": "combat" }, { "pick": "melee" }])
	s.switch(&"ai.callouts", false)
	s.switch(&"ai.hostile_on_sight", true)
	s.switch(&"projectile.flyover", false)
	s.actor(&"defender", &"defender", Vector2(300, 300), { "start_slot": 2, "start_rounds": 0, "spare_magazine_types": [] })
	s.actor(&"stranger", &"puppet", Vector2(338, 300), { "start_slot": 1, "faction": &"invader", "max_health": 400.0 })


func run(t: TestContext) -> void:
	var stranger := t.actor(&"stranger")
	var punched := func(d): return d["actor"] == &"defender" and d["body"] == stranger and d["hand"] >= 0 and d["hand"] < 2
	t.check(await t.until(func(): return t.happened(&"hit_landed", punched), 10.0), "the unarmed defender punches the stranger")
	t.check(not t.happened(&"hit_landed", func(d): return d["actor"] == &"defender" and d["hand"] == 2), "and never kicks")

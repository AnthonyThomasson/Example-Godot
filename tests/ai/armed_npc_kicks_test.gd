extends GameTest

## In melee range an NPC holding a gun kicks instead of swapping to its fists: the pistol stays in hand and the
## blow lands as a kick (hit_landed hand code 2).


func describe() -> Dictionary:
	return {
		"name": "Armed NPC kicks in melee",
		"description": "A hostile stands point-blank; Von picks combat then melee; the defender kicks it and keeps its pistol.",
		"tags": ["ai", "melee", "kick", "scripted"],
		"timeout": 15.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 900, 600))
	s.von_script([{ "pick": "combat" }, { "pick": "melee" }])
	s.switch(&"ai.callouts", false)
	s.switch(&"ai.hostile_on_sight", true)
	s.switch(&"projectile.flyover", false)
	# The defender faces east at spawn, toward the stranger a step away.
	s.actor(&"defender", &"defender", Vector2(300, 300))
	s.actor(&"stranger", &"puppet", Vector2(338, 300), { "start_slot": 1, "faction": &"invader", "max_health": 400.0 })


func run(t: TestContext) -> void:
	var defender := t.actor(&"defender")
	var stranger := t.actor(&"stranger")
	var held: int = defender.current_slot()
	t.check(defender.ammo_capacity() >= 0, "the defender holds a gun")
	var kicked := func(d): return d["actor"] == &"defender" and d["body"] == stranger and d["hand"] == 2
	t.check(await t.until(func(): return t.happened(&"hit_landed", kicked), 10.0), "the defender kicks the stranger")
	t.expect_eq(defender.current_slot(), held, "the defender kept its gun in hand")
	t.check(not t.happened(&"hit_landed", func(d): return d["actor"] == &"defender" and d["hand"] >= 0 and d["hand"] < 2), "the defender never punched")

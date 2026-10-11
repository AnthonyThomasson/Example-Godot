extends GameTest

## With Von down, an NPC whose pistol is empty reloads on its own rather than staying unarmed.


func describe() -> Dictionary:
	return {
		"name": "A steady NPC reloads an empty pistol",
		"description": "Every Von decision fails; the defender's empty pistol is reloaded by the behaviour's reflex.",
		"tags": ["ai", "reload", "ammo", "scripted", "fallback"],
		"timeout": 12.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 900, 600))
	s.von_down()
	s.actor(&"defender", &"defender", Vector2(650, 300), { "start_rounds": 0 })


func run(t: TestContext) -> void:
	var defender := t.actor(&"defender")
	t.expect_eq(defender.ammo(3), 0, "the pistol starts empty")
	t.check(await t.until(func(): return defender.ammo(3) == 12, 6.0), "the NPC reloads it itself (%d rounds)" % defender.ammo(3))

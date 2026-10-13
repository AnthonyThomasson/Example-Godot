extends GameTest

## With nobody about, an NPC whose pistol is nearly empty has the quiet RELOAD as the only thing on offer at the
## top level, so it is taken without asking Von, and runs it.


func describe() -> Dictionary:
	return {
		"name": "A quiet NPC tops up its pistol",
		"description": "No threat is known and the defender's pistol is nearly empty; the quiet reload is the only thing on offer at the top level, so it is taken and the pistol is refilled.",
		"tags": ["ai", "decision", "reload", "ammo"],
		"timeout": 15.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 900, 600))
	s.actor(&"defender", &"defender", Vector2(450, 300), { "start_rounds": 2, "spare_magazine_types": [&"standard", &"standard"] })


func run(t: TestContext) -> void:
	var defender := t.actor(&"defender")
	var brain := t.controller(&"defender", &"current_act")
	t.check(await t.until(func(): return String(brain.current_act()) == "reload_quiet/reload", 6.0), "the decision path is the quiet reload (%s)" % brain.current_act())
	t.check(await t.until(func(): return defender.ammo(3) == 12, 6.0), "the pistol is full again (%d)" % defender.ammo(3))
	t.expect_eq(defender.spare_magazines(), 2, "the old magazine was kept as a spare")

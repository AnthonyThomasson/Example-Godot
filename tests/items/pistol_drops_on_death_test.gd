extends GameTest

## An armed character that dies lets go of its pistol: a DroppedItem lands in the world.


func describe() -> Dictionary:
	return {
		"name": "A dead gunman drops the pistol",
		"description": "A 1 hp pistol-holder is shot dead; a DroppedItem appears in the world.",
		"tags": ["item", "drop", "pistol", "death"],
		"timeout": 8.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 800, 500))
	s.switch(&"projectile.flyover", false)
	s.actor(&"shooter", &"puppet", Vector2(200, 250), { "start_slot": 3 })
	s.actor(&"target", &"puppet", Vector2(560, 250), { "start_slot": 3, "max_health": 1.0 })


func run(t: TestContext) -> void:
	var shooter := t.puppet(&"shooter")
	shooter.aim_at(t.actor(&"target"))
	await t.seconds(0.4)
	shooter.shoot()
	if not t.require(await t.until(func(): return t.happened(&"died", func(d): return d["actor"] == &"target"), 2.0), "the target dies"):
		return
	t.check(await t.until(func(): return t.world.get_children().any(func(n): return n is DroppedItem), 2.0), "a DroppedItem lies in the world")

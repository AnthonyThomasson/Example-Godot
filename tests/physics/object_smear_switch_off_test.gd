extends GameTest

## With the smear switch off a chair pushed through fresh blood leaves no streaks.


func describe() -> Dictionary:
	return {
		"name": "No smear with the smear switch off",
		"description": "physics.smear off: a chair pushed through a splatter lays no streaks.",
		"tags": ["blood", "smear", "switch"],
		"timeout": 12.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 900, 400))
	s.switch(&"physics.blood", true)
	s.switch(&"physics.smear", false)
	s.switch(&"nav.rebake", false)
	s.object(&"chair", "chair", Vector2(300, 200))
	s.actor(&"pusher", &"puppet", Vector2(240, 200))


func run(t: TestContext) -> void:
	BloodSpawner.splat(t.world, Vector2(300, 200), 30.0, Vector2.RIGHT, 0.0, [])
	await t.frames(2)
	t.puppet(&"pusher").walk(Vector2.RIGHT)
	await t.until(func(): return t.object(&"chair").global_position.x > 600.0, 8.0, "the chair is pushed across")
	var layer := BloodDecals.find(t.object(&"chair").get_parent())
	t.expect_eq(layer.ribbon_count() if layer else 0, 0, "no streaks were laid")

extends GameTest

## With the footprints switch off a walker crossing fresh blood prints nothing.


func describe() -> Dictionary:
	return {
		"name": "No footprints with the footprints switch off",
		"description": "physics.footprints off: a puppet walks through a fresh splatter and leaves no prints.",
		"tags": ["blood", "footprints", "switch"],
		"timeout": 12.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 700, 400))
	s.switch(&"physics.blood", true)
	s.switch(&"physics.footprints", false)
	s.actor(&"walker", &"puppet", Vector2(100, 200))


func run(t: TestContext) -> void:
	BloodSpawner.splat(t.world, Vector2(250, 200), 30.0, Vector2.RIGHT, 0.0, [])
	await t.frames(2)
	t.puppet(&"walker").walk(Vector2.RIGHT)
	await t.until(func(): return t.actor(&"walker").global_position.x > 550.0, 8.0, "the walker crosses")
	var layer := BloodDecals.find(t.world)
	t.expect_eq(layer.print_count() if layer else 0, 0, "no prints were left")

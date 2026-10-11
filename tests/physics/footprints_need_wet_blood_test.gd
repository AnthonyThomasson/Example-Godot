extends GameTest

## Footprints need wet blood under the feet: of three walkers crossing at once, the one over bare floor
## and the one over a splatter that has dried leave no prints; the one over a fresh splatter does.


func describe() -> Dictionary:
	return {
		"name": "Footprints need wet blood",
		"description": "Three puppets walk side by side: over bare floor, over a dried splatter and over a fresh one; only the fresh one prints.",
		"tags": ["blood", "footprints", "dried"],
		"timeout": 15.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 900, 700))
	s.switch(&"physics.blood", true)
	s.set_static(BloodConfig, &"splat_dry_time", 3.0)
	s.actor(&"clean", &"puppet", Vector2(100, 100))
	s.actor(&"dried", &"puppet", Vector2(100, 300))
	s.actor(&"fresh", &"puppet", Vector2(100, 500))


func run(t: TestContext) -> void:
	BloodSpawner.splat(t.world, Vector2(300, 300), 30.0, Vector2.RIGHT, 0.0, [])
	await t.seconds(3.5)  # the first splatter dries; the walkers have not moved yet
	BloodSpawner.splat(t.world, Vector2(300, 500), 30.0, Vector2.RIGHT, 0.0, [])
	await t.frames(2)
	for id in [&"clean", &"dried", &"fresh"]:
		t.puppet(id).walk(Vector2.RIGHT)
	await t.until(func(): return t.actor(&"clean").global_position.x > 600.0, 8.0, "the walkers cross")
	for id in [&"clean", &"dried", &"fresh"]:
		t.puppet(id).stop()
	var layer := BloodDecals.find(t.world)
	var near := { 100: 0, 300: 0, 500: 0 }
	if layer != null:
		for m in layer.items():
			if m["kind"] == "print":
				near[_lane(m["poly"][0].y)] += 1
	t.expect_eq(near[100], 0, "no prints over bare floor")
	t.expect_eq(near[300], 0, "no prints over dried blood")
	t.check(near[500] > 0, "prints over fresh blood (%d)" % near[500])


## The walker lane (its starting y) a print at `y` belongs to.
func _lane(y: float) -> int:
	return 100 if y < 200.0 else (300 if y < 400.0 else 500)

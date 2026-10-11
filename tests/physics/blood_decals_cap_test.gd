extends GameTest

## The decal layer keeps at most BloodConfig.print_max marks, dropping the oldest, and draws what it
## holds without engine errors.


func describe() -> Dictionary:
	return {
		"name": "Blood decals are capped",
		"description": "Adding three times print_max prints and strokes keeps the layer at print_max, newest kept.",
		"tags": ["blood", "decals", "stress"],
		"timeout": 10.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 900, 500))
	s.set_static(BloodConfig, &"print_max", 100)


func run(t: TestContext) -> void:
	var layer := BloodDecals.layer(t.world)
	for i in 300:
		var at := Vector2(50 + (i * 7) % 800, 50 + (i * 13) % 400)
		if i % 2 == 0:
			layer.print_at(PackedVector2Array([at, at + Vector2(6, 0), at + Vector2(6, 3), at + Vector2(0, 3)]), 0.5)
		else:
			layer.ribbon_begin(at, 3.0, 0.5)
	await t.frames(3)
	t.expect_eq(layer.items().size(), 100, "the layer holds print_max marks")
	t.check(BloodDecals.layer(t.world) == layer, "the world has one decal layer")

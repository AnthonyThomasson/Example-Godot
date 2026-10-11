extends GameTest

## Smear ribbons draw without engine errors whatever their shape: a straight run, a hairpin turn, a
## pinched zero-width tail, repeated and single-sample ribbons. Any logged error fails the test.


func describe() -> Dictionary:
	return {
		"name": "Smear ribbons draw cleanly in any shape",
		"description": "Straight, hairpin, zero-length, tapered and one-point ribbons are drawn with no engine error.",
		"tags": ["blood", "decals", "smear"],
		"timeout": 10.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 900, 500))


func run(t: TestContext) -> void:
	var layer := BloodDecals.layer(t.world)
	var straight := layer.ribbon_begin(Vector2(100, 100), 6.0, 0.8)
	for i in range(1, 30):
		layer.ribbon_extend(straight, Vector2(100 + i * 3, 100), 6.0 - i * 0.2, 0.8)
	layer.ribbon_extend(straight, Vector2(190, 100), 0.0, 0.0)

	var hairpin := layer.ribbon_begin(Vector2(300, 200), 8.0, 0.8)
	layer.ribbon_extend(hairpin, Vector2(330, 200), 8.0, 0.8)
	layer.ribbon_extend(hairpin, Vector2(300, 201), 8.0, 0.8)  # turns straight back on itself
	layer.ribbon_extend(hairpin, Vector2(300, 201), 8.0, 0.8)  # repeated point: zero-length segment

	layer.ribbon_begin(Vector2(500, 300), 5.0, 0.5)  # a single sample: nothing to draw
	var pinch := layer.ribbon_begin(Vector2(600, 300), 0.0, 0.0)
	layer.ribbon_extend(pinch, Vector2(640, 310), 0.0, 0.0)
	await t.frames(3)
	t.expect_eq(layer.ribbon_count(), 4, "all four ribbons are held")

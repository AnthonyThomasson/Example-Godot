extends GameTest

## A pinned seed reproduces the house: generating it again from the same seed and entrance gives the
## same rooms (keys, types and world rects).


func describe() -> Dictionary:
	return {
		"name": "Same seed, same house",
		"description": "WorldGen.generate with a pinned seed yields identical rooms when run twice.",
		"tags": ["seed", "house", "determinism"],
		"timeout": 5.0,
	}


func configure(s: TestSetup) -> void:
	s.house(424242)


func run(t: TestContext) -> void:
	if not t.require(not t.rooms.is_empty(), "the house has rooms"):
		return
	var again := WorldGen.generate(424242, "", Vector2.ZERO, t.world)
	var rooms_again := WorldGen.get_rooms(again)
	again.queue_free()
	t.expect_eq(rooms_again.size(), t.rooms.size(), "same number of rooms")
	var same := true
	for i in mini(rooms_again.size(), t.rooms.size()):
		var a: Dictionary = t.rooms[i]
		var b: Dictionary = rooms_again[i]
		same = same and a["key"] == b["key"] and a["type"] == b["type"] and (a["rect"] as Rect2).is_equal_approx(b["rect"])
	t.check(same, "every room matches (key, type, rect)")
	await t.frames(1)

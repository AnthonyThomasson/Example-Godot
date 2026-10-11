extends GameTest

## The baked nav map carves furniture out: a path across the arena detours around a bookshelf, and once
## the re-baker has seen the shelf moved away the path straightens again.


func describe() -> Dictionary:
	return {
		"name": "Paths route around furniture and re-bake when it moves",
		"description": "A bookshelf sits on the straight line; the nav path bends around it, then straightens after the shelf is moved off the line and the map re-bakes.",
		"tags": ["navigation", "bake", "rebake", "furniture"],
		"timeout": 15.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 600, 300))
	s.switch(&"nav.rebake", true)
	s.object(&"shelf", "bookshelf", Vector2(300, 150))


func _path_length(t: TestContext) -> float:
	var map := t.world.get_world_2d().navigation_map
	var path := NavigationServer2D.map_get_path(map, Vector2(60, 150), Vector2(540, 150), false)
	var length := 0.0
	for i in range(1, path.size()):
		length += path[i - 1].distance_to(path[i])
	return length


func run(t: TestContext) -> void:
	await t.seconds(0.5)  # the bake is applied a frame or two after the build
	var around := _path_length(t)
	t.trace("path_length", around)
	t.check(around > 520.0, "the path detours around the shelf (%.1f px; 480 is straight)" % around)
	var shelf: Node2D = t.object(&"shelf")
	shelf.global_position = Vector2(300, 40)
	var straight := func():
		var length := _path_length(t)
		t.trace("path_length", length)
		return length > 0.0 and length < around - 30.0
	t.check(await t.until(straight, 10.0), "the path shortens once the map re-bakes (%.1f px)" % _path_length(t))

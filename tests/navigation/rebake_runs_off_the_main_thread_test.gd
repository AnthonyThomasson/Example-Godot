extends GameTest

## A re-bake of the nav map runs on the NavigationServer's worker thread: `NavBuilder.rebake_async` returns before the
## region's polygon changes, the new polygon is in place by the time its `done` callback runs, and the re-baker
## (`nav_updater.gd`) still re-carves a shoved piece's hole at its new spot, so a path that had to bend around it
## straightens once the bake lands.


func describe() -> Dictionary:
	return {
		"name": "The re-bake runs off the main thread",
		"description": "rebake_async returns before the map changes and delivers the new polygon through its callback; the re-baker still re-carves a moved bookshelf.",
		"tags": ["navigation", "bake", "rebake", "furniture"],
		"timeout": 15.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 600, 300))
	s.switch(&"nav.rebake", true)
	s.object(&"shelf", "bookshelf", Vector2(300, 150))


func run(t: TestContext) -> void:
	await t.seconds(0.5)  # the first bake is applied a frame or two after the build
	var region: NavigationRegion2D = t.world.find_children("*", "NavigationRegion2D", true, false)[0]
	var before: NavigationPolygon = region.navigation_polygon
	var landed := [false]  # a lambda captures a bool by value
	NavBuilder.rebake_async(region, t.world.house, t.rooms, 14.0, func() -> void: landed[0] = true)
	t.check(region.navigation_polygon == before, "rebake_async returns before the region's polygon changes")
	t.check(not landed[0], "its callback has not run yet when it returns")
	if not t.require(await t.until(func(): return landed[0], 5.0), "the bake lands and calls back"):
		return
	t.check(region.navigation_polygon != before, "the region holds the new polygon once the callback runs")

	var around := _path_length(t)
	t.check(around > 520.0, "the path detours around the shelf (%.1f px; 480 is straight)" % around)
	var shelf: Node2D = t.object(&"shelf")
	shelf.global_position = Vector2(300, 40)
	var straight := func():
		var length := _path_length(t)
		t.trace("path_length", length)
		return length > 0.0 and length < around - 30.0
	t.check(await t.until(straight, 10.0), "the re-baker re-carves the moved shelf and the path straightens (%.1f px)" % _path_length(t))


## The navigated length of a path straight across the arena.
func _path_length(t: TestContext) -> float:
	var map := t.world.get_world_2d().navigation_map
	var path := NavigationServer2D.map_get_path(map, Vector2(60, 150), Vector2(540, 150), false)
	var length := 0.0
	for i in range(1, path.size()):
		length += path[i - 1].distance_to(path[i])
	return length

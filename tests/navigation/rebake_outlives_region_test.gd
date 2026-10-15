extends GameTest

## A re-bake still in flight when its region is freed (a world torn down mid-bake: a test ending, a match restarting)
## lands quietly: `NavBuilder.rebake_async` leaves the freed region alone and still calls `done`, with no engine error
## (a callback that held the freed region logged one into whatever ran next).


func describe() -> Dictionary:
	return {
		"name": "A re-bake outlives its freed region",
		"description": "rebake_async on a region freed before the bake lands calls back without logging an engine error.",
		"tags": ["navigation", "bake", "rebake"],
		"timeout": 10.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 600, 300))
	s.object(&"shelf", "bookshelf", Vector2(300, 150))


func run(t: TestContext) -> void:
	await t.seconds(0.2)
	# A region of its own, never put on a map: freeing it leaves the world's navigation alone.
	var region := NavigationRegion2D.new()
	var landed := [false]  # a lambda captures a bool by value
	NavBuilder.rebake_async(region, t.world.house, t.rooms, 14.0, func() -> void: landed[0] = true)
	t.check(not landed[0], "the bake is still in flight when it returns")
	region.free()
	t.check(await t.until(func(): return landed[0], 5.0), "the bake lands and calls back after its region is freed")
	await t.frames(2)

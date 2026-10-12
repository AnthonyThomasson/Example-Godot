extends GameTest

## The "Navigation holes" overlay (`NavDebug`) draws what the nav bake carves: the red furniture holes and the orange
## holes of the characters at rest. A standing puppet is one, a walking puppet is none until it stops, and a puppet
## that dies drops out; the overlay follows each re-bake.


func describe() -> Dictionary:
	return {
		"name": "The navigation-holes overlay shows character holes",
		"description": "NavDebug holds the furniture hole and the hole of the standing puppet, not the walking one's until it stops at the wall, and drops a puppet that dies.",
		"tags": ["navigation", "overlay", "character", "rebake"],
		"timeout": 25.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 600, 300))
	s.switch(&"nav.rebake", true)
	s.show_overlays(["show_nav_holes"])
	s.object(&"shelf", "bookshelf", Vector2(300, 50))
	s.actor(&"standing", &"puppet", Vector2(200, 200))
	s.actor(&"walker", &"puppet", Vector2(60, 120), { "max_health": 10.0 })


## The overlay's character holes, as the polygons it will draw.
func _characters(dbg: Node) -> Array:
	return dbg.get("_character_holes")


## Where a hole is: the mean of its points.
func _centre(hole: PackedVector2Array) -> Vector2:
	var sum := Vector2.ZERO
	for p in hole:
		sum += p
	return sum / float(hole.size())


func run(t: TestContext) -> void:
	var dbg := t.world.get_node("NavDebug")
	t.check(dbg.get("show_holes"), "the overlay is on")
	t.puppet(&"walker").walk(Vector2.RIGHT)

	var one_hole := func(): return _characters(dbg).size() == 1
	if not t.require(await t.until(one_hole, 5.0), "while the other walks, only the standing character is a hole (%d)" % _characters(dbg).size()):
		return
	t.expect_near(_centre(_characters(dbg)[0]).distance_to(t.actor(&"standing").global_position), 0.0, 2.0, "and it is where the standing character is")
	t.expect_eq((dbg.get("_holes") as Array).size(), 1, "the shelf is the one furniture hole")

	var two_holes := func(): return _characters(dbg).size() == 2
	t.check(await t.until(two_holes, 10.0), "the walker is a hole once it has stopped at the wall (%d)" % _characters(dbg).size())

	t.actor(&"walker").take_damage(100.0)
	t.check(await t.until(one_hole, 5.0), "a character that dies drops out of the overlay (%d)" % _characters(dbg).size())
	t.expect_eq((dbg.get("_holes") as Array).size(), 1, "the furniture hole stays")

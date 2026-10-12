extends GameTest

## SoundSurface answers what a world point is on: the newest floor covering it (a floor laid over another
## wins), or the open ground when no floor does. Floors name their material and pattern; planks and parquet are
## wood, ceramic is tile, slate is stone, poured concrete is concrete, fabric is carpet. A room's real floor
## registers itself and unregisters when it leaves.


func describe() -> Dictionary:
	return {
		"name": "SoundSurface knows the floor under a point",
		"description": "Registered floors answer by point, newest first, outdoors elsewhere; materials map to surfaces; a real arena floor registers while it exists.",
		"tags": ["sound", "surface", "floor"],
		"timeout": 5.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 800, 500))


func run(t: TestContext) -> void:
	# The arena's own floor (oak planks) covers the arena and nothing past it.
	t.expect_eq(SoundSurface.at(Vector2(400, 250)), &"wood", "the arena floor is wood")
	t.expect_eq(SoundSurface.at(Vector2(-200, 250)), &"outdoor", "past the arena it is the open ground")
	t.expect_eq(SoundSurface.at(Vector2(400, 900)), &"outdoor", "and below it")

	var before := SoundSurface.count()
	var carpet := FloorFactory.spawn(Rect2(500, 100, 200, 200), {
		"art": "floor", "color": Color(0.7, 0.7, 0.7), "material": "fabric", "art_opts": { "pattern": "carpet" },
	}, "TestCarpet", t.world)
	await t.frames(1)
	t.expect_eq(SoundSurface.count(), before + 1, "a spawned floor registers itself")
	t.expect_eq(SoundSurface.at(Vector2(600, 200)), &"carpet", "a floor laid over another wins")
	t.expect_eq(SoundSurface.at(Vector2(300, 200)), &"wood", "beside it the older floor shows")
	carpet.free()
	t.expect_eq(SoundSurface.count(), before, "a floor unregisters when it goes")
	t.expect_eq(SoundSurface.at(Vector2(600, 200)), &"wood", "and the floor beneath is heard again")

	# Direct registration, newest first.
	var low := SoundSurface.register(Rect2(1000, 0, 100, 100), "ceramic", "tiles")
	var high := SoundSurface.register(Rect2(1050, 0, 100, 100), "stone", "concrete")
	t.expect_eq(SoundSurface.at(Vector2(1020, 50)), &"tile", "tile where only tile lies")
	t.expect_eq(SoundSurface.at(Vector2(1075, 50)), &"concrete", "the newer floor wins where they overlap")
	SoundSurface.unregister(high)
	t.expect_eq(SoundSurface.at(Vector2(1075, 50)), &"tile", "the older shows once the newer is gone")
	SoundSurface.unregister(low)
	SoundSurface.unregister(low)  # unknown ids are ignored
	t.expect_eq(SoundSurface.at(Vector2(1020, 50)), &"outdoor", "nothing registered is the open ground")
	t.expect_eq(SoundSurface.count(), before, "the registry is back where it started")

	for case in [
		["wood", "planks", &"wood"], ["wood", "parquet", &"wood"], ["ceramic", "tiles", &"tile"], ["ceramic", "checker", &"tile"],
		["ceramic", "mosaic", &"tile"], ["stone", "tiles", &"stone"], ["stone", "concrete", &"concrete"], ["fabric", "carpet", &"carpet"],
		["", "", &"wood"], ["unobtainium", "x", &"wood"],
	]:
		t.expect_eq(SoundSurface.surface_for(case[0], case[1]), case[2], "%s / %s" % [case[0], case[1]])
	# Every floor the house catalogue can lay maps to a surface footsteps are voiced for.
	for key in ["oak_planks", "walnut_planks", "ash_planks", "grey_planks", "parquet", "white_tile", "terracotta_tile",
			"slate_tile", "checker", "mosaic", "beige_carpet", "blue_carpet", "green_carpet", "concrete"]:
		var def := WorldGen.floor_definition(key)
		if not t.require(not def.is_empty(), "the catalogue has a %s floor" % key):
			return
		var surface := SoundSurface.surface_for(def["material"], String(def["art_opts"].get("pattern", "")))
		t.check(SoundBank.FOOTSTEPS.has(String(surface)),
			"%s (%s) is voiced as %s" % [key, def["material"], surface])

extends GameTest

## `NavBuilder.avoid_map(region, key, holes)` (interface 9, issue #51): the planning bake plus extra hole polygons on a map of its own,
## baked off the main thread, cached by key and freed once nobody asks for it. In an empty walled arena, a hole
## across the middle (leaving a gap above and below) makes a route that goes round it, longer than the straight one; the world's own
## map still goes straight through; the same key answers the same map, another key another; a map not asked for in
## `avoid_idle_ms` (wall clock) is freed (the test shortens that to 0.3 s).

const ARENA := Rect2(0, 0, 800, 500)
const FROM := Vector2(100, 250)
const TO := Vector2(700, 250)
## A wall of floor across the middle, with 100 px open above and below.
const HOLE := [Vector2(380, 100), Vector2(420, 100), Vector2(420, 400), Vector2(380, 400)]


func describe() -> Dictionary:
	return {
		"name": "An avoid map carves the holes it is given",
		"description": "avoid_map bakes the planning bake plus extra holes on a map of its own: routes go round them, the world's map is untouched, the key caches it, an idle one is freed.",
		"tags": ["navigation", "bake", "avoid"],
		"timeout": 20.0,
	}


func configure(s: TestSetup) -> void:
	s.arena(ARENA)
	s.set_static(NavBuilder, "avoid_idle_ms", 300)


func run(t: TestContext) -> void:
	var world_map := t.world.get_world_2d().navigation_map
	var region := NavBuilder.planning_region(world_map)
	if not t.require(region != null, "the planning region is found from the world's map"):
		return
	var straight := NavBuilder.path_length(NavBuilder.route(world_map, FROM, TO))
	t.check(straight < 620.0, "the plain route goes straight across (%.0f px)" % straight)

	var hole := PackedVector2Array(HOLE)
	var map := NavBuilder.avoid_map(region, "middle", [hole])
	if not t.require(map.is_valid(), "avoid_map answers a map"):
		return
	t.check(NavBuilder.avoid_map(region, "middle", [hole]) == map, "the same key answers the same map")
	if not t.require(await t.until(func(): return NavBuilder.ready(map), 8.0), "the avoid map is baked and answers queries"):
		return
	var path := NavBuilder.route(map, FROM, TO)
	var length := NavBuilder.path_length(path)
	t.check(length > straight + 20.0, "its route goes round the hole (%.0f px against %.0f straight)" % [length, straight])
	t.check(path[path.size() - 1].distance_to(TO) < 10.0, "and still reaches the far side")
	t.check(Geometry2D.intersect_polyline_with_polygon(path, hole).is_empty(), "no stretch of it is inside the hole")
	t.check(is_equal_approx(NavBuilder.path_length(NavBuilder.route(world_map, FROM, TO)), straight), "the world's own map still goes straight through")

	var other := NavBuilder.avoid_map(region, "elsewhere", [PackedVector2Array([Vector2(100, 20), Vector2(140, 20), Vector2(140, 60), Vector2(100, 60)])])
	t.check(other != map, "another key is another map")
	if not t.require(await t.until(func(): return NavBuilder.ready(other), 8.0), "the other map is baked too"):
		return
	t.check(is_equal_approx(NavBuilder.path_length(NavBuilder.route(other, FROM, TO)), straight), "and a hole off the route leaves the route straight")

	# Only `other` is asked for from here on: `map` goes idle (on the wall clock, which a headless run outpaces: wait it out) and is
	# freed with its region.
	OS.delay_msec(450)
	NavBuilder.avoid_map(region, "elsewhere", [])
	t.check(await t.until(func(): return not NavigationServer2D.get_maps().has(map), 5.0), "a map nobody asks for is freed")
	t.check(NavigationServer2D.get_maps().has(other), "the one still asked for is kept")

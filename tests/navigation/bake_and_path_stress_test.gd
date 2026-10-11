extends GameTest

## Performance guard: re-baking the nav map of a furnished house and answering many path queries stay fast.
## Budgets are wall-clock ms with headroom over the baseline.

const Perf := preload("res://tests/_perf/perf_probe.gd")

const REBAKES := 10
const QUERIES := 300
# Baseline: ~2.5 ms per re-bake, ~1.2 ms for all 300 queries. Budgets ~5-8x (small numbers jitter more).
const REBAKE_BUDGET_MS := 12.0
const QUERY_BUDGET_MS := 10.0


func describe() -> Dictionary:
	return {
		"name": "Nav re-bake and path queries stay fast",
		"description": "A generated house is re-baked ten times and 300 paths are queried between its rooms; per-bake and per-query wall time stay within budget.",
		"tags": ["perf", "stress", "navigation", "bake", "path"],
		"timeout": 10.0,
	}


func configure(s: TestSetup) -> void:
	s.house(424242)


func run(t: TestContext) -> void:
	await t.seconds(0.5)  # the first bake is applied a frame or two after the build
	if not t.require(t.rooms.size() >= 2, "the house has rooms to path between"):
		return
	var region: NavigationRegion2D = t.world.find_children("*", "NavigationRegion2D", true, false)[0]
	var house: Node2D = t.world.house
	var rooms: Array = t.rooms

	var rebake_ms := Perf.time_ms(func():
		for i in REBAKES:
			NavBuilder.rebake(region, house, rooms))
	Perf.within(t, "nav rebake ms each", rebake_ms / REBAKES, REBAKE_BUDGET_MS)
	await t.frames(2)  # let the last bake apply

	var map := t.world.get_world_2d().navigation_map
	var found := [0]  # a lambda captures ints by value
	var query_ms := Perf.time_ms(func():
		for i in QUERIES:
			var a: Rect2 = rooms[i % rooms.size()]["rect"]
			var b: Rect2 = rooms[(i * 7 + 3) % rooms.size()]["rect"]
			var path := NavigationServer2D.map_get_path(map, a.get_center(), b.get_center(), true)
			if not path.is_empty():
				found[0] += 1)
	Perf.within(t, "nav %d path queries total ms" % QUERIES, query_ms, QUERY_BUDGET_MS)
	t.check(found[0] > QUERIES / 2, "most room-to-room paths are found (%d of %d)" % [found[0], QUERIES])

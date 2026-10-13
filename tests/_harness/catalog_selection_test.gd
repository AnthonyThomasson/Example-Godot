extends GameTest

## Harness self-test: the catalog's selection helpers — comma lists, exact domain/id pre-filtering, and
## shards that partition a run (disjoint, complete, Von tests together in shard 0).

const Catalog = preload("res://scenes/testing/test_catalog.gd")


func describe() -> Dictionary:
	return { "name": "Catalog selection and shards", "tags": ["harness", "catalog"], "internal": true, "timeout": 3.0 }


func configure(s: TestSetup) -> void:
	s.arena(Rect2(0, 0, 200, 200))


func run(t: TestContext) -> void:
	t.expect_eq(Catalog.csv("ai, navigation,,x"), ["ai", "navigation", "x"], "csv trims and drops blanks")
	t.expect_eq(Catalog.csv(""), [], "csv of nothing is empty")

	var all := Catalog.discover()
	var ai := Catalog.discover(Catalog.ROOT, ["ai"])
	t.check(not ai.is_empty() and ai.all(func(e): return e["domain"] == "ai"), "a domain filter keeps exactly that domain")
	t.check(ai.size() < all.size(), "and leaves the others out")
	var one := Catalog.discover(Catalog.ROOT, [], [ai[0]["id"]])
	t.expect_eq(one.size(), 1, "an id filter keeps exactly one test")
	var without_ai := Catalog.discover(Catalog.ROOT, [], [], ["ai"])
	t.check(not without_ai.is_empty() and not without_ai.any(func(e): return e["domain"] == "ai"), "a skipped domain is left out")
	t.expect_eq(without_ai.size() + ai.size(), all.size(), "and nothing else is")
	t.expect_eq(Catalog.discover(Catalog.ROOT, ["ai"], [], ["ai"]).size(), 0, "a skip wins over a selection of the same domain")

	var fake: Array = []
	for i in 7:
		fake.append({ "id": "d/t%d" % i, "requires_von": i == 3 })
	var seen: Array = []
	for i in 3:
		var part := Catalog.shard(fake, "%d/3" % i)
		for e in part:
			t.check(not seen.has(e["id"]), "%s lands in one shard only" % e["id"])
			seen.append(e["id"])
		if i != 0:
			t.check(not part.any(func(e): return e["requires_von"]), "Von tests stay out of shard %d" % i)
	t.expect_eq(seen.size(), fake.size(), "the shards together cover every test")
	t.expect_eq(Catalog.shard(fake, "0/1").size(), fake.size(), "one shard is the whole run")

	# With measured costs the shards balance by them, not by the declared timeout: two heavy tests (declared
	# 1 s, measured 1000 ms) and six light ones (declared 50 s, measured 100 ms) split evenly, one heavy each.
	var costed: Array = []
	var costs := {}
	for i in 8:
		var id := "d/c%d" % i
		costed.append({ "id": id, "requires_von": false, "timeout": 1.0 if i < 2 else 50.0 })
		costs[id] = 1000.0 if i < 2 else 100.0
	var weights: Array = []
	for i in 2:
		var part := Catalog.shard(costed, "%d/2" % i, costs)
		var weight := 0.0
		for e in part:
			weight += costs[e["id"]]
		weights.append(weight)
		t.expect_eq(part.filter(func(e): return costs[e["id"]] == 1000.0).size(), 1, "shard %d holds one of the heavy tests" % i)
	t.expect_eq(weights, [1300.0, 1300.0], "the shards weigh the same by measured cost")

	# An id without a measurement costs the median, so a long declared timeout does not make it the heaviest.
	costed.append({ "id": "d/new", "requires_von": false, "timeout": 500.0 })
	var with_new := Catalog.shard(costed, "0/2", costs) + Catalog.shard(costed, "1/2", costs)
	t.expect_eq(with_new.size(), costed.size(), "an unmeasured test is still run exactly once")
	t.check(Catalog.shard(costed, "0/2", costs).any(func(e): return e["id"] == "d/new") \
		or Catalog.shard(costed, "1/2", costs).any(func(e): return e["id"] == "d/new"), "and lands in a shard")

	# A Von test that will be skipped weighs nothing; one that will run keeps shard 0 to itself.
	var light: Array = []
	var light_costs := { "d/von": 100000.0 }
	for i in 4:
		light.append({ "id": "d/l%d" % i, "requires_von": false, "timeout": 1.0 })
		light_costs["d/l%d" % i] = 100.0
	light.append({ "id": "d/von", "requires_von": true, "timeout": 40.0 })
	t.expect_eq(Catalog.shard(light, "0/2", light_costs, true).size(), 1, "a running Von test fills shard 0")
	t.expect_eq(Catalog.shard(light, "0/2", light_costs, false).size(), 3, "a skipped Von test does not")

	# The costs file: missing or blank is empty, a written one reads back (numbers only).
	t.expect_eq(Catalog.load_costs(""), {}, "no costs path means no costs")
	t.expect_eq(Catalog.load_costs("user://catalog_costs_missing.json"), {}, "a missing costs file means no costs")
	var path := "user://catalog_costs_test.json"
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(JSON.stringify({ "a/b": 12.5, "c/d": 7, "e/f": "slow" }))
	f.close()
	t.expect_eq(Catalog.load_costs(path), { "a/b": 12.5, "c/d": 7.0 }, "a costs file reads back its numbers")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

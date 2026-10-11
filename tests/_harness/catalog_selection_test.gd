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

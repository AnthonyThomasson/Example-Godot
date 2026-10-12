extends GameTest

## Desired (E8): once a pair has cleared the kitchen (in by the back door), each of them covers a different one of the
## kitchen's doorways on into rooms nobody has cleared, the living room's and the hall's: it stands in the kitchen with
## its gun through that doorway. Neither is left watching the garden they came from while a doorway on is unwatched.

const Entry := preload("res://tests/_ai/entry_probe.gd")
const Maps := preload("res://tests/_ai/flank_maps.gd")


func describe() -> Dictionary:
	return {
		"name": "Entry pair covers the doorways on",
		"description": "After clearing the kitchen, one invader covers the living room doorway and the other the hall's, from inside the kitchen.",
		"tags": ["ai", "entry", "scripted", "callout"],
		"timeout": 70.0,
	}


func configure(s: TestSetup) -> void:
	Maps.house(s, false)
	Entry.rules(s, Entry.BACK)
	Entry.npc(s, &"a", Vector2(960, 60), 0.4)
	Entry.npc(s, &"b", Vector2(985, 110), 0.55)


func run(t: TestContext) -> void:
	var covering := func(): return not Entry.calls(t, "cover", &"a").is_empty() and not Entry.calls(t, "cover", &"b").is_empty()
	await Entry.watch(t, [&"a", &"b"], Entry.BACK, 60.0, covering)
	if not t.require(covering.call(), "both radioed that they cover a doorway on (%s / %s)" % [Entry.brain(t, &"a").current_act(), Entry.brain(t, &"b").current_act()]):
		return
	var named := {}
	for id in [&"a", &"b"]:
		named[id] = String(Entry.calls(t, "cover", id)[-1].get("covering", ""))
	t.check(named[&"a"] != named[&"b"], "they cover different doorways (%s / %s)" % [named[&"a"], named[&"b"]])
	t.check(named.values().all(func(d): return d in [Entry.KITCHEN_LIVING["id"], Entry.KITCHEN_HALL["id"]]), "each covers a doorway on out of the kitchen (%s)" % str(named.values()))
	var samples := await Entry.watch(t, [&"a", &"b"], Entry.BACK, 3.0)
	var in_kitchen := func(p: Vector2): return Maps.HOUSE_KITCHEN.has_point(p)
	var held := {}
	for id in [&"a", &"b"]:
		for door in [Entry.KITCHEN_LIVING, Entry.KITCHEN_HALL]:
			var share := Entry.time_facing_through(samples, id, door, in_kitchen) / 3.0
			if share >= 0.7:
				held[id] = door["id"]
		t.check(held.has(id), "%s stood in the kitchen with its gun through a doorway on (act %s)" % [id, Entry.brain(t, id).current_act()])
		t.check(Entry.time_facing_through(samples, id, Entry.BACK) < 0.3, "%s did not watch the garden instead" % id)
	if held.size() == 2:
		t.check(held[&"a"] != held[&"b"], "they held different doorways (%s / %s)" % [held[&"a"], held[&"b"]])

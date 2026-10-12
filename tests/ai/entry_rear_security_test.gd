extends GameTest

## Desired (E8): a doorway on into a room nobody has cleared comes first, and a member left over holds the rear. A pair
## clears the living room, in from the hall: its one doorway on is the kitchen's, so one of them covers it, gun through
## it from inside the living room, and the other stays on the hall door as rear security, just inside it and facing back
## out the way they came.

const Entry := preload("res://tests/_ai/entry_probe.gd")
const Maps := preload("res://tests/_ai/flank_maps.gd")


func describe() -> Dictionary:
	return {
		"name": "Entry leaves rear security",
		"description": "After clearing the living room, one invader covers the kitchen doorway and the other holds the hall door facing out.",
		"tags": ["ai", "entry", "scripted", "callout"],
		"timeout": 70.0,
	}


func configure(s: TestSetup) -> void:
	Maps.house(s, false)
	Entry.rules(s, Entry.HALL_LIVING)
	Entry.npc(s, &"a", Vector2(600, 415), 0.4)
	Entry.npc(s, &"b", Vector2(700, 415), 0.55)


func run(t: TestContext) -> void:
	var door := Entry.HALL_LIVING
	var holding := func(): return not Entry.calls(t, "cover").is_empty() and not Entry.calls(t, "rear").is_empty()
	await Entry.watch(t, [&"a", &"b"], door, 60.0, holding)
	if not t.require(holding.call(), "one radioed it covers a doorway on and one that it holds the rear (%s / %s)" % [Entry.brain(t, &"a").current_act(), Entry.brain(t, &"b").current_act()]):
		return
	t.expect_eq(String(Entry.calls(t, "cover")[-1].get("covering", "")), Entry.LIVING_KITCHEN["id"], "the doorway covered is the kitchen's")
	var samples := await Entry.watch(t, [&"a", &"b"], door, 3.0)
	var guard: StringName = &""
	var coverer: StringName = &""
	var in_living := func(p: Vector2): return Maps.HOUSE_LIVING.has_point(p)
	for id in [&"a", &"b"]:
		var held := samples.filter(func(s):
			var p: Vector2 = s["pos"][id]
			return p.distance_to(door["pos"]) <= 90.0 and Entry.outward(door, p) <= 0.0 and (s["facing"][id] as Vector2).dot(door["out"]) > 0.7)
		if held.size() >= samples.size() * 0.5:
			guard = id
		elif Entry.time_facing_through(samples, id, Entry.LIVING_KITCHEN, in_living) >= 3.0 * 0.6:
			coverer = id
	t.check(guard != &"", "one of them holds the hall door from inside, facing out")
	t.check(coverer != &"", "the other points its gun through the kitchen doorway from the living room")

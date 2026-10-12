extends GameTest

## Desired (E8): when a pair has cleared the kitchen, one of them stays on the back door as rear security, just inside
## it and facing back out the way they came, while the other moves on to a new decision.

const Entry := preload("res://tests/_ai/entry_probe.gd")
const Maps := preload("res://tests/_ai/flank_maps.gd")


func describe() -> Dictionary:
	return {
		"name": "Entry leaves rear security",
		"description": "After clearing, one invader holds the back door facing out while the other moves on.",
		"tags": ["ai", "entry", "scripted", "gap", "callout"],
		"timeout": 70.0,
	}


func configure(s: TestSetup) -> void:
	Maps.house(s, false)
	Entry.rules(s, Entry.BACK)
	Entry.npc(s, &"a", Vector2(960, 60), 0.4)
	Entry.npc(s, &"b", Vector2(985, 110), 0.55)


func run(t: TestContext) -> void:
	var door := Entry.BACK
	var cleared := func(): return not Entry.calls(t, "clear").is_empty()
	await Entry.watch(t, [&"a", &"b"], door, 60.0, cleared)
	if not t.require(cleared.call(), "the pair radioed the room clear (%s / %s)" % [Entry.brain(t, &"a").current_act(), Entry.brain(t, &"b").current_act()]):
		return
	var samples := await Entry.watch(t, [&"a", &"b"], door, 3.0)
	var guard: StringName = &""
	for id in [&"a", &"b"]:
		var held := samples.filter(func(s):
			var p: Vector2 = s["pos"][id]
			return p.distance_to(door["pos"]) <= 90.0 and Entry.outward(door, p) <= 0.0 and (s["facing"][id] as Vector2).dot(door["out"]) > 0.7)
		if held.size() >= samples.size() * 0.5:
			guard = id
	if not t.require(guard != &"", "one of them holds the door from inside, facing out"):
		return
	var other: StringName = &"b" if guard == &"a" else &"a"
	t.check(not String(Entry.brain(t, other).current_act()).ends_with(door["id"]), "the other moved on (%s)" % Entry.brain(t, other).current_act())

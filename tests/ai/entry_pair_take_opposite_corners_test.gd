extends GameTest

## Desired (E5): two invaders entering the kitchen by its centre-fed back door take opposite corners: the point turns
## to the near corner on its side, the second crosses to the corner on the other side of the door. Each stops at a
## corner on the door's wall, one either side of the door axis.

const Entry := preload("res://tests/_ai/entry_probe.gd")
const Maps := preload("res://tests/_ai/flank_maps.gd")


func describe() -> Dictionary:
	return {
		"name": "Entry pair takes opposite corners",
		"description": "Two invaders entering the kitchen stop at the two door-wall corners, one either side of the door.",
		"tags": ["ai", "entry", "scripted", "gap", "callout"],
		"timeout": 50.0,
	}


func configure(s: TestSetup) -> void:
	Maps.house(s, false)
	Entry.rules(s, Entry.BACK)
	Entry.npc(s, &"a", Vector2(960, 60), 0.4)
	Entry.npc(s, &"b", Vector2(985, 110), 0.55)


func run(t: TestContext) -> void:
	var door := Entry.BACK
	var stops := {}
	var samples := await Entry.watch(t, [&"a", &"b"], door, 45.0, func():
		return not Entry.calls(t, "in", &"a").is_empty() and not Entry.calls(t, "in", &"b").is_empty() and t.time - maxf(Entry.first_call_time(t, "in", &"a"), Entry.first_call_time(t, "in", &"b")) > 3.0)
	for id in [&"a", &"b"]:
		stops[id] = Entry.first_stop_in_room(samples, id, door)
	if not t.require(stops.values().all(func(p): return p != Vector2.INF), "both went in and stopped at a corner (%s)" % str(stops)):
		return
	var la := Entry.lateral(door, stops[&"a"])
	var lb := Entry.lateral(door, stops[&"b"])
	t.check(signf(la) != signf(lb), "they took opposite sides of the door (%s / %s)" % [stops[&"a"].round(), stops[&"b"].round()])
	for id in stops:
		t.check(Entry.outward(door, stops[id]) > -130.0 and absf(Entry.lateral(door, stops[id])) > float(door["width"]) * 0.5,
			"%s stopped in a corner on the door's wall (%s)" % [id, stops[id].round()])

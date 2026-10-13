extends GameTest

## Desired (E5): entering the living room from the hall by its corner-fed door, the second invader crosses to the hard
## corner on the other side of the door (a corner on the door's wall, unseen from outside), not to the far corner the
## pie left hidden; the point takes the near corner on its own side.

const Entry := preload("res://tests/_ai/entry_probe.gd")
const Maps := preload("res://tests/_ai/flank_maps.gd")


func describe() -> Dictionary:
	return {
		"name": "Entry pair takes the hard corner first",
		"description": "Through the corner-fed living room door, the pair stops at the two door-wall corners, never a far one.",
		"tags": ["ai", "entry", "scripted", "callout"],
		"timeout": 50.0,
	}


func configure(s: TestSetup) -> void:
	Maps.house(s, false)
	Entry.rules(s, Entry.HALL_LIVING)
	Entry.npc(s, &"a", Vector2(600, 415), 0.4)
	Entry.npc(s, &"b", Vector2(700, 415), 0.55)


func run(t: TestContext) -> void:
	var door := Entry.HALL_LIVING
	var samples := await Entry.watch(t, [&"a", &"b"], door, 45.0, func():
		return not Entry.calls(t, "in", &"a").is_empty() and not Entry.calls(t, "in", &"b").is_empty() and t.time - maxf(Entry.first_call_time(t, "in", &"a"), Entry.first_call_time(t, "in", &"b")) > 3.0)
	var corners := Entry.corners(door)
	var used := {}
	for id in [&"a", &"b"]:
		var stop := Entry.first_stop_in_room(samples, id, door)
		if not t.check(stop != Vector2.INF, "%s went in and stopped (act %s)" % [id, Entry.brain(t, id).current_act()]):
			continue
		var near := -1
		for i in corners["near"].size():
			if stop.distance_to(corners["near"][i]) < 90.0:
				near = i
		t.check(near >= 0, "%s stopped at a hard corner on the door's wall, not a far one (%s)" % [id, stop.round()])
		used[near] = true
	t.check(used.size() == 2 and not used.has(-1), "they took both hard corners, one each")

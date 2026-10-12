extends GameTest

## Desired (E7): alone, the invader makes one committed entry: it crosses the doorway once, straight to a hard corner
## (one on the door's wall), and clears the rest by sight.

const Entry := preload("res://tests/_ai/entry_probe.gd")
const Maps := preload("res://tests/_ai/flank_maps.gd")


func describe() -> Dictionary:
	return {
		"name": "Solo entry commits once",
		"description": "Alone, the invader crosses the back door once and goes straight to a door-wall corner.",
		"tags": ["ai", "entry", "scripted"],
		"timeout": 50.0,
	}


func configure(s: TestSetup) -> void:
	Maps.house(s, false)
	Entry.rules(s, Entry.BACK)
	Entry.npc(s, &"inv", Vector2(960, 60))


func run(t: TestContext) -> void:
	var door := Entry.BACK
	var samples := await Entry.watch(t, [&"inv"], door, 45.0, func():
		var at := Entry.first_call_time(t, "in", &"inv")
		return at < INF and t.time - at > 3.0)
	var stop := Entry.first_stop_in_room(samples, &"inv", door)
	if not t.require(stop != Vector2.INF, "the invader went in and stopped (act %s)" % Entry.brain(t, &"inv").current_act()):
		return
	t.expect_eq(Entry.funnel_entries(samples, &"inv", door), 1, "it crossed the doorway once")
	t.check(Entry.corners(door)["near"].any(func(c): return stop.distance_to(c) < 90.0), "it went straight to a hard corner (%s)" % stop.round())

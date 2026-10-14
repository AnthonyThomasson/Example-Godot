extends GameTest

## Issue #53, one mechanism: two NPCs walking head-on at each other through the one doorway between two rooms, each in
## the other's view, do not collide. One gives way (it steps aside or waits) and the other passes; then both carry on and
## get where they were going. Neither walks into the other at any time ("walks into": `tests/_ai/bump_probe.gd`). The
## test requires the premise first: both were sent across, and they were near the doorway together, coming at each other.
##
## Switches and props: none. Two defenders with scripted Von (search > the other room), so each walk is a plain move;
## each starts facing the doorway (`aim_point`), so they see each other as they come.

const Bump := preload("res://tests/_ai/bump_probe.gd")

const WEST := Rect2(0, 0, 400, 500)
const EAST := Rect2(400, 0, 400, 500)
const DOOR := Vector2(400, 250)
const A_START := Vector2(130, 250)
const B_START := Vector2(670, 250)
## Both within this distance (px) of the doorway at once, walking toward it: they meet there.
const MEET := 150.0
const WATCH_S := 20.0


func describe() -> Dictionary:
	return {
		"name": "Two NPCs walking head-on give way to each other",
		"description": "Two NPCs cross one doorway in opposite directions at the same time; one gives way, neither walks into the other, both arrive.",
		"tags": ["ai", "navigation", "character", "doorway", "scripted"],
		"timeout": 30.0,
	}


func configure(s: TestSetup) -> void:
	s.layout([
		{ "key": "west", "type": "living_room", "rect": WEST },
		{ "key": "east", "type": "kitchen", "rect": EAST },
	], [{ "pos": DOOR, "width": 70.0 }])
	s.von_script([{ "pick": "search" }, { "pick": "room_east" }, { "pick": "room_west" }])
	s.actor(&"a", &"defender", A_START, { "aim_point": DOOR, "facing": Vector2.RIGHT })
	s.actor(&"b", &"defender", B_START, { "aim_point": DOOR, "facing": Vector2.LEFT })


func run(t: TestContext) -> void:
	var a := t.actor(&"a")
	var b := t.actor(&"b")
	var brain_a := t.controller(&"a", &"current_act")
	var brain_b := t.controller(&"b", &"current_act")
	var a_home := func(): return EAST.grow(-30).has_point(a.global_position)
	var b_home := func(): return WEST.grow(-30).has_point(b.global_position)
	var st := { "met": false }
	var seen: Dictionary = await Bump.watch(t, [&"a", &"b"], WATCH_S, func():
		if not st["met"] and a.global_position.distance_to(DOOR) < MEET and b.global_position.distance_to(DOOR) < MEET \
				and a.global_position.x < DOOR.x and b.global_position.x > DOOR.x:
			st["met"] = true
		return a_home.call() and b_home.call())
	if not t.require(String(brain_a.current_act()).contains("room_east") and String(brain_b.current_act()).contains("room_west"),
			"premise: a was sent east and b west (%s / %s)" % [brain_a.current_act(), brain_b.current_act()]):
		return
	if not t.require(st["met"], "premise: they came at each other at the doorway together"):
		return
	var bumps: Array = seen["bumps"]
	t.check(bumps.is_empty(), "neither walks into the other (%s)" % Bump.describe(bumps))
	t.check(a_home.call(), "a gets to the east room (at %s, %s)" % [a.global_position.round(), brain_a.current_act()])
	t.check(b_home.call(), "b gets to the west room (at %s, %s)" % [b.global_position.round(), brain_b.current_act()])

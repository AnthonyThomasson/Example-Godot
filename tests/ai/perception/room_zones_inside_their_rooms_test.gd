extends GameTest

## Issue #49: a room's tactical zone was drawn outside the generated house instead of in its room, on some houses right
## after a match starts. The room options the snapshot offers (go to a room, search it, explore it) point at the room's
## centre snapped onto the navmesh, and the room zones are what the tactics overlay draws. Desired: every room point an
## NPC weighs lies inside the room it is named for.
##
## The match is built here the way `main.gd` builds one (generate the house, bake its navmesh, drop the NPCs in, no wait
## in between) in a world whose shared navigation map is already live with another navmesh, as the map is when a match
## starts after the menu or a previous match. A test world waits for its own navmesh to be in the map before an actor
## spawns, so it never sees this; the match does not.

const MatchSpawner := preload("res://scenes/match_spawner.gd")
const SEED := 18
## Far from the arena the test world is built on, so a point snapped onto the wrong navmesh is plainly outside the house.
const FRONT_ENTRANCE := Vector2(4000, 3000)
## Categories of `debug_zones()` that stand for a room (the `waypoint` ones — post, entrance — are not rooms).
const ROOM_CATEGORIES := [&"room", &"search"]


func describe() -> Dictionary:
	return {
		"name": "Room zones lie inside their rooms",
		"description": "A match is built over a live navigation map as main.gd builds one: every room point the defender and the invader weigh on their first decisions is inside a room of the house, and the one named for a room is in a room of that kind.",
		"tags": ["ai", "perception", "zones", "navigation", "scripted"],
		"timeout": 20.0,
	}


func configure(s: TestSetup) -> void:
	s.von_script([{ "pick": "search" }])
	s.switch(&"ai.hostile_on_trespass", false)   # nobody to fight: the NPCs just weigh rooms


func run(t: TestContext) -> void:
	var house := WorldGen.generate(SEED, "", FRONT_ENTRANCE, t.world)
	var rooms := WorldGen.get_rooms(house)
	var spawner = MatchSpawner.new()
	spawner.world = t.world
	spawner.openings = WorldGen.get_openings(house)
	NavBuilder.build(house, rooms, t.world)
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED
	spawner.spawn_defender(rooms, rng, 0)
	spawner.spawn_invader(rooms, rng, 0, 1, FRONT_ENTRANCE)

	await t.seconds(2.0)
	var misplaced: Array = []
	var seen := 0
	for npc in spawner.combatants:
		var brain: Node = TestContext.controller_of(npc)
		for zone: Dictionary in brain.debug_zones():
			if not ROOM_CATEGORIES.has(zone["category"]):
				continue
			seen += 1
			var why := _problem(rooms, zone)
			if why != "":
				misplaced.append("%s: %s (%s) at %s %s" % [npc.name, zone["label"], zone["category"], zone["point"], why])
	t.require(seen > 0, "the NPCs weighed room points")
	t.check(misplaced.is_empty(), "every room point lies in its room: %s" % [misplaced])


## What is wrong with `zone`'s point ("" = nothing): outside every room, or in a room of another kind than the zone names.
## Explore zones name a direction only ("unexplored north"), so only the first test applies to them.
func _problem(rooms: Array, zone: Dictionary) -> String:
	var p: Vector2 = zone["point"]
	var room := {}
	for r in rooms:
		if (r["rect"] as Rect2).has_point(p):
			room = r
			break
	if room.is_empty():
		return "is outside every room of the house"
	var label := str(zone["label"])
	if label.begins_with("the ") and label != "the front entrance":
		var kind := str(room["type"]).replace("_", " ")
		if label != "the %s" % kind:
			return "is in the %s, not %s" % [kind, label]
	return ""

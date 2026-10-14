extends GameTest

## Issue #53, one mechanism: an NPC goes round a body at rest that stands on its walk even when the way round is a real
## detour. Two tall rooms share two doorways, a near one and a far one. A teammate stands still in the near doorway, in
## the walker's view. The walker (a defender sent to search the far room, scripted Von) takes the far doorway: it never
## walks into the teammate and never moves it. The way round is a real detour, more than 1.5 x the plain walk + 100 px
## (a walk round a body is not capped by its length); the test requires that premise from the walk's real destination
## before it judges, and that the walker SAW the teammate and the steering
## map had it carved out while it was still short of the near doorway (so a pass cannot come from no body being there).
##
## Switches and props: the teammate is a puppet that stands still (the body at rest the scenario is about) and cannot die;
## nothing else is changed. Defenders, so the walk is a plain move and not an invader's tactical entry.

const Bump := preload("res://tests/_ai/bump_probe.gd")

const WEST := Rect2(0, 0, 400, 1000)
const EAST := Rect2(400, 0, 400, 1000)
const NEAR_DOOR := Vector2(400, 150)
const FAR_DOOR := Vector2(400, 940)
const START := Vector2(100, 150)
## What makes the way round a real detour: longer than `DETOUR_RATIO` x the plain walk + `DETOUR_SLACK` px.
const DETOUR_RATIO := 1.5
const DETOUR_SLACK := 100.0


func describe() -> Dictionary:
	return {
		"name": "An NPC detours round a body at rest, even a long way",
		"description": "A teammate stands in the near doorway; the walker goes round by the far doorway, without walking into or moving it.",
		"tags": ["ai", "navigation", "character", "scripted"],
		"timeout": 45.0,
	}


func configure(s: TestSetup) -> void:
	s.layout([
		{ "key": "west", "type": "living_room", "rect": WEST },
		{ "key": "east", "type": "kitchen", "rect": EAST },
	], [{ "pos": NEAR_DOOR, "width": 70.0 }, { "pos": FAR_DOOR, "width": 70.0 }])
	s.von_script([{ "pick": "search" }, { "pick": "room_east" }])
	s.actor(&"walker", &"defender", START)
	s.actor(&"mate", &"puppet", NEAR_DOOR, { "faction": &"household", "max_health": 1.0e6 })


func run(t: TestContext) -> void:
	var walker := t.actor(&"walker")
	var mate := t.actor(&"mate")
	var brain := t.controller(&"walker", &"current_act")
	var arrived := func(): return EAST.grow(-30).has_point(walker.global_position)
	var map := t.world.get_world_2d().navigation_map
	var deepest := [0.0]   # the farthest south the walker went on the west side (an Array: a lambda captures a float by value)
	var carved := [false]  # the walker saw the teammate while the steering map had it carved out, short of the near doorway
	var seen: Dictionary = await Bump.watch(t, [&"walker", &"mate"], 35.0, func():
		if walker.global_position.x < NEAR_DOOR.x + 40.0:
			deepest[0] = maxf(deepest[0], walker.global_position.y)
		var sees: bool = brain.known_contacts_for_display().any(func(c): return c["node"] == mate and c["visible"])
		if not carved[0] and sees and walker.global_position.x < NEAR_DOOR.x - 30.0:
			var through := NavBuilder.route(NavBuilder.steering_map(map), walker.global_position, EAST.get_center())
			carved[0] = through[through.size() - 1].distance_to(EAST.get_center()) > 24.0 \
					or NavBuilder.path_length(through) > NavBuilder.path_length(NavBuilder.route(map, walker.global_position, EAST.get_center())) + 1.0
		return arrived.call())
	var dest = brain.debug_state().get("params", {}).get("point", null)
	if not t.require(String(brain.current_act()).contains("room_east"), "the walker was sent to the east room (%s)" % brain.current_act()):
		return
	if not t.require(carved[0], "premise: the walker saw the teammate in the doorway, carved out of the steering map, before it reached the doorway"):
		return
	var target: Vector2 = Vector2(dest[0], dest[1]) if dest is Array else EAST.get_center()
	var plain := NavBuilder.path_length(NavBuilder.route(map, START, target))
	var round_by_far := START.distance_to(FAR_DOOR) + FAR_DOOR.distance_to(target)
	if not t.require(round_by_far > plain * DETOUR_RATIO + DETOUR_SLACK, "premise: the way round (%.0f px) costs more than %.1f x the plain walk (%.0f px) + %.0f px" % [round_by_far, DETOUR_RATIO, plain, DETOUR_SLACK]):
		return
	var bumps: Array = seen["bumps"]
	t.trace("mate_moved", mate.global_position.distance_to(NEAR_DOOR))
	t.check(arrived.call(), "the walker reaches the east room (at %s, %s)" % [walker.global_position.round(), brain.current_act()])
	t.check(bumps.is_empty(), "it never walks into the teammate in the doorway (%s)" % Bump.describe(bumps))
	t.check(mate.global_position.distance_to(NEAR_DOOR) < 3.0, "the teammate is not moved (%.1f px off its spot)" % mate.global_position.distance_to(NEAR_DOOR))
	t.check(deepest[0] > FAR_DOOR.y - 100.0, "it goes round by the far doorway (deepest on the west side y=%.0f)" % deepest[0])

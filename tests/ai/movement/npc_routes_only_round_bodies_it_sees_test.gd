extends GameTest

## Issue #53, one mechanism: an NPC's walk accounts for the bodies it SEES, not for every body in the world. A room
## opens by two doorways onto a narrow corridor; the walker (a defender sent to search the corridor, scripted Von) is
## nearer the north doorway, and a teammate stands still in the corridor between that doorway and the walker's
## destination, round the jamb where the walker cannot see it from where it starts. Not knowing of the teammate, the walker
## heads for the north doorway, the way it knows to be clear; only once it sees the teammate does it go round (the south
## doorway) or wait. The steering map carves every character at rest, seen or not (`NavBuilder.character_holes`), so a
## walker that went by it alone would turn for the south doorway from its first step. The test requires the premises: the
## teammate seals the corridor and is out of the walker's sight at the start, and the way round is a short detour (so a
## walker turning early would be knowing too much, not choosing a cheaper way).
##
## Switches and props: the teammate is a puppet that stands still (the body at rest the scenario is about) and cannot die;
## nothing else is changed. Defenders, so the walk is a plain move and not an invader's tactical entry.

const Bump := preload("res://tests/_ai/bump_probe.gd")

const WEST := Rect2(0, 0, 400, 600)
const CORRIDOR := Rect2(400, 0, 100, 600)
const NORTH_DOOR := Vector2(400, 100)
const SOUTH_DOOR := Vector2(400, 500)
const START := Vector2(100, 100)
const MATE := Vector2(450, 200)
## A short detour: no longer than `DETOUR_RATIO` x the plain walk + `DETOUR_SLACK` px.
const DETOUR_RATIO := 1.5
const DETOUR_SLACK := 100.0
## Near the north doorway (px): the walker got there before it turned for the other one.
const AT_DOOR := 80.0


func describe() -> Dictionary:
	return {
		"name": "An NPC routes only round the bodies it sees",
		"description": "A teammate stands round a corner in the corridor ahead, out of sight; the walker heads for the near doorway it knows to be clear, not straight for the far one.",
		"tags": ["ai", "navigation", "character", "vision", "scripted"],
		"timeout": 40.0,
	}


func configure(s: TestSetup) -> void:
	s.layout([
		{ "key": "west", "type": "living_room", "rect": WEST },
		{ "key": "corridor", "type": "hallway", "rect": CORRIDOR },
	], [{ "pos": NORTH_DOOR, "width": 70.0 }, { "pos": SOUTH_DOOR, "width": 70.0 }])
	s.von_script([{ "pick": "search" }, { "pick": "room_corridor" }])
	s.actor(&"walker", &"defender", START)
	s.actor(&"mate", &"puppet", MATE, { "faction": &"household", "max_health": 1.0e6 })


func run(t: TestContext) -> void:
	var walker := t.actor(&"walker")
	var mate := t.actor(&"mate")
	var brain := t.controller(&"walker", &"current_act")
	var map := t.world.get_world_2d().navigation_map
	var space := t.world.get_world_2d().direct_space_state
	var ray := PhysicsRayQueryParameters2D.create(START, MATE, PhysicsLayers.SOLID, [walker.get_rid(), mate.get_rid()])
	if not t.require(not space.intersect_ray(ray).is_empty(), "premise: a wall stands between the walker's start and the teammate"):
		return
	# Lambdas capture plain values by copy, so the state the watch updates lives in one Dictionary.
	var st := { "near_north": INF, "south_turn": INF, "dest": Vector2.INF, "sealed": false }
	var seen: Dictionary = await Bump.watch(t, [&"walker", &"mate"], 25.0, func():
		var p: Vector2 = walker.global_position
		if st["dest"] == Vector2.INF:
			var point = brain.debug_state().get("params", {}).get("point", null)
			if point is Array and point.size() == 2 and String(brain.current_act()).contains("room_corridor"):
				st["dest"] = Vector2(point[0], point[1])
		if st["dest"] != Vector2.INF and not st["sealed"]:
			var through := NavBuilder.route(NavBuilder.steering_map(map), p, st["dest"])
			st["sealed"] = NavBuilder.path_length(through) > NavBuilder.path_length(NavBuilder.route(map, p, st["dest"])) + 1.0
			st["sealed_at"] = t.time
		if st["near_north"] == INF and p.distance_to(NORTH_DOOR) < AT_DOOR:
			st["near_north"] = t.time
		if st["south_turn"] == INF and p.x < NORTH_DOOR.x and p.y > NORTH_DOOR.y + AT_DOOR:
			st["south_turn"] = t.time
		return CORRIDOR.has_point(p) and p.y > MATE.y + 40.0)
	if not t.require(st["dest"] != Vector2.INF, "the walker was sent to search the corridor (%s)" % brain.current_act()):
		return
	var dest: Vector2 = st["dest"]
	if not t.require(dest.y > MATE.y + 40.0, "premise: the walk's destination (%s) lies past the teammate" % dest.round()):
		return
	if not t.require(st["sealed"], "premise: the steering map had the teammate carved out across the corridor during the walk (dest %s)" % st["dest"].round()):
		return
	GameLog.say("sight test: dest %s, teammate carved by %.2f s, near north %s, turned south %s" % [dest.round(), st["sealed_at"], st["near_north"], st["south_turn"]])
	var plain := NavBuilder.path_length(NavBuilder.route(map, START, dest))
	var round_by_south := START.distance_to(SOUTH_DOOR) + SOUTH_DOOR.distance_to(dest)
	if not t.require(round_by_south <= plain * DETOUR_RATIO + DETOUR_SLACK, "premise: the way round (%.0f px) is a short detour (%.1f x %.0f + %.0f px)" % [round_by_south, DETOUR_RATIO, plain, DETOUR_SLACK]):
		return
	t.check(st["near_north"] < st["south_turn"], "the walker heads for the north doorway it knows to be clear before turning for the south one (near the north doorway at %s, turned south at %s)" % [
			"never" if st["near_north"] == INF else "%.1f s" % st["near_north"], "never" if st["south_turn"] == INF else "%.1f s" % st["south_turn"]])
	t.check(seen["bumps"].is_empty(), "it never walks into the teammate (%s)" % Bump.describe(seen["bumps"]))

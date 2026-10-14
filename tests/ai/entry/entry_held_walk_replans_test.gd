extends GameTest

## Issue #53, one mechanism: an entry's walk that a teammate's body seals re-plans; it is never held for ever. A row of
## counters splits the room the invader starts in, with one gap a body wide by the south wall, and a teammate stands still
## in the gap. The invader is ordered to ENTER the doorway on the far side of the row (scripted Von): its walk to its stack
## slot has no way but the gap. It stops short of the teammate, waits a moment, and re-plans within `REPLAN_S` s of
## stopping: the entry is given up (`abort` on the radio) and the NPC re-decides BECAUSE the way is blocked
## (`debug_state()`: `decisions` grows with `decision_reason` "way blocked"). It never walks into the teammate or moves it,
## and it is never held (`loco.way` "held") for `REPLAN_S` s without such a re-plan. The test requires that the steering
## map really had the gap sealed when the walker came near, before it judges.
##
## Switches and props: the teammate is an invader puppet that stands still and cannot die (the body at rest the scenario is
## about); scripted Von and the shared entry switches; nothing else changed.

const Bump := preload("res://tests/_ai/bump_probe.gd")
const Entry := preload("res://tests/_ai/entry_probe.gd")

const WEST := Rect2(0, 0, 600, 400)
const EAST := Rect2(600, 0, 300, 400)
const DOOR := { "id": "door_600_200", "pos": Vector2(600, 200), "width": 80.0, "out": Vector2.LEFT, "room": EAST, "room_key": "east" }
## The row of counters (each 50 x 100 turned upright) across the west room from the north wall, and the gap left by the
## south wall, where the teammate stands.
const ROW_X := 300.0
const ROW := [Vector2(ROW_X, 50), Vector2(ROW_X, 150), Vector2(ROW_X, 250)]
const GAP := Vector2(ROW_X, 352)
const START := Vector2(100, 200)
## How near the teammate (px, centre to centre) a stop counts as "short of it".
const STOP_NEAR := 140.0
## Seconds from a stop by which the walk has re-planned.
const REPLAN_S := 5.0
const WATCH_S := 16.0


func describe() -> Dictionary:
	return {
		"name": "An entry walk sealed by a teammate re-plans",
		"description": "A teammate stands in the only gap on the way to the stack; the invader stops short of it, never touches it, and re-plans within 5 s (gives the entry up, re-decides because the way is blocked).",
		"tags": ["ai", "entry", "navigation", "character", "scripted"],
		"timeout": 40.0,
	}


func configure(s: TestSetup) -> void:
	s.layout([
		{ "key": "west", "type": "living_room", "rect": WEST },
		{ "key": "east", "type": "kitchen", "rect": EAST },
	], [{ "pos": DOOR["pos"], "width": DOOR["width"] }])
	for i in ROW.size():
		s.object(StringName("counter_%d" % i), "kitchen_counter", ROW[i], { "rotated": true })
	Entry.rules(s, DOOR)
	Entry.npc(s, &"walker", START)
	s.actor(&"mate", &"puppet", GAP, { "faction": &"invader", "max_health": 1.0e6 })


func run(t: TestContext) -> void:
	var walker := t.actor(&"walker")
	var mate := t.actor(&"mate")
	var brain := Entry.brain(t, &"walker")
	var map := t.world.get_world_2d().navigation_map
	# Lambdas capture plain values by copy, so the state the watch updates lives in one Dictionary.
	var st := { "sealed": false, "held_since": INF, "longest": 0.0, "longest_at": Vector2.INF, "walks": 0, "replans": 0,
			"aborts": 0, "entered": false }
	var seen: Dictionary = await Bump.watch(t, [&"walker", &"mate"], WATCH_S, func():
		var p: Vector2 = walker.global_position
		var state: Dictionary = brain.debug_state()
		var loco: Dictionary = state.get("loco", {})
		if String(brain.current_act()).contains(DOOR["id"]):
			st["entered"] = true
		if not st["sealed"] and p.distance_to(mate.global_position) < STOP_NEAR:
			var through := NavBuilder.route(NavBuilder.steering_map(map), p, DOOR["pos"] + Vector2(-40, 0))
			st["sealed"] = through[through.size() - 1].x < ROW_X
		var aborts := Entry.calls(t, "abort", &"walker").size()
		var blocked_walk: bool = int(state.get("decisions", 0)) > int(st["walks"]) and String(state.get("decision_reason", "")) == "way blocked"
		st["walks"] = int(state.get("decisions", 0))
		if aborts > int(st["aborts"]) or blocked_walk:
			st["replans"] = int(st["replans"]) + 1
			st["held_since"] = INF if String(loco.get("way", "")) != "held" else t.time
		st["aborts"] = aborts
		if String(loco.get("way", "")) == "held" and p.distance_to(mate.global_position) < STOP_NEAR:
			if st["held_since"] == INF:
				st["held_since"] = t.time
			elif t.time - float(st["held_since"]) > float(st["longest"]):
				st["longest"] = t.time - float(st["held_since"])
				st["longest_at"] = p
		else:
			st["held_since"] = INF
		t.trace("walker_to_mate", p.distance_to(mate.global_position))
		return false)
	if not t.require(st["entered"], "the walker was sent to ENTER the far doorway (%s)" % brain.current_act()):
		return
	if not t.require(st["sealed"], "premise: the steering map had the gap sealed by the teammate when the walker came near"):
		return
	var bumps: Array = seen["bumps"]
	t.check(bumps.is_empty(), "it never walks into the teammate in the gap (%s)" % Bump.describe(bumps))
	t.check(mate.global_position.distance_to(GAP) < 3.0, "the teammate is not moved (%.1f px off its spot)" % mate.global_position.distance_to(GAP))
	t.check(int(st["replans"]) > 0, "it re-planned because the way is blocked (entry given up or a 'way blocked' decision; act %s)" % brain.current_act())
	t.check(float(st["longest"]) < REPLAN_S, "it is never held short of the teammate %.0f s without re-planning (held %.1f s at %s)" % [REPLAN_S,
			float(st["longest"]), st["longest_at"]])

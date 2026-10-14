extends GameTest

## Issue #53, one mechanism: a teammate standing in the only doorway seals the way, and the walker neither shoves it nor
## presses against it. Two rooms share one doorway; a teammate stands still in it, in the walker's view. The walker (a
## defender sent to search the far room, scripted Von) stops short of the teammate, waits a moment, and then re-plans: it
## takes up another walk (its nav target moves off the sealed one) or starts a new decision BECAUSE the way is blocked
## (`debug_state()`: `decisions` grows with `decision_reason` "way blocked", not the decide cadence; asked of Von or not,
## since a level with one option is taken without asking). For the whole watch it never walks into the teammate and never
## moves it. The test requires that the steering map really had the doorway sealed when the walker came
## near, before it judges.
##
## "A moment" is not a number in the spec; the test gives the walker `WAIT_MIN` s still (a stop, not a stumble) and
## `REPLAN_S` s from the stop to re-plan, which a person waiting on a teammate in a doorway would not exceed.
##
## Switches and props: the teammate is a puppet that stands still (the body at rest the scenario is about) and cannot die;
## nothing else is changed. Defenders, so the walk is a plain move and not an invader's tactical entry.

const Bump := preload("res://tests/_ai/bump_probe.gd")

const WEST := Rect2(0, 0, 400, 500)
const EAST := Rect2(400, 0, 400, 500)
const DOOR := Vector2(400, 250)
const START := Vector2(100, 250)
## How near the doorway (px, centre to centre) a stop counts as "short of the teammate".
const STOP_NEAR := 140.0
## How slow (px/s) counts as stopped, and for how long it must hold to be a wait.
const STILL_SPEED := 10.0
const WAIT_MIN := 0.5
## Seconds from the stop by which the walker has re-planned.
const REPLAN_S := 5.0
const WATCH_S := 14.0


func describe() -> Dictionary:
	return {
		"name": "An NPC waits at a doorway a teammate holds, then re-plans",
		"description": "A teammate stands in the only doorway; the walker stops short of it without touching it, waits, re-plans, and never shoves it.",
		"tags": ["ai", "navigation", "character", "doorway", "scripted"],
		"timeout": 30.0,
	}


func configure(s: TestSetup) -> void:
	s.layout([
		{ "key": "west", "type": "living_room", "rect": WEST },
		{ "key": "east", "type": "kitchen", "rect": EAST },
	], [{ "pos": DOOR, "width": 70.0 }])
	s.von_script([{ "pick": "search" }, { "pick": "room_east" }])
	s.actor(&"walker", &"defender", START)
	s.actor(&"mate", &"puppet", DOOR, { "faction": &"household", "max_health": 1.0e6 })


func run(t: TestContext) -> void:
	var walker := t.actor(&"walker")
	var mate := t.actor(&"mate")
	var brain := t.controller(&"walker", &"current_act")
	var map := t.world.get_world_2d().navigation_map
	# Lambdas capture plain values by copy, so the state the watch updates lives in one Dictionary.
	var st := { "sealed": false, "still": 0.0, "stopped_at": INF, "target": Vector2.INF, "walks": 0, "replanned_at": INF,
			"last": walker.global_position }
	var seen: Dictionary = await Bump.watch(t, [&"walker", &"mate"], WATCH_S, func():
		var p: Vector2 = walker.global_position
		var speed: float = p.distance_to(st["last"]) * Engine.physics_ticks_per_second
		st["last"] = p
		if not st["sealed"] and p.distance_to(mate.global_position) < STOP_NEAR:
			var through := NavBuilder.route(NavBuilder.steering_map(map), p, EAST.get_center())
			st["sealed"] = through[through.size() - 1].x < DOOR.x
		var state: Dictionary = brain.debug_state()
		var loco: Dictionary = state.get("loco", {})
		var target = loco.get("target", [])
		if st["stopped_at"] == INF:
			var gap: float = p.distance_to(mate.global_position)
			if speed < STILL_SPEED and p.x < DOOR.x - 20.0 and gap < STOP_NEAR and gap > Bump.RADIUS * 2.0 + Bump.CONTACT_TOL:
				st["still"] = float(st["still"]) + 1.0 / Engine.physics_ticks_per_second
				if st["still"] >= WAIT_MIN:
					st["stopped_at"] = t.time
					st["target"] = Vector2(target[0], target[1]) if target is Array and target.size() == 2 else Vector2.INF
					st["walks"] = int(state.get("decisions", 0))
			else:
				st["still"] = 0.0
		elif st["replanned_at"] == INF:
			var now_target: Vector2 = Vector2(target[0], target[1]) if target is Array and target.size() == 2 else Vector2.INF
			var moved_off: bool = st["target"] != Vector2.INF and now_target != Vector2.INF and now_target.distance_to(st["target"]) > 40.0
			var blocked_walk: bool = int(state.get("decisions", 0)) > int(st["walks"]) and String(state.get("decision_reason", "")) == "way blocked"
			if moved_off or blocked_walk:
				st["replanned_at"] = t.time
		return false)
	if not t.require(String(brain.current_act()).contains("room_east") or t.von_requests().any(func(r): return String(r["pick"]) == "room_east"), "the walker was sent to the east room (%s)" % brain.current_act()):
		return
	if not t.require(st["sealed"], "premise: the steering map had the doorway sealed by the teammate when the walker came near"):
		return
	var bumps: Array = seen["bumps"]
	t.trace("mate_moved", mate.global_position.distance_to(DOOR))
	t.check(bumps.is_empty(), "it never walks into the teammate in the doorway (%s)" % Bump.describe(bumps))
	t.check(mate.global_position.distance_to(DOOR) < 3.0, "the teammate is not moved (%.1f px off its spot)" % mate.global_position.distance_to(DOOR))
	t.check(st["stopped_at"] < INF, "it stops short of the teammate and waits (still %.1f s or more within %.0f px of it on its own side, not touching; ended at %s, %s)" % [WAIT_MIN, STOP_NEAR, walker.global_position.round(), brain.current_act()])
	if st["stopped_at"] < INF:
		t.check(float(st["replanned_at"]) - float(st["stopped_at"]) <= REPLAN_S, "it re-plans within %.0f s of stopping, because the way is blocked (stopped at %.1f s, re-planned at %s)" % [REPLAN_S, st["stopped_at"], "never" if st["replanned_at"] == INF else "%.1f s" % st["replanned_at"]])

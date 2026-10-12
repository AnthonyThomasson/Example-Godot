extends RefCounted

## AI BEHAVIOUR sub-domain — TACTICAL ENTRY. How an NPC gets through a doorway into a room the way police and
## soldiers do (`docs/tactical-entry.md`, E1 to E8), as one member of a team or alone. Von only chose the doorway
## (the ENTER tactic); the choreography is this phase machine, so it runs with the server down:
##
##   approach — to its stack slot beside the door, stepping off the door's axis while still well out and
##              arriving along the wall (E1)
##   stack    — in the slot, facing the door; radios `ready` (E2)
##   pie      — the point (or a lone entrant) sweeps the arc beside the door in angle steps, looking through it,
##              and notes the share of the room seen and the corners still hidden (E3); alone, both sides (E7)
##   cross    — committed: through the threshold without stopping, to its corner (E4, E5); radios `going_in`, then
##              `in` once it is in the room and off the door's axis
##   corner   — holds the corner looking across the room, then clears the rest by sight (`search_coverage.gd`)
##   rear     — once the room is clear, the last of the team holds the doorway facing back out (E8)
##
## Its role comes from its slot. Slots, readiness and progress travel on the team radio: the behaviour queues each
## step (`take_calls()`) and the controller radios it; the team is read back through the perception
## (`entry_team`). The point crosses when every member of the stack is ready or `ready_timeout` runs out (E6); a
## follower crosses `follow_gap` after the member ahead of it is through. With nobody else claiming the doorway the
## NPC goes alone; an ally that claims a slot before it commits joins the stack (E7). Owns that state and nothing
## else: `Behavior` calls `begin()` on adopting an ENTER leaf and `step()` every tick until it reports done.

const AgentEntry := preload("res://scenes/ai/perception/agent_entry.gd")

## A member whose latest call is one of these is through the doorway.
const THROUGH := ["in", "clear", "rear"]
## How far (px) out from the wall an entrant crosses in front of a door it must get past.
const CROSS_DEPTH := 140.0
## How far (px) beyond its slot, along the wall, an entrant arrives from.
const APPROACH_LEAD := 60.0
## How far (px) inside the wall plane an entrant counts as through the threshold.
const THROUGH_DEPTH := 26.0
## Seconds between repeats of the latest call, so the claim stays live on the radio (callouts lapse after a while).
const HEARTBEAT := 2.0
## A waypoint (px) counts as reached this close.
const WAYPOINT_REACH := 20.0
## Most seconds the committed crossing may take before it gives up the commitment (a blocked doorway).
const CROSS_CAP := 6.0
## Gaze (rad) within which the look through the door has settled at a pie step.
const GAZE_SETTLED := 0.12

var ready_timeout: float = 6.0     ## Seconds the point waits for the stack, once ready, before going in without it.
var follow_gap: float = 0.3        ## Seconds a follower leaves after the member ahead of it is through.
var pie_dwell: float = 0.35        ## Seconds the point looks through the door from each pie step.
var corner_dwell: float = 0.6      ## Seconds held in the corner looking across the room before clearing it.
var rear_time: float = 10.0        ## Seconds the last of the team holds the doorway facing out once the room is clear.
var approach_time: float = 20.0    ## Safety cap (s) on reaching the slot; past it the claim is given up.
var look_rate: float = 2.5         ## Gaze turn speed (rad/s).

var phase := ""                    ## approach / stack / pie / cross / corner / clear / rear / done ("" = idle).
var opening := ""                  ## The doorway's id (agent_entry.gd `opening_id`).
var into := ""                     ## The key of the room behind it.
var slot := 0                      ## This NPC's stack slot (1 = nearest the door).
var side := 0                      ## The side of the door the stack is on (1 / -1 along its wall).
var solo := true                   ## Nobody else claims the doorway: no barrier, and the pie is sliced from both sides.
var seen_fraction := 0.0           ## Share of the room's sample points seen from outside during the pie.
var pie_sides := 0                 ## How many sides of the door the pie was sliced from.
var corner := Vector2.INF          ## The corner this NPC enters to.

var _loco: Node                    ## The Locomotion child (pathing, rooms).
var _perception: Node              ## The perception sub-domain (doorway geometry, the team on the radio, sight).
var _coverage: RefCounted          ## The room coverage by sight, reused to clear the room once inside.
var _geo := {}                     ## The doorway's geometry (agent_entry.gd `geometry`).
var _calls: Array = []             ## Steps to radio, oldest first: { step, cleared_room? }.
var _last_step := ""               ## The latest step radioed (repeated on the heartbeat).
var _heartbeat := 0.0              ## Seconds until the latest step is radioed again.
var _clock := 0.0                  ## Seconds into the phase.
var _waypoints: Array = []         ## Points still to walk through before the current phase's spot.
var _ready_at := -1.0              ## `_time` this NPC got to its slot (-1 = not yet).
var _team_size := 0                ## How many allies claimed the doorway last tick (a new one restarts the wait).
var _team_grew_at := 0.0           ## `_time` the stack last grew.
var _time := 0.0                   ## Seconds since `begin()`.
var _turn_at := -1.0               ## `_time` the member ahead of this one was first seen through (-1 = not yet).
var _pie_queue: Array = []         ## Pie steps still to look from (points on the arc).
var _pie_side := 0                 ## The side being sliced now.
var _points: Array = []            ## The room's sample points (coverage grid).
var _unseen: Array = []            ## Those not yet seen from outside.
var _corners_seen := {}            ## Index into the geometry's corners -> seen during the pie.
var _look_angle := 0.0             ## Current gaze angle (rad), eased toward what the phase looks at.
var _rear_spot := Vector2.INF      ## Where the rear guard stands, just inside the doorway.
var _dwell := 0.0                  ## Seconds held at the current spot (the corner).
var _covered := false              ## The room has been covered by sight (waiting for the rest of the stack to be in).
var _through := {}                 ## Allies seen through this doorway this entry: instance id -> slot (kept when they move on).


## Capture the locomotion, the perception and the room coverage. Called once by `Behavior.setup()`.
func setup(loco: Node, perception: Node, coverage: RefCounted) -> void:
	_loco = loco
	_perception = perception
	_coverage = coverage


## Start an entry from an ENTER leaf's params (`opening`, `into`, `slot`, `side`). False when the doorway is unknown
## (the leaf is then dropped and the NPC re-decides).
func begin(character, params: Dictionary) -> bool:
	reset()
	opening = str(params.get("opening", ""))
	into = str(params.get("into", ""))
	_geo = _perception.entry_geometry(character, opening, into)
	if _geo.is_empty():
		phase = "done"
		return false
	var team: Array = _perception.entry_team(opening)
	slot = AgentEntry.free_slot(team, character.get_instance_id(), int(params.get("slot", 0)))
	side = AgentEntry.stack_side(_geo, team, character.global_position)
	solo = team.is_empty()
	_team_size = team.size()
	_points = _coverage.sample_room(into)
	_unseen = _points.duplicate()
	_look_angle = character.facing.angle()
	_enter_approach(character)
	_radio("claim")
	return true


## Forget the running entry.
func reset() -> void:
	phase = ""
	opening = ""
	into = ""
	slot = 0
	side = 0
	solo = true
	seen_fraction = 0.0
	pie_sides = 0
	corner = Vector2.INF
	_geo = {}
	_calls = []
	_last_step = ""
	_heartbeat = HEARTBEAT
	_clock = 0.0
	_waypoints = []
	_ready_at = -1.0
	_team_size = 0
	_team_grew_at = 0.0
	_time = 0.0
	_turn_at = -1.0
	_pie_queue = []
	_pie_side = 0
	_points = []
	_unseen = []
	_corners_seen = {}
	_rear_spot = Vector2.INF
	_dwell = 0.0
	_covered = false
	_through = {}


## Give the entry up (the NPC chose something else, e.g. a fight): radio `abort` so the stack stops counting on it.
func abandon() -> void:
	if phase in ["", "done"]:
		return
	_radio("abort")
	phase = "done"


## Whether the entrant is committed to the crossing: nothing may stop it (no re-decision, no reload, no crouch)
## until it is through the threshold and off the door's axis (E4).
func committed() -> bool:
	return phase == "cross"


## Whether the entrant may shoot on the move this tick (crossing, or in the room).
func fires_at_will() -> bool:
	return phase in ["cross", "corner", "clear", "rear"]


## Where the entrant is walking to while it may run (the approach to its slot), else Vector2.INF.
func travel_target() -> Vector2:
	if phase != "approach":
		return Vector2.INF
	return _waypoints[0] if not _waypoints.is_empty() else _stack_point()


## The steps queued for the radio since the last call, oldest first: { step, cleared_room? }.
func take_calls() -> Array:
	var out := _calls
	_calls = []
	return out


## The entry as data, for `debug_entry()` / `debug_state()` and the tests: the doorway, slot, side, role, phase, what
## the pie saw and where it is going.
func debug() -> Dictionary:
	if phase == "":
		return {}
	var hidden: Array = []
	for i in _geo.get("corners", []).size():
		if not _corners_seen.get(i, false):
			hidden.append(_geo["corners"][i]["pos"])
	return {
		"opening": opening, "into": into, "slot": slot, "side": side, "solo": solo, "phase": phase,
		"seen_fraction": seen_fraction, "pie_sides": pie_sides, "hidden_corners": hidden, "corner": corner,
		"stack_point": _stack_point() if not _geo.is_empty() else Vector2.INF, "team": _team_size,
	}


# --- The tick ----------------------------------------------------------------------------------

## One tick of the entry. True once it is over (the room is clear and any rear watch is done, or it was given up),
## when the NPC should re-decide.
func step(character, delta: float) -> bool:
	if phase in ["", "done"]:
		return true
	_time += delta
	_clock += delta
	var team: Array = _perception.entry_team(opening)
	if team.size() > _team_size:
		_team_grew_at = _time  # Someone joined: the point gives the newcomer the full wait.
	_team_size = team.size()
	for m in team:
		if THROUGH.has(m["step"]):
			_through[m["id"]] = m["slot"]
	if phase in ["approach", "stack", "pie"]:
		_keep_slot(character, team)
	_heartbeat -= delta
	if _heartbeat <= 0.0 and _last_step != "":
		_radio(_last_step)  # Keep the claim alive on the radio.
	match phase:
		"approach":
			_tick_approach(character)
		"stack":
			_tick_stack(character, team, delta)
		"pie":
			_tick_pie(character, team, delta)
		"cross":
			_tick_cross(character, delta)
		"corner":
			_tick_corner(character, team, delta)
		"clear":
			_tick_clear(character, team, delta)
		"rear":
			_tick_rear(character, delta)
	return phase == "done"


## Keep this NPC's slot and side in step with the radio: a slot an ally with a lower instance id also claimed is
## given up for the next free one, and the side follows the point's (the side is never re-read from where this NPC
## stands: a lone entrant crosses in front of the door to slice its other side). A change is radioed as a new claim.
func _keep_slot(character, team: Array) -> void:
	var was := slot
	slot = AgentEntry.free_slot(team, character.get_instance_id(), slot)
	var new_side := side
	for m in team:
		if slot != 1 and m["slot"] == 1 and m["side"] != 0:
			new_side = m["side"]
	if slot != was or new_side != side:
		side = new_side
		if phase != "approach":
			_enter_approach(character)  # Walk to the new slot.
		_radio("claim")


# --- Approach (E1) and stack (E2, E6) ----------------------------------------------------------

## Head for the slot: if on the wrong side of the door, first out from the wall and across in front of it, far
## out; then (when not already beyond the slot along the wall) sideways at that depth to a point past the slot,
## then in to the wall and along it to the slot. So the last leg runs along the wall, never down the door's axis.
func _enter_approach(character) -> void:
	_set_phase(character, "approach")
	var door: Vector2 = _geo["pos"]
	var out: Vector2 = _geo["out"]
	var along: Vector2 = _geo["along"]
	var target := _stack_point()
	var target_out := (target - door).dot(out)
	var target_lat := absf((target - door).dot(along))
	var here: Vector2 = character.global_position
	var depth := (here - door).dot(out)
	var lat := (here - door).dot(along)
	_waypoints = []
	if signf(lat) != float(side) and absf(lat) >= 1.0:
		depth = maxf(depth, CROSS_DEPTH)
		_waypoints.append(door + out * depth + along * lat)  # Out from the wall before crossing the door's front.
	if signf(lat) != float(side) or absf(lat) < target_lat + APPROACH_LEAD * 0.5:
		_waypoints.append(door + out * maxf(depth, target_out) + along * side * (target_lat + APPROACH_LEAD))
	_waypoints.append(door + out * target_out + along * side * (target_lat + APPROACH_LEAD))
	_waypoints = _waypoints.map(func(p): return _loco.reachable(p))


## Walk the approach waypoints, then into the slot; give up the claim when it takes too long.
func _tick_approach(character) -> void:
	if _clock > approach_time:
		_radio("abort")
		phase = "done"
		return
	_aim_travel(character)
	while not _waypoints.is_empty() and character.global_position.distance_to(_waypoints[0]) <= WAYPOINT_REACH:
		_waypoints.pop_front()
	if not _waypoints.is_empty():
		_loco.move_to(character, _waypoints[0])
		return
	var spot := _stack_point()
	if not _at(character, spot):
		_loco.move_to(character, spot)
		return
	character.move_input = Vector2.ZERO
	_set_phase(character, "stack")
	if _ready_at < 0.0:
		_ready_at = _time
	_radio("ready")


## In the slot, facing the door: the point slices the pie; a follower waits its turn, then crosses.
func _tick_stack(character, team: Array, delta: float) -> void:
	var spot := _stack_point()
	if character.global_position.distance_to(spot) > WAYPOINT_REACH:
		_loco.move_to(character, spot)  # Shoved out of the slot: step back in.
	else:
		character.move_input = Vector2.ZERO
	_look_toward(character, _geo["pos"], delta)
	var ahead := _ahead(team)
	if ahead.is_empty():
		_start_pie(character, team)
		return
	if THROUGH.has(ahead[-1]["step"]):
		if _turn_at < 0.0:
			_turn_at = _time
		if _time - _turn_at >= follow_gap:
			_start_cross(character, team)


## The members of the stack still ahead of this one (lower slots), lowest first. One that never reached its slot is
## dropped once this NPC has waited `ready_timeout` for it.
func _ahead(team: Array) -> Array:
	var waited := _ready_at >= 0.0 and _time - _ready_at >= ready_timeout
	return team.filter(func(m): return m["slot"] < slot and not (waited and m["step"] == "claim"))


# --- The pie (E3, E7) ---------------------------------------------------------------------------

## Become the point: slice the pie from this side (and, alone, from the other side after).
func _start_pie(character, team: Array) -> void:
	solo = team.is_empty()
	_set_phase(character, "pie")
	_pie_side = side
	_pie_queue = (_geo["pie"][side] as Array).duplicate()
	pie_sides = 1


## Walk the pie arc a step at a time; at each step look through the door until the gaze settles plus `pie_dwell`,
## noting what is seen. When the arc is done: alone, slice the other side too; else wait for the stack, then go in.
func _tick_pie(character, team: Array, delta: float) -> void:
	_note_seen(character)
	if not team.is_empty():
		solo = false  # An ally claimed a slot: no second side, it joins the stack.
	if _pie_queue.is_empty():
		character.move_input = Vector2.ZERO
		_look_toward(character, _geo["pos"] - (_geo["out"] as Vector2) * 300.0, delta)
		if solo and pie_sides < 2:
			_pie_other_side()
			return
		if _stack_ready(team):
			_start_cross(character, team)
		return
	var spot: Vector2 = _pie_queue[0]
	if not _at(character, spot):
		_loco.move_to(character, spot)
		_look_toward(character, _through_door(character.global_position), delta)
		_clock = 0.0
		return
	character.move_input = Vector2.ZERO
	var settled := _look_toward(character, _through_door(spot), delta)
	if settled and _clock >= pie_dwell:
		_pie_queue.pop_front()
		_clock = 0.0
	elif not settled:
		_clock = 0.0


## Alone: cross in front of the door (as far out as the arc's end) and slice it from the other side, from the axis
## outward.
func _pie_other_side() -> void:
	_pie_side = -side
	pie_sides = 2
	_pie_queue = (_geo["pie"][-side] as Array).duplicate()
	_pie_queue.reverse()


## Whether the point may go in: every other member of the stack is in its slot, or the wait (from when the point was
## ready, or the stack last grew) has run out.
func _stack_ready(team: Array) -> bool:
	if team.all(func(m): return m["step"] != "claim"):
		return true
	return _time - maxf(_ready_at, _team_grew_at) >= ready_timeout


## Drop every room point and corner now in sight from the unseen sets, and update the share seen.
func _note_seen(character) -> void:
	for p in _perception.visible_points(character, _unseen):
		_unseen.erase(p)
	if not _points.is_empty():
		seen_fraction = 1.0 - float(_unseen.size()) / float(_points.size())
	var corners: Array = _geo["corners"]
	var unseen_corners: Array = []
	for i in corners.size():
		if not _corners_seen.get(i, false):
			unseen_corners.append(corners[i]["pos"])
	for p in _perception.visible_points(character, unseen_corners):
		for i in corners.size():
			if corners[i]["pos"] == p:
				_corners_seen[i] = true


## A point through the door, on the line from `from` through the threshold: where to look from a pie step.
func _through_door(from: Vector2) -> Vector2:
	var door: Vector2 = _geo["pos"]
	return door + (door - from).normalized() * 300.0


# --- The crossing (E4, E5) ----------------------------------------------------------------------

## Commit to the crossing: pick the corner for this member's place in the order, radio `going_in`, go.
func _start_cross(character, team: Array) -> void:
	var order := team.filter(func(m): return m["slot"] < slot and THROUGH.has(m["step"])).size()
	corner = _corner_for(order)
	_set_phase(character, "cross")
	_radio("going_in")


## The corner (or spot) the member `order`-th through the door enters to. The point buttonhooks to the corner on
## the door's wall on its own side; alone, it goes to that wall's corner on the side away from where it stands, so it
## crosses the room's front. The second crosses to the hard corner on the other side (on the door's wall, else any
## hard one there, else the near one). Later members take a spot inside, off the axis.
func _corner_for(order: int) -> Vector2:
	var corners: Array = _geo["corners"]
	if order == 0:
		var own := side
		if solo:
			own = -_pie_side if pie_sides > 0 else -side
		return _pick_corner(corners, own, false)
	if order == 1:
		return _pick_corner(corners, -side, true)
	var door: Vector2 = _geo["pos"]
	return _loco.reachable(door - (_geo["out"] as Vector2) * 90.0 + (_geo["along"] as Vector2) * side * (float(_geo["width"]) * 0.5 + 30.0 * (order - 1)))


## The corner on side `on`: on the door's own wall first (a hard one when `hard_first`), else a hard one on that side,
## else any on that side.
func _pick_corner(corners: Array, on: int, hard_first: bool) -> Vector2:
	var best := Vector2.INF
	var best_rank := 99
	for c in corners:
		if c["side"] != on:
			continue
		var rank := 0 if c["near"] else 2
		if hard_first and not c["hard"]:
			rank += 1
		if rank < best_rank:
			best_rank = rank
			best = c["pos"]
	return best


## Through the threshold to the corner without stopping, gaze across the room; `in` once in the room and off the
## door's axis, then on to the corner.
func _tick_cross(character, delta: float) -> void:
	_loco.move_to(character, corner)
	if character.move_input == Vector2.ZERO:
		character.move_input = (corner - character.global_position).normalized()  # Never stand in the funnel.
	_look_toward(character, _across_from(corner), delta, 3.0)
	var rel: Vector2 = character.global_position - (_geo["pos"] as Vector2)
	var through: bool = rel.dot(_geo["out"]) < -THROUGH_DEPTH and absf(rel.dot(_geo["along"])) > float(_geo["width"]) * 0.5
	if through or _clock > CROSS_CAP or character.global_position.distance_to(corner) <= WAYPOINT_REACH:
		_radio("in")
		_set_phase(character, "corner")


## Where to look from a corner: across the room, at the far side opposite it.
func _across_from(p: Vector2) -> Vector2:
	var room: Rect2 = _geo["room"]
	return room.get_center() * 2.0 - p


# --- In the room (E5, E8) -----------------------------------------------------------------------

## Into the corner, then hold it looking across the room for `corner_dwell` (even when the team has already called the
## room clear: its sector is covered either way); then clear the room by sight.
func _tick_corner(character, team: Array, delta: float) -> void:
	_look_toward(character, _across_from(corner), delta, 3.0)
	if not _at(character, corner) and _clock < CROSS_CAP:
		_loco.move_to(character, corner)
		_dwell = 0.0
		return
	character.move_input = Vector2.ZERO
	_dwell += delta
	if _dwell >= corner_dwell and _cleared_by_team(team):
		_finish(character)
	elif _dwell >= corner_dwell:
		_set_phase(character, "clear")
		_coverage.begin(character)


## Cover the room by sight; when done, and the rest of the stack is in too (or has had `ready_timeout` to come), radio
## it clear and move on. An ally that radioed it clear first ends this NPC's search.
func _tick_clear(character, team: Array, delta: float) -> void:
	if _cleared_by_team(team):
		_finish(character)
		return
	if not _covered:
		_covered = _coverage.step(character, delta)
		return
	character.move_input = Vector2.ZERO
	_look_toward(character, _across_from(character.global_position), delta)
	var coming := team.filter(func(m): return not THROUGH.has(m["step"]) and m["step"] != "claim")
	if coming.is_empty() or _clock >= ready_timeout + CROSS_CAP:
		_radio("clear", { "cleared_room": into })
		_finish(character)


## Whether an ally of this entry has radioed the room clear.
func _cleared_by_team(team: Array) -> bool:
	return team.any(func(m): return m["step"] == "clear")


## The room is clear: the last of the team in holds the doorway as rear security; everyone else is done.
func _finish(character) -> void:
	var last := not _through.is_empty() and _through.values().all(func(other_slot): return other_slot < slot)
	if not last:
		phase = "done"
		return
	var door: Vector2 = _geo["pos"]
	_rear_spot = _loco.reachable(door - (_geo["out"] as Vector2) * 30.0 + (_geo["along"] as Vector2) * side * (float(_geo["width"]) * 0.5 + 24.0))
	_set_phase(character, "rear")
	_radio("rear")
	character.move_input = Vector2.ZERO


## Hold just inside the doorway facing back out the way the team came, for `rear_time`.
func _tick_rear(character, delta: float) -> void:
	if not _at(character, _rear_spot):
		_loco.move_to(character, _rear_spot)
	else:
		character.move_input = Vector2.ZERO
	_look_toward(character, (_geo["pos"] as Vector2) + (_geo["out"] as Vector2) * 300.0, delta, 3.0)
	if _clock >= rear_time:
		phase = "done"


# --- Helpers ------------------------------------------------------------------------------------

## Move on to phase `next`, restarting the phase clock, and log it (the game's "what is happening" log).
func _set_phase(character, next: String) -> void:
	phase = next
	_clock = 0.0
	GameLog.say("%s entry %s > %s: %s at %s (slot %d%s)" % [character.name, opening, into, next, character.global_position.round(),
		slot, ", alone" if solo else ""])


## Whether the character has got to `p`: close by, or at the end of its nav path there.
func _at(character, p: Vector2) -> bool:
	return character.global_position.distance_to(p) <= WAYPOINT_REACH * 0.6 or _loco.reached(character, p)


## This NPC's stack slot on the team's side.
func _stack_point() -> Vector2:
	return AgentEntry.slot_point(_geo, side, slot)


## Queue step `what` for the radio (and remember it for the heartbeat).
func _radio(what: String, extra := {}) -> void:
	var msg := { "step": what }
	msg.merge(extra)
	_calls.append(msg)
	_last_step = what
	_heartbeat = HEARTBEAT


## Look where it walks.
func _aim_travel(character) -> void:
	if character.move_input != Vector2.ZERO:
		character.aim_point = character.global_position + character.move_input * 100.0
		_look_angle = character.move_input.angle()


## Turn the gaze toward `point` at `look_rate` (× `speed`); true once it is there.
func _look_toward(character, point: Vector2, delta: float, speed := 1.0) -> bool:
	var self_pos: Vector2 = character.global_position
	var desired := (point - self_pos).angle()
	_look_angle = rotate_toward(_look_angle, desired, look_rate * speed * delta)
	character.aim_point = self_pos + Vector2.from_angle(_look_angle) * 100.0
	return absf(angle_difference(_look_angle, desired)) <= GAZE_SETTLED

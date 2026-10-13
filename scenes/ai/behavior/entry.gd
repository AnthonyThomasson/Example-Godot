extends RefCounted

## AI BEHAVIOUR sub-domain — TACTICAL ENTRY. How an NPC gets through a doorway into a room the way police and
## soldiers do (`docs/tactical-entry.md`, E1 to E8), as one member of a team or alone. Von only chose the doorway
## (the ENTER tactic); the choreography is this phase machine, so it runs with the server down:
##
##   approach — to its stack slot beside the door, stepping off the door's axis while still well out and
##              arriving along the wall (E1)
##   stack    — in the slot, facing the door (a member past a short room's two holds here as security, E13) (the last of three or more faces back along the line instead, E12); radios `ready` (E2)
##   pie      — the point (or a lone entrant) sweeps the arc beside the door in angle steps, looking through it,
##              and notes the share of the room seen and the corners still hidden (E3); alone, both sides (E7)
##   cross    — committed: through the threshold without stopping, to its corner (E4, E5); radios `going_in`, then
##              `in` once it is in the room and off the door's axis
##   corner   — holds the corner looking across the room, then clears the rest by sight (`search_coverage.gd`)
##   cover    — once the room is clear, each member covers a different doorway on into a room not yet cleared, its gun
##              through it, until a teammate moves on (E8); alone, it looks through each such doorway in turn
##   rear     — a member left over (no such doorway free) that was the last of the team in holds the doorway it came
##              by, facing back out (E8)
##
## Its role comes from its slot. Slots, readiness and progress travel on the team radio: the behaviour queues each
## step (`take_calls()`) and the controller radios it; the team is read back through the perception
## (`entry_team`). The point crosses when every member of the stack is ready or `ready_timeout` runs out (E6); a
## follower crosses `follow_gap` after the member ahead of it is through. With nobody else claiming the doorway the
## NPC goes alone; an ally that claims a slot before it commits joins the stack (E7). Owns that state and nothing
## else: `Behavior` calls `begin()` on adopting an ENTER leaf and `step()` every tick until it reports done.

const Watch := preload("res://scenes/ai/behavior/watch.gd")

## A member whose latest call is one of these is through the doorway.
const THROUGH := ["in", "clear", "cover", "rear"]
## A member whose latest call is one of these has called the room clear (`clear`, then the watch it keeps after).
const CLEARED := ["clear", "cover", "rear"]
## A member whose latest call is one of these is holding the cleared room (covering a doorway or the rear).
const HOLDING := ["cover", "rear"]
## How far (px) back from a doorway, inside the cleared room, a member stands to cover it.
const COVER_DEPTH := 110.0
## How far (px) a cover spot is kept off the cleared room's walls.
const COVER_INSET := 20.0
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
## Most seconds a member that holds outside a short room waits for the room to be called clear before it gives up.
const SECURITY_CAP := 30.0
## Most seconds one entry spends topping its gun off before the crossing (a reload that will not start is not waited on forever).
const TOP_OFF_CAP := 8.0

var ready_timeout: float = 6.0     ## Seconds the point waits for the stack, once ready, before going in without it.
var follow_gap: float = 0.3        ## Seconds a follower leaves after the member ahead of it is through.
var pie_dwell: float = 0.35        ## Seconds the point looks through the door from each pie step.
var corner_dwell: float = 0.6      ## Seconds held in the corner looking across the room before clearing it.
var rear_time: float = 10.0        ## Most seconds the last of the team holds the doorway facing out once the room is clear.
var cover_time: float = 8.0        ## Most seconds a member covers a doorway on when no teammate moves on first.
var watch_dwell: float = 0.8       ## Seconds a lone entrant looks through each doorway on, once its gaze has settled.
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
var covering := ""                 ## The doorway on (its id) this NPC covers once the room is clear ("" = none).

var _loco: Node                    ## The Locomotion child (pathing, rooms).
var _perception: Node              ## The perception sub-domain (doorway geometry, the team on the radio, sight).
var _coverage: RefCounted          ## The room coverage by sight, reused to clear the room once inside.
var _geo := {}                     ## The doorway's geometry (agent_entry.gd `geometry`).
var _calls: Array = []             ## Steps to radio, oldest first: { step, cleared_room? }.
var _last_call := {}               ## The latest step radioed, whole (repeated on the heartbeat).
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
var _watch: Array = []             ## The doorways on out of the cleared room: { id, into, pos, spot, aim }.
var _sweep: Array = []             ## Alone: the doorways still to look through, in turn.
var _cover_spot := Vector2.INF     ## Where this NPC stands to cover its doorway.
var _cover_aim := Vector2.INF      ## A point through that doorway, in the room beyond: where its gun points.
var _holders := {}                 ## Allies seen holding the cleared room (cover / rear): instance id -> true.
var _eyes: RefCounted              ## The watch module: where a walking entrant looks (`Watch.travel_point`).
var _combat: RefCounted            ## The combat module: the tactical reload at the stack (`Combat.top_off`).
var _top_off_spent := 0.0          ## Seconds this entry has spent topping its gun off.
var _security_clock := 0.0         ## Seconds spent holding the stack outside a short room (E13).
var _security_held_at := -1.0      ## `_security_clock` the room was first called clear (-1 = not yet).
## A threat holds the entrant's eyes this tick (set by `Behavior` from the watch stage): a gaze step that cannot settle
## because the entrant is looking at a hostile counts as settled, so the entry carries on instead of waiting at the pie
## for a gaze the hostile will not let go of.
var gaze_held := false


## Capture the locomotion, the perception, the room coverage, the watch module (where a walker looks) and the combat module
## (the tactical reload). Called once by `Behavior.setup()`.
func setup(loco: Node, perception: Node, coverage: RefCounted, eyes: RefCounted, combat: RefCounted) -> void:
	_loco = loco
	_perception = perception
	_coverage = coverage
	_eyes = eyes
	_combat = combat


## Start an entry from an ENTER leaf's params (`opening`, `into`, `slot`). False when the doorway is unknown
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
	slot = _perception.entry_free_slot(team, character.get_instance_id(), int(params.get("slot", 0)))
	side = _perception.entry_stack_side(_geo, team, character.global_position)
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
	covering = ""
	_geo = {}
	_calls = []
	_last_call = {}
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
	_watch = []
	_sweep = []
	_cover_spot = Vector2.INF
	_cover_aim = Vector2.INF
	_holders = {}
	_top_off_spent = 0.0
	_security_clock = 0.0
	_security_held_at = -1.0


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
		"covering": covering, "watch_doors": _watch.map(func(w): return w["id"]),
	}


## The entry as world-space data for the entry debug overlays (observation only): the doorway's frame, slots, pie
## arc and corners (with what the pie saw), this NPC's role, slot, approach and gaze, the ready-barrier timers, the
## team off the radio, and once the room is clear the doorways on it covers. {} when no entry is running.
func debug_view() -> Dictionary:
	if phase in ["", "done"] or _geo.is_empty():
		return {}
	var team: Array = _perception.entry_team(opening)
	var corners: Array = []
	for i in (_geo["corners"] as Array).size():
		var c: Dictionary = (_geo["corners"][i] as Dictionary).duplicate()
		c["seen"] = _corners_seen.get(i, false)
		corners.append(c)
	var role := "solo" if team.is_empty() and _through.is_empty() else ("point" if _ahead(team).is_empty() else "follower")
	var ready_left := -1.0
	if role == "point" and _ready_at >= 0.0 and phase in ["stack", "pie"]:
		ready_left = maxf(ready_timeout - (_time - maxf(_ready_at, _team_grew_at)), 0.0)
	var hold_left := -1.0
	if phase == "cover":
		hold_left = maxf(cover_time - _clock, 0.0)
	elif phase == "rear":
		hold_left = maxf(rear_time - _clock, 0.0)
	return {
		"door": { "pos": _geo["pos"], "width": _geo["width"], "out": _geo["out"], "along": _geo["along"], "room": _geo["room"] },
		"opening": opening, "into": into, "phase": phase, "role": role, "slot": slot, "side": side,
		"slots": _geo["slots"], "my_slot": _stack_point(), "pie": _geo["pie"], "pie_queue": _pie_queue.duplicate(),
		"pie_side": _pie_side, "pie_sides": pie_sides, "corners": corners, "corner": corner,
		"waypoints": _waypoints.duplicate(), "unseen": _unseen.duplicate() if phase == "pie" else [],
		"seen_fraction": seen_fraction, "gaze": Vector2.from_angle(_look_angle),
		"ready_left": ready_left, "follow_left": maxf(follow_gap - (_time - _turn_at), 0.0) if _turn_at >= 0.0 and phase == "stack" else -1.0,
		"waiting_for": team.filter(func(m): return m["step"] == "claim").map(func(m): return str(m["name"])),
		"team": team.map(func(m): var d: Dictionary = m.duplicate(); d["through"] = THROUGH.has(m["step"]); return d),
		"watch": _watch.map(func(w): return { "id": w["id"], "pos": w["pos"], "spot": w["spot"], "aim": w["aim"] }),
		"covering": covering,
		"sweep": _sweep.map(func(w): return w["id"]), "rear_spot": _rear_spot, "hold_left": hold_left,
		"ready_total": ready_timeout, "follow_total": follow_gap, "hold_total": rear_time if phase == "rear" else cover_time,
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
	if _heartbeat <= 0.0 and not _last_call.is_empty():
		_radio(_last_call["step"], _last_call)  # Keep the claim (and what it covers) alive on the radio.
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
		"cover":
			_tick_cover(character, team, delta)
		"rear":
			_tick_rear(character, team, delta)
	return phase == "done"


## Keep this NPC's slot and side in step with the radio: a slot an ally with a lower instance id also claimed is
## given up for the next free one, and the side follows the point's (the side is never re-read from where this NPC
## stands: a lone entrant crosses in front of the door to slice its other side). A change is radioed as a new claim.
func _keep_slot(character, team: Array) -> void:
	var was := slot
	slot = _perception.entry_free_slot(team, character.get_instance_id(), slot)
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
	if _covers_rear(team):
		_look_toward(character, spot + (_geo["along"] as Vector2) * side * 300.0, delta, 3.0)  # Back along the line, away from the door.
	else:
		_look_toward(character, _geo["pos"], delta)
	if _topping_off(character, delta):
		return
	if _holds_outside(team):
		_tick_security(character, team, delta)
		return
	var ahead := _ahead(team)
	if ahead.is_empty():
		_start_pie(character, team)
		return
	if THROUGH.has(ahead[-1]["step"]):
		if _turn_at < 0.0:
			_turn_at = _time
		if _time - _turn_at >= follow_gap:
			_start_cross(character, team)


## Whether this member is the stack's rear guard (E12): the last slot of a stack of three or more, until the member ahead
## of it is through the door and its own turn to cross is near. It faces back along the line the team came by instead of at
## the door; the point and the second watch the door.
func _covers_rear(team: Array) -> bool:
	return _turn_at < 0.0 and team.size() >= 2 and team.all(func(m): return m["slot"] < slot)


## The tactical reload (E11): the stack is the one lull before the crossing, so a gun short of full is swapped for a full
## magazine here, standing still, and never in the threshold or the room just taken. True while that is under way: the
## caller does not move on armed with a part-spent gun. Not with a hostile holding the entrant's eyes (it fires, and an empty
## gun is the watch stage's reload) and not for longer than `TOP_OFF_CAP` s.
func _topping_off(character, delta: float) -> bool:
	if gaze_held or _top_off_spent >= TOP_OFF_CAP:
		return false
	if not _combat.top_off(character):
		return false
	character.move_input = Vector2.ZERO
	_top_off_spent += delta
	return true


## Whether this member holds the stack outside instead of going in (E13): a room too small for the team takes two
## (`geometry.capacity`), so every slot past them stays on the stack side. It does while the two ahead are still on the
## radio, and keeps holding once the room has been called clear. With nobody ahead and the room not cleared (they died or
## gave it up) it is not held back, and takes the lead.
func _holds_outside(team: Array) -> bool:
	if slot <= int(_geo.get("capacity", 99)):
		return false
	return _security_held_at >= 0.0 or not _ahead(team).is_empty()


## Hold the stack side as security while the two in the short room clear it (facing back along the line, `_covers_rear`):
## until the room is called clear and a teammate that held it moves on (or `rear_time` runs out after that), then done. It
## never steps into the doorway. Gives up after `SECURITY_CAP` s with the room never called clear.
func _tick_security(character, team: Array, delta: float) -> void:
	_security_clock += delta
	character.move_input = Vector2.ZERO
	if _security_held_at < 0.0 and _cleared_by_team(team):
		_security_held_at = _security_clock
	if _security_held_at >= 0.0:
		if _team_moved(team) or _security_clock - _security_held_at >= rear_time:
			_radio("done")
			phase = "done"
	elif _security_clock >= SECURITY_CAP:
		_radio("abort")
		phase = "done"


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
		_finish(character, team)
	elif _dwell >= corner_dwell:
		_set_phase(character, "clear")
		_coverage.begin(character)


## Cover the room by sight; when done, and the rest of the stack is in too (or has had `ready_timeout` to come), radio
## it clear and move on. An ally that radioed it clear first ends this NPC's search.
func _tick_clear(character, team: Array, delta: float) -> void:
	if _cleared_by_team(team):
		_finish(character, team)
		return
	if not _covered:
		_covered = _coverage.step(character, delta)
		return
	character.move_input = Vector2.ZERO
	_look_toward(character, _across_from(character.global_position), delta)
	var coming := team.filter(func(m): return not THROUGH.has(m["step"]) and m["step"] != "claim")
	if coming.is_empty() or _clock >= ready_timeout + CROSS_CAP:
		_radio("clear", { "cleared_room": into })
		_finish(character, team)


## Whether an ally of this entry has radioed the room clear (its latest call may already be the watch it keeps after).
func _cleared_by_team(team: Array) -> bool:
	return team.any(func(m): return CLEARED.has(m["step"]))


## The room is clear (by this NPC's sight or an ally's call): it is marked cleared, so nothing walks into it unprepared
## again (the entry guard, E9). Then the room is held (E8): with a team, each member covers a different doorway on into a
## room not yet cleared, and a member left over holds the doorway it came by, facing back out. A room with no doorway on
## leaves only the last of the team in on the rear; everyone else is done. Alone, it looks through each doorway on in
## turn.
func _finish(character, team: Array) -> void:
	_perception.mark_cleared(into)
	_watch = _watch_doors(character)
	if _watch.is_empty():
		_hold_rear_or_done(character)
		return
	if _through.is_empty():
		_sweep = _watch.duplicate()
		_dwell = 0.0
		_set_phase(character, "cover")
		return
	if _claim_door(character, team):
		_set_phase(character, "cover")
		_radio("cover", { "covering": covering })
		return
	_hold_rear_or_done(character, true)


## Hold the doorway this NPC came by, facing back out (rear security): a member left over when the team covers the
## doorways on (`spare`), or the last of the team in; anyone else is done.
func _hold_rear_or_done(character, spare := false) -> void:
	covering = ""
	var last := not _through.is_empty() and _through.values().all(func(other_slot): return other_slot < slot)
	if not (last or (spare and not _through.is_empty())):
		_end_hold()
		return
	var door: Vector2 = _geo["pos"]
	_rear_spot = _loco.reachable(door - (_geo["out"] as Vector2) * 30.0 + (_geo["along"] as Vector2) * side * (float(_geo["width"]) * 0.5 + 24.0))
	_set_phase(character, "rear")
	_radio("rear")
	character.move_input = Vector2.ZERO


## The doorways on out of the cleared room, each with where to stand to cover it and where to point the gun: inside the
## cleared room, `COVER_DEPTH` back from the doorway and off its axis on the side this NPC is on, looking through it.
func _watch_doors(character) -> Array:
	var out: Array = []
	var room: Rect2 = (_geo["room"] as Rect2).grow(-COVER_INSET)
	for d in _perception.entry_watch_doors(into, opening):
		var g: Dictionary = _perception.entry_geometry(character, d["id"], d["into"])
		if g.is_empty():
			continue
		var pos: Vector2 = g["pos"]
		var back: Vector2 = g["out"]  # Away from the room beyond: into the cleared room.
		var along: Vector2 = g["along"]
		var lean := 1.0 if (character.global_position - pos).dot(along) >= 0.0 else -1.0
		var spot := pos + back * COVER_DEPTH + along * lean * (float(g["width"]) * 0.5 + 20.0)
		spot = _loco.reachable(spot.clamp(room.position, room.end))
		out.append({ "id": d["id"], "into": d["into"], "pos": pos, "spot": spot,
			"aim": pos + (pos - spot).normalized() * 300.0 })
	return out


## Claim the doorway on that is nearest this NPC and that no teammate covers, keeping the one it already covers while
## that stays its own (when two claim one, the lower instance id keeps it, as with a stack slot). False when every
## doorway on is covered.
func _claim_door(character, team: Array) -> bool:
	var me: int = character.get_instance_id()
	var best := {}
	for w in _watch:
		var mine := team.all(func(m): return m["step"] != "cover" or m["covering"] != w["id"] or me < m["id"])
		if not mine:
			continue
		if w["id"] == covering:
			best = w
			break
		if best.is_empty() or character.global_position.distance_to(w["spot"]) < character.global_position.distance_to(best["spot"]):
			best = w
	if best.is_empty():
		return false
	covering = best["id"]
	_cover_spot = best["spot"]
	_cover_aim = best["aim"]
	return true


## Hold the cleared room covering a doorway on: to the cover spot with the gun through that doorway, kept there until a
## teammate who held the room moves on, or `cover_time` runs out. A teammate that takes the same doorway with a lower
## instance id makes this NPC take another (or the rear). Alone: look through each doorway on in turn, `watch_dwell`
## each once the gaze has settled, then done.
func _tick_cover(character, team: Array, delta: float) -> void:
	if _clock >= cover_time:
		_end_hold()
		return
	if not _sweep.is_empty():
		character.move_input = Vector2.ZERO
		var w: Dictionary = _sweep[0]
		var at: Vector2 = w["pos"]
		if _look_toward(character, at + (at - character.global_position).normalized() * 300.0, delta, 2.0):
			_dwell += delta
		else:
			_dwell = 0.0
		if _dwell >= watch_dwell:
			_sweep.pop_front()
			_dwell = 0.0
			if _sweep.is_empty():
				_end_hold()
		return
	if _team_moved(team):
		_end_hold()
		return
	var was := covering
	if not _claim_door(character, team):
		_hold_rear_or_done(character, true)
		return
	if covering != was:
		_radio("cover", { "covering": covering })
	if not _at(character, _cover_spot):
		_loco.move_to(character, _cover_spot)
	else:
		character.move_input = Vector2.ZERO
	_look_toward(character, _cover_aim, delta, 3.0)


## Hold just inside the doorway facing back out the way the team came, until a teammate who held the room moves on or
## `rear_time` runs out.
func _tick_rear(character, team: Array, delta: float) -> void:
	if not _at(character, _rear_spot):
		_loco.move_to(character, _rear_spot)
	else:
		character.move_input = Vector2.ZERO
	_look_toward(character, (_geo["pos"] as Vector2) + (_geo["out"] as Vector2) * 300.0, delta, 3.0)
	if _clock >= rear_time or _team_moved(team):
		_end_hold()


## Whether a teammate who was holding the cleared room (covering a doorway or the rear) has moved on: its latest call is
## no longer a hold on this doorway (it radioed `done` or `abort`, or claims another doorway).
func _team_moved(team: Array) -> bool:
	for m in team:
		if HOLDING.has(m["step"]):
			_holders[m["id"]] = true
	for id in _holders:
		if not team.any(func(m): return m["id"] == id and HOLDING.has(m["step"])):
			return true
	return false


## The watch is over: radio `done` (a teammate still holding the room takes it as the team moving on) and finish.
func _end_hold() -> void:
	if phase in ["cover", "rear"] and not _through.is_empty():
		_radio("done")
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
	return _perception.entry_slot_point(_geo, side, slot)


## Queue step `what` for the radio (and remember it, with its extra fields, for the heartbeat).
func _radio(what: String, extra := {}) -> void:
	var msg := { "step": what }
	msg.merge(extra)
	_calls.append(msg)
	_last_call = msg.duplicate()
	_heartbeat = HEARTBEAT


## Look where it walks: a few paces down its path (the door it is lining up), not the next waypoint beside it.
func _aim_travel(character) -> void:
	if character.move_input == Vector2.ZERO:
		return
	var ahead: Vector2 = _eyes.travel_point(character)
	var toward: Vector2 = (ahead - character.global_position) if ahead != Vector2.INF else character.move_input
	character.aim_point = character.global_position + toward.normalized() * 100.0
	_look_angle = toward.angle()


## Turn the gaze toward `point` at `look_rate` (× `speed`); true once it is there.
func _look_toward(character, point: Vector2, delta: float, speed := 1.0) -> bool:
	_look_angle = Watch.ease_gaze(character, point, look_rate * speed, delta)
	var desired := (point - (character.global_position as Vector2)).angle()
	return gaze_held or absf(angle_difference(_look_angle, desired)) <= GAZE_SETTLED

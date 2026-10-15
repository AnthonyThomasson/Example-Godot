extends RefCounted

## AI BEHAVIOUR sub-domain — TACTICAL ENTRY. How an NPC gets through a doorway into a room the way police and
## soldiers do (`docs/tactical-entry.md`, E1 to E15), as one member of a team or alone. Von only chose the doorway
## (the ENTER tactic); the choreography is this phase machine, so it runs with the server down:
##
##   approach — to its stack slot beside the door, stepping off the door's axis while still well out and
##              arriving along the wall (E1)
##   stack    — in the slot, facing the door (the last of three or more faces back along the line instead, E12; a member
##              past a short room's two holds here as security, E13); radios `ready` (E2)
##   pie      — the point (or a lone entrant) sweeps the arc beside the door in angle steps, looking through it,
##              and notes the share of the room seen and the corners still hidden (E3); alone, both sides (E7)
##              Nobody crosses while a hostile stands in view (E14): the pie stops where it is and the watch stage fires.
##   bang     — a bang entry (`docs/grenades.md` G18): once the stack is ready its thrower radios `bang`, steps out beside the door and
##              throws a stun into the room; every member holds its slot turned away from the door until the stun goes off
##   cross    — committed: through the threshold without stopping, to its corner (E4, E5); radios `going_in`, then
##              `in` once it is in the room and off the door's axis
##   corner   — holds the corner looking across the room, then clears the rest by sight (`search_coverage.gd`)
##              A pass-by (`secure`, E15) stops here: it slices one side of the pie from beside the jamb and walks on.
##   cover    — once the room is clear, each member covers a different doorway on into a room not yet cleared, its gun
##              through it, until a teammate moves on (E8); alone, it looks through each such doorway in turn
##   rear     — a member left over (no such doorway free) that was the last of the team in holds the doorway it came
##              by, facing back out (E8)
##
## Its role comes from its slot. Slots, readiness and progress travel on the team radio: the behaviour queues each
## step (`take_calls()`) and the controller radios it; the team is read back through the perception
## (`entry_team`). The point crosses when every member of the stack is ready or `ready_timeout` runs out (E6); a
## follower crosses `follow_gap` after the member ahead of it is through. With nobody else claiming the doorway the
## NPC goes alone; an ally that claims a slot before it commits joins the stack (E7). In a **bang entry** the stack throws a stun grenade
## into the room first (the `bang` phase, below): the point skips the pie and crosses the moment it goes off. Owns that state and nothing
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
## How close (px) a member walks into its stack slot: a stride short of it would stand on the next slot.
const SLOT_REACH := 6.0
## How close (px) an entrant walks into its corner: all the way, since a few px short of a corner beside the doorway (a small
## room's) is still in the way of the one crossing behind it.
const CORNER_REACH := 6.0
## Distance (px) between the spots two members hold side by side (the later members' spots inside, the rear spots): clear of
## each other's footprint, so neither stands in the hole the other's body cuts in the steering map.
const SPOT_SPACING := 44.0
## Most seconds the committed crossing may take before it gives up the commitment (a blocked doorway).
const CROSS_CAP := 6.0
## Gaze (rad) within which the look through the door has settled at a pie step.
const GAZE_SETTLED := 0.12
## Most seconds a member that holds outside a short room waits for the room to be called clear before it gives up.
const SECURITY_CAP := 30.0
## Most seconds one entry spends topping its gun off before the crossing (a reload that will not start is not waited on forever).
const TOP_OFF_CAP := 8.0
## A bang entry (G18): where the thrower steps out to throw from (px out from the wall, and along it from the doorway's centre as shares of
## its width, toward the stack's side first), how far its throwing hand reaches to its right (px) and how much room a throw leaves either
## side of the doorway's edge, how deep into the room and how far across it (shares of the room's depth and width) the stun is aimed, in order
## of preference, and the least distance (px) from the door it lands at.
const BANG_STEP_OUT := 78.0
const BANG_STEP_ALONG := [0.25, 0.0, -0.25]
const BANG_HAND_REACH := 28.0
const BANG_EDGE_MARGIN := 8.0
const BANG_DEPTHS := [0.85, 0.7, 0.55]
const BANG_ACROSS := [0.0, 0.2, -0.2]
const BANG_MIN_DEPTH := 120.0
## The most seconds a stack-ready member waits for its thrower to call the bang before the stack goes in quietly, and the most the
## stack waits for the stun to go off once it was called.
const BANG_CALL_CAP := 8.0
const BANG_BURST_CAP := 5.0
## Seconds after the stun went off in which the stack goes in whatever stands in view (a hostile in the doorway is blind and deaf).
const BANG_WINDOW := 3.0

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
var secure := false                ## A pass-by (E15): the doorway is only secured, from one side of its pie, never crossed or radioed.
var secured := false               ## A secure entry got to the end of its pie.
var covering := ""                 ## The doorway on (its id) this NPC covers once the room is clear ("" = none).
var bang := false                  ## A bang entry (G18): a stun is thrown into the room before anyone crosses. Radioed with every claim; the stack is in bang mode only if all of it is.

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
var _stuns := 0                    ## Stun grenades this NPC carries (radioed, so the stack knows who can throw).
var _self_id := 0                  ## This NPC's instance id (to know it is the thrower on the radio's terms).
var _bang_stage := ""              ## The thrower's part: "go" (to the throw spot), "throw", "back" (to its slot); "" for everyone else.
var _bang_spot := Vector2.INF      ## Where the thrower throws from.
var _bang_route: Array = []        ## The points it walks through to get there: out from its slot first, clear of the member ahead of it, then along.
var _bang_target := Vector2.INF    ## Where the stun is thrown to, in the room.
var _bang_wait := 0.0              ## Seconds a stack-ready member has waited for the bang to be called.
var _bang_over := false            ## The stun went off (or the bang was given up): the point crosses at once, no pie.
var _burst_seen := -1              ## The physics frame of the last stun burst in the room this entry has taken note of.
var _burst_at := -INF              ## `_time` of the stun burst in the room.
var _security_clock := 0.0         ## Seconds spent holding the stack outside a short room (E13).
var _security_held_at := -1.0      ## `_security_clock` the room was first called clear (-1 = not yet).
var _blocked_count := 0            ## How many times the walk of this phase has been found sealed (`way_blocked`).
## A threat holds the entrant's eyes this tick (set by `Behavior` from the watch stage): a gaze step that cannot settle
## because the entrant is looking at a hostile counts as settled, so the entry carries on instead of waiting at the pie
## for a gaze the hostile will not let go of.
var gaze_held := false
## A hostile stands in view this tick (set by `Behavior`: seen now, or a moment ago with a clear line to where it stood): nobody
## crosses (E14). The entry holds where it is, outside, and the watch stage fires; it goes in once the hostile is gone.
var hostile_in_view := false


## Capture the locomotion, the perception, the room coverage, the watch module (where a walker looks) and the combat module
## (the tactical reload). Called once by `Behavior.setup()`.
func setup(loco: Node, perception: Node, coverage: RefCounted, eyes: RefCounted, combat: RefCounted) -> void:
	_loco = loco
	_perception = perception
	_coverage = coverage
	_eyes = eyes
	_combat = combat


## Start an entry from `params`: `opening`, `into` and `slot` from an ENTER leaf, `secure` from the guard's pass-by detour. False
## when the doorway is unknown (the leaf is then dropped and the NPC re-decides).
func begin(character, params: Dictionary) -> bool:
	reset()
	opening = str(params.get("opening", ""))
	into = str(params.get("into", ""))
	secure = bool(params.get("secure", false))
	_geo = _perception.entry_geometry(opening, into)
	if _geo.is_empty():
		phase = "done"
		return false
	var team: Array = [] if secure else _perception.entry_team(opening)
	_self_id = character.get_instance_id()
	bang = bool(params.get("bang", false)) and not secure
	if not team.is_empty():
		bang = team.all(func(m): return m["bang"])  # The stack goes in the way its first claimer chose.
	_stuns = character.item_count(ItemRegistry.STUN_SLOT)
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
	secure = false
	secured = false
	seen_fraction = 0.0
	pie_sides = 0
	corner = Vector2.INF
	covering = ""
	bang = false
	_bang_stage = ""
	_bang_spot = Vector2.INF
	_bang_route = []
	_bang_target = Vector2.INF
	_bang_wait = 0.0
	_bang_over = false
	_burst_seen = -1
	_burst_at = -INF
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
	_blocked_count = 0


## Give the entry up (the NPC chose something else, e.g. a fight): radio `abort` so the stack stops counting on it.
func abandon() -> void:
	if phase in ["", "done"]:
		return
	_radio("abort")
	phase = "done"


## Whether the entrant is committed to the crossing: nothing may stop it (no re-decision, no reload, no crouch)
## until it is through the threshold and off the door's axis (E4).
func committed() -> bool:
	return phase == "cross" or (phase == "bang" and _combat.throw_stage == "windup")


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
		"opening": opening, "into": into, "slot": slot, "side": side, "solo": solo, "phase": phase, "secure": secure,
		"seen_fraction": seen_fraction, "pie_sides": pie_sides, "hidden_corners": hidden, "corner": corner,
		"stack_point": _stack_point() if not _geo.is_empty() else Vector2.INF, "team": _team_size,
		"covering": covering, "watch_doors": _watch.map(func(w): return w["id"]), "bang": bang, "bang_stage": _bang_stage,
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
	var team: Array = [] if secure else _perception.entry_team(opening)
	_stuns = character.item_count(ItemRegistry.STUN_SLOT)
	_note_burst()
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
			_tick_approach(character, team, delta)
		"stack":
			_tick_stack(character, team, delta)
		"bang":
			_tick_bang(character, team, delta)
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


## The walk this phase is on has no way through: a body seals it and stays (`Locomotion.take_blocked`, after a moment's
## wait and then every few seconds while it stays held). The phase re-plans, so no member stands held for ever: the approach
## goes on to its next point (or its slot) by whatever way there is; a member the stack itself keeps from its slot takes the
## back of the stack (`_to_back`), and with no slot to take it gives the claim up; a pie step is skipped; the thrower gives
## the bang up; a member crossing waits out the first signal (the one ahead is still in the doorway and moves on in a moment),
## then takes its corner where it stands once through, or gives the entry up when the doorway is still sealed; a corner, a
## cover spot or the rear spot is held from where it stands, and the room is covered from where it stands. True when the
## entry is given up (radioed `abort`): the caller re-decides because the way is blocked.
func way_blocked(character) -> bool:
	_blocked_count += 1
	match phase:
		"approach":
			if not _waypoints.is_empty():
				_waypoints.pop_front()
				return false
			if _to_back(character):
				return false
			_radio("abort")
			phase = "done"
			return true
		"pie":
			if not _pie_queue.is_empty():
				_pie_queue.pop_front()
				_clock = 0.0
		"bang":
			if _bang_stage == "go":
				_give_up_bang()
				_set_phase(character, "stack")
		"cross":
			if _blocked_count < 2:
				return false  # The member ahead is still in the doorway: it moves on into the room in a moment.
			if (character.global_position - (_geo["pos"] as Vector2)).dot(_geo["out"]) >= -THROUGH_DEPTH:
				_radio("abort")
				phase = "done"
				return true
			corner = character.global_position
		"corner":
			corner = character.global_position
		"clear":
			_covered = true
		"cover":
			_cover_spot = character.global_position
		"rear":
			_rear_spot = character.global_position
	return false


## Take the back of the stack (E2: the slots go by arrival): the slot behind the last one claimed, when this member is not
## already the last and the doorway's wall has a slot there. A change is radioed as a new claim. False when there is none to
## take.
func _to_back(character) -> bool:
	var team: Array = [] if secure else _perception.entry_team(opening)
	var last := 0
	for m in team:
		last = maxi(last, int(m["slot"]))
	if last < slot or last >= (_geo["slots"][side] as Array).size():
		return false
	slot = last + 1
	_enter_approach(character)
	_radio("claim")
	return true


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
func _tick_approach(character, team: Array, delta: float) -> void:
	if _clock > approach_time:
		_radio("abort")
		phase = "done"
		return
	if not team.is_empty() and _bang_due(character, team, delta):
		return  # The rest of the stack is in place: the thrower goes straight to throw, rather than into its slot first.
	_aim_travel(character)
	while not _waypoints.is_empty() and (character.global_position.distance_to(_waypoints[0]) <= WAYPOINT_REACH \
			or _loco.reached(_waypoints[0])):
		_waypoints.pop_front()  # Got there, or to the free spot beside it when a body stands on it.
	if not _waypoints.is_empty():
		_loco.move_to(_waypoints[0])
		return
	var spot := _stack_point()
	if not _at(character, spot, SLOT_REACH):
		_loco.move_to(spot, SLOT_REACH)
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
		_loco.move_to(spot, SLOT_REACH)  # Shoved out of the slot: step back in.
	else:
		character.move_input = Vector2.ZERO
	if _covers_rear(team):
		_look_toward(character, spot + (_geo["along"] as Vector2) * side * 300.0, delta, 3.0)  # Back along the line, away from the door.
	else:
		_look_toward(character, _geo["pos"], delta)
	if not _bang_over and _topping_off(character, delta):
		return
	if _holds_outside(team):
		_tick_security(character, team, delta)
		return
	if _bang_due(character, team, delta):
		return
	var ahead := _ahead(team)
	if ahead.is_empty():
		if _bang_over:
			_start_cross(character, team)  # The stun went off: in at once, whatever stands in view, no pie.
		elif _waits_for_bang(team):
			return
		else:
			_start_pie(character, team)
		return
	if THROUGH.has(ahead[-1]["step"]):
		if _turn_at < 0.0:
			_turn_at = _time
		if _time - _turn_at >= follow_gap and (not hostile_in_view or _in_bang_window()):
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
	if not _combat.top_off():
		return false
	character.move_input = Vector2.ZERO
	_top_off_spent += delta
	return true


## Whether this member holds the stack outside instead of going in (E13): a room too small for the team takes two
## (`geometry.capacity`), so every member with two or more ahead of it in the stack stays on the stack side (its place in
## the stack, not its slot's number: a member that took the back of the stack leaves its old slot empty). It does while the
## two ahead are still on the radio, and keeps holding once the room has been called clear. With nobody ahead and the room
## not cleared (they died or gave it up) it is not held back, and takes the lead.
func _holds_outside(team: Array) -> bool:
	if team.filter(func(m): return m["slot"] < slot).size() < int(_geo.get("capacity", 99)):
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


# --- The bang (G18) ------------------------------------------------------------------------------

## Whether the stack is in bang mode and has a stun to throw: every member's claim says bang (one that gave it up vetoes it) and a
## member carries one. The mode is the first claimer's (`begin`), so a stack goes in all one way.
func _banging(team: Array) -> bool:
	return bang and not _bang_over and team.all(func(m): return m["bang"]) and _thrower(team) != -1


## The instance id of the member who throws the stun, or -1 when nobody can: the second of the stack if it carries one, else the lowest
## slot that does (alone, this NPC). Every member works it out from the radio's `stuns` the same way.
func _thrower(team: Array) -> int:
	var carriers: Array = team.filter(func(m): return int(m["stuns"]) > 0).map(func(m): return { "id": m["id"], "slot": m["slot"] })
	if _stuns > 0:
		carriers.append({ "id": _self_id, "slot": slot })
	if carriers.is_empty():
		return -1
	carriers.sort_custom(func(a, b): return a["slot"] < b["slot"] if a["slot"] != b["slot"] else a["id"] < b["id"])
	for c: Dictionary in carriers:
		if c["slot"] == 2:
			return c["id"]
	return carriers[0]["id"]


## A member in its slot with the stack ready that is the thrower calls the bang and goes to throw. Returns true once the phase has
## changed. A thrower with nowhere to throw from (no clear lob into the room) gives the bang up: the stack goes in quietly.
func _bang_due(character, team: Array, delta: float) -> bool:
	if _bang_over or not bang:
		return false
	if not team.all(func(m): return m["bang"]):
		_give_up_bang()  # A teammate gave the bang up: this member goes in quietly too, and its claims say so.
		return false
	if team.any(func(m): return m["step"] == "bang"):
		_enter_bang(character)  # The thrower called it: hold, turned away, until the stun goes off.
		return true
	if _thrower(team) == -1 or not _stack_ready(team) or hostile_in_view:
		return false
	if _thrower(team) != _self_id:
		_bang_wait += delta  # Waiting for the thrower to call the bang.
		return false
	if not _plan_bang():
		_give_up_bang()
		return false
	_bang_stage = "go"
	_enter_bang(character)
	_radio("bang")
	return true


## Begin the bang phase, taking note of the last burst so only a stun that goes off from now on ends it.
func _enter_bang(character) -> void:
	_set_phase(character, "bang")
	_burst_seen = int(_perception.last_burst.get("frame", -1))
	_burst_at = -INF


## Whether the point holds in its slot for the bang the stack's thrower is about to call, rather than slicing the pie: the stack is in
## bang mode and has waited less than `BANG_CALL_CAP` for it.
func _waits_for_bang(team: Array) -> bool:
	if not _banging(team):
		return false
	if _bang_wait >= BANG_CALL_CAP:
		_give_up_bang()
		return false
	return true


## The bang is off: the stack goes in quietly (the point slices the pie). Radioed with the next claim, so the whole stack follows.
func _give_up_bang() -> void:
	bang = false
	_bang_stage = ""
	_radio(str(_last_call.get("step", "ready")), _last_call)


## Plan the throw: a spot to throw from and a target in the room, a clear lob from the thrower's hand there to the target (a hand that
## clears the jamb, with `BANG_EDGE_MARGIN` to spare either side). The target is the room's far side, `BANG_DEPTHS` of the way in and
## `BANG_ACROSS` of the way across, at least `BANG_MIN_DEPTH` from the door; the first of them that some spot can reach wins, the thrower's
## own slot before a step out in front of the door (`BANG_STEP_ALONG`). False when nowhere gives a clear lob.
func _plan_bang() -> bool:
	var door: Vector2 = _geo["pos"]
	var out: Vector2 = _geo["out"]
	var along: Vector2 = _geo["along"]
	var room: Rect2 = _geo["room"]
	var depth := 0.0
	for c: Vector2 in [room.position, Vector2(room.end.x, room.position.y), room.end, Vector2(room.position.x, room.end.y)]:
		depth = maxf(depth, (door - c).dot(out))
	var width := absf(room.size.dot(along.abs()))
	var spots: Array = [_stack_point()]
	for share: float in BANG_STEP_ALONG:
		spots.append(_loco.reachable(door + out * BANG_STEP_OUT + along * side * float(_geo["width"]) * share))
	for d: float in BANG_DEPTHS:
		for a: float in BANG_ACROSS:
			var target: Vector2 = door - out * depth * d + along * width * a
			if not room.grow(-30.0).has_point(target) or target.distance_to(door) < BANG_MIN_DEPTH:
				continue
			for spot: Vector2 in spots:
				if _clear_lob(spot, target):
					_bang_spot = spot
					_bang_target = target
					_bang_route = [_loco.reachable(door + out * maxf(BANG_STEP_OUT, (spot - door).dot(out)) + along * (_stack_point() - door).dot(along)), spot]
					return true
	return false


## Whether a stun thrown from the hand of a thrower standing at `spot` and facing `target` flies to it clear of the jamb: its throwing hand
## is `BANG_HAND_REACH` to its right, and the lob must be clear from there and `BANG_EDGE_MARGIN` either side of it. The target is within the
## stun's throw reach (`Combat.throw_reach`) of the spot, so the thrower throws from where it stands and does not close in.
func _clear_lob(spot: Vector2, target: Vector2) -> bool:
	if spot.distance_to(target) > _combat.throw_reach(_perception.grenade_range(&"stun")):
		return false
	var toward := (target - spot).normalized()
	var hand := spot + toward.rotated(PI * 0.5) * BANG_HAND_REACH
	for lateral: float in [0.0, BANG_EDGE_MARGIN, -BANG_EDGE_MARGIN]:
		if not _perception.can_lob(hand + toward.rotated(PI * 0.5) * lateral, target, &"stun"):
			return false
	return true


## The bang phase. Everyone holds its slot turned away from the door while the stun is thrown and goes off; the thrower first steps to its
## throw spot, throws (taking the stun in hand, `Combat`) and comes back. When the stun has gone off the stack is over the bang: the point
## crosses at once (`_tick_stack`), the rest follow as usual. The bang is given up if the throw fails, a teammate gave it up (its claims say
## quiet) or the stun does not go off.
func _tick_bang(character, team: Array, delta: float) -> void:
	if _burst_at > -INF:
		_bang_over = true
		_set_phase(character, "stack")
		return
	if _clock > BANG_BURST_CAP or not team.all(func(m): return m["bang"]):
		_give_up_bang()
		_set_phase(character, "stack")
		return
	var away: Vector2 = _stack_point() + (_geo["out"] as Vector2) * 300.0
	match _bang_stage:
		"go":
			while _bang_route.size() > 1 and character.global_position.distance_to(_bang_route[0]) <= WAYPOINT_REACH:
				_bang_route.pop_front()
			if not _at(character, _bang_spot):
				_loco.move_to(_bang_route[0])
				_look_toward(character, _bang_target, delta, 3.0)
				return
			character.move_input = Vector2.ZERO
			_combat.begin_throw(ItemRegistry.STUN_SLOT, _bang_target, _perception.grenade_range(&"stun"))
			_bang_stage = "throw"
		"throw":
			if _combat.throw_stage != "away" and _combat.throw_step(delta) == &"failed":
				_combat.end_throw()
				_give_up_bang()
				_set_phase(character, "stack")
				return
			if _combat.throw_released():
				_combat.end_throw()
				_bang_stage = "back"
		_:
			var spot := _stack_point()
			if character.global_position.distance_to(spot) > WAYPOINT_REACH:
				_loco.move_to(spot, SLOT_REACH)  # Back in its slot (or, shoved out of it, a step back in).
			else:
				character.move_input = Vector2.ZERO
			_look_toward(character, away, delta, 3.0)


## Whether the stun grenade the stack threw has gone off in the room being entered: the perception notes every burst
## (`last_burst`), and one in this room that came after the bang phase began ends it.
func _note_burst() -> void:
	var burst: Dictionary = _perception.last_burst
	if phase != "bang" or burst.is_empty() or int(burst["frame"]) <= _burst_seen or burst["kind"] != &"stun" \
			or not (_geo.get("room", Rect2()) as Rect2).has_point(burst["position"]):
		return
	_burst_seen = int(burst["frame"])
	_burst_at = _time


## Whether the stun went off a moment ago (`BANG_WINDOW`): the stack goes in without the usual hold for a hostile in view.
func _in_bang_window() -> bool:
	return _bang_over and _time - _burst_at < BANG_WINDOW


## Whether a live grenade of `kind` is the stun this entry is waiting for (the evade reflex then leaves the stack to its own turned-away
## hold, beside the wall and out of the burst's line): any stun, while the bang phase runs. (In flight it is at the doorway, where its
## landing is not known to those who did not throw it.)
func expects_burst(kind: StringName) -> bool:
	return phase == "bang" and kind == &"stun"


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
	_note_seen()
	if not team.is_empty():
		solo = false  # An ally claimed a slot: no second side, it joins the stack.
	if hostile_in_view:
		character.move_input = Vector2.ZERO  # E14: what is in view is fought from where it stands, not walked past or into.
		_clock = 0.0
		return
	if _pie_queue.is_empty():
		character.move_input = Vector2.ZERO
		_look_toward(character, _geo["pos"] - (_geo["out"] as Vector2) * 300.0, delta)
		if secure:
			secured = true  # Seen from beside the jamb and covered: on its way, nothing left behind it.
			phase = "done"
			return
		if solo and pie_sides < 2:
			_pie_other_side()
			return
		if _stack_ready(team) and not hostile_in_view and not _topping_off(character, delta):
			_start_cross(character, team)
		return
	var spot: Vector2 = _pie_queue[0]
	if not _at(character, spot):
		_loco.move_to(spot)
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
func _note_seen() -> void:
	for p in _perception.visible_points(_unseen):
		_unseen.erase(p)
	if not _points.is_empty():
		seen_fraction = 1.0 - float(_unseen.size()) / float(_points.size())
	var corners: Array = _geo["corners"]
	var unseen_corners: Array = []
	for i in corners.size():
		if not _corners_seen.get(i, false):
			unseen_corners.append(corners[i]["pos"])
	for p in _perception.visible_points(unseen_corners):
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
	return _loco.reachable(door - (_geo["out"] as Vector2) * 90.0 + (_geo["along"] as Vector2) * side * (float(_geo["width"]) * 0.5 + SPOT_SPACING * (order - 1)))


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
	_loco.move_to(corner, CORNER_REACH)
	if character.move_input == Vector2.ZERO and not _loco.holding():
		character.move_input = (corner - character.global_position).normalized()  # Never stand in the funnel (unless a body is in the way).
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
	if not _at(character, corner, CORNER_REACH) and _clock < CROSS_CAP:
		_loco.move_to(corner, CORNER_REACH)
		_dwell = 0.0
		return
	character.move_input = Vector2.ZERO
	_dwell += delta
	if _dwell >= corner_dwell and _cleared_by_team(team):
		_finish(character, team)
	elif _dwell >= corner_dwell:
		_set_phase(character, "clear")
		_coverage.begin()


## Cover the room by sight; when done, and the rest of the stack is in too (or has had `ready_timeout` to come), radio
## it clear and move on. An ally that radioed it clear first ends this NPC's search.
func _tick_clear(character, team: Array, delta: float) -> void:
	if _cleared_by_team(team):
		_finish(character, team)
		return
	if not _covered:
		_covered = _coverage.step(delta)
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
	# A spot of its own: the slots take turns either side of the doorway, each pair a body's clearance further along the wall.
	var door: Vector2 = _geo["pos"]
	var rank := maxi(slot - 1, 0)
	var on := side if rank % 2 == 0 else -side
	_rear_spot = _loco.reachable(door - (_geo["out"] as Vector2) * 30.0 + (_geo["along"] as Vector2) * on * (float(_geo["width"]) * 0.5 + 24.0 + SPOT_SPACING * floorf(rank / 2.0)))
	_set_phase(character, "rear")
	_radio("rear")
	character.move_input = Vector2.ZERO


## The doorways on out of the cleared room, each with where to stand to cover it and where to point the gun: inside the
## cleared room, `COVER_DEPTH` back from the doorway and off its axis on the side this NPC is on, looking through it.
func _watch_doors(character) -> Array:
	var out: Array = []
	var room: Rect2 = (_geo["room"] as Rect2).grow(-COVER_INSET)
	for d in _perception.entry_watch_doors(into, opening):
		var g: Dictionary = _perception.entry_geometry(d["id"], d["into"])
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
		_loco.move_to(_cover_spot)
	else:
		character.move_input = Vector2.ZERO
	_look_toward(character, _cover_aim, delta, 3.0)


## Hold just inside the doorway facing back out the way the team came, until a teammate who held the room moves on or
## `rear_time` runs out.
func _tick_rear(character, team: Array, delta: float) -> void:
	if not _at(character, _rear_spot):
		_loco.move_to(_rear_spot)
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
	_blocked_count = 0
	GameLog.say("%s entry %s > %s: %s at %s (slot %d%s)" % [character.name, opening, into, next, character.global_position.round(),
		slot, ", alone" if solo else ""])


## Whether the character has got to `p`: close by, or at the end of its nav path there (arriving within `within` px when
## given, `Locomotion.move_to`).
func _at(character, p: Vector2, within := 0.0) -> bool:
	return character.global_position.distance_to(p) <= (within if within > 0.0 else WAYPOINT_REACH * 0.6) or _loco.reached(p, within)


## This NPC's stack slot on the team's side.
func _stack_point() -> Vector2:
	return _perception.entry_slot_point(_geo, side, slot)


## Queue step `what` for the radio (and remember it, with its extra fields, for the heartbeat).
func _radio(what: String, extra := {}) -> void:
	if secure:
		return  # A pass-by joins no stack and claims nothing on the radio.
	var msg := { "step": what }
	msg.merge(extra)
	msg["bang"] = bang
	msg["stuns"] = _stuns
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

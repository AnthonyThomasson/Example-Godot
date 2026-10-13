extends Node

## AI domain · TEAM — the human's place in an AI stack (`docs/tactical-entry.md` E16). A child of the human's character
## (Main attaches it with `attach`, as it hands an NPC its `rooms` and `openings`): it listens to the same `&"callout"`
## radio the NPCs use, and when an allied team is stacking at a doorway near the human it reserves the human the first
## free slot there, the way an NPC claims one: a `callout` with the human as speaker (`opening`, `into`, `slot`, `side`,
## `entry_step`), repeated every `HEARTBEAT` s so the claim stays live. The AI's entry code reads it like any teammate's
## claim, so the point waits for the human at the ready barrier, a lone AI is no longer solo, and an AI behind the human
## crosses after it. Nothing in the entry code knows it is a human.
##
## The human is never ordered: its radio step is read from where it stands (`claim` away from the slot, `ready` in it,
## `going_in` in the doorway, `in` through it). The claim is withdrawn (`abort`) when the human leaves (walks beyond
## `reserve_range * leave_factor`, dies), when no one is left stacking, or when the AI ahead is through and the human has
## not crossed within `go_timeout`; it is finished with `done` once through and nobody waits behind it.
##
## `view()` is what the UI's stack markers draw. Observation and radio only: it never moves or steers the character.

const AgentEntry := preload("res://scenes/ai/perception/agent_entry.gd")
const AgentGrenades := preload("res://scenes/ai/perception/agent_grenades.gd")

## Entry steps that mean a member is still on its way into the room (it holds a place in the stack).
const STACKING := ["claim", "ready", "going_in"]
## Entry steps of a member that is through the doorway.
const THROUGH := ["in", "clear", "cover", "rear"]
## Seconds between repeats of the latest call.
const HEARTBEAT := 2.0
## How close (px) to its slot the human counts as standing in it (the NPCs' `WAYPOINT_REACH`).
const SLOT_REACH := 20.0
## How deep (px) either side of the wall plane the doorway's funnel reaches (the entry tests' `FUNNEL_DEPTH`).
const FUNNEL_DEPTH := 40.0
## How far (px) past the wall plane the human is through (the entry's `THROUGH_DEPTH`).
const THROUGH_DEPTH := 26.0
## Seconds the human's `in` stays on the radio for an AI waiting behind it to hear, and the most it is held.
const IN_HOLD_MIN := 1.0
const IN_HOLD_MAX := 8.0
## Seconds between the checks that need a path query (is a team near, has the human left).
const CHECK_INTERVAL := 0.25

## How far (px of walking) from a doorway the human may be and still be reserved a slot there.
@export var reserve_range: float = 300.0
## The reservation is dropped beyond `reserve_range` times this.
@export var leave_factor: float = 1.5
## How far (px) a callout carries to the human (the NPCs' `callout_range`).
@export var callout_range: float = 1500.0
## Seconds a heard callout stays current (the NPCs' `callout_ttl`).
@export var callout_ttl: float = 6.0
## Seconds the human is given to follow once the AI ahead of it is through, before its slot is withdrawn.
@export var go_timeout: float = 6.0

var _char: Node2D = null                      ## The human's character (the parent).
var _entry: RefCounted = AgentEntry.new()    ## The doorway geometry (slots), the same the NPCs build.
var _clock := 0.0                             ## Seconds since the stack was built (physics time).
var _heard := {}                              ## speaker instance id -> { data, at }: the latest callout of each speaker.
var _opening := ""                            ## The doorway reserved ("" = no reservation).
var _into := ""                              ## The key of the room the reserved doorway leads into.
var _geo := {}                                ## The reserved doorway's geometry (`AgentEntry.geometry`).
var _slot := 0                                ## The human's slot number (1 = the point; 0 = none).
var _side := 0                                ## The side of the door the team stacks on (1 / -1 along its wall).
var _step := ""                               ## The human's latest radio step (claim / ready / going_in / in).
var _heartbeat := 0.0                         ## Seconds until the latest step is radioed again.
var _check := 0.0                             ## Seconds until the next walking-distance check.
var _ahead_through_at := -1.0                 ## `_clock` the AI ahead of the human was first all through (-1 = not yet).
var _in_at := -1.0                            ## `_clock` the human was through.
var _barred := {}                             ## doorway id -> true: declined, until nobody stacks there any more.


## Give `character` its stack radio: the house's `rooms` and `openings` as an NPC controller is handed them. Returns it.
static func attach(character: Node, rooms: Array, openings: Array) -> Node:
	var existing := character.get_node_or_null("PlayerStack")
	if existing != null:
		return existing
	var stack := new()
	stack.name = "PlayerStack"
	stack._char = character as Node2D
	stack._entry.set_house(openings, rooms)
	character.add_child(stack)
	return stack


func _ready() -> void:
	if _char == null:
		_char = get_parent() as Node2D
	EventBus.posted.connect(_on_posted)


func _exit_tree() -> void:
	if EventBus.posted.is_connected(_on_posted):
		EventBus.posted.disconnect(_on_posted)


## The reservation as data for the markers (`{}` with none): `opening`, `door`, `slots` (`{ n, point, mine, held }` for
## slot 1 up to the last taken), `mine` (the human's slot) and `step` (its own radio step).
func view() -> Dictionary:
	if _opening == "" or _geo.is_empty():
		return {}
	var held := {}
	var top := _slot
	for m in AgentEntry.claims(_opening, _callouts()):
		held[m["slot"]] = true
		top = maxi(top, m["slot"])
	var slots: Array = []
	for n in range(1, top + 1):
		slots.append({ "n": n, "point": AgentEntry.slot_point(_geo, _side, n), "mine": n == _slot, "held": held.has(n) or n == _slot })
	return { "opening": _opening, "door": _geo["pos"], "slots": slots, "mine": _slot, "step": _step }


## Keep the latest callout of each allied speaker within range (`_heard`).
func _on_posted(topic: StringName, data: Dictionary) -> void:
	if topic != &"callout" or _char == null or AgentGrenades.is_call(data.get("status")):
		return  # (A call about a live grenade is not the speaker's place in a stack: it must not replace its claim.)
	var speaker = data.get("speaker")
	if speaker == _char or not speaker is Node or not is_instance_valid(speaker):
		return
	if StringName(data.get("faction", &"")) != StringName(_char.get("faction")):
		return
	var at: Vector2 = data.get("position", _char.global_position)
	if callout_range > 0.0 and _char.global_position.distance_to(at) > callout_range:
		return
	_heard[speaker.get_instance_id()] = { "data": data, "at": _clock }


func _physics_process(delta: float) -> void:
	if _char == null or not is_instance_valid(_char):
		return
	_clock += delta
	_forget_stale()
	_check -= delta
	var due := _check <= 0.0
	if due:
		_check = CHECK_INTERVAL
	if _opening == "":
		if due and _char.get("is_dead") != true:
			_look_for_team()
		return
	_keep_reservation(delta, due)


## Drop the callouts that lapsed or whose speaker is gone or dead.
func _forget_stale() -> void:
	for id in _heard.keys():
		var rec: Dictionary = _heard[id]
		var speaker = rec["data"].get("speaker")
		if _clock - rec["at"] > callout_ttl or not is_instance_valid(speaker) or (speaker as Node).get("is_dead") == true:
			_heard.erase(id)


## The live callouts heard, latest per speaker, in the shape `AgentEntry.claims` reads: the data with `age`, `id`, `name`.
func _callouts() -> Array:
	var out: Array = []
	for id in _heard:
		var rec: Dictionary = _heard[id]
		var c: Dictionary = (rec["data"] as Dictionary).duplicate()
		c["age"] = _clock - rec["at"]
		c["id"] = id
		c["name"] = str(c["speaker"].name)
		out.append(c)
	return out


## Reserve the first free slot at the nearest doorway near the human where an allied team is stacking up.
func _look_for_team() -> void:
	var calls := _callouts()
	var map: RID = _char.get_world_2d().navigation_map
	var space: PhysicsDirectSpaceState2D = _char.get_world_2d().direct_space_state
	var best := {}
	var best_dist := INF
	var tried := {}
	var stacking_now := {}
	for c in calls:
		var id := str(c.get("opening", ""))
		if id == "" or tried.has(id):
			continue
		tried[id] = true
		var team := AgentEntry.claims(id, calls)
		if not team.any(func(m): return STACKING.has(m["step"])):
			continue
		stacking_now[id] = true
		if _barred.has(id):
			continue
		var geo: Dictionary = _entry.geometry(id, str(c.get("into", "")), map, space)
		if geo.is_empty():
			continue
		var dist := _walk_distance(geo["pos"])
		if dist <= reserve_range and dist < best_dist:
			best_dist = dist
			best = { "id": id, "into": str(c.get("into", "")), "geo": geo, "team": team }
	for id in _barred.keys():
		if not stacking_now.has(id):
			_barred.erase(id)   # Their stack is over: a later one is a new offer.
	if best.is_empty():
		return
	_opening = best["id"]
	_into = best["into"]
	_geo = best["geo"]
	_slot = AgentEntry.free_slot(best["team"], _char.get_instance_id(), 0)
	_side = AgentEntry.stack_side(_geo, best["team"], _char.global_position)
	_step = "claim"
	_ahead_through_at = -1.0
	_in_at = -1.0
	_post(_step)


## Walking distance (px) from the human to `to` over the baked map; the straight line before it is baked.
func _walk_distance(to: Vector2) -> float:
	var from := _char.global_position
	var straight := from.distance_to(to)
	var map: RID = _char.get_world_2d().navigation_map
	if straight > reserve_range * leave_factor or not NavBuilder.ready(map):
		return straight
	return NavBuilder.path_length(NavBuilder.route(map, from, to))


## One tick of a held reservation: leave it, follow the radio, and say where the human stands. `due` is true on the ticks
## that may afford a path query.
func _keep_reservation(delta: float, due: bool) -> void:
	if _char.get("is_dead") == true:
		_withdraw("abort")
		return
	var calls := _callouts()
	var team := AgentEntry.claims(_opening, calls)
	var self_id := _char.get_instance_id()
	var pos := _char.global_position
	if due and _step != "in" and _walk_distance(_geo["pos"]) > reserve_range * leave_factor:
		_withdraw("abort")
		return
	if not team.any(func(m): return STACKING.has(m["step"]) or m["step"] == "in"):
		_withdraw("abort" if _step != "in" else "done")   # Nobody is stacking here any more.
		return
	if _step != "in":
		var was := _slot
		_slot = AgentEntry.free_slot(team, self_id, _slot)   # An AI with a lower instance id that claimed the same slot keeps it.
		_side = AgentEntry.stack_side(_geo, team, pos)
		if _slot != was:
			_post(_step)
	var ahead := team.filter(func(m): return m["slot"] < _slot)
	var ahead_through: bool = ahead.all(func(m): return THROUGH.has(m["step"]))
	if ahead_through and _ahead_through_at < 0.0:
		_ahead_through_at = _clock
	elif not ahead_through:
		_ahead_through_at = -1.0
	if _step in ["claim", "ready"] and _ahead_through_at >= 0.0 and _clock - _ahead_through_at >= go_timeout:
		_barred[_opening] = true   # It had its chance at this stack.
		_withdraw("abort")
		return
	var now := _step_at(pos)
	if now != _step:
		_step = now
		if _step == "in":
			_in_at = _clock
		_post(_step)
	if _step == "in":
		var waiting := team.any(func(m): return m["slot"] > _slot and STACKING.has(m["step"]) and m["step"] != "going_in")
		var held := _clock - _in_at
		if held >= IN_HOLD_MAX or (held >= IN_HOLD_MIN and not waiting):
			_barred[_opening] = true
			_withdraw("done")
			return
	_heartbeat -= delta
	if _heartbeat <= 0.0:
		_post(_step)


## The radio step for the human standing at `pos`: through the doorway (and it stays so), in the doorway's funnel, in its
## slot, or still on its way.
func _step_at(pos: Vector2) -> String:
	if _step == "in":
		return "in"
	var door: Vector2 = _geo["pos"]
	var out: Vector2 = _geo["out"]
	var outward := (pos - door).dot(out)
	var lateral := absf((pos - door).dot(out.orthogonal()))
	if outward < -THROUGH_DEPTH and lateral < float(_geo["width"]) * 0.5 + THROUGH_DEPTH:
		return "in"
	if absf(outward) < FUNNEL_DEPTH and lateral < float(_geo["width"]) * 0.5:
		return "going_in"
	var spot := AgentEntry.slot_point(_geo, _side, _slot)
	var d := pos.distance_to(spot)
	if d <= SLOT_REACH or (_step == "ready" and d <= SLOT_REACH * 2.0):
		return "ready"
	return "claim"


## Give the reservation up, telling the radio (`abort`: dropped; `done`: went through and moved on).
func _withdraw(how: String) -> void:
	_post(how)
	_opening = ""
	_into = ""
	_geo = {}
	_slot = 0
	_side = 0
	_step = ""
	_ahead_through_at = -1.0
	_in_at = -1.0


## Radio the human's step as a `callout` (the same fields the NPCs' entry steps carry) and restart the heartbeat.
func _post(step: String) -> void:
	_heartbeat = HEARTBEAT
	var pos := _char.global_position
	EventBus.post(&"callout", {
		"speaker": _char,
		"faction": _char.get("faction"),
		"position": pos,
		"status": "",
		"path": "",
		"label": "stacking up (%s)" % step.replace("_", " "),
		"target_id": 0,
		"point": pos,
		"opening": _opening,
		"into": _into,
		"slot": _slot,
		"side": _side,
		"entry_step": step,
		"cleared_room": "",
		"covering": "",
	})

extends Node

## AI domain · TEAM — one side's squad (`docs/leadership.md` LD3 to LD7): its roster, its leader, the line of succession and the
## orders its leader gives. Main builds one per faction under the match's `World` node (`setup`, after arming the characters) and
## hands each NPC its squad (`MatchSpawner.bind_squad`).
##
## **The leader (LD3).** The member of the highest `rank`, the first in spawn order among equals: the invaders' unit lead (rank 2),
## and, a defenders' crew carrying no rank, its first spawned. A squad the human leads (`setup`'s `human`) is led by the human.
## **Succession (LD4).** When the leader dies, the next in line by the same rule leads at once and the squad posts `&"leader"`
## `{ faction, leader, previous }` (interface 10). The orders already given stand; a later order replaces them.
##
## **Orders (LD5).** `issue(request)` turns what a leader asks for (`{ kind, to, pos?, room?, bang? }`, the command menu's plain dict)
## into an order in the AI's terms and posts it as `&"order"` `{ id, leader, faction, to, kind, ... }`: `defend_room` names its `room`
## (a key, or the room under `pos`); `stack` names the doorway nearest `pos` within its width (`opening`) and the room it goes into
## (`into`), the stack forming on the side of the wall plane `pos` lies on (an exterior door always goes into the house), on the side of
## the door `pos` lies on along the wall (`stack_at`, the click) or, for a click on the opening itself, both (`split`), quiet or with a
## stun (`bang`); `cancel` ends what the recipients were told. A `defend_room` or `stack` order also carries its target point, `pos`
## (the room's centre, the doorway's), which the order markers draw. No `to` means every living member but the leader. Range is unlimited:
## the recipients take it off the bus, wherever they are. `resolve(request)` is the same resolution, read-only (the command menu's labels).
##
## **Progress (LD7).** The members radio how their order goes (`&"callout"` with `order_id` and `order_step`: moving, in_position,
## done, refused); the squad keeps each one's latest step for `view()`, which the order markers draw. A done order is no longer held. It reads its members only
## through the Character API (`rank`, `is_dead`, `died`) and the bus, never an NPC's brain.

const AgentEntry := preload("res://scenes/ai/perception/agent_entry.gd")

## The order kinds.
const DEFEND := "defend_room"
const STACK := "stack"
const CANCEL := "cancel"

var _faction: StringName = &""  ## The side this squad is (its members' `faction`).
var _members: Array = []          ## The roster, in spawn order (the human leader among them when it leads).
var _openings: Array = []         ## The house's doorways (`WorldGen.get_openings`).
var _rooms: Array = []            ## The house's rooms (`WorldGen.get_rooms`).
var _leader: Node = null          ## Who leads now (LD3, LD4); null when nobody is left.
var _human: Node = null           ## The human leader, when the human leads (it keeps the lead while it lives).
var _orders := {}                 ## Member instance id -> the order it holds (the posted dict).
var _steps := {}                  ## Member instance id -> the latest `order_step` it radioed about that order.
var _issued := 0                  ## Orders posted so far (each order's id counts on from it).


## Set the squad up: `faction`, its members (`roster`) in spawn order, the house's `openings` and `rooms`, and the `human` when the
## human leads (null: the leader is the rule's). Listens to each member's `died` and to the radio from here on.
func setup(faction: StringName, roster: Array, openings: Array, rooms: Array, human: Node = null) -> void:
	_faction = faction
	_members = roster.filter(func(m): return m is Node and is_instance_valid(m))
	_openings = openings
	_rooms = rooms
	_human = human if human != null and _members.has(human) else null
	for m: Node in _members:
		if m.has_signal(&"died"):
			m.died.connect(_on_died.bind(m))
	if not EventBus.posted.is_connected(_on_event):
		EventBus.posted.connect(_on_event)
	_leader = _next_leader()


## The squad's leader (null when every member is dead).
func leader() -> Node:
	return _leader


## Every member, in spawn order, the dead included.
func members() -> Array:
	return _members.duplicate()


## Whether `member` is a living member of this squad.
func alive(member: Node) -> bool:
	return _members.has(member) and is_instance_valid(member) and member.get("is_dead") != true


## What the squad looks like now, for observers (the order markers, the command menu): `{ leader, members: [{ node, order, step }] }`,
## `order` being the order the member holds ({} for none, and once it is done) and `step` its latest progress on it ("" for none;
## `done` with no order held once it is done).
func view() -> Dictionary:
	var rows: Array = []
	for m: Node in _members:
		if not is_instance_valid(m):
			continue
		var id := m.get_instance_id()
		rows.append({ "node": m, "order": _orders.get(id, {}), "step": _steps.get(id, "") })
	return { "leader": _leader, "members": rows }


## Turn a leader's request (`{ kind, to, pos?, room?, bang? }`) into an order and post it as `&"order"`. Returns the order posted, or {}
## when there is nothing to post (no living recipient, an unknown room or doorway, an unknown kind).
func issue(request: Dictionary) -> Dictionary:
	var to: Array = []
	for m in request.get("to", []):
		if m is Node and alive(m) and not to.has(m):
			to.append(m)
	if (request.get("to", []) as Array).is_empty():
		to = _members.filter(func(m): return alive(m) and m != _leader)
	if to.is_empty():
		return {}
	var kind := String(request.get("kind", ""))
	var order := { "leader": _leader, "faction": _faction, "to": to, "kind": kind }
	match kind:
		DEFEND, STACK:
			var at := resolve(request)
			if at.is_empty():
				return {}
			order.merge(at)
			if kind == STACK:
				order["bang"] = bool(request.get("bang", false))
		CANCEL:
			pass
		_:
			return {}
	_issued += 1
	order["id"] = "%s_%d" % [_faction, _issued]
	for m: Node in to:
		var id := m.get_instance_id()
		if kind == CANCEL:
			_orders.erase(id)
		else:
			_orders[id] = order
		_steps.erase(id)
	EventBus.post(&"order", order)
	return order


## What a leader's request names in the AI's terms, the way `issue` posts it, without posting anything (read-only): for `defend_room`
## `{ room, pos }` (the room key, its centre), for `stack` `{ opening, pos, into, split, stack_at? }` (the doorway, its centre, the room
## it goes into, the side, D3); {} when it names nothing (an unknown room, no doorway near `pos`, another kind). The command menu names
## the room a stack goes into from it, so its label and the order agree.
func resolve(request: Dictionary) -> Dictionary:
	match String(request.get("kind", "")):
		DEFEND:
			var room := _room_for(request)
			return {} if room == "" else { "room": room, "pos": _rect_of(room).get_center() }
		STACK:
			var pos = request.get("pos")
			return _door_for(pos) if pos is Vector2 else {}
	return {}


## The room a defend request names: its `room` key, else the room under its `pos`; "" when neither is a room of the house.
func _room_for(request: Dictionary) -> String:
	var key := String(request.get("room", ""))
	for r in _rooms:
		if key != "" and String(r["key"]) == key:
			return key
	var pos = request.get("pos")
	if pos is Vector2:
		for r in _rooms:
			if (r["rect"] as Rect2).has_point(pos):
				return String(r["key"])
	return ""


## Where a click at `pos` stacks (D3): the doorway nearest it within its width (`opening`, and its centre as the order's `pos`), the room
## it goes into (`into`: the room on the far side of the wall plane from the click, the house's room for an exterior door), and the side
## of the door: `split` for a click on the opening itself (within its half-width along the wall), else `stack_at`, the click, whose side
## along the wall the stack forms on. {} when no doorway is that near.
func _door_for(pos: Vector2) -> Dictionary:
	if pos == Vector2.INF:
		return {}
	var best := {}
	for o in _openings:
		var d := pos.distance_to(o["pos"])
		if d <= float(o.get("width", 80.0)) and (best.is_empty() or d < pos.distance_to(best["pos"])):
			best = o
	if best.is_empty():
		return {}
	var joins: Array = (best.get("rooms", []) as Array).map(func(k): return String(k))
	if joins.is_empty():
		return {}
	var door: Vector2 = best["pos"]
	var into: String = joins[0]
	var first := _rect_of(joins[0])
	var into_first := AgentEntry.normal_into(first, door)
	if joins.size() == 2 and (pos - door).dot(into_first) > 0.0:
		into = joins[1]  # The click is on the first room's side of the wall: the stack forms there and goes into the other.
	var along := into_first.orthogonal()
	var out := { "opening": AgentEntry.opening_id(best), "pos": door, "into": into, "split": absf((pos - door).dot(along)) <= float(best.get("width", 80.0)) * 0.5 }
	if not out["split"]:
		out["stack_at"] = pos
	return out


## The rect of room `key`, or an empty Rect2.
func _rect_of(key: String) -> Rect2:
	for r in _rooms:
		if String(r["key"]) == key:
			return r["rect"]
	return Rect2()


## The leader by the rule (LD3): the human while it leads and lives; else the living member of the highest `rank`, the first in spawn
## order among equals; null when nobody is left.
func _next_leader() -> Node:
	if _human != null and alive(_human):
		return _human
	var best: Node = null
	for m: Node in _members:
		if alive(m) and (best == null or int(m.get("rank")) > int(best.get("rank"))):
			best = m
	return best


## A member died (LD4): when it led, the next in line leads now, and the squad says so on the bus. Its own order is dropped.
func _on_died(member: Node) -> void:
	_orders.erase(member.get_instance_id())
	if member != _leader:
		return
	var previous := _leader
	_leader = _next_leader()
	EventBus.post(&"leader", { "faction": _faction, "leader": _leader, "previous": previous })


## The radio (LD7): a member's progress on the order it holds (`order_id`, `order_step`) is kept as its latest step. An order radioed
## `done` is no longer held (the step `done` stays, the order goes), so nothing offers to cancel it; a `refused` one is still held.
func _on_event(topic: StringName, data: Dictionary) -> void:
	if topic != &"callout":
		return
	var step := String(data.get("order_step", ""))
	var speaker = data.get("speaker")
	if step == "" or not speaker is Node or not is_instance_valid(speaker):
		return
	var id: int = speaker.get_instance_id()
	var held: Dictionary = _orders.get(id, {})
	if not held.is_empty() and str(held.get("id", "")) == str(data.get("order_id", "")):
		_steps[id] = step
		if step == "done":
			_orders.erase(id)

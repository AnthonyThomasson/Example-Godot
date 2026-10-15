extends RefCounted

## AI PERCEPTION sub-domain — SUSPICION. Why the NPC suspects a hostile is waiting in a room (`docs/grenades.md` G18): the facts
## behind a bang entry, read off the event memory, the lost hostiles and the allies' radio. A pure read; it holds no state and words
## nothing (the snapshot turns each reason into its phrase, `SnapshotOptions`; the behaviour's entry reads whether a new one has come
## up since it began, `docs/tactical-entry.md` E17). Owned by `agent_perception.gd`, shared with the snapshot author.

## The reasons, in the order the snapshot words them.
const GUNFIRE := &"gunfire"          ## Gunfire it heard came from inside the room (`heard_gunfire`).
const FOOTSTEPS := &"footsteps"      ## A stranger's footsteps it heard there (`heard_footsteps`, `docs/hearing.md` H1).
const SHOT_FROM := &"shot_from"      ## The line back from a shot at it runs through the room (`shot_from`, `shot_line`).
const ALLY_FIGHT := &"ally_fight"    ## An ally's combat call puts its hostile (`target_pos`) in the room.
const SEEN_IN := &"seen_in"          ## A hostile it lost sight of was last seen in the room.
const LOST_BY_DOOR := &"lost_by_door"  ## ... lost outside it, within `LOST_NEAR_DOOR` of one of its doorways.
const HEADING_IN := &"heading_in"    ## ... lost moving, and where it was heading lies in the room.
const ORDER := [GUNFIRE, FOOTSTEPS, SHOT_FROM, ALLY_FIGHT, SEEN_IN, LOST_BY_DOOR, HEADING_IN]

## A hostile lost outside a room within this many px of one of its doorways makes the room suspect.
const LOST_NEAR_DOOR := 150.0
## The line back from a shot (`shot_line`) starts this many px past the edge of the room it landed in, so the room beyond that edge,
## not the one it shares the edge with, is the first it runs through.
const LEAVE_STEP := 1.0

var memory: RefCounted       ## The event memory (read-only); see agent_memory.gd.
var entry: RefCounted        ## The doorway geometry (`room_doorways`); see agent_entry.gd.
var still_speed := 20.0      ## A lost hostile slower than this (px/s) was not heading anywhere.
var extrapolate_cap := 3.0   ## Most seconds its last-seen velocity is carried forward to where it was heading.


## Every suspect room: room key -> its reasons (`ORDER`), from the memory, the lost hostiles `lost` (`AgentPerception.lost_hostiles()`)
## and the live ally `callouts` heard.
func rooms_suspected(rooms: Array, lost: Array, callouts: Array) -> Dictionary:
	var out := {}
	var add := func(key: String, why: StringName) -> void:
		if key == "":
			return
		var list: Array = out.get(key, [])
		if not list.has(why):
			list.append(why)
		out[key] = list
	for data in memory.recall_all(&"heard_gunfire"):
		add.call(room_key_at(rooms, data["pos"]), GUNFIRE)
	for data in memory.recall_all(&"heard_footsteps"):
		add.call(room_key_at(rooms, data["pos"]), FOOTSTEPS)
	for data in memory.recall_all(&"shot_from"):
		for key in shot_rooms(rooms, data):
			add.call(key, SHOT_FROM)
	for c in callouts:
		if str(c.get("path", "")).begins_with("combat"):
			add.call(room_key_at(rooms, c.get("target_pos", Vector2.INF)), ALLY_FIGHT)
	for c in lost:
		var by := lost_rooms(rooms, c)
		for key in by:
			add.call(key, by[key])
	for key in out:
		out[key].sort_custom(func(x, y): return ORDER.find(x) < ORDER.find(y))
	return out


## The rooms a lost hostile `c` (a contact dict: `pos`, `vel`, `age`) makes suspect, room key -> reason: the room it was last seen in
## (`SEEN_IN`), else each room whose doorway it was lost by, outside it (`LOST_BY_DOOR`), and the room where it was heading, when it was
## moving (`HEADING_IN`; reckoned as the "where they were heading" lead does).
func lost_rooms(rooms: Array, c: Dictionary) -> Dictionary:
	var out := {}
	var pos: Vector2 = c["pos"]
	var key := room_key_at(rooms, pos)
	if key != "":
		out[key] = SEEN_IN
	for room in rooms:
		var k := str(room["key"])
		if k == key or out.has(k):
			continue
		if entry.room_doorways(k).any(func(d): return (d["pos"] as Vector2).distance_to(pos) <= LOST_NEAR_DOOR):
			out[k] = LOST_BY_DOOR
	var vel: Vector2 = c.get("vel", Vector2.ZERO)
	if vel.length() >= still_speed:
		var ahead := room_key_at(rooms, pos + vel * minf(c["age"], extrapolate_cap))
		if ahead != "" and ahead != key and not out.has(ahead):
			out[ahead] = HEADING_IN
	return out


## The rooms the shots at the NPC came from: those the line back from a shot (`shot_line`) runs through.
static func shot_rooms(rooms: Array, shot: Dictionary) -> Array:
	var out: Array = []
	var line := shot_line(rooms, shot)
	for room in rooms:
		var r: Rect2 = room["rect"]
		var poly := PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)])
		if not Geometry2D.intersect_polyline_with_polygon(line, poly).is_empty():
			out.append(str(room["key"]))
	return out


## The part of the line back from a shot at the NPC (`shot_from`: from where it landed, `at`, to the wall behind, `pos`) the shooter
## stood on: from where it leaves the room it landed in, which is only where the NPC stood (a shot from another room came in through a
## doorway, and the room behind that doorway is the shooter's). The whole line when it landed in no room, or never leaves that room (the
## shooter stood in the room with the NPC).
static func shot_line(rooms: Array, shot: Dictionary) -> PackedVector2Array:
	var at: Vector2 = shot["at"]
	var end: Vector2 = shot["pos"]
	var landed := Rect2()
	for room in rooms:
		if (room["rect"] as Rect2).has_point(at):
			landed = room["rect"]
			break
	var dir := (end - at).normalized()
	if not landed.has_area() or landed.has_point(end) or dir == Vector2.ZERO:
		return PackedVector2Array([at, end])
	# How far along the line it crosses the landed room's edge: the nearer of the two edges it heads for.
	var leave := INF
	if dir.x != 0.0:
		leave = minf(leave, ((landed.end.x if dir.x > 0.0 else landed.position.x) - at.x) / dir.x)
	if dir.y != 0.0:
		leave = minf(leave, ((landed.end.y if dir.y > 0.0 else landed.position.y) - at.y) / dir.y)
	return PackedVector2Array([at + dir * (leave + LEAVE_STEP), end])


## The key of the room world point `p` lies in, or "".
static func room_key_at(rooms: Array, p: Vector2) -> String:
	if p == Vector2.INF:
		return ""
	for room in rooms:
		if (room["rect"] as Rect2).has_point(p):
			return str(room["key"])
	return ""

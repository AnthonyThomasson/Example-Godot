extends RefCounted

## AI PERCEPTION sub-domain — ENTRY GEOMETRY. What an NPC knows about getting through a doorway into a room
## (`docs/tactical-entry.md`): for each opening of the house, entered into one of the rooms it joins, the door's
## frame (its outward normal and the axis along its wall), the stack slots in single file against the wall on
## either side, the pie arc a point man sweeps from, and the four corners of the room behind, each tagged hard
## (unseen from just outside the threshold) or soft. Plus the team's claims on an opening, read off allies'
## radio callouts (the same claim pattern as a flank side, `agent_tactics.side_holder`).
##
## Pure geometry over the house's openings (Main's `WorldGen.get_openings`, injected), its rooms, the nav map
## (slots and pie points are snapped onto it) and sight rays (via the vision sense). The walls never move, so
## an opening's geometry is built once, the first time it is asked for on a baked map, and kept. No policy: it
## never decides which door, which slot or when to go.

## How far (px) outside the threshold the "entry point" is that a corner is judged hard or soft from.
const SnapshotVocab := preload("res://scenes/ai/perception/snapshot/snapshot_vocab.gd")
const ENTRY_POINT_DEPTH := 24.0
## Slots worked out per side: a fuller team queues in the last one.
const MAX_SLOTS := 6
## How many bodies go into a room too small for the team (`short_room`): the point and the second, who take its corners.
const SHORT_ROOM_CAPACITY := 2
## How far (px) `threshold_ahead` extends the end of a walk, so a destination in the doorway itself crosses it.
const THRESHOLD_EXTEND := 30.0
## How far (px) past the doorway's width a step may cross the wall plane and still count as through it.
const THRESHOLD_SLACK := 8.0
## How far (px) out from a doorway's wall a walk may pass it and still count as passing it: a corridor's width, not a room's.
const PASS_DEPTH := 150.0

var vision: RefCounted                ## The perception's sight sense (sight rays over low cover).
var stack_spacing: float = 44.0       ## Distance (px) between neighbouring stack slots: clear of a neighbour's footprint.
var wall_standoff: float = 28.0       ## Distance (px) of a stack slot off the wall's centreline.
var pie_radius: float = 100.0         ## Distance (px) from the threshold of the pie arc a point man sweeps from.
var pie_steps: int = 5                ## Points on the pie arc (angle steps).
var corner_inset: float = 40.0        ## Inset (px) of a corner point from the room's two walls.
var short_room: float = 150.0         ## A room with a side under this (px) is too small for the team: two go in (E13).

var _openings: Array = []             ## The house's doorways (`{ pos, width, front, exit, rooms }`), as injected.
var _rooms: Array = []                ## The house's rooms (`{ key, type, rect }`).
var _cache := {}                      ## "<opening id>><room key>" -> the geometry of that entry.


## Hand in the house: its doorways and rooms. Forgets the cached geometry when they changed.
func set_house(openings: Array, rooms: Array) -> void:
	if openings == _openings and rooms == _rooms:
		return
	_openings = openings
	_rooms = rooms
	_cache.clear()


## The stable id of doorway `o` ("door_<x>_<y>", its rounded world position): what the snapshot's options, the
## behaviour and the radio call it.
static func opening_id(o: Dictionary) -> String:
	var p: Vector2 = o["pos"]
	return "door_%d_%d" % [roundi(p.x), roundi(p.y)]


## The doorways an NPC standing in room `here_key` ("" = outside) can go through into a room: an outer door from
## outside, any door of its room into the room on the far side. Each `{ id, into, pos, width, front }`.
func entries_from(here_key: String) -> Array:
	var out: Array = []
	for o in _openings:
		var joins: Array = o.get("rooms", [])
		var into := ""
		if here_key == "" and joins.size() == 1:
			into = str(joins[0])
		elif here_key != "" and joins.size() == 2 and here_key in joins.map(func(k): return str(k)):
			into = str(joins[0]) if str(joins[1]) == here_key else str(joins[1])
		if into == "":
			continue
		out.append({ "id": opening_id(o), "into": into, "pos": o["pos"], "width": float(o.get("width", 80.0)),
			"front": bool(o.get("front", false)) })
	return out


## Every doorway of room `room_key`, outer doors (to outside) included: where something can come from. Each
## `{ id, pos, width }`, in the order the house lists them. A resting NPC watches these (`Watch.idle_gaze`).
func room_doorways(room_key: String) -> Array:
	var out: Array = []
	for o in _openings:
		if room_key in (o.get("rooms", []) as Array).map(func(k): return str(k)):
			out.append({ "id": opening_id(o), "pos": o["pos"], "width": float(o.get("width", 80.0)) })
	return out


## The doorways out of room `room_key` (one already cleared) that lead on into another room that `is_cleared` (a Callable
## on the room key) says is not cleared, other than doorway `exclude_id` (the one the NPC came in by). Doors to outside
## are left out. Each `{ id, into, pos, width }`. What the team covers once it has cleared a room (E8).
func watch_doors(room_key: String, exclude_id: String, is_cleared: Callable) -> Array:
	return entries_from(room_key).filter(func(e): return e["id"] != exclude_id and not is_cleared.call(e["into"]))


## The first doorway on a walk that leads into a room the NPC has not cleared: the polyline from `from_pos` through the
## waypoints of `path` from `from_idx` on, as far as `max_dist` px of walking. A doorway counts when a step of the walk
## crosses its wall plane within the doorway's width, heading into a room that is not the one the NPC is in and that
## `is_cleared` (a Callable on the room key) says is not cleared. The walk's last step is extended by a body's length, so
## a destination that is the doorway itself crosses it. `{ opening, into, dist }` (`dist` = px of walking to it), or {}.
## Used by the behaviour's entry guard (E9): any walk, not only the ENTER order, goes in by the entry.
func threshold_ahead(path: PackedVector2Array, from_idx: int, from_pos: Vector2, is_cleared: Callable, max_dist: float) -> Dictionary:
	var pts: Array = [from_pos]
	for i in range(maxi(from_idx, 0), path.size()):
		pts.append(path[i])
	if pts.size() < 2:
		return {}
	var tail: Vector2 = (pts[-1] as Vector2) - (pts[-2] as Vector2)
	if tail.length() > 0.001:
		pts.append((pts[-1] as Vector2) + tail.normalized() * THRESHOLD_EXTEND)
	var here := str(SnapshotVocab.room_at(from_pos, _rooms).get("key", ""))
	var walked := 0.0
	for i in range(1, pts.size()):
		var a: Vector2 = pts[i - 1]
		var b: Vector2 = pts[i]
		var best := {}
		for o in _openings:
			var pos: Vector2 = o["pos"]
			for key in o.get("rooms", []):
				var into := str(key)
				if into == here or is_cleared.call(into):
					continue
				var room := _room_rect(into)
				if room.size == Vector2.ZERO:
					continue
				var inward := _inward(room, pos)
				var sa := (a - pos).dot(inward)
				var sb := (b - pos).dot(inward)
				if sa >= 0.0 or sb < 0.0:
					continue  # Not a step from outside the wall plane to its far side.
				var q := a + (b - a) * (-sa / (sb - sa))
				if absf((q - pos).dot(inward.orthogonal())) > float(o.get("width", 80.0)) * 0.5 + THRESHOLD_SLACK:
					continue
				var d := walked + a.distance_to(q)
				if best.is_empty() or d < best["dist"]:
					best = { "opening": opening_id(o), "into": into, "dist": d }
		if not best.is_empty():
			return best if best["dist"] <= max_dist else {}
		walked += a.distance_to(b)
		if walked > max_dist:
			break
	return {}


## The first doorway a walk goes past without entering (E15): the walk crosses its axis (the line out from its centre) within
## `PASS_DEPTH` px of its wall, outside it, within `max_dist` px of walking. It leads into a room that is not the NPC's own and
## not cleared, and the walk never crosses its wall plane (that doorway is `threshold_ahead`'s). Only doors between two rooms of
## the house, from inside it. `{ opening, into, dist }` (`dist` = px of walking until abreast of it), or {}.
func passing_ahead(path: PackedVector2Array, from_idx: int, from_pos: Vector2, is_cleared: Callable, max_dist: float) -> Dictionary:
	var pts: Array = [from_pos]
	for i in range(maxi(from_idx, 0), path.size()):
		pts.append(path[i])
	if pts.size() < 2:
		return {}
	var here := str(SnapshotVocab.room_at(from_pos, _rooms).get("key", ""))
	if here == "":
		return {}
	var candidates: Array = []
	for o in _openings:
		var joins: Array = o.get("rooms", [])
		if joins.size() != 2:
			continue
		for key in joins:
			var into := str(key)
			if into == here or is_cleared.call(into):
				continue
			var room := _room_rect(into)
			if room.size == Vector2.ZERO:
				continue
			var pos: Vector2 = o["pos"]
			var inward := _inward(room, pos)
			if _walk_enters(pts, pos, inward, float(o.get("width", 80.0))):
				continue
			candidates.append({ "opening": opening_id(o), "into": into, "pos": pos, "out": -inward })
	var walked := 0.0
	for i in range(1, pts.size()):
		var a: Vector2 = pts[i - 1]
		var b: Vector2 = pts[i]
		var best := {}
		for c in candidates:
			var pos: Vector2 = c["pos"]
			var out: Vector2 = c["out"]
			var along := out.orthogonal()
			var la := (a - pos).dot(along)
			var lb := (b - pos).dot(along)
			if la * lb >= 0.0:
				continue  # Not a step across the doorway's axis.
			var q := a + (b - a) * (la / (la - lb))
			var depth := (q - pos).dot(out)
			if depth <= 0.0 or depth > PASS_DEPTH:
				continue
			var d := walked + a.distance_to(q)
			if best.is_empty() or d < best["dist"]:
				best = { "opening": c["opening"], "into": c["into"], "dist": d }
		if not best.is_empty():
			return best if best["dist"] <= max_dist else {}
		walked += a.distance_to(b)
		if walked > max_dist:
			break
	return {}


## Whether the walk `pts` crosses the wall plane of a doorway at `pos` (into the room that lies along `inward`) within its width:
## it goes in by it somewhere.
func _walk_enters(pts: Array, pos: Vector2, inward: Vector2, width: float) -> bool:
	for i in range(1, pts.size()):
		var a: Vector2 = pts[i - 1]
		var b: Vector2 = pts[i]
		var sa := (a - pos).dot(inward)
		var sb := (b - pos).dot(inward)
		if sa >= 0.0 or sb < 0.0:
			continue
		var q := a + (b - a) * (-sa / (sb - sa))
		if absf((q - pos).dot(inward.orthogonal())) <= width * 0.5 + THRESHOLD_SLACK:
			return true
	return false


## The rect of room `key`, or an empty Rect2.
func _room_rect(key: String) -> Rect2:
	return SnapshotVocab.room_by_key(_rooms, key).get("rect", Rect2())


## The geometry of going through opening `id` into room `into`, or {} when either is unknown. Built once on a
## baked nav map (`map`) and kept: { id, into, pos, width, out (unit normal away from the room), along (unit
## axis along the wall), wall: { 1: px, -1: px } (the room's wall either side of the door), side (the side with
## more wall to stack against, 0 when even), slots: { 1: [..], -1: [..] } (stack slots, nearest the door first),
## pie: { 1: [..], -1: [..] } (pie arc points, from the wall toward the axis), corners: [{ pos, near, side, hard }],
## room (the room's rect), capacity (how many may go in: 2 for a short room, else MAX_SLOTS) }.
func geometry(id: String, into: String, map: RID, space) -> Dictionary:
	var key := "%s>%s" % [id, into]
	if _cache.has(key):
		return _cache[key]
	var opening := {}
	for o in _openings:
		if opening_id(o) == id:
			opening = o
	var room := {}
	for r in _rooms:
		if str(r["key"]) == into:
			room = r
	if opening.is_empty() or room.is_empty():
		return {}
	var g := _build(opening, room, map, space)
	if NavBuilder.ready(map):
		_cache[key] = g  # Only keep what was snapped onto a baked map.
	return g


## Lay out one entry: the door's frame from the room edge it sits on, then slots, pie arc and corners.
func _build(opening: Dictionary, room: Dictionary, map: RID, space) -> Dictionary:
	var pos: Vector2 = opening["pos"]
	var width := float(opening.get("width", 80.0))
	var rect: Rect2 = room["rect"]
	var inward := _inward(rect, pos)
	var out := -inward
	var along := out.orthogonal()
	var wall := { 1: _wall_length(rect, pos, along), -1: _wall_length(rect, pos, -along) }
	var side := 0
	if absf(wall[1] - wall[-1]) >= 1.0:
		side = 1 if wall[1] > wall[-1] else -1
	var slots := {}
	var pie := {}
	for s in [1, -1]:
		var row: Array = []
		for k in MAX_SLOTS:
			var lateral := width * 0.5 + 18.0 + k * stack_spacing
			row.append(NavBuilder.snap(map, pos + out * wall_standoff + along * s * lateral))
		slots[s] = row
		var arc: Array = []
		var steps := maxi(pie_steps, 2)
		for i in steps:
			# From 55° off the door's axis (clear of the stack against the wall) toward it (25° off), on side `s`.
			var theta := deg_to_rad(lerpf(55.0, 25.0, float(i) / float(steps - 1)))
			arc.append(NavBuilder.snap(map, pos + out * cos(theta) * pie_radius + along * s * sin(theta) * pie_radius))
		pie[s] = arc
	var inset := minf(corner_inset, minf(rect.size.x, rect.size.y) * 0.25)
	var inner := rect.grow(-inset)
	var entry_point := pos + out * ENTRY_POINT_DEPTH
	var corners: Array = []
	var depth_max := -INF
	var raw := [inner.position, Vector2(inner.end.x, inner.position.y), inner.end, Vector2(inner.position.x, inner.end.y)]
	for c in raw:
		depth_max = maxf(depth_max, (c - pos).dot(out))
	for c in raw:
		var p := NavBuilder.snap(map, c)
		corners.append({
			"pos": p,
			"near": absf((c - pos).dot(out) - depth_max) < 1.0,  # On the door's own wall.
			"side": 1 if (c - pos).dot(along) >= 0.0 else -1,
			"hard": not _sees(space, entry_point, p),
		})
	return { "id": opening_id(opening), "into": str(room["key"]), "pos": pos, "width": width, "out": out,
		"along": along, "wall": wall, "side": side, "slots": slots, "pie": pie, "corners": corners, "room": rect,
		"capacity": SHORT_ROOM_CAPACITY if minf(rect.size.x, rect.size.y) < short_room else MAX_SLOTS }


## The unit normal pointing into `rect` from the edge door `pos` lies on (the nearest edge).
func _inward(rect: Rect2, pos: Vector2) -> Vector2:
	var edges := [
		[absf(pos.x - rect.position.x), Vector2.RIGHT],
		[absf(pos.x - rect.end.x), Vector2.LEFT],
		[absf(pos.y - rect.position.y), Vector2.DOWN],
		[absf(pos.y - rect.end.y), Vector2.UP],
	]
	edges.sort_custom(func(a, b): return a[0] < b[0])
	return edges[0][1]


## How much of the room's wall runs from door `pos` toward `dir` (to the room's corner on that side).
func _wall_length(rect: Rect2, pos: Vector2, dir: Vector2) -> float:
	if absf(dir.x) > 0.5:
		return (rect.end.x - pos.x) if dir.x > 0.0 else (pos.x - rect.position.x)
	return (rect.end.y - pos.y) if dir.y > 0.0 else (pos.y - rect.position.y)


## Whether the line `from` → `to` is clear for sight (over low cover; walls and tall furniture block it).
func _sees(space, from: Vector2, to: Vector2) -> bool:
	return vision == null or space == null or vision.can_see(from, to - from, to, space, [])


# --- The team, off the radio -------------------------------------------------------------------

## The allies' live claims on opening `id`, from the callouts heard (latest per speaker, see the perception's
## `_callouts()`): `{ id (speaker instance id), name, slot, side, step, covering, pos, age }`, lowest slot first
## (`covering` = the doorway a member holding the cleared room watches, with step `cover`; `bang` = it goes in with a stun thrown first, true
## for a member that says nothing of it, such as the human; `stuns` = how many stun grenades it carries). A member who aborted or is
## done with the doorway, or whose latest call is about something else, holds no claim.
static func claims(id: String, callouts: Array) -> Array:
	var out: Array = []
	for c in callouts:
		if str(c.get("opening", "")) != id:
			continue
		var step := str(c.get("entry_step", ""))
		if step == "" or step == "abort" or step == "done":
			continue
		out.append({ "id": c["id"], "name": c.get("name", ""), "slot": int(c.get("slot", 0)), "side": int(c.get("side", 0)),
			"step": step, "covering": str(c.get("covering", "")), "pos": c.get("position", Vector2.ZERO), "age": c.get("age", 0.0),
			"bang": bool(c.get("bang", true)), "stuns": int(c.get("stuns", 0)) })
	out.sort_custom(func(a, b): return a["slot"] < b["slot"] if a["slot"] != b["slot"] else a["id"] < b["id"])
	return out


## The lowest stack slot (1 = the point) not claimed by an ally in `team` (see `claims`). `self_id` is this NPC's
## instance id: when an ally claims the same slot, the lower instance id keeps it, so two members who claimed on
## the same frame settle on different slots.
static func free_slot(team: Array, self_id: int, current := 0) -> int:
	var taken := {}
	for m in team:
		taken[m["slot"]] = taken.get(m["slot"], []) + [m["id"]]
	if current > 0 and (not taken.has(current) or taken[current].all(func(other): return self_id < other)):
		return current
	var slot := 1
	while taken.has(slot):
		slot += 1
	return slot


## The side of the door (1 / -1 along its wall, see `geometry`) the team stacks on: the side with more wall to stack
## against; when both have the same, the side the point (the slot 1 claim in `team`) stacks on, else the side
## `self_pos` is on. Every member works it out the same way, so the stack forms on one side.
static func stack_side(g: Dictionary, team: Array, self_pos: Vector2) -> int:
	if int(g["side"]) != 0:
		return int(g["side"])
	for m in team:
		if m["slot"] == 1 and m["side"] != 0:
			return m["side"]
	return 1 if (self_pos - (g["pos"] as Vector2)).dot(g["along"]) >= 0.0 else -1


## Where stack slot `slot` (1 = nearest the door) stands on side `side`.
static func slot_point(g: Dictionary, side: int, slot: int) -> Vector2:
	var row: Array = g["slots"][side]
	return row[clampi(slot - 1, 0, row.size() - 1)]

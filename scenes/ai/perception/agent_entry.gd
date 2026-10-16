extends RefCounted

## AI PERCEPTION sub-domain — ENTRY GEOMETRY. What an NPC knows about getting through a doorway into a room
## (`docs/tactical-entry.md`): for each opening of the house, entered into one of the rooms it joins, the door's
## frame (its outward normal and the axis along its wall), the stack slots in single file against the wall on
## either side, the pie arc a point man sweeps from, and the four corners of the room behind, each tagged hard
## (unseen from just outside the threshold) or soft. Plus the team's claims on an opening, read off allies'
## radio callouts (the same claim pattern as a flank side, `agent_tactics.side_holder`).
##
## It also lays out each doorway's VIEW (`door_view`: the area outside it that someone inside the room sees through it) and, from the
## views of the doorways into rooms not clear for passing, the walk that keeps out of them (`walk_route`, `docs/tactical-entry.md` E18).
##
## Pure geometry over the house's openings (Main's `WorldGen.get_openings`, injected), its rooms, the nav map
## (slots and pie points are snapped onto it) and sight rays (via the vision sense). The walls never move, so
## an opening's geometry is built once, the first time it is asked for on a baked map, and kept. No policy: it
## never decides which door, which slot or when to go.

## How far (px) outside the threshold the "entry point" is that a corner is judged hard or soft from.
const SnapshotVocab := preload("res://scenes/ai/perception/snapshot/snapshot_vocab.gd")
const AgentVision := preload("res://scenes/ai/perception/agent_vision.gd")
const ENTRY_POINT_DEPTH := 24.0
## Slots worked out per side: a fuller team queues in the last one.
const MAX_SLOTS := 6
## How many bodies go into a room too small for the team (`short_room`): the point and the second, who take its corners.
const SHORT_ROOM_CAPACITY := 2
## How far (px) `threshold_ahead` extends the end of a walk, so a destination in the doorway itself crosses it.
const THRESHOLD_EXTEND := 30.0
## How far (px) past the doorway's width a step may cross the wall plane and still count as through it.
const THRESHOLD_SLACK := 8.0
## How far (px) off the wall plane a doorway view's rays start (clear of the wall's thickness), and how many rays one fan casts along
## each side edge of the view and across its far edge.
const VIEW_APEX_OUT := 8.0
const VIEW_SIDE_RAYS := 6
const VIEW_FAR_RAYS := 10
## How far (px) the door-avoiding route may end short of the point it was asked for before it counts as not reaching it.
const AVOID_REACH := 24.0
## A defend spot (`defend_spot`, `docs/leadership.md` D2): how far back from its doorway's wall (px) it is sought, at best `DEFEND_DEPTH`...
const DEFEND_DEPTHS := [60.0, 90.0, 120.0, 150.0]
const DEFEND_DEPTH := 100.0
## ... and how far along the wall past the doorway's jamb (px), at best `DEFEND_LATERAL`: off the doorway's axis, out of its funnel.
const DEFEND_LATERALS := [30.0, 50.0, 75.0, 100.0]
const DEFEND_LATERAL := 50.0
## Inset (px) of a defend spot from the room's walls (a body and half a wall), and the most a snap onto the navmesh may move it.
const DEFEND_INSET := 22.0
const DEFEND_SNAP := 10.0
## A spot within a body (px) of a doorway's width and closer than `DEFEND_FUNNEL_DEPTH` (px) to its wall stands in its fatal funnel.
const DEFEND_BODY := 14.0
const DEFEND_FUNNEL_DEPTH := 200.0
## Where (px into the room from the doorway's centre) a defender's sight line to its doorway ends.
const DEFEND_DOOR_IN := 8.0

var vision: RefCounted = AgentVision.new()  ## The sight sense (sight rays over low cover): the perception hands in its own.
var stack_spacing: float = 44.0       ## Distance (px) between neighbouring stack slots: clear of a neighbour's footprint.
var wall_standoff: float = 28.0       ## Distance (px) of a stack slot off the wall's centreline.
var pie_radius: float = 100.0         ## Distance (px) from the threshold of the pie arc a point man sweeps from.
var pie_steps: int = 5                ## Points on the pie arc (angle steps).
var corner_inset: float = 40.0        ## Inset (px) of a corner point from the room's two walls.
var short_room: float = 150.0         ## A room with a side under this (px) is too small for the team: two go in (E13).
var door_view_depth: float = 450.0    ## How far (px) out of a doorway its view reaches, along its edge rays (E18).
var door_avoid_ratio: float = 2.0     ## A walk round the views is taken when no longer than this many times the plain route...
var door_avoid_slack: float = 300.0   ## ... plus this many px.
var avoid_views := true               ## Whether a walk keeps out of doorway views at all (the controller's `entry_guard`, with `entry_enabled` or on an ordered stack's walk).
var pass_clear: Callable              ## Room key -> whether that room counts as safe to walk past (cleared lately enough, or on an ordered walk seen empty).

var _openings: Array = []             ## The house's doorways (`{ pos, width, front, exit, rooms }`), as injected.
var _rooms: Array = []                ## The house's rooms (`{ key, type, rect }`).
var _cache := {}                      ## "<opening id>><room key>" -> the geometry of that entry.
var _views := {}                      ## "<opening id>><room key>@<depth>" -> the view out of that doorway (a polygon).
var _avoided_frame := -1              ## The physics frame `avoided` last worked out its answer in, and for which room...
var _avoided_here := ""
var _avoided_exempt := ""
var _avoided_clear: Callable          ## ... with which `pass_clear` rule...
var _avoided_set := {}                ## ... and the answer: `{ key, holes, views }`.


## Hand in the house: its doorways and rooms. Forgets the cached geometry when they changed.
func set_house(openings: Array, rooms: Array) -> void:
	if openings == _openings and rooms == _rooms:
		return
	_openings = openings
	_rooms = rooms
	_cache.clear()
	_views.clear()
	_avoided_frame = -1


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


## Where member `nth` of `count` holds room `room_key` it was ordered to defend (`docs/leadership.md` LD8, D2), and what it watches: the
## members share out the room's doorways (sorted by id; member `nth` takes doorway `nth` mod their number, the extras doubling up on
## the other side of it), each standing back in the room off its doorway's axis, out of every doorway's fatal funnel, with a sight line
## to it and, where there is one, low furniture between (cover it sees over); a lone member takes the spot from which it sees the most
## doorways. `{ spot, door, door_pos, doors }`: `door` is the id of the doorway it keeps its gun on ("" for a lone member of a room with
## several: it turns among `doors`, the room's doorways), `door_pos` that doorway's centre (INF for none). {} for a room it does not know.
func defend_spot(room_key: String, nth: int, count: int, map: RID, space) -> Dictionary:
	var rect := _room_rect(room_key)
	if rect.size == Vector2.ZERO:
		return {}
	var doors := room_doorways(room_key)
	doors.sort_custom(func(a, b): return String(a["id"]) < String(b["id"]))
	if doors.is_empty():
		return { "spot": NavBuilder.snap(map, rect.get_center()), "door": "", "door_pos": Vector2.INF, "doors": doors }
	var lone := count <= 1 and doors.size() > 1
	var own: Dictionary = doors[posmod(nth, doors.size())]
	var round_no := int(float(nth) / float(doors.size()))
	var best := {}
	for d in (doors if lone else [own]):
		var pos: Vector2 = d["pos"]
		var width := float(d["width"])
		var into := normal_into(rect, pos)
		var along := into.orthogonal()
		var first := 1 if _wall_length(rect, pos, along) >= _wall_length(rect, pos, -along) else -1
		var wanted := first if round_no % 2 == 0 else -first
		for depth in DEFEND_DEPTHS:
			for lateral in DEFEND_LATERALS:
				for s in [1, -1]:
					var raw: Vector2 = pos + into * depth + along * s * (width * 0.5 + lateral)
					var c := _defend_candidate(rect, raw, doors, map, space)
					if c.is_empty():
						continue
					var score: float = absf(depth - DEFEND_DEPTH) + absf(lateral - DEFEND_LATERAL) + float(c["funnel"]) * 1000.0
					if lone:
						score -= float(c["sees"]) * 2000.0
					else:
						score += (0.0 if c["sees_door"].has(d["id"]) else 3000.0) + (0.0 if s == wanted else 400.0)
					score += 0.0 if c["cover"].has(d["id"]) or (lone and not c["cover"].is_empty()) else 300.0
					if best.is_empty() or score < float(best["score"]):
						best = { "score": score, "spot": c["spot"] }
	if best.is_empty():
		return { "spot": NavBuilder.snap(map, rect.get_center()), "door": "" if lone else String(own["id"]),
			"door_pos": Vector2.INF if lone else own["pos"], "doors": doors }
	return { "spot": best["spot"], "door": "" if lone else String(own["id"]), "door_pos": Vector2.INF if lone else own["pos"], "doors": doors }


## A candidate defend spot near `raw` (`defend_spot`): snapped onto the navmesh inside the room (dropped when the snap moves it off),
## with `funnel` (how many of the room's `doors` it stands in the fatal funnel of), `sees` / `sees_door` (the doorways it has a sight line
## to, how many and which) and `cover` (the ids of those with low furniture on the line, which it sees over). {} when it is no spot.
func _defend_candidate(rect: Rect2, raw: Vector2, doors: Array, map: RID, space) -> Dictionary:
	var inner := rect.grow(-DEFEND_INSET)
	if not inner.has_point(raw):
		return {}
	var p := NavBuilder.snap(map, raw)
	if p.distance_to(raw) > DEFEND_SNAP or not inner.has_point(p):
		return {}
	var funnel := 0
	var sees: Dictionary = {}
	var cover: Dictionary = {}
	for d in doors:
		var pos: Vector2 = d["pos"]
		var into := normal_into(rect, pos)
		var off := p - pos
		if absf(off.dot(into.orthogonal())) < float(d["width"]) * 0.5 + DEFEND_BODY and off.dot(into) < DEFEND_FUNNEL_DEPTH:
			funnel += 1
		var aim := pos + into * DEFEND_DOOR_IN
		if _sees(space, p, aim):
			sees[d["id"]] = true
			var hit: Dictionary = vision.raycast(space, p, aim, []) if vision != null and space != null else {}
			if hit.get("collider") is RigidBody2D:
				cover[d["id"]] = true
	return { "spot": p, "funnel": funnel, "sees": sees.size(), "sees_door": sees, "cover": cover }


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
				var inward := normal_into(room, pos)
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


## The first doorway view a walk goes into without entering the rooms it belongs to (E15 / E18): the walk comes from outside one of the
## `avoided` views into it, within `max_dist` px of walking. Not the view of a doorway of a room the walk goes into (by any of its doors:
## that is an entry, `threshold_ahead`'s, and it clears the room and covers its doorways), nor of the room the NPC stands in.
## `{ opening, into, dist }` (`dist` = px of walking until it is in the view), or {}. The view of any doorway counts, outside the house
## and at its exterior doors too.
func passing_ahead(path: PackedVector2Array, from_idx: int, from_pos: Vector2, max_dist: float, map: RID, space) -> Dictionary:
	var pts: Array = [from_pos]
	for i in range(maxi(from_idx, 0), path.size()):
		pts.append(path[i])
	if pts.size() < 2:
		return {}
	var best := {}
	for v in _crossed_views(pts, avoided(_room_key_at(from_pos), map, space)["views"], max_dist):
		if best.is_empty() or v["dist"] < best["dist"]:
			best = { "opening": v["id"], "into": v["into"], "dist": v["dist"] }
	return best


## The `views` the walk `pts` comes into from outside within `max_dist` px of walking, each with its `dist`; not those of a doorway of
## a room the walk goes into.
func _crossed_views(pts: Array, views: Array, max_dist: float) -> Array:
	var entered := _entered_rooms(pts)
	var out: Array = []
	for v in views:
		if (v["joins"] as Array).any(func(k): return entered.has(k)):
			continue
		var d := _entering_distance(pts, v["poly"], max_dist)
		if d < INF:
			out.append({ "id": v["id"], "into": v["into"], "poly": v["poly"], "dist": d })
	return out


## The route from `from` to `to` as the NPC walks it (E18), on the world navigation map `map`: the plain route, unless it goes into
## the view of a doorway into a room not clear for passing (`avoided`) and a route that keeps out of every such view reaches `to` within
## `door_avoid_ratio` x the plain length + `door_avoid_slack`: that one, on the avoid map. `{ map, path, len, plain_len, doors, pending,
## views }`: `map` the map the route is on, `doors` whether it is the door-avoiding one, `pending` that the plain route goes into a view and
## the avoid map is still being baked (the NPC walks the plain route meanwhile and asks again), `views` the views the plain route goes into.
## `exempt` is a doorway whose view is left alone: the one the walk is for (the approach to its stack).
func walk_route(from: Vector2, to: Vector2, map: RID, space, exempt := "") -> Dictionary:
	var plain := NavBuilder.route(map, from, to)
	var plain_len := NavBuilder.path_length(plain)
	var out := { "map": map, "path": plain, "len": plain_len, "plain_len": plain_len, "doors": false, "pending": false, "views": [] }
	if not avoid_views or not NavBuilder.ready(map):
		return out
	var avoid_set := avoided(_room_key_at(from), map, space, exempt)
	var crossed := _crossed_views([from] + Array(plain), avoid_set["views"], INF)
	out["views"] = crossed
	if crossed.is_empty():
		return out
	var region := NavBuilder.planning_region(map)
	var avoid := NavBuilder.avoid_map(region, avoid_set["key"], avoid_set["holes"])
	if not avoid.is_valid() or not NavBuilder.ready(avoid):
		out["pending"] = true
		return out
	var path := NavBuilder.route(avoid, from, to)
	if path[path.size() - 1].distance_to(NavBuilder.snap(map, to)) > AVOID_REACH:
		return out  # No way round: the walk goes the plain way and the guard secures what it crosses.
	var length := NavBuilder.path_length(path)
	if length > door_avoid_ratio * plain_len + door_avoid_slack:
		return out
	out.merge({ "map": avoid, "path": path, "len": length, "doors": true }, true)
	return out


## Whether the routes weighed from point `from` can be measured as they would be walked (E18): the avoid map for the doorway views
## from the room it is in exists. Asks for it, which starts its bake on the worker thread, so it is under way before a decision is. True when there
## is nothing to avoid (no views, no planning region, door avoidance off) and once the map answers.
func warm(from: Vector2, map: RID, space) -> bool:
	if not avoid_views or not NavBuilder.ready(map):
		return true
	var avoid_set := avoided(_room_key_at(from), map, space)
	var region := NavBuilder.planning_region(map)
	if avoid_set["views"].is_empty() or region == null:
		return true
	return NavBuilder.ready(NavBuilder.avoid_map(region, avoid_set["key"], avoid_set["holes"]))


## The views a walk from point `from` keeps out of, each `{ id, into, poly }` (see `avoided`).
func views_from(from: Vector2, map: RID, space) -> Array:
	return avoided(_room_key_at(from), map, space)["views"]


## The doorway views a walk from room `here_key` ("" = outside) keeps out of: the view out of every doorway into a room that is not
## clear for passing (`pass_clear`), other than the room the NPC stands in. `{ key, holes, views }`: `key` names the set (for
## `NavBuilder.avoid_map`), `holes` the polygons, `views` each `{ id, into, poly, joins }` (`joins`: the keys of the rooms the doorway joins). Empty until the map is baked. The views of doorway
## `exempt` (the doorway a walk is for) are left out.
func avoided(here_key: String, map: RID, space, exempt := "") -> Dictionary:
	var frame := Engine.get_physics_frames()
	if frame == _avoided_frame and here_key == _avoided_here and exempt == _avoided_exempt and pass_clear == _avoided_clear:
		return _avoided_set
	var keys: Array = []
	var holes: Array = []
	var views: Array = []
	for o in _openings:
		for k in o.get("rooms", []):
			var into := str(k)
			if into == here_key or opening_id(o) == exempt or (pass_clear.is_valid() and pass_clear.call(into)):
				continue
			var poly := door_view(opening_id(o), into, map, space)
			if poly.is_empty():
				continue
			keys.append("%s>%s" % [opening_id(o), into])
			holes.append(poly)
			views.append({ "id": opening_id(o), "into": into, "poly": poly, "joins": (o.get("rooms", []) as Array).map(func(j): return str(j)) })
	_avoided_set = { "key": "%d:%s" % [int(door_view_depth), ",".join(keys)], "holes": holes, "views": views }
	_avoided_frame = frame
	_avoided_here = here_key
	_avoided_exempt = exempt
	_avoided_clear = pass_clear
	return _avoided_set


## The view out of doorway `id` seen from inside room `into` through it, as a polygon in world space (empty when either is unknown or
## the map is not baked): the area bounded by the rays from the room's two far corners through the opposite jambs, `door_view_depth` px
## long, and stopped at walls, and, for a doorway between two rooms, cut at the edge of the room in front of it. It is laid out once per doorway (walls do not move) from three points in the gap, the middle and each
## jamb, so what one of them sees past a wall's end counts.
func door_view(id: String, into: String, map: RID, space) -> PackedVector2Array:
	var key := "%s>%s@%d" % [id, into, int(door_view_depth)]
	if _views.has(key):
		return _views[key]
	var opening := {}
	for o in _openings:
		if opening_id(o) == id:
			opening = o
	var room := SnapshotVocab.room_by_key(_rooms, into)
	if opening.is_empty() or room.is_empty() or space == null or vision == null or not NavBuilder.ready(map):
		return PackedVector2Array()
	# A view lies in the room (or the open) in front of the doorway: it does not run on through the next doorway into another room.
	var in_front := Rect2()
	for k in opening.get("rooms", []):
		if str(k) != into:
			in_front = _room_rect(str(k))
	var view := _build_view(opening, room["rect"], space)
	if in_front.size != Vector2.ZERO:
		var front_ring := PackedVector2Array([in_front.position, Vector2(in_front.end.x, in_front.position.y), in_front.end, Vector2(in_front.position.x, in_front.end.y)])
		var cut: Array = Geometry2D.intersect_polygons(view, front_ring)
		if not cut.is_empty():
			cut.sort_custom(func(a, b): return absf(_area(a)) > absf(_area(b)))
			view = cut[0]
	_views[key] = view
	return view


## The area of polygon `ring` (positive or negative by its winding).
func _area(ring: PackedVector2Array) -> float:
	var total := 0.0
	for i in ring.size():
		total += ring[i].cross(ring[(i + 1) % ring.size()])
	return total * 0.5


## The view of `opening` into the room `rect`: see `door_view`.
func _build_view(opening: Dictionary, rect: Rect2, space) -> PackedVector2Array:
	var pos: Vector2 = opening["pos"]
	var half := float(opening.get("width", 80.0)) * 0.5
	var out := -normal_into(rect, pos)
	var along := out.orthogonal()
	var corners := [rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y)]
	corners.sort_custom(func(a, b): return (a - pos).dot(out) < (b - pos).dot(out))
	var far_a: Vector2 = corners[0]
	var far_b: Vector2 = corners[1]
	# Each jamb is seen past by the far corner on the other side of the door's axis.
	var for_a: Vector2 = far_a if (far_a - pos).dot(along) > (far_b - pos).dot(along) else far_b
	var for_b: Vector2 = far_b if for_a == far_a else far_a
	var jamb_a := pos - along * half
	var jamb_b := pos + along * half
	var end_a := jamb_a + (jamb_a - for_a).normalized() * door_view_depth
	var end_b := jamb_b + (jamb_b - for_b).normalized() * door_view_depth
	# The view's outline from jamb to jamb the long way round, sampled for the rays.
	var boundary: Array = []
	for i in range(1, VIEW_SIDE_RAYS + 1):
		boundary.append(jamb_a.lerp(end_a, float(i) / VIEW_SIDE_RAYS))
	for i in range(1, VIEW_FAR_RAYS):
		boundary.append(end_a.lerp(end_b, float(i) / VIEW_FAR_RAYS))
	for i in range(VIEW_SIDE_RAYS, 0, -1):
		boundary.append(jamb_b.lerp(end_b, float(i) / VIEW_SIDE_RAYS))
	var merged: Array = []
	for apex in [pos, jamb_a + along * 2.0, jamb_b - along * 2.0]:
		var eye: Vector2 = apex + out * VIEW_APEX_OUT
		var ring := PackedVector2Array([jamb_a])
		for target in boundary:
			var hit: Dictionary = vision.wall_hit(space, eye, target)
			ring.append(hit["position"] if not hit.is_empty() else target)
		ring.append(jamb_b)
		if merged.is_empty():
			merged = [ring]
			continue
		var fused := Geometry2D.merge_polygons(merged[0], ring)
		var outer: Array = fused.filter(func(poly: PackedVector2Array) -> bool: return not Geometry2D.is_polygon_clockwise(poly))
		if outer.size() == 1:
			merged = [outer[0]]
	return merged[0]


## The room key at world point `p` ("" = outside every room).
func _room_key_at(p: Vector2) -> String:
	return str(SnapshotVocab.room_at(p, _rooms).get("key", ""))


## The keys of the rooms the walk `pts` goes into, by any of their doorways.
func _entered_rooms(pts: Array) -> Dictionary:
	var entered := {}
	for o in _openings:
		for k in o.get("rooms", []):
			var key := str(k)
			if entered.has(key):
				continue
			var room := _room_rect(key)
			if room.size != Vector2.ZERO and _walk_enters(pts, o["pos"], normal_into(room, o["pos"]), float(o.get("width", 80.0))):
				entered[key] = true
	return entered


## The px of walking along the polyline `pts` until it comes into `poly` from outside it, or INF when it does not within `max_dist`. A
## walk that starts in the polygon has not come into it: its first stretch inside is not counted.
func _entering_distance(pts: Array, poly: PackedVector2Array, max_dist: float) -> float:
	var line := PackedVector2Array(pts)
	var inside: Array = Geometry2D.intersect_polyline_with_polygon(line, poly)
	var best := INF
	for piece in inside:
		var first: Vector2 = piece[0]
		if first.distance_to(pts[0]) < 0.5:
			continue
		var walked := 0.0
		for i in range(1, pts.size()):
			var a: Vector2 = pts[i - 1]
			var b: Vector2 = pts[i]
			if first.distance_to(Geometry2D.get_closest_point_to_segment(first, a, b)) < 0.5:
				best = minf(best, walked + a.distance_to(first))
				break
			walked += a.distance_to(b)
	return best if best <= max_dist else INF


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
	var room := SnapshotVocab.room_by_key(_rooms, into)
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
	var inward := normal_into(rect, pos)
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


## The unit normal pointing into `rect` from the edge door `pos` lies on (the nearest edge). Also read by the squad (`ai/team/squad.gd`),
## which tells which side of a doorway's wall a leader clicked.
static func normal_into(rect: Rect2, pos: Vector2) -> Vector2:
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
## for a member that says nothing of it, such as the human; `stuns` = how many stun grenades it carries; `order_id` = the order it stacks
## under, "" for none, with the order's mode `order_bang` and side `order_side`, 1 / -1 along the wall or 0 for a split stack:
## `docs/leadership.md` LD9). A member who aborted or is done with the doorway, or whose latest call is about something else, holds no claim.
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
			"bang": bool(c.get("bang", true)), "bang_off": bool(c.get("bang_off", false)), "stuns": int(c.get("stuns", 0)),
			"order_id": str(c.get("order_id", "")), "order_bang": bool(c.get("order_bang", false)), "order_side": int(c.get("order_side", 0)) })
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


## The side of the door (1 / -1 along its wall, see `geometry`) the team stacks on: the side the point (the slot 1 claim
## in `team`) stacks on; with no point yet, the side with more wall to stack against; when both have the same, the side
## `self_pos` is on. Every member works it out the same way, so the stack forms on one side unless a member cannot get
## there (`stack_side_from`, E19).
static func stack_side(g: Dictionary, team: Array, self_pos: Vector2) -> int:
	for m in team:
		if m["slot"] == 1 and m["side"] != 0:
			return m["side"]
	if int(g["side"]) != 0:
		return int(g["side"])
	return side_of(g, self_pos)


## The side of the door (1 / -1 along its wall) point `p` is on.
static func side_of(g: Dictionary, p: Vector2) -> int:
	return 1 if (p - (g["pos"] as Vector2)).dot(g["along"]) >= 0.0 else -1


## The side a member standing at `from` stacks on (E19): the team's side (`stack_side`), unless its way there crosses the
## doorway's view (`cuts_view`): then its own side, and the stack is split across the door.
func stack_side_from(g: Dictionary, team: Array, from: Vector2, map: RID, space) -> int:
	var team_side := stack_side(g, team, from)
	var own := side_of(g, from)
	if own == team_side or not cuts_view(g, from, slot_point(g, team_side, 1), map, space):
		return team_side
	return own


## Whether the walk from `from` to `to` crosses the view of doorway `g` (E19): it starts outside the view (`door_view`) and its
## plain route crosses the door's axis inside it, in front of the door. A walk that starts in the view, or goes round it, does not.
func cuts_view(g: Dictionary, from: Vector2, to: Vector2, map: RID, space) -> bool:
	var view := door_view(g["id"], g["into"], map, space)
	if view.is_empty() or Geometry2D.is_point_in_polygon(from, view):
		return false
	var pos: Vector2 = g["pos"]
	var out: Vector2 = g["out"]
	var axis := PackedVector2Array([pos + out * VIEW_APEX_OUT, pos + out * door_view_depth])
	var route: Array = [from] + Array(NavBuilder.route(map, from, to))
	for piece: PackedVector2Array in Geometry2D.intersect_polyline_with_polygon(axis, view):
		for i in range(1, route.size()):
			for j in range(1, piece.size()):
				if Geometry2D.segment_intersects_segment(route[i - 1], route[i], piece[j - 1], piece[j]) != null:
					return true
	return false


## The members of a stack (`members`: claims with `id`, `slot` and `side`, this member's own among them) in the order they
## cross (E6, E19): by slot on a one-sided stack; on a split one the point (the lowest slot), then the front man of the other
## side, then the sides take turns, each side's file in slot order (one that runs out leaves the rest to the other).
static func crossing_order(members: Array) -> Array:
	var sorted := members.duplicate()
	sorted.sort_custom(func(a, b): return a["slot"] < b["slot"] if a["slot"] != b["slot"] else a["id"] < b["id"])
	if sorted.is_empty():
		return sorted
	var lead_side := int(sorted[0]["side"])
	var lead: Array = sorted.filter(func(m): return int(m["side"]) == lead_side or int(m["side"]) == 0)
	var other: Array = sorted.filter(func(m): return int(m["side"]) != lead_side and int(m["side"]) != 0)
	if other.is_empty():
		return sorted
	var out: Array = []
	for i in maxi(lead.size(), other.size()):
		if i < lead.size():
			out.append(lead[i])
		if i < other.size():
			out.append(other[i])
	return out


## The place (1 = nearest the door) in its side's file of the member holding stack slot `slot` on side `side`: the slots are
## numbered across both sides in the order they were claimed, so a split stack (E19) leaves out the claims on the other side
## ahead of it (`team`, the claims, this member's own left out or not). On a one-sided stack the place is the slot.
static func place(team: Array, side: int, slot: int) -> int:
	var across := 0
	for m in team:
		if int(m["side"]) != side and int(m["side"]) != 0 and int(m["slot"]) < slot:
			across += 1
	return maxi(slot - across, 1)


## Where the `nth` place (1 = nearest the door, see `place`) in the file on side `side` stands.
static func slot_point(g: Dictionary, side: int, nth: int) -> Vector2:
	var row: Array = g["slots"][side]
	return row[clampi(nth - 1, 0, row.size() - 1)]

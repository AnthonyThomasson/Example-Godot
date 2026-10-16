extends RefCounted

## Shared helpers for the doorway-view tests (not a test itself): `const View := preload("res://tests/_ai/door_view_probe.gd")`.
## The behaviour they assert is `docs/tactical-entry.md` E15 / E18 (issue #51, R1 to R3, R9): a walk the entry guard covers stays
## out of the VIEW of every doorway into a room not clear for passing, else secures the doorway from beside the jamb and crosses
## the view in one go.
##
## The view is the test's own copy of the rule, so the spec isn't read back from the code under test: the area outside the
## doorway seen from inside its room through it, bounded by the rays from the room's two far corners through the opposite jambs,
## out to `DEPTH` px along each ray, and stopped at walls (a point counts only with a clear line past the walls to the doorway).
## Furniture does not stop the view. A doorway is given as an `entry_probe.gd` frame: `{ id, pos, width, out, room }` (`out` the
## unit normal away from the room).

const Entry := preload("res://tests/_ai/entry_probe.gd")

## `door_view_depth`: how far (px) the view reaches out of the doorway, along its edge rays.
const DEPTH := 450.0
## `door_avoid_ratio` / `door_avoid_slack`: a route round the views is taken when it is no longer than this many times the plain
## route plus this many px.
const AVOID_RATIO := 2.0
const AVOID_SLACK := 300.0
## `entry_pass_clear_time`: how long (s) a cleared room counts as safe to walk past.
const PASS_CLEAR_TIME := 60.0
## How far (px) inside the view's edge a body's centre must be before it counts as in the view: the agent cuts a path's
## corners by up to 16 px, so a walk that keeps to the edge is not taken for one that crosses it.
const EDGE_MARGIN := 10.0


## The view of `door` as a polygon: jamb, far end of the ray through it, far end of the other ray, the other jamb.
static func polygon(door: Dictionary, depth := DEPTH) -> PackedVector2Array:
	var pos: Vector2 = door["pos"]
	var out: Vector2 = door["out"]
	var along := out.orthogonal()
	var half := float(door["width"]) * 0.5
	var room: Rect2 = door["room"]
	var corners := [room.position, Vector2(room.end.x, room.position.y), room.end, Vector2(room.position.x, room.end.y)]
	# The two far corners: the ones deepest into the room (least outward).
	corners.sort_custom(func(a, b): return (a - pos).dot(out) < (b - pos).dot(out))
	var far := [corners[0], corners[1]]
	var jamb_a := pos - along * half
	var jamb_b := pos + along * half
	# Each jamb is seen past by the far corner on the other side of the door's axis.
	var corner_for_a: Vector2 = far[0] if (far[0] - pos).dot(along) > (far[1] - pos).dot(along) else far[1]
	var corner_for_b: Vector2 = far[1] if corner_for_a == far[0] else far[0]
	var end_a := jamb_a + (jamb_a - corner_for_a).normalized() * depth
	var end_b := jamb_b + (jamb_b - corner_for_b).normalized() * depth
	return PackedVector2Array([jamb_a, end_a, end_b, jamb_b])


## Whether a body at `p` stands in the view of `door`: inside the polygon by more than `margin` px, on the outer side of the
## wall, with a clear line past the walls to the doorway.
static func in_view(t: TestContext, door: Dictionary, p: Vector2, margin := EDGE_MARGIN) -> bool:
	if (p - (door["pos"] as Vector2)).dot(door["out"]) <= 0.0:
		return false
	var poly := polygon(door)
	if not Geometry2D.is_point_in_polygon(p, poly):
		return false
	if margin > 0.0 and _edge_distance(poly, p) < margin:
		return false
	return _sees_doorway(t, door, p)


## The sim time of the first sample where actor `id` stood in the view of `door` (see `in_view`), or INF. `before` limits it to
## samples up to that time.
static func first_in_view(t: TestContext, samples: Array, id: StringName, door: Dictionary, before := INF) -> float:
	for s in samples:
		if float(s["t"]) > before:
			break
		if s["pos"].has(id) and in_view(t, door, s["pos"][id]):
			return s["t"]
	return INF


## How long (s) actor `id` stood in the view of `door` in `samples`.
static func time_in_view(t: TestContext, samples: Array, id: StringName, door: Dictionary) -> float:
	var total := 0.0
	for i in range(1, samples.size()):
		var s: Dictionary = samples[i]
		if s["pos"].has(id) and in_view(t, door, s["pos"][id]):
			total += float(s["t"]) - float(samples[i - 1]["t"])
	return total


## The longest run (s) actor `id` spent in the view of `door` moving slower than `still_speed` px/s: a stop in the view. `from` /
## `to` limit it to the samples between those sim times.
static func longest_pause_in_view(t: TestContext, samples: Array, id: StringName, door: Dictionary, still_speed := 20.0, from := -INF, to := INF) -> float:
	var longest := 0.0
	var run := 0.0
	for i in range(1, samples.size()):
		var a: Dictionary = samples[i - 1]
		var b: Dictionary = samples[i]
		if not a["pos"].has(id) or not b["pos"].has(id) or float(b["t"]) < from or float(b["t"]) > to:
			continue
		var dt: float = float(b["t"]) - float(a["t"])
		var p: Vector2 = b["pos"][id]
		var speed := (p - (a["pos"][id] as Vector2)).length() / maxf(dt, 0.0001)
		if in_view(t, door, p) and speed < still_speed:
			run += dt
			longest = maxf(longest, run)
		else:
			run = 0.0
	return longest


## How many separate times actor `id` walked into the view of `door` in `samples` (a crossing in one go is one).
static func view_entries(t: TestContext, samples: Array, id: StringName, door: Dictionary) -> int:
	var count := 0
	var was_in := false
	for s in samples:
		if not s["pos"].has(id):
			continue
		var now_in := in_view(t, door, s["pos"][id])
		if now_in and not was_in:
			count += 1
		was_in = now_in
	return count


## The sim time actor `id` first stood outside `door` (on the outer side of its wall) across the door's axis from `from_side`
## (the sign of `entry_probe.lateral` on the side it came from), more than `beyond` px past the axis: when its walk crossed the
## doorway's line of sight. INF when it never did.
static func axis_crossed_at(samples: Array, id: StringName, door: Dictionary, from_side: float, beyond := 20.0) -> float:
	for s in samples:
		if not s["pos"].has(id):
			continue
		var p: Vector2 = s["pos"][id]
		if Entry.outward(door, p) > 0.0 and signf(Entry.lateral(door, p)) == -from_side and absf(Entry.lateral(door, p)) > beyond:
			return s["t"]
	return INF


## The span `[start, end]` (sim s) of the unbroken run of samples, around time `at`, in which actor `id` stood in the view of `door`:
## the crossing that took it across the axis at `at`. `[at, at]` when it was not in the view then.
static func crossing_span(t: TestContext, samples: Array, id: StringName, door: Dictionary, at: float) -> Array:
	var i0 := -1
	for i in samples.size():
		if float(samples[i]["t"]) >= at:
			i0 = i
			break
	if i0 < 0:
		return [at, at]
	var lo := i0
	while lo > 0 and samples[lo - 1]["pos"].has(id) and in_view(t, door, samples[lo - 1]["pos"][id]):
		lo -= 1
	var hi := i0
	while hi < samples.size() - 1 and samples[hi + 1]["pos"].has(id) and in_view(t, door, samples[hi + 1]["pos"][id]):
		hi += 1
	return [float(samples[lo]["t"]), float(samples[hi]["t"])]


## How long (s) actor `id` stood and pointed its gun through `door` from its outer side, within `reach` px of the wall plane (beside
## the jamb, or slicing one side of the pie), in the samples before `before`: what securing it is (E15). Only while it moves slower
## than `still_speed` px/s: a walk past the door looking down its path toward it is not a cover.
static func time_covering(samples: Array, id: StringName, door: Dictionary, before := INF, reach := 90.0, still_speed := 40.0) -> float:
	var total := 0.0
	for i in range(1, samples.size()):
		var a: Dictionary = samples[i - 1]
		var s: Dictionary = samples[i]
		if float(s["t"]) >= before:
			break
		if not a["pos"].has(id) or not s["pos"].has(id):
			continue
		var p: Vector2 = s["pos"][id]
		var dt := float(s["t"]) - float(a["t"])
		var speed := (p - (a["pos"][id] as Vector2)).length() / maxf(dt, 0.0001)
		var o := Entry.outward(door, p)
		if o > 0.0 and o < reach and speed < still_speed and Entry.faces_through(door, p, s["facing"][id]):
			total += dt
	return total


## Wait until `seconds` have passed on the wall clock since `since_ms` (`Time.get_ticks_msec`) and `sim_seconds` in sim time since
## `since_t`, pacing the sim to about real time meanwhile (a headless scripted run otherwise outruns the clock many times over, as the
## runner paces a Von test). The perception's memory ages in game time (`GameClock`), which the `sim_seconds` half covers.
static func wait_wall(t: TestContext, since_ms: int, seconds: float, since_t: float, sim_seconds: float) -> void:
	while Time.get_ticks_msec() - since_ms < int(seconds * 1000.0) or t.time - since_t < sim_seconds:
		OS.delay_msec(16)
		await t.frames(1)


## The navigated length (px) of the plain route from `a` to `b` on the test world's planning map: what the avoiding route is
## measured against (`AVOID_RATIO` x this + `AVOID_SLACK`).
static func plain_route_length(t: TestContext, a: Vector2, b: Vector2) -> float:
	var map := t.world.get_world_2d().navigation_map
	return NavBuilder.path_length(NavBuilder.route(map, a, b))


# --- internals ---------------------------------------------------------------------------------------

## The distance (px) from `p` to the nearest edge of `poly`.
static func _edge_distance(poly: PackedVector2Array, p: Vector2) -> float:
	var best := INF
	for i in poly.size():
		var a := poly[i]
		var b := poly[(i + 1) % poly.size()]
		best = minf(best, p.distance_to(Geometry2D.get_closest_point_to_segment(p, a, b)))
	return best


## A clear line from `p` to some point of the doorway's gap, past walls only (characters and furniture let the view through).
static func _sees_doorway(t: TestContext, door: Dictionary, p: Vector2) -> bool:
	var pos: Vector2 = door["pos"]
	var along := (door["out"] as Vector2).orthogonal()
	var half := float(door["width"]) * 0.5 - 4.0
	for target in [pos, pos - along * half, pos + along * half]:
		if _walls_clear(t, p, target):
			return true
	return false


## Whether no wall (a static body) lies on the line from `a` to `b`; furniture and characters are looked past.
static func _walls_clear(t: TestContext, a: Vector2, b: Vector2) -> bool:
	var space := t.world.get_world_2d().direct_space_state
	var exclude: Array = []
	for i in 12:
		var query := PhysicsRayQueryParameters2D.create(a, b, PhysicsLayers.SOLID)
		query.exclude = exclude
		var hit := space.intersect_ray(query)
		if hit.is_empty():
			return true
		if hit["collider"] is StaticBody2D:
			return false
		exclude.append(hit["rid"])
	return false

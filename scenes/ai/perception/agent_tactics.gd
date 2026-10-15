extends RefCounted

## AI PERCEPTION sub-domain — TACTICS: the combat geometry an NPC reads off what it knows. Pure
## queries over known contacts, the physics space (via the vision sense's ray helpers) and the
## navigation map (Navigation interface 9): where it could flank a target from, which spots give a
## clear shot or cover, how to close in, where to fall back to — each candidate annotated with the
## facts a tactical choice turns on (clear shot, cover, route length and exposure, which ally already
## holds a side, which other hostile would see it, which hostile the route passes). It returns DATA
## only; the perception turns that into the words Von reads. It holds no policy and never decides.
## Firing spots are the one candidate set it screens: a spot whose route passes a known hostile, or
## where a hostile would catch the NPC in the open, is not a place to fight from at all.
##
## A target's FLANKS are measured in its own frame: its front is where it was last seen facing (when
## recent), else the side facing this NPC. Left/right are the target's own left/right.

## The flanking sides offered, as degrees off the target's front (screen space, +y down).
const SIDES := { "left": -90.0, "right": 90.0, "rear": 180.0 }
## How far (px) a sampled point may be pulled by navmesh snapping before it counts as unreachable.
const SNAP_TOLERANCE := 48.0
## Points sampled along a route to judge whether the target can see it.
const ROUTE_SAMPLES := 8
## A place a walk ends within this (px of walking) of where the NPC stands is where it stands: the walk is over the moment it begins
## (a stride, twice the walk's own arrival distance), and the unchanged situation would offer it again. No retreat nor walk toward the
## shots (LOCATE, the "where the shots came from" lead: `where_it_stands`) goes to one.
const STRIDE := 32.0
## A place closer than this (px) to a character the NPC knows of is taken (a body's footprint): a walk there is held short of the body.
const TAKEN := 32.0
## How far (px) from an ally lies the spot beside it that the NPC falls back to: a body clear of it (the stack's spacing).
const BESIDE_ALLY := 44.0

var vision: RefCounted               ## The perception's sight sense; owner of the ray queries.
var cover_min: float = 40.0          ## Surface coverage at or above which a blocking object is cover.
var flank_distance: float = 220.0    ## Distance (px) from the target a flanking spot is sought at.
var flank_arc: float = 60.0          ## Angular spread (degrees) sampled around each side's bearing.
var flank_ally_radius: float = 500.0 ## An ally this close to the target holds the side it stands on.
var shoot_range: float = 500.0       ## Pistol range (px): a spot beyond it gives no shot.
var combat_ring_radius: float = 80.0 ## Radius (px) of the ring of nearby candidate fighting spots.
var combat_ring_count: int = 12      ## Points sampled on that ring.
var still_speed: float = 20.0        ## Speed (px/s) under which a contact counts as standing still.
var route_clearance: float = 120.0   ## A route coming this close (px) to a known hostile passes it.
var watch_arc: float = 90.0          ## Full cone (degrees) around a hostile's front in which it is looking.
var fire_spot_distances: Array[float] = [200.0, 350.0] ## Distances (px) from a target at which firing spots are sampled.
var throw_spot_walk: float = 250.0  ## Longest walk (px of route) to a throw spot (`throw_spot`).


# --- Ray + nav primitives --------------------------------------------------------------------

## Whether the straight line `a`→`b` is blocked by a wall or solid object.
func blocked(space, a: Vector2, b: Vector2, exclude: Array) -> bool:
	return vision.blocked(space, a, b, exclude)


## The first solid object on `a`→`b`, or null when the line is clear.
func blocker(space, a: Vector2, b: Vector2, exclude: Array) -> Object:
	return vision.raycast(space, a, b, exclude).get("collider")


## Whether `obj` is solid enough to hide behind (coverage at or above `cover_min`). A character is never
## cover — it is someone to shoot or protect, and it moves.
func is_cover(obj: Object) -> bool:
	if obj == null or (obj is Node and obj.is_in_group(&"characters")) or not obj.has_method("get_surface"):
		return false
	return float(obj.get_surface().get("coverage", 0.0)) >= cover_min


## A readable name for a blocking object: a furniture piece's own name ("fridge"), a character's name,
## else "wall" — walls are named after their room, which would read as a place ("behind the kitchen").
func object_label(obj: Object) -> String:
	if obj == null:
		return ""
	var named = obj.get("object_name")
	if named is String and named != "":
		return named.to_lower()
	if obj is Node and obj.is_in_group(&"characters"):
		return str(obj.get("name")).to_lower()
	return "wall"


## Whether most of a route lies in the open from `threat` (a clear line from it to most samples). With a
## `front` (the threat's facing, radians) a sample also has to lie inside its view cone (`watch_arc`): a
## route behind the threat's back is not in its view, however clear the line. Without one, only the line counts.
func route_exposed(space, path: PackedVector2Array, threat: Vector2, exclude: Array, front := NAN) -> bool:
	var total := NavBuilder.path_length(path)
	if total <= 0.0:
		return false
	var half := deg_to_rad(watch_arc) * 0.5
	var seen := 0
	for i in ROUTE_SAMPLES:
		var sample := _along(path, total * (i + 1) / (ROUTE_SAMPLES + 1))
		if not is_nan(front) and not _looking_at(threat, front, sample, half):
			continue
		if not blocked(space, threat, sample, exclude):
			seen += 1
	return seen * 2 > ROUTE_SAMPLES


## The point `dist` px along a route.
func _along(path: PackedVector2Array, dist: float) -> Vector2:
	for i in range(1, path.size()):
		var seg := path[i - 1].distance_to(path[i])
		if dist <= seg:
			return path[i - 1].lerp(path[i], dist / seg if seg > 0.0 else 0.0)
		dist -= seg
	return path[path.size() - 1]


# --- Frames and sides ------------------------------------------------------------------------

## The target's front bearing (radians): its last-seen facing when `use_facing`, else toward `self_pos`.
func front_angle(target: Dictionary, self_pos: Vector2, use_facing: bool) -> float:
	var facing: Vector2 = target.get("facing", Vector2.ZERO)
	if use_facing and facing != Vector2.ZERO:
		return facing.angle()
	return (self_pos - (target["pos"] as Vector2)).angle()


## Which side of a target at `target_pos` (front bearing `front`) the point `p` is on:
## "front" / "left" / "right" / "rear".
func side_of(target_pos: Vector2, front: float, p: Vector2) -> String:
	var d := angle_difference(front, (p - target_pos).angle())
	if absf(d) <= PI * 0.25:
		return "front"
	if absf(d) >= PI * 0.75:
		return "rear"
	return "left" if d < 0.0 else "right"


# --- Spot classification ---------------------------------------------------------------------

## Points on a ring around `self_pos` classified against `tgt_pos`: `fire` (a clear line to it) and
## `cover` (shielded by a cover-grade object). Points walled off from the NPC are dropped. Both lists
## nearest-first.
func combat_spots(space, self_pos: Vector2, tgt_pos: Vector2, exclude: Array, radius: float, count: int) -> Dictionary:
	var fire: Array = []
	var cover: Array = []
	for i in count:
		var p := self_pos + Vector2.RIGHT.rotated(TAU * i / count) * radius
		if blocked(space, self_pos, p, exclude):
			continue
		var obj := blocker(space, p, tgt_pos, exclude)
		if obj == null:
			fire.append(p)
		elif is_cover(obj):
			cover.append(p)
	fire.sort_custom(func(a, b): return a.distance_squared_to(self_pos) < b.distance_squared_to(self_pos))
	cover.sort_custom(func(a, b): return a.distance_squared_to(self_pos) < b.distance_squared_to(self_pos))
	return { "fire": fire, "cover": cover }


## The cover-grade object that shields a spot within one step of `p` from `threat`, or "" when none.
func cover_near(space, p: Vector2, threat: Vector2, exclude: Array) -> String:
	for i in 9:
		var q := p if i == 0 else p + Vector2.RIGHT.rotated(TAU * i / 8.0) * 36.0
		var obj := blocker(space, q, threat, exclude)
		if is_cover(obj):
			return object_label(obj)
	return ""


## Names of the known hostiles other than `skip_id` with a clear line to `p` within shooting reach.
func exposed_to(space, p: Vector2, hostiles: Array, skip_id: int, exclude: Array) -> Array:
	var out: Array = []
	for h in hostiles:
		if h["id"] == skip_id or (h["pos"] as Vector2).distance_to(p) > shoot_range * 1.5:
			continue
		if not blocked(space, h["pos"], p, exclude + body_rid(h)):
			out.append(h["name"])
	return out


## The ally (perceived, or via a radio callout) holding side `side` of a target, or "".
func side_holder(target: Dictionary, front: float, side: String, allies: Array, callouts: Array) -> String:
	var tpos: Vector2 = target["pos"]
	for a in allies:
		if (a["pos"] as Vector2).distance_to(tpos) <= flank_ally_radius and side_of(tpos, front, a["pos"]) == side:
			return a["name"]
	for c in callouts:
		var point: Vector2 = c.get("point", Vector2.INF)
		if point != Vector2.INF and point.distance_to(tpos) <= flank_ally_radius and side_of(tpos, front, point) == side:
			return "%s (radio)" % c.get("name", "an ally")
	return ""


## The ally whose line of fire on the target passes close to `p`, or that the route `path` to `p` crosses,
## or "". Walking across a friend's line of fire is as bad as standing in it.
func ally_lane(p: Vector2, target_pos: Vector2, allies: Array, path := PackedVector2Array()) -> String:
	for a in allies:
		var apos: Vector2 = a["pos"]
		if apos.distance_to(target_pos) > flank_ally_radius:
			continue
		if Geometry2D.get_closest_point_to_segment(p, apos, target_pos).distance_to(p) < 40.0:
			return a["name"]
		for i in range(1, path.size()):
			if Geometry2D.segment_intersects_segment(path[i - 1], path[i], apos, target_pos) != null:
				return a["name"]
	return ""


# --- Route safety ----------------------------------------------------------------------------

## The first known hostile a route passes, or "": its last-known position lies within `route_clearance`
## of the route AND nearer than the route's start already is, so walking away from someone close by is
## not passing them.
func route_crosses(path: PackedVector2Array, hostiles: Array) -> String:
	if path.size() < 2:
		return ""
	for h in hostiles:
		var hpos: Vector2 = h["pos"]
		var closest := INF
		for i in range(1, path.size()):
			closest = minf(closest, Geometry2D.get_closest_point_to_segment(hpos, path[i - 1], path[i]).distance_to(hpos))
		if closest < route_clearance and closest < path[0].distance_to(hpos) - 1.0:
			return h["name"]
	return ""


## The known hostile that would catch the NPC in the open, or "": one looking toward `p` (within
## `watch_arc` of its front, from `ctx.fronts`) with a clear line to it in reach and no cover within a
## step of `p` against it. With a `path`, also one looking along the route there while the NPC is now
## hidden or covered from it, when most of that route is open to it — stepping out of cover under its eye.
func watched_in_open(ctx: Dictionary, p: Vector2, path: PackedVector2Array = PackedVector2Array()) -> String:
	var self_pos: Vector2 = ctx["self_pos"]
	var half := deg_to_rad(watch_arc) * 0.5
	var fronts: Dictionary = ctx.get("fronts", {})
	for h in ctx["hostiles"]:
		var hpos: Vector2 = h["pos"]
		# Unknown facing counts as facing this NPC, the safe assumption.
		var front: float = fronts.get(h["id"], (self_pos - hpos).angle())
		var ex: Array = ctx["exclude"] + body_rid(h)
		if _looking_at(hpos, front, p, half) and hpos.distance_to(p) <= shoot_range * 1.5 \
				and not blocked(ctx["space"], hpos, p, ex) and cover_near(ctx["space"], p, hpos, ex) == "":
			return h["name"]
		if path.size() >= 2 and _looking_at(hpos, front, _along(path, NavBuilder.path_length(path) * 0.5), half):
			# Whether this NPC is hidden from `h` where it stands does not depend on the spot judged, so it is worked out
			# once per hostile for the whole snapshot (`ctx.covered_from`) rather than for every candidate spot.
			var covered_from: Dictionary = ctx.get("covered_from", {})
			var covered: bool
			if covered_from.has(h["id"]):
				covered = covered_from[h["id"]]
			else:
				covered = blocked(ctx["space"], hpos, self_pos, ex) or cover_near(ctx["space"], self_pos, hpos, ex) != ""
				covered_from[h["id"]] = covered
			if covered and route_exposed(ctx["space"], path, hpos, ex):
				return h["name"]
	return ""


## Whether a hostile at `hpos` facing `front` is looking toward `p` (within `half` radians).
func _looking_at(hpos: Vector2, front: float, p: Vector2, half: float) -> bool:
	return absf(angle_difference(front, (p - hpos).angle())) <= half


# --- Candidate positions ---------------------------------------------------------------------

## The flanking spots around `target` (one per side, excluding the side this NPC is already on), each
## annotated — `crosses` names a known hostile the route there passes. `ctx` = { space, map, self_pos,
## exclude, hostiles, allies, callouts, fronts, covered_from }.
func flank_sides(ctx: Dictionary, target: Dictionary, front: float) -> Array:
	var tpos: Vector2 = target["pos"]
	var ex: Array = ctx["exclude"] + body_rid(target)
	var own_side := side_of(tpos, front, ctx["self_pos"])
	var out: Array = []
	for side in SIDES:
		if side == own_side:
			continue
		var p = _flank_point(ctx, tpos, front, side, ex)
		if p == null:
			continue
		var path := NavBuilder.route(ctx["map"], ctx["self_pos"], p)
		var vel: Vector2 = target.get("vel", Vector2.ZERO)
		out.append({
			"side": side,
			"point": p,
			"clear_shot": not blocked(ctx["space"], p, tpos, ex),
			"cover": cover_near(ctx["space"], p, tpos, ex),
			"route_len": NavBuilder.path_length(path),
			"route_exposed": route_exposed(ctx["space"], path, tpos, ex, front),
			"crosses": route_crosses(path, ctx["hostiles"]),
			"held_by": side_holder(target, front, side, ctx["allies"], ctx["callouts"]),
			"exposed_to": exposed_to(ctx["space"], p, ctx["hostiles"], target["id"], ctx["exclude"]),
			"heading_toward": vel.length() >= still_speed and absf(vel.angle_to(p - tpos)) < PI / 3.0,
			"ally_lane": ally_lane(p, tpos, ctx["allies"], path),
		})
	return out


## A reachable point on `side` of a target: sampled across `flank_arc` at full then shorter range,
## preferring one with a clear shot. Null when the side has no reachable point.
func _flank_point(ctx: Dictionary, tpos: Vector2, front: float, side: String, ex: Array):
	var base := front + deg_to_rad(SIDES[side])
	var fallback = null
	for dist in [flank_distance, flank_distance * 0.65]:
		for k in [0.0, -0.5, 0.5]:
			var raw: Vector2 = tpos + Vector2.from_angle(base + deg_to_rad(flank_arc) * k) * dist
			var p := NavBuilder.snap(ctx["map"], raw)
			if p.distance_to(raw) > SNAP_TOLERANCE or side_of(tpos, front, p) != side:
				continue
			if not blocked(ctx["space"], p, tpos, ex):
				return p
			if fallback == null:
				fallback = p
	return fallback


## Where to fight `target` from: `here` (this spot, when it has a clear shot in range), firing `spots`
## spread around the target, and an `ambush` spot in cover. Spot candidates come from rings around the
## NPC (`combat_ring_radius`, ×2) and around the target (each of `fire_spot_distances`); each must have a
## clear shot in range and pass `_safe_spot`, and the best is kept per 8-way sector around the target
## (cover close by first, then the shortest step). `here` is never screened: staying put is not a move.
func fire_positions(ctx: Dictionary, target: Dictionary) -> Dictionary:
	var tpos: Vector2 = target["pos"]
	var self_pos: Vector2 = ctx["self_pos"]
	var ex: Array = ctx["exclude"] + body_rid(target)
	var out := { "here": {}, "spots": [], "ambush": {} }
	if self_pos.distance_to(tpos) <= shoot_range and not blocked(ctx["space"], self_pos, tpos, ex):
		out["here"] = _annotate(ctx, target, self_pos, ex)
	var candidates: Array = []
	var cover_spots: Array = []
	for radius in [combat_ring_radius, combat_ring_radius * 2.0]:
		var ring := combat_spots(ctx["space"], self_pos, tpos, ex, radius, combat_ring_count)
		candidates.append_array(ring["fire"])
		cover_spots.append_array(ring["cover"])
	for dist in fire_spot_distances:
		for i in combat_ring_count:
			var raw: Vector2 = tpos + Vector2.RIGHT.rotated(TAU * i / combat_ring_count) * dist
			var p := NavBuilder.snap(ctx["map"], raw)
			if p.distance_to(raw) <= SNAP_TOLERANCE and not blocked(ctx["space"], p, tpos, ex):
				candidates.append(p)
	# Cheap facts first (range, sector, cover); the route checks run only until a sector has its spot.
	var sectors := {}
	for p in candidates:
		if p.distance_to(tpos) > shoot_range or p.distance_to(self_pos) < combat_ring_radius * 0.5:
			continue
		var sector := posmod(int(round((p - tpos).angle() / (TAU / 8.0))), 8)
		if not sectors.has(sector):
			sectors[sector] = []
		sectors[sector].append({ "point": p, "cover": cover_near(ctx["space"], p, tpos, ex) })
	var spots: Array = []
	for sector in sectors:
		var group: Array = sectors[sector]
		group.sort_custom(func(a, b):
			if (a["cover"] != "") != (b["cover"] != ""):
				return a["cover"] != ""
			return (a["point"] as Vector2).distance_squared_to(self_pos) < (b["point"] as Vector2).distance_squared_to(self_pos))
		for c in group:
			var spot = _safe_spot(ctx, target, c["point"], ex)
			if spot != null:
				spots.append(spot)
				break
	# Cover close by first, then a hidden route, then the shortest.
	spots.sort_custom(func(a, b):
		if (a["cover"] != "") != (b["cover"] != ""):
			return a["cover"] != ""
		if a["route_exposed"] != b["route_exposed"]:
			return not a["route_exposed"]
		return a["route_len"] < b["route_len"])
	out["spots"] = spots
	for p in cover_spots:
		var amb = _safe_spot(ctx, target, p, ex)
		if amb != null:
			amb["cover"] = object_label(blocker(ctx["space"], p, tpos, ex))
			out["ambush"] = amb
			break
	return out


## Rings (px from the NPC, and shares of the throw reach from the burst spot) and directions the throw spots are sampled on, and the most
## candidates routed per call.
const THROW_RINGS := [48.0, 96.0, 144.0, 192.0, 240.0]
const THROW_REACH_SHARES := [0.95, 0.8]
const THROW_DIRECTIONS := 16
const THROW_ROUTES := 10


## Where to throw a grenade onto `spot` from when it cannot be thrown from where the NPC stands (out of range, or no clear lob: docs/grenades.md
## G17): a point on the navmesh within `reach` of `spot` from which `lob` holds (a `Callable(from: Vector2) -> bool`: the lob
## from there is clear), a walk of at most `throw_spot_walk` along a route that passes no known hostile, and not inside the rect `keep_out`
## (the room the hostile holds, which the NPC is outside of; an empty rect for none). `route` (a `Callable(to: Vector2) -> Dictionary`,
## `{ path, len, detour }`) is the walk there as the NPC would walk it and whether it would be stopped on the way to go into or secure a
## doorway (the entry guard, E9 / E15 / E18); without it the plain route, no detour. Chosen as the fire spots are, and so that the walk needs no
## detour: one that needs none first, then out of the line from `spot` (low furniture between: hidden from whoever is there), then with cover
## close by against it (a doorway's jamb, a piece), then the shortest walk. `{ point, route_len, hidden, cover, detour }`, or {} when there is none.
func throw_spot(ctx: Dictionary, spot: Vector2, reach: float, lob: Callable, ex: Array, keep_out := Rect2(), route := Callable()) -> Dictionary:
	var self_pos: Vector2 = ctx["self_pos"]
	var raw: Array = []
	for radius: float in THROW_RINGS:
		if radius > throw_spot_walk:
			break
		for i in THROW_DIRECTIONS:
			raw.append(self_pos + Vector2.RIGHT.rotated(TAU * i / THROW_DIRECTIONS) * radius)
	for share: float in THROW_REACH_SHARES:
		for i in THROW_DIRECTIONS:
			raw.append(spot + Vector2.RIGHT.rotated(TAU * i / THROW_DIRECTIONS) * reach * share)
	# Cheap facts first (range, the walk's straight-line floor, the navmesh, the lob), then the line and cover; routes last, for the best few.
	var found: Array = []
	for r: Vector2 in raw:
		if self_pos.distance_to(r) > throw_spot_walk or r.distance_to(spot) > reach + SNAP_TOLERANCE:
			continue  # Past the walk, or past the reach even once snapped: not worth a navmesh query.
		var p := NavBuilder.snap(ctx["map"], r)
		if p.distance_to(r) > SNAP_TOLERANCE or p.distance_to(spot) > reach or self_pos.distance_to(p) < STRIDE:
			continue
		if keep_out.has_area() and keep_out.has_point(p):
			continue
		if found.any(func(c): return (c["point"] as Vector2).distance_to(p) < 12.0) or not lob.call(p):
			continue
		var hidden := blocked(ctx["space"], spot, p, ex)
		found.append({ "point": p, "hidden": hidden, "cover": "" if hidden else cover_near(ctx["space"], p, spot, ex) })
	found.sort_custom(func(a, b):
		var ra := _throw_rank(a)
		var rb := _throw_rank(b)
		if ra != rb:
			return ra < rb
		return self_pos.distance_squared_to(a["point"]) < self_pos.distance_squared_to(b["point"]))
	var walkable: Array = []
	for c: Dictionary in found.slice(0, THROW_ROUTES):
		var way: Dictionary = route.call(c["point"]) if route.is_valid() else {}
		if way.is_empty():
			var plain := NavBuilder.route(ctx["map"], self_pos, c["point"])
			way = { "path": plain, "len": NavBuilder.path_length(plain), "detour": false }
		var path: PackedVector2Array = way["path"]
		var length: float = way["len"]
		if length > throw_spot_walk or path.is_empty() or path[path.size() - 1].distance_to(c["point"]) > 12.0:
			continue
		if route_crosses(path, ctx["hostiles"]) != "":
			continue
		walkable.append(c.merged({ "route_len": length, "detour": bool(way.get("detour", false)) }))
	if walkable.is_empty():
		return {}
	walkable.sort_custom(func(a, b):
		if a["detour"] != b["detour"]:
			return not a["detour"]
		if _throw_rank(a) != _throw_rank(b):
			return _throw_rank(a) < _throw_rank(b)
		return a["route_len"] < b["route_len"])
	return walkable[0]


## How a throw spot ranks (lower first): hidden from the burst spot, then covered against it, then in the open.
static func _throw_rank(c: Dictionary) -> int:
	return 0 if c["hidden"] else (1 if c["cover"] != "" else 2)


## `p` annotated as a place to fight `target` from (with its route's exposure to the target), or null
## when the route there passes a known hostile or a hostile would catch the NPC in the open on the way
## or once there.
func _safe_spot(ctx: Dictionary, target: Dictionary, p: Vector2, ex: Array):
	var path := NavBuilder.route(ctx["map"], ctx["self_pos"], p)
	if route_crosses(path, ctx["hostiles"]) != "" or watched_in_open(ctx, p, path) != "":
		return null
	var a := _annotate(ctx, target, p, ex, path)
	a["route_exposed"] = route_exposed(ctx["space"], path, target["pos"], ex)
	return a


## Ways to close in on `target`: points part-way along the route to it (with any cover there) and its
## last-known position itself.
func advance_positions(ctx: Dictionary, target: Dictionary) -> Array:
	var tpos: Vector2 = target["pos"]
	var ex: Array = ctx["exclude"] + body_rid(target)
	var path := NavBuilder.route(ctx["map"], ctx["self_pos"], tpos)
	var total := NavBuilder.path_length(path)
	var out: Array = []
	if total > 160.0:
		for frac in [0.5, 0.75]:
			var p := NavBuilder.snap(ctx["map"], _along(path, total * frac))
			var a := _annotate(ctx, target, p, ex)
			a["fraction"] = frac
			out.append(a)
	var rush := _annotate(ctx, target, NavBuilder.snap(ctx["map"], tpos), ex)
	rush["rush"] = true
	rush["route_exposed"] = route_exposed(ctx["space"], path, tpos, ex)
	out.append(rush)
	return out


## Places to fall back to from `threats` (world points): known room centres, cover spots nearby, and
## a spot beside each nearby ally — each annotated with whether it is hidden from every threat, cover, route
## and the ally it lies toward. Each is the point on the navmesh a walk there ends at, judged there. A retreat
## takes the NPC out of sight of every threat when it stands in sight of one, else farther (by a `STRIDE`) from
## the nearest; one taken by a character it knows of (`TAKEN`) or where it already stands (`STRIDE`) is no
## place to fall back to.
func retreat_positions(ctx: Dictionary, threats: Array, rooms: Array) -> Array:
	var self_pos: Vector2 = ctx["self_pos"]
	var here_gap := _nearest_gap(self_pos, threats)
	# Rays toward a threat end on the hostile's own body — it must not count as what hides a spot.
	var ex: Array = ctx["exclude"].duplicate()
	for h in ctx["hostiles"]:
		ex += body_rid(h)
	var here_hidden := threats.all(func(t): return blocked(ctx["space"], t, self_pos, ex))
	var candidates: Array = []
	for room in rooms:
		var rect: Rect2 = room["rect"]
		if rect.has_point(self_pos):
			continue
		candidates.append({ "point": NavBuilder.snap(ctx["map"], rect.get_center()), "room": str(room.get("type", "room")).replace("_", " ") })
	if not threats.is_empty():
		var nearest: Vector2 = threats[0]
		for p in combat_spots(ctx["space"], self_pos, nearest, ex, combat_ring_radius * 2.0, combat_ring_count)["cover"]:
			candidates.append({ "point": NavBuilder.snap(ctx["map"], p), "room": "" })  # A ring point off the navmesh is walked to its edge.
		for a in ctx["allies"]:
			var spot := _beside(ctx, a["pos"], nearest)
			if spot != Vector2.INF:
				candidates.append({ "point": spot, "room": "", "ally": a["name"] })
	var bodies: Array = (ctx["allies"] + ctx["hostiles"]).map(func(c): return c["pos"])
	var out: Array = []
	for c in candidates:
		var p: Vector2 = c["point"]
		if bodies.any(func(b): return p.distance_to(b) < TAKEN):
			continue  # Taken: the walk would be held short of the body on it.
		var hidden := true
		for t in threats:
			if not blocked(ctx["space"], t, p, ex):
				hidden = false
				break
		var farther := _nearest_gap(p, threats) >= here_gap + STRIDE
		if not farther and (not hidden or here_hidden):
			continue  # Neither out of sight (from in it) nor farther away: not a retreat.
		var path := NavBuilder.route(ctx["map"], self_pos, p)
		var route_len := NavBuilder.path_length(path)
		if route_len < STRIDE:
			continue  # Where it stands: the walk would be over before it began.
		var cover := ""
		if not threats.is_empty():
			cover = cover_near(ctx["space"], p, threats[0], ex)
		c["hidden"] = hidden
		c["cover"] = cover
		c["route_len"] = route_len
		c["route_exposed"] = not threats.is_empty() and route_exposed(ctx["space"], path, threats[0], ex)
		out.append(c)
	return out


## Whether a walk from where the NPC stands to `p` is over the moment it begins: the point on the navmesh it ends at is within a `STRIDE`
## of walking (cheap straight-line test first).
func where_it_stands(ctx: Dictionary, p: Vector2) -> bool:
	var self_pos: Vector2 = ctx["self_pos"]
	var q := NavBuilder.snap(ctx["map"], p)
	return self_pos.distance_to(q) < STRIDE and NavBuilder.path_length(NavBuilder.route(ctx["map"], self_pos, q)) < STRIDE


## The spot beside the ally at `ally` that the NPC falls back to: `BESIDE_ALLY` px behind it from `threat` (the ally between the NPC
## and the threat), else to one side of it; open floor (the navmesh does not pull it) with no wall between it and the ally. INF when
## there is none.
func _beside(ctx: Dictionary, ally: Vector2, threat: Vector2) -> Vector2:
	var away := (ally - threat).normalized()
	if away == Vector2.ZERO:
		away = Vector2.RIGHT
	for turn in [0.0, PI * 0.5, -PI * 0.5]:
		var p: Vector2 = ally + away.rotated(turn) * BESIDE_ALLY
		var q := NavBuilder.snap(ctx["map"], p)
		if q.distance_to(p) <= 3.0 and not blocked(ctx["space"], ally, q, ctx["exclude"]):
			return q
	return Vector2.INF


## The facts about standing at `p` to fight `target`: clear shot, cover, route length, exposure.
## `path` is the route there when the caller already has it.
func _annotate(ctx: Dictionary, target: Dictionary, p: Vector2, ex: Array, path := PackedVector2Array()) -> Dictionary:
	var tpos: Vector2 = target["pos"]
	if path.is_empty():
		path = NavBuilder.route(ctx["map"], ctx["self_pos"], p)
	return {
		"point": p,
		"clear_shot": not blocked(ctx["space"], p, tpos, ex),
		"cover": cover_near(ctx["space"], p, tpos, ex),
		"route_len": NavBuilder.path_length(path),
		"route_exposed": false,
		"exposed_to": exposed_to(ctx["space"], p, ctx["hostiles"], target["id"], ctx["exclude"]),
	}


## Distance from `p` to the nearest of `threats` (INF with none).
func _nearest_gap(p: Vector2, threats: Array) -> float:
	var best := INF
	for t in threats:
		best = minf(best, p.distance_to(t))
	return best


## The contact's body rid as a one-element array, for excluding it from a ray (empty when gone).
func body_rid(contact: Dictionary) -> Array:
	var n = contact.get("node")
	return [n.get_rid()] if n is Node and is_instance_valid(n) and n.has_method("get_rid") else []

extends RefCounted

## AI PERCEPTION sub-domain — TACTICS: the combat geometry an NPC reads off what it knows. Pure
## queries over known contacts, the physics space (via the vision sense's ray helpers) and the
## navigation map (Navigation interface 9): where it could flank a target from, which spots give a
## clear shot or cover, how to close in, where to fall back to — each candidate annotated with the
## facts a tactical choice turns on (clear shot, cover, route length and exposure, which ally already
## holds a side, which other hostile would see it). It returns DATA only; the perception turns that
## into the words Von reads. It holds no policy and never decides.
##
## A target's FLANKS are measured in its own frame: its front is where it was last seen facing (when
## recent), else the side facing this NPC. Left/right are the target's own left/right.

## The flanking sides offered, as degrees off the target's front (screen space, +y down).
const SIDES := { "left": -90.0, "right": 90.0, "rear": 180.0 }
## How far (px) a sampled point may be pulled by navmesh snapping before it counts as unreachable.
const SNAP_TOLERANCE := 48.0
## Points sampled along a route to judge whether the target can see it.
const ROUTE_SAMPLES := 8

var vision: RefCounted               ## The perception's sight sense; owner of the ray queries.
var cover_min: float = 40.0          ## Surface coverage at or above which a blocking object is cover.
var flank_distance: float = 220.0    ## Distance (px) from the target a flanking spot is sought at.
var flank_arc: float = 60.0          ## Angular spread (degrees) sampled around each side's bearing.
var flank_ally_radius: float = 500.0 ## An ally this close to the target holds the side it stands on.
var shoot_range: float = 500.0       ## Pistol range (px): a spot beyond it gives no shot.
var combat_ring_radius: float = 80.0 ## Radius (px) of the ring of nearby candidate fighting spots.
var combat_ring_count: int = 12      ## Points sampled on that ring.
var still_speed: float = 20.0        ## Speed (px/s) under which a contact counts as standing still.


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
	if obj == null or obj.has_method("current_item") or not obj.has_method("get_surface"):
		return false
	return float(obj.get_surface().get("coverage", 0.0)) >= cover_min


## A readable name for a blocking object ("fridge", "wall").
func object_label(obj: Object) -> String:
	if obj == null:
		return ""
	var named = obj.get("object_name")
	if named is String and named != "":
		return named.to_lower()
	return "wall" if str(obj.get("name")).to_lower().begins_with("wall") else str(obj.get("name")).to_lower()


## `p` snapped onto the navmesh (unchanged while the map isn't ready).
func snap(map: RID, p: Vector2) -> Vector2:
	if not map.is_valid() or NavigationServer2D.map_get_iteration_id(map) == 0:
		return p
	return NavigationServer2D.map_get_closest_point(map, p)


## The navigated route `from`→`to` (a straight segment while the map isn't ready).
func route(map: RID, from: Vector2, to: Vector2) -> PackedVector2Array:
	if not map.is_valid() or NavigationServer2D.map_get_iteration_id(map) == 0:
		return PackedVector2Array([from, to])
	var path := NavigationServer2D.map_get_path(map, from, to, true)
	return path if path.size() >= 2 else PackedVector2Array([from, to])


## Total length (px) of a route.
func path_length(path: PackedVector2Array) -> float:
	var total := 0.0
	for i in range(1, path.size()):
		total += path[i - 1].distance_to(path[i])
	return total


## Whether most of a route lies in the open from `threat` (a clear line from it to most samples).
func route_exposed(space, path: PackedVector2Array, threat: Vector2, exclude: Array) -> bool:
	var total := path_length(path)
	if total <= 0.0:
		return false
	var seen := 0
	for i in ROUTE_SAMPLES:
		if not blocked(space, threat, _along(path, total * (i + 1) / (ROUTE_SAMPLES + 1)), exclude):
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


## The ally whose line of fire on the target passes close to `p`, or "".
func ally_lane(p: Vector2, target_pos: Vector2, allies: Array) -> String:
	for a in allies:
		var apos: Vector2 = a["pos"]
		if apos.distance_to(target_pos) > flank_ally_radius:
			continue
		if Geometry2D.get_closest_point_to_segment(p, apos, target_pos).distance_to(p) < 40.0:
			return a["name"]
	return ""


# --- Candidate positions ---------------------------------------------------------------------

## The flanking spots around `target` (one per side, excluding the side this NPC is already on), each
## annotated. `ctx` = { space, map, self_pos, exclude, hostiles, allies, callouts }.
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
		var path := route(ctx["map"], ctx["self_pos"], p)
		var vel: Vector2 = target.get("vel", Vector2.ZERO)
		out.append({
			"side": side,
			"point": p,
			"clear_shot": not blocked(ctx["space"], p, tpos, ex),
			"cover": cover_near(ctx["space"], p, tpos, ex),
			"route_len": path_length(path),
			"route_exposed": route_exposed(ctx["space"], path, tpos, ex),
			"held_by": side_holder(target, front, side, ctx["allies"], ctx["callouts"]),
			"exposed_to": exposed_to(ctx["space"], p, ctx["hostiles"], target["id"], ctx["exclude"]),
			"heading_toward": vel.length() >= still_speed and absf(vel.angle_to(p - tpos)) < PI / 3.0,
			"ally_lane": ally_lane(p, tpos, ctx["allies"]),
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
			var p := snap(ctx["map"], raw)
			if p.distance_to(raw) > SNAP_TOLERANCE or side_of(tpos, front, p) != side:
				continue
			if not blocked(ctx["space"], p, tpos, ex):
				return p
			if fallback == null:
				fallback = p
	return fallback


## Where to fight `target` from: `here` (this spot, when it has a clear shot in range), nearby `spots`
## with a clear shot (two rings, one per compass sector), and an `ambush` spot in cover. Each spot is
## annotated with cover and exposure to other hostiles.
func fire_positions(ctx: Dictionary, target: Dictionary) -> Dictionary:
	var tpos: Vector2 = target["pos"]
	var self_pos: Vector2 = ctx["self_pos"]
	var ex: Array = ctx["exclude"] + body_rid(target)
	var out := { "here": {}, "spots": [], "ambush": {} }
	if self_pos.distance_to(tpos) <= shoot_range and not blocked(ctx["space"], self_pos, tpos, ex):
		out["here"] = _annotate(ctx, target, self_pos, ex)
	var by_sector := {}
	var ambush = null
	for radius in [combat_ring_radius, combat_ring_radius * 2.0]:
		var ring := combat_spots(ctx["space"], self_pos, tpos, ex, radius, combat_ring_count)
		for p in ring["fire"]:
			var sector := posmod(int(round((p - self_pos).angle() / (TAU / 8.0))), 8)
			if not by_sector.has(sector) and p.distance_to(tpos) <= shoot_range:
				by_sector[sector] = _annotate(ctx, target, p, ex)
		if ambush == null and not ring["cover"].is_empty():
			ambush = ring["cover"][0]
	var spots: Array = by_sector.values()
	# Spots with cover close by first, then the shortest step.
	spots.sort_custom(func(a, b):
		if (a["cover"] != "") != (b["cover"] != ""):
			return a["cover"] != ""
		return a["dist"] < b["dist"])
	out["spots"] = spots
	if ambush != null:
		var a := _annotate(ctx, target, ambush, ex)
		a["cover"] = object_label(blocker(ctx["space"], ambush, tpos, ex))
		out["ambush"] = a
	return out


## Ways to close in on `target`: points part-way along the route to it (with any cover there) and its
## last-known position itself.
func advance_positions(ctx: Dictionary, target: Dictionary) -> Array:
	var tpos: Vector2 = target["pos"]
	var ex: Array = ctx["exclude"] + body_rid(target)
	var path := route(ctx["map"], ctx["self_pos"], tpos)
	var total := path_length(path)
	var out: Array = []
	if total > 160.0:
		for frac in [0.5, 0.75]:
			var p := snap(ctx["map"], _along(path, total * frac))
			var a := _annotate(ctx, target, p, ex)
			a["fraction"] = frac
			out.append(a)
	var rush := _annotate(ctx, target, snap(ctx["map"], tpos), ex)
	rush["rush"] = true
	rush["route_exposed"] = route_exposed(ctx["space"], path, tpos, ex)
	out.append(rush)
	return out


## Places to fall back to from `threats` (world points): known room centres, cover spots nearby, and
## a spot beside each nearby ally — each annotated with whether it is hidden from every threat, farther
## from the nearest threat than here, cover, route and the ally it lies toward.
func retreat_positions(ctx: Dictionary, threats: Array, rooms: Array) -> Array:
	var self_pos: Vector2 = ctx["self_pos"]
	var here_gap := _nearest_gap(self_pos, threats)
	# Rays toward a threat end on the hostile's own body — it must not count as what hides a spot.
	var ex: Array = ctx["exclude"].duplicate()
	for h in ctx["hostiles"]:
		ex += body_rid(h)
	var candidates: Array = []
	for room in rooms:
		var rect: Rect2 = room["rect"]
		if rect.has_point(self_pos):
			continue
		candidates.append({ "point": snap(ctx["map"], rect.get_center()), "room": str(room.get("type", "room")).replace("_", " ") })
	if not threats.is_empty():
		var nearest: Vector2 = threats[0]
		for p in combat_spots(ctx["space"], self_pos, nearest, ex, combat_ring_radius * 2.0, combat_ring_count)["cover"]:
			candidates.append({ "point": p, "room": "" , "nearby": true })
	for a in ctx["allies"]:
		candidates.append({ "point": snap(ctx["map"], a["pos"]), "room": "", "ally": a["name"] })
	var out: Array = []
	for c in candidates:
		var p: Vector2 = c["point"]
		var hidden := true
		for t in threats:
			if not blocked(ctx["space"], t, p, ex):
				hidden = false
				break
		var gap := _nearest_gap(p, threats)
		if not hidden and gap <= here_gap:
			continue  # Neither out of sight nor farther away: not a retreat.
		var path := route(ctx["map"], self_pos, p)
		var cover := ""
		if not threats.is_empty():
			cover = cover_near(ctx["space"], p, threats[0], ex)
		c["hidden"] = hidden
		c["farther"] = gap > here_gap
		c["cover"] = cover
		c["route_len"] = path_length(path)
		c["route_exposed"] = not threats.is_empty() and route_exposed(ctx["space"], path, threats[0], ex)
		out.append(c)
	return out


## The facts about standing at `p` to fight `target`: clear shot, cover, step length, exposure.
func _annotate(ctx: Dictionary, target: Dictionary, p: Vector2, ex: Array) -> Dictionary:
	var tpos: Vector2 = target["pos"]
	var path := route(ctx["map"], ctx["self_pos"], p)
	return {
		"point": p,
		"clear_shot": not blocked(ctx["space"], p, tpos, ex),
		"cover": cover_near(ctx["space"], p, tpos, ex),
		"dist": (ctx["self_pos"] as Vector2).distance_to(p),
		"route_len": path_length(path),
		"route_exposed": false,
		"exposed_to": exposed_to(ctx["space"], p, ctx["hostiles"], target["id"], ctx["exclude"]),
		"to_target": p.distance_to(tpos),
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

extends RefCounted

## Shared helpers for the throw-spot tests (tests/ai/grenade/grenade_throw_spot_*, grenade_walks_to_throw_spot, grenade_shots_origin_throw_spot;
## not a test itself): `const Spot := preload("res://tests/_ai/throw_spot_probe.gd")`. The behaviour they assert is `docs/grenades.md` G17:
## GRENADE is also offered when the hostile (or the shots' origin) is out of range or has no clear lob from where the NPC stands, if a reachable
## throw spot exists (a point on the navmesh within the grenade's range of the spot, with a clear lob, a short walk away); the `throw`
## primitive walks there first, then throws, and the ally-in-blast and self-safety tags are judged from the throw spot.
##
## The read-out the tests rely on (reached duck-typed): the controller's `debug_zones()` lists every `grenade_throws` option of the last
## snapshot (the bound hostile's and the shots' one, dropped ones included) as a zone of category `grenade`, with `point` (where the grenade is
## to burst), `from` (the throw spot: where it throws from, its own position when it throws from where it stands) and `tags` (`ally_in_blast`,
## `no_safe_spot`, judged with the thrower at `from`).

const Probe := preload("res://tests/_ai/grenade_probe.gd")

## The throw range of both kinds (`max_range` 550): a spot farther than this from the NPC is out of range, and a throw spot must be within it.
const THROW_RANGE := 550.0
## The tests' reading of "a short walk away": the walk to a throw spot, for a target out of range by 100 px or less, is at most this long.
const SHORT_WALK := 250.0
## The release height of a lob (`AgentThrow.LOB_CLEARANCE`, the spec's number): furniture at or below it does not stop a lob, a wall always does.
const LOB_CLEARANCE := 50.0


## The `grenade` zones of `brain`'s last snapshot (`debug_zones()` entries of category `grenade`); [] before the read-out exists.
static func throws(brain: Node) -> Array:
	if not brain.has_method("debug_zones"):
		return []
	return brain.debug_zones().filter(func(z): return str(z.get("category", "")) == "grenade")


## The throw spot of zone `z` (its `from`), or `Vector2.INF` when it has none.
static func from_of(z: Dictionary) -> Vector2:
	var f = z.get("from", null)
	return f if f is Vector2 else Vector2.INF


## The test's own lob test: nothing taller than `LOB_CLEARANCE` (a wall, a tall piece) lies on the straight line from `a` to `b`; characters
## are looked past.
static func lob_clear(t: TestContext, a: Vector2, b: Vector2) -> bool:
	var exclude := Probe.character_rids(t)
	var space := t.world.get_world_2d().direct_space_state
	for i in 12:
		var query := PhysicsRayQueryParameters2D.create(a, b, PhysicsLayers.SOLID)
		query.exclude = exclude
		var hit := space.intersect_ray(query)
		if hit.is_empty():
			return true
		var collider: Object = hit["collider"]
		var height := float(collider.get_surface().get("coverage", 100.0)) if collider.has_method("get_surface") else 100.0
		if height > LOB_CLEARANCE:
			return false
		exclude.append(hit["rid"])
	return false


## How far (px) either side of the line from the hand a lob must be clear (G17, the doc's number, not the code's).
const LOB_MARGIN := 8.0


## The spec's lob from the hand (G17): a grenade leaves `thrower`, standing at `at` and facing `to`, from its throwing hand (where the
## Character says a grenade leaves it, `throw_release_offset`: the hand of its `throw` stance), and the lob is clear only when the test's own
## `lob_clear` holds along the band `LOB_MARGIN` px either side of the line from there (its middle and both edges, the whole way).
static func hand_lob_clear(t: TestContext, thrower: Node, at: Vector2, to: Vector2) -> bool:
	var toward := (to - at).normalized()
	var right := toward.rotated(PI * 0.5)
	var offset: Vector2 = thrower.throw_release_offset(Probe.STUN if Probe.count(thrower, Probe.STUN) > 0 else Probe.FRAG)
	var hand := at + toward * offset.x + right * offset.y
	var side := (to - hand).normalized().rotated(PI * 0.5) * LOB_MARGIN
	return lob_clear(t, hand, to) and lob_clear(t, hand + side, to + side) and lob_clear(t, hand - side, to - side)


## The walk on the world's navigation map from `a` to `b`: `{ len, reaches }` (`reaches`: the route ends within 12 px of `b`).
static func walk(t: TestContext, a: Vector2, b: Vector2) -> Dictionary:
	var map := t.world.get_world_2d().navigation_map
	var path: PackedVector2Array = NavBuilder.route(map, a, b)
	return { "len": NavBuilder.path_length(path), "reaches": not path.is_empty() and path[path.size() - 1].distance_to(b) <= 12.0 }


## Whether any point every 10 px along the stretch `a`..`b` has a clear lob (the test's own `lob_clear`) from `from` within `reach` px.
static func any_lob_along(t: TestContext, from: Vector2, a: Vector2, b: Vector2, reach: float) -> bool:
	var n := maxi(1, ceili(a.distance_to(b) / 10.0))
	for i in n + 1:
		var p := a.lerp(b, float(i) / float(n))
		if from.distance_to(p) <= reach and lob_clear(t, from, p):
			return true
	return false


## Follow the decision walks of `brain` (the NPC `npc`) every frame: call it once a frame with the same `state` ({} at first) and `walks`
## ([] at first). Each walk started is noted with where the NPC stood when it began (the snapshot it decides over is made then); once it is
## over, `walks` gains `{ time, pos, levels, combat }` (`combat`: the option ids the last COMBAT level offered, [] when it had none).
static func note(t: TestContext, brain: Node, npc: Node2D, state: Dictionary, walks: Array) -> void:
	var st: Dictionary = brain.debug_state()
	var dec: Dictionary = st.get("decision", {})
	var count := int(st.get("decisions", 0))
	if count != int(state.get("count", 0)):
		if state.has("pos") and not state.get("logged", true):
			_close(state, walks, dec)  # A walk that ended and was replaced within a frame.
		state["count"] = count
		state["pos"] = npc.global_position
		state["start"] = t.time
		state["logged"] = false
	if not state.get("logged", true) and not dec.get("pending", false):
		_close(state, walks, dec)


## Note the walk under way in `state` as over: append it to `walks` with the levels `dec` (the planner's state) holds for it.
static func _close(state: Dictionary, walks: Array, dec: Dictionary) -> void:
	var levels: Array = (dec.get("levels", []) as Array).duplicate(true)
	var combat: Array = []
	for l in levels:
		if l.get("node", "") == "combat":
			combat = (l.get("offered", {}) as Dictionary).keys()
	walks.append({ "time": state["start"], "pos": state["pos"], "levels": levels, "combat": combat, "path": dec.get("path", "") })
	state["logged"] = true


## The walks of `walks` that asked the COMBAT level (offered tactics), as short strings for messages.
static func describe(walks: Array) -> Array:
	return walks.filter(func(w): return not w["combat"].is_empty()).map(func(w): return "%.1fs at %s: %s" % [w["time"], str((w["pos"] as Vector2).round()), str(w["combat"])])

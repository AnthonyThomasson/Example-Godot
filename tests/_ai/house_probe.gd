extends RefCounted

## Shared helpers for the "defenders stay in the house" tests (tests/ai/defenders_stay_in_house_*; not a test itself): place
## defenders (and optionally invaders) in a generated house the way Main does, then watch whether a defender ever steps outside.

const MatchSpawner := preload("res://scenes/match_spawner.gd")
## How far past a room's rectangle (px) a defender may stand before it has left: a doorway's depth.
const SLACK := 30.0


## Place `defenders` defenders in random rooms and `invaders` invaders around the outside, as Main does (seeded by `seed`);
## returns the spawner (its `combatants` are the defenders first, then the invaders).
static func spawn(t: TestContext, seed_value: int, defenders: int, invaders: int) -> RefCounted:
	var spawner = MatchSpawner.new()
	spawner.world = t.world
	spawner.openings = t.world.openings
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	for i in defenders:
		spawner.spawn_defender(t.rooms, rng, i)
	var entrance := Vector2.ZERO
	for o in WorldGen.get_openings(t.world.get("house")):
		if o["front"]:
			entrance = o["pos"]
	for i in invaders:
		spawner.spawn_invader(t.rooms, rng, i, invaders, entrance)
	return spawner


## Whether `p` is within the house: inside some room's rectangle, with a doorway's slack.
static func inside(t: TestContext, p: Vector2) -> bool:
	for room in t.rooms:
		if (room["rect"] as Rect2).grow(SLACK).has_point(p):
			return true
	return false


## Watch `defenders` for `seconds`; returns {} when none ever left the house, else what the first to leave was doing
## (`name`, `at`, `t`, `status`, `path`).
static func watch(t: TestContext, defenders: Array, seconds: float) -> Dictionary:
	var elapsed := 0.0
	var history := {}
	while elapsed < seconds:
		await t.seconds(0.1)
		elapsed += 0.1
		for npc in defenders:
			if not is_instance_valid(npc) or npc.get("is_dead"):
				continue
			var brain: Node = npc.get_node("GoalController")
			var trail: Array = history.get(npc.name, [])
			if trail.is_empty() or elapsed - trail[-1]["t"] >= 0.5:
				var st: Dictionary = brain.debug_state()
				trail.append({ "t": snappedf(elapsed, 0.1), "at": npc.global_position.round(), "act": brain.current_act(),
					"to": st.get("params", {}).get("point", null), "arrived": st.get("arrived"), "prim": st.get("primitive") })
				history[npc.name] = trail.slice(-14)
			if not inside(t, npc.global_position):
				return { "name": npc.name, "at": npc.global_position.round(), "t": snappedf(elapsed, 0.1),
					"status": brain.debug_status(), "nearest_room": _nearest_room(t, npc.global_position),
					"levels": _levels(brain), "asked": _last_asked(brain), "trail": history[npc.name] }
	return {}


## The room whose rectangle is closest to `p`, as "key rect", for a failure message.
static func _nearest_room(t: TestContext, p: Vector2) -> String:
	var best := ""
	var best_d := INF
	for room in t.rooms:
		var rect: Rect2 = room["rect"]
		var d := p.distance_to(Vector2(clampf(p.x, rect.position.x, rect.end.x), clampf(p.y, rect.position.y, rect.end.y)))
		if d < best_d:
			best_d = d
			best = "%s %s (%.0f px away)" % [room["key"], rect, d]
	return best


## The last decision walk's levels as "node: pick (of offered)" lines.
static func _levels(brain: Node) -> Array:
	var out: Array = []
	for l in brain.debug_state().get("decision", {}).get("levels", []):
		out.append("%s: %s of %s%s" % [l.get("node"), l.get("pick"), (l.get("offered", {}) as Dictionary).keys(), " (auto)" if l.get("auto", false) else ""])
	return out


## What Von was last asked about investigating (state, offered ids, its probabilities and pick), for a failure message.
static func _last_asked(brain: Node) -> Dictionary:
	var found := {}
	for l in brain.debug_state().get("decision", {}).get("levels", []):
		if (l.get("offered", {}) as Dictionary).has("stay") or String(l.get("node")) == "investigate":
			found = { "node": l.get("node"), "state": l.get("state"), "offered": l.get("offered"), "pick": l.get("pick"), "p": l.get("probabilities") }
	return found

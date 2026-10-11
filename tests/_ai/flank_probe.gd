extends RefCounted

## Shared helpers for the flanking tests (tests/ai/flank_*_test.gd; not a test itself). Everything reads
## an NPC through its public observer API: `debug_state()` (the last decision walk's levels) and
## `debug_zones()` (every flank side the snapshot weighed, including those the planner then dropped).

## How a side reads at the start of its option description (agent_snapshot.gd SIDE_WORDS).
const SIDE_WORDS := { "left": "their left side", "right": "their right side", "rear": "behind them" }

## The standard flank script: tactic combat, then flank, then the first side offered from this list.
const SCRIPT_LEFT := [{ "pick": "combat" }, { "pick": "flank" }, { "pick": "side_left" }, { "pick": "side_right" }, { "pick": "side_rear" }]


## A target at `pos` standing still and already facing `look_at`: a household puppet (hostile to an
## invader on sight). The aim point and facing are set before the first frame, because the NPC decides
## on its very first tick and reads the target's facing then. `props` merge over the defaults.
static func target(s: TestSetup, id: StringName, pos: Vector2, look_at: Vector2, props: Dictionary = {}) -> void:
	var p := { "faction": &"household", "max_health": 1000000.0, "aim_point": look_at, "facing": (look_at - pos).normalized() }
	p.merge(props, true)
	s.actor(id, &"puppet", pos, p)


## Scripted Von and the switches every flank test shares: no gunfire interference from trespass hostility
## or bullets flying over cover. Call it after the map (`Maps.house(s)` etc.) has laid out the world.
static func rules(s: TestSetup, script: Array = SCRIPT_LEFT) -> void:
	s.von_script(script)
	s.switch(&"ai.hostile_on_trespass", false)
	s.switch(&"projectile.flyover", false)


## An NPC held in place so the geometry it judges stays fixed: no movement (`speed` 0) and a short
## commit/tactic cadence so it re-decides every ~0.4 s and a test can read a full decision after a moment.
## `look_at` sets its starting facing (default: unset), `gc` overrides GoalController exports.
static func npc(s: TestSetup, id: StringName, pos: Vector2, gc: Dictionary = {}, kind: StringName = &"invader", look_at := Vector2.INF) -> void:
	var props := { "speed": 0.0 }
	if look_at != Vector2.INF:
		props["facing"] = (look_at - pos).normalized()   # starts looking at the fight, so the target is in its view cone
	s.actor(id, kind, pos, props)
	var cadence := { "max_commit_time": 0.4, "tactic_interval": 0.4, "decide_interval": 0.4 }
	cadence.merge(gc, true)
	s.set_props(id, "GoalController", cadence)


## Let a held NPC (see `npc`) run its ~0.4 s decision cadence a couple of times, then wait out any walk
## in flight, so `levels` / `zones` describe a full decision made on a synced navmesh.
static func settle(t: TestContext, brain: Node) -> bool:
	await t.seconds(1.0)
	return await t.until(func(): return not brain.debug_state().get("decision", {}).get("pending", false) and not levels(brain).is_empty(),
		3.0, "the NPC finished a decision")


## The decision levels of the NPC's last walk (empty before its first decision).
static func levels(brain: Node) -> Array:
	var d: Dictionary = brain.debug_state().get("decision", {})
	return d.get("levels", [])


## The last level of node `node` (`combat` = the tactic level, `flank` = the side level), or {}.
static func level(brain: Node, node: String) -> Dictionary:
	var found := {}
	for l in levels(brain):
		if l["node"] == node:
			found = l
	return found


## The option ids offered at `node`'s level of the last walk.
static func offered(brain: Node, node: String) -> Array:
	return level(brain, node).get("offered", {}).keys()


## The flank sides ("left" / "right" / "rear") the NPC's last walk offered at the flank level.
static func offered_sides(brain: Node) -> Array:
	var out: Array = []
	for id in offered(brain, "flank"):
		out.append(String(id).trim_prefix("side_"))
	return out


## One line per weighed flank side (point, place, shot, cover, route, tags) for failure messages.
static func dump(brain: Node, around := Vector2.INF) -> String:
	var lines: Array = []
	var weighed := zones(brain, around)
	for side in weighed:
		var z: Dictionary = weighed[side]
		var tg: Dictionary = z["tags"]
		lines.append("%s %s %s%s%s %s%s" % [side, z["point"].round(), "inside" if tg.get("inside") else "outside",
			" held" if tg.get("held") else "", (" crosses " + String(tg.get("crosses_name", ""))) if tg.get("crosses") else "", "clear" if tg.get("clear_shot") else "blocked",
			" lane:" + tg["ally_lane"] if tg.get("ally_lane") else ""])
	return "; ".join(lines)


## The flank zones of the last snapshot, keyed by side ("left" / "right" / "rear"): `{ point, desc, tags }`.
## With several hostiles known, `around` (a target's position) keeps only that target's zones: a flank
## point lies within about 270 px of the target it belongs to.
static func zones(brain: Node, around := Vector2.INF) -> Dictionary:
	var out := {}
	for z in brain.debug_zones():
		if z["category"] != &"flank":
			continue
		if around != Vector2.INF and (z["point"] as Vector2).distance_to(around) > 270.0:
			continue
		for side in SIDE_WORDS:
			if String(z["desc"]).begins_with(SIDE_WORDS[side]):
				out[side] = z
	return out


## Make the NPCs fight `target_id` (an actor id) whenever they are asked which hostile to fight, so the
## options read are that target's flanks. Each hostile is an option named `t_<instance id>`.
static func prefer_target(t: TestContext, target_id: StringName) -> void:
	var rules: Array = DecisionStub.rules.duplicate()
	rules.push_front({ "pick": "t_%d" % t.actor(target_id).get_instance_id(), "question": "Which hostile" })
	DecisionStub.rules = rules


## Which side of a target at `tpos` facing `facing` (unit vector) the point `p` lies on — the test's own
## copy of the frame (front ±45°, rear ±45° behind, left/right between), so the spec isn't read back
## from the code under test. "left" is the target's own left.
static func side_of(tpos: Vector2, facing: Vector2, p: Vector2) -> String:
	var d := angle_difference(facing.angle(), (p - tpos).angle())
	if absf(d) <= PI * 0.25:
		return "front"
	if absf(d) >= PI * 0.75:
		return "rear"
	return "left" if d < 0.0 else "right"


## The point `dist` px from a target at `tpos` on its own `side` ("left" / "right" / "rear") when it
## faces `facing` (a unit vector) — where a flank point on that side lies, in the same frame as `side_of`.
static func side_point(tpos: Vector2, facing: Vector2, side: String, dist := 220.0) -> Vector2:
	var turn := { "left": -PI / 2.0, "right": PI / 2.0, "rear": PI }[side] as float
	return tpos + facing.rotated(turn) * dist


## An ally of the NPC (same faction as the invader preset) standing at `pos`, for seen-ally and radio
## tests. `props` merge over the defaults.
static func ally(s: TestSetup, id: StringName, pos: Vector2, props: Dictionary = {}) -> void:
	var p := { "faction": &"invader", "max_health": 1000000.0 }
	p.merge(props, true)
	s.actor(id, &"puppet", pos, p)


## `speaker` (an ally actor) radios that it is going to `point`, as a deciding AI controller would
## (EventBus `callout`, interface 10). The NPC hears it for `callout_ttl` seconds.
static func radio(t: TestContext, speaker: StringName, point: Vector2) -> void:
	var who := t.actor(speaker)
	EventBus.post(&"callout", {
		"speaker": who, "faction": who.faction, "position": who.global_position, "status": "",
		"path": "combat/flank", "label": "COMBAT - target - FLANK", "target_id": 0, "point": point,
	})


## The flank side an NPC is carrying out ("left" / "right" / "rear"), from its decision path, or "".
static func side_of_act(brain: Node) -> String:
	var act := String(brain.current_act())
	for side in SIDE_WORDS:
		if act.ends_with("flank/side_" + side):
			return side
	return ""


## The navmesh route `from` > `to` in the test's world (what an NPC would walk).
static func route(t: TestContext, from: Vector2, to: Vector2) -> PackedVector2Array:
	return NavigationServer2D.map_get_path(t.world.get_world_2d().navigation_map, from, to, true)


## Whether walking the route `from` > `to` crosses the line of fire between `shooter` and `target_pos`.
static func crosses_fire_line(t: TestContext, from: Vector2, to: Vector2, shooter: Vector2, target_pos: Vector2) -> bool:
	var path := route(t, from, to)
	for i in range(1, path.size()):
		if Geometry2D.segment_intersects_segment(path[i - 1], path[i], shooter, target_pos) != null:
			return true
	return false


## The number of flank callouts posted on the radio so far.
static func sides_claimed(t: TestContext) -> int:
	return t.events_of(&"callout", func(d): return String(d.get("path", "")).contains("flank")).size()


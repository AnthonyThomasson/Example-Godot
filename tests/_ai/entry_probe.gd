extends RefCounted

## Shared helpers for the tactical-entry tests (tests/ai/entry/; not a test itself). The behaviour they
## assert is `docs/tactical-entry.md` (E1 to E9). The doorway geometry here is the test's own copy (a door's axis,
## its outward side, the funnel), so the spec isn't read back from the code under test; the NPC is read only
## through its public observer API: `current_act()`, `debug_entry()`, `debug_room_zones()` and its radio callouts.

const Maps := preload("res://tests/_ai/flank_maps.gd")

## The Terrace house doorways the tests go through, each with the side the team stacks on (`out`, a unit normal
## pointing away from the room being entered) and the room behind it.
const BACK := { "id": "door_840_190", "pos": Maps.DOOR_BACK, "width": 90.0, "out": Vector2.RIGHT, "room": Maps.HOUSE_KITCHEN, "room_key": "kitchen" }
const FRONT := { "id": "door_0_415", "pos": Maps.DOOR_FRONT, "width": 80.0, "out": Vector2.LEFT, "room": Maps.HOUSE_HALL, "room_key": "hall" }
const KITCHEN_LIVING := { "id": "door_480_150", "pos": Maps.DOOR_LIVING_KITCHEN, "width": 90.0, "out": Vector2.RIGHT, "room": Maps.HOUSE_LIVING, "room_key": "living_room" }
const HALL_LIVING := { "id": "door_150_360", "pos": Maps.DOOR_HALL_LIVING, "width": 80.0, "out": Vector2.DOWN, "room": Maps.HOUSE_LIVING, "room_key": "living_room" }
## The doorways on out of a cleared room, framed from the side the team holds (`out` points into the cleared room): the
## kitchen's into the hall, and the living room's into the kitchen. With `KITCHEN_LIVING` (the kitchen's into the living
## room) they are what a team that has cleared the kitchen or the living room covers (E8).
const KITCHEN_HALL := { "id": "door_690_360", "pos": Maps.DOOR_HALL_KITCHEN, "width": 80.0, "out": Vector2.UP, "room": Maps.HOUSE_HALL, "room_key": "hall" }
const LIVING_KITCHEN := { "id": "door_480_150", "pos": Maps.DOOR_LIVING_KITCHEN, "width": 90.0, "out": Vector2.LEFT, "room": Maps.HOUSE_KITCHEN, "room_key": "kitchen" }

## How deep (px) the funnel reaches either side of the wall plane: the strip in the doorway where an entrant is exposed.
const FUNNEL_DEPTH := 40.0
## Half the wall thickness plus a body radius: past this far inside the wall plane a body is in the room.
const INSIDE_DEPTH := 22.0


## Scripted Von for an entry through `door`: whenever asked, SEARCH → ENTER → that doorway, and in a fight engage
## (the first firing spot offered). The switches every entry test shares: no trespass hostility, no bullets flying
## over cover. Call it after the map.
static func rules(s: TestSetup, door: Dictionary, extra: Array = []) -> void:
	var script: Array = [{ "pick": "enter" }, { "pick": door["id"] }, { "pick": "engage" }]
	script.append_array(extra)
	s.von_script(script)
	s.switch(&"ai.hostile_on_trespass", false)
	s.switch(&"projectile.flyover", false)


## Scripted Von for a test of the entry guard (E9): whenever asked, the first of `picks` that is offered (ids, in order of
## preference; never ENTER, the point is a plain order that crosses a doorway), the same shared switches as `rules`. Call
## it after the map.
static func guard_rules(s: TestSetup, picks: Array) -> void:
	s.von_script(picks.map(func(p): return { "pick": p }))
	s.switch(&"ai.hostile_on_trespass", false)
	s.switch(&"projectile.flyover", false)


## An invader at `pos` that walks (unlike `flank_probe.npc`, which holds still). `cadence` offsets its decide
## timers so two invaders never decide on the same frame unless a test wants them to; `gc` overrides
## GoalController exports, `props` the character's.
static func npc(s: TestSetup, id: StringName, pos: Vector2, cadence := 0.4, gc: Dictionary = {}, props: Dictionary = {}) -> void:
	var p := { "max_health": 1000000.0 }
	p.merge(props, true)
	s.actor(id, &"invader", pos, p)
	var g := { "decide_interval": cadence, "tactic_interval": 3.0, "max_commit_time": 30.0 }
	g.merge(gc, true)
	s.set_props(id, "GoalController", g)


## A household target puppet at `pos` facing `look_at`: hostile to an invader on sight, never killed.
static func target(s: TestSetup, id: StringName, pos: Vector2, look_at: Vector2, props: Dictionary = {}) -> void:
	var p := { "faction": &"household", "max_health": 1000000.0, "aim_point": look_at, "facing": (look_at - pos).normalized() }
	p.merge(props, true)
	s.actor(id, &"puppet", pos, p)


# --- The doorway, in the test's own frame ------------------------------------------------------

## How far `p` lies out from the wall plane of `door` (positive = on the stacking side, negative = in the room).
static func outward(door: Dictionary, p: Vector2) -> float:
	return (p - (door["pos"] as Vector2)).dot(door["out"])


## How far `p` lies along the wall from the door's centre (signed; the sign tells the side of the door axis).
static func lateral(door: Dictionary, p: Vector2) -> float:
	return (p - (door["pos"] as Vector2)).dot((door["out"] as Vector2).orthogonal())


## Whether `p` is in the fatal funnel: inside the doorway's width and within `FUNNEL_DEPTH` of the wall plane.
static func in_funnel(door: Dictionary, p: Vector2) -> bool:
	return absf(lateral(door, p)) < float(door["width"]) * 0.5 and absf(outward(door, p)) < FUNNEL_DEPTH


## Whether a body at `p` facing `facing` points its gun through `door` from the side the door is framed from: it stands
## on the `out` side and looks within about 30° of the doorway's centre.
static func faces_through(door: Dictionary, p: Vector2, facing: Vector2) -> bool:
	var to_door := (door["pos"] as Vector2) - p
	return outward(door, p) > 0.0 and to_door.length() > 1.0 and facing.normalized().dot(to_door.normalized()) > 0.85


## How long (s) actor `id` pointed its gun through `door` (see `faces_through`) in `samples`, optionally only while
## `where` (a Callable on its position) holds.
static func time_facing_through(samples: Array, id: StringName, door: Dictionary, where := Callable()) -> float:
	var total := 0.0
	for i in range(1, samples.size()):
		var sample: Dictionary = samples[i]
		if not sample["pos"].has(id):
			continue
		var p: Vector2 = sample["pos"][id]
		if where.is_valid() and not where.call(p):
			continue
		if faces_through(door, p, sample["facing"][id]):
			total += float(sample["t"]) - float(samples[i - 1]["t"])
	return total


## Whether `p` is in the room behind `door`.
static func in_room(door: Dictionary, p: Vector2) -> bool:
	return (door["room"] as Rect2).has_point(p) and outward(door, p) < -INSIDE_DEPTH


## Whether `p` is against the wall beside the door, out of the doorway's view into the room: on the stacking side,
## close to the wall plane, and clear of the door's width by a body.
static func beside_door(door: Dictionary, p: Vector2) -> bool:
	var o := outward(door, p)
	return o > 0.0 and o <= 48.0 and absf(lateral(door, p)) >= float(door["width"]) * 0.5 + 10.0


## The four corners of the room behind `door`, inset `inset` px: the two on the door's wall (unseen from outside:
## hard) first, then the two far ones.
static func corners(door: Dictionary, inset := 40.0) -> Dictionary:
	var r: Rect2 = (door["room"] as Rect2).grow(-inset)
	var all := [r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]
	all.sort_custom(func(a, b): return outward(door, a) > outward(door, b))
	return { "near": all.slice(0, 2), "far": all.slice(2, 4) }


# --- Watching the run ----------------------------------------------------------------------------

## Sample the actors `ids` every physics frame for up to `duration` s (or until `stop` returns true): one
## `{ t, pos: { id: Vector2 }, facing: { id: Vector2 } }` per frame. Each actor's distance to the door is traced
## for the failure output.
static func watch(t: TestContext, ids: Array, door: Dictionary, duration: float, stop := Callable()) -> Array:
	var samples: Array = []
	var end := t.time + duration
	while t.time < end:
		var pos := {}
		var facing := {}
		for id in ids:
			var a := t.actor(id)
			if a == null:
				continue
			pos[id] = a.global_position
			facing[id] = a.facing
			t.trace("%s_to_door" % id, a.global_position.distance_to(door["pos"]))
		samples.append({ "t": t.time, "pos": pos, "facing": facing })
		if stop.is_valid() and stop.call():
			break
		await t.frames(1)
	return samples


## The positions of actor `id` in `samples`, in order.
static func path_of(samples: Array, id: StringName) -> Array:
	var out: Array = []
	for s in samples:
		if s["pos"].has(id):
			out.append(s["pos"][id])
	return out


## The longest run of time (s) actor `id` spent in the funnel of `door` moving slower than `still_speed` px/s.
static func longest_pause_in_funnel(samples: Array, id: StringName, door: Dictionary, still_speed := 20.0) -> float:
	var longest := 0.0
	var run := 0.0
	for i in range(1, samples.size()):
		var a: Dictionary = samples[i - 1]
		var b: Dictionary = samples[i]
		if not a["pos"].has(id) or not b["pos"].has(id):
			continue
		var dt: float = b["t"] - a["t"]
		var p: Vector2 = b["pos"][id]
		var speed: float = (p - (a["pos"][id] as Vector2)).length() / maxf(dt, 0.0001)
		if in_funnel(door, p) and speed < still_speed:
			run += dt
			longest = maxf(longest, run)
		else:
			run = 0.0
	return longest


## Where actor `id` first stood still (slower than `still_speed` px/s for `still_time` s) inside the room behind
## `door`: the corner it entered to. `Vector2.INF` when it never did.
static func first_stop_in_room(samples: Array, id: StringName, door: Dictionary, still_time := 0.3, still_speed := 15.0) -> Vector2:
	var run := 0.0
	for i in range(1, samples.size()):
		var a: Dictionary = samples[i - 1]
		var b: Dictionary = samples[i]
		if not a["pos"].has(id) or not b["pos"].has(id):
			continue
		var dt: float = b["t"] - a["t"]
		var p: Vector2 = b["pos"][id]
		var speed: float = (p - (a["pos"][id] as Vector2)).length() / maxf(dt, 0.0001)
		if in_room(door, p) and speed < still_speed:
			run += dt
			if run >= still_time:
				return p
		else:
			run = 0.0
	return Vector2.INF



## The position of actor `id` at the first sample at or after time `at`, or Vector2.INF.
static func pos_at(samples: Array, id: StringName, at: float) -> Vector2:
	for s in samples:
		if s["t"] >= at and s["pos"].has(id):
			return s["pos"][id]
	return Vector2.INF


## How many separate times actor `id` stepped into the funnel of `door` in `samples`.
static func funnel_entries(samples: Array, id: StringName, door: Dictionary) -> int:
	var count := 0
	var was_in := false
	for p in path_of(samples, id):
		var now_in := in_funnel(door, p)
		if now_in and not was_in:
			count += 1
		was_in = now_in
	return count


## The time of the first sample where actor `id` is in the funnel of `door`, or INF.
static func first_in_funnel(samples: Array, id: StringName, door: Dictionary) -> float:
	for s in samples:
		if s["pos"].has(id) and in_funnel(door, s["pos"][id]):
			return s["t"]
	return INF


## The time of the last sample where actor `id` is in the funnel of `door`, or -INF.
static func last_in_funnel(samples: Array, id: StringName, door: Dictionary) -> float:
	var last := -INF
	for s in samples:
		if s["pos"].has(id) and in_funnel(door, s["pos"][id]):
			last = s["t"]
	return last


# --- The radio and the brain ---------------------------------------------------------------------

## The NPC brain of actor `id` (its controller, found by `debug_entry`).
static func brain(t: TestContext, id: StringName) -> Node:
	return t.controller(id, &"debug_entry")


## What the brain reports of its running entry (`{}` when it isn't entering): `opening`, `slot`, `solo`,
## `phase`, `seen_fraction`, `hidden_corners`, `corner`, `stack_point`, `pie_sides`.
static func entry(b: Node) -> Dictionary:
	return b.debug_entry() if b != null else {}


## The entry callouts radioed so far, optionally only step `step` and / or only from actor `id`'s character.
static func calls(t: TestContext, step := "", id: StringName = &"") -> Array:
	var who := t.actor(id) if id != &"" else null
	return t.events_of(&"callout", func(d):
		if String(d.get("entry_step", "")) == "":
			return false
		if step != "" and String(d.get("entry_step", "")) != step:
			return false
		return who == null or d.get("speaker") == who)


## The sim time of the first entry callout of step `step` from actor `id` (about doorway `opening` when given), or INF.
static func first_call_time(t: TestContext, step: String, id: StringName, opening := "") -> float:
	var who := t.actor(id)
	for e in t.events:
		if e["topic"] != &"callout" or e["data"].get("speaker") != who or String(e["data"].get("entry_step", "")) != step:
			continue
		if opening == "" or String(e["data"].get("opening", "")) == opening:
			return e["time"]
	return INF


## Whether any Von question so far was answered with an option id starting with `prefix` (a script that picks by id
## falls back to the first option offered, so a test of a plain order checks the order was really the one chosen).
static func asked(t: TestContext, prefix: String) -> bool:
	for r in t.von_requests():
		if String(r["pick"]).begins_with(prefix):
			return true
	return false


## Check that actor `id` got through `door` by tactical entry (E9): it radioed `going_in` for it, no later than the first
## time it stood in the doorway's funnel, and it did not pause in the funnel.
static func check_entered(t: TestContext, samples: Array, id: StringName, door: Dictionary) -> void:
	var going := first_call_time(t, "going_in", id, door["id"])
	var funnel := first_in_funnel(samples, id, door)
	t.check(going < INF, "%s went through %s by entry (it never radioed going_in for it)" % [id, door["id"]])
	if going < INF and funnel < INF:
		t.check(funnel >= going - 0.05, "%s was in the funnel of %s at %.2f s, before it radioed going_in at %.2f s" % [id, door["id"], funnel, going])
	# Up to the moment it is through: a narrow room's corner can lie inside the funnel, and it holds that corner.
	var through := first_call_time(t, "in", id, door["id"])
	var crossing := samples.filter(func(sample): return sample["t"] <= through)
	t.check(longest_pause_in_funnel(crossing, id, door) < 0.5, "%s did not pause in the funnel of %s" % [id, door["id"]])


## The status the brain of actor `id` gives the room with key `room_key` (`current` / `searched` / `unsearched` /
## `unknown`), matched by rect.
static func room_status(t: TestContext, id: StringName, rect: Rect2) -> String:
	for z in brain(t, id).debug_room_zones():
		if (z["rect"] as Rect2) == rect:
			return String(z["status"])
	return ""

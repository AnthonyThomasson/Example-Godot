extends RefCounted

## Shared helpers for the suspect-room STUN ENTRY tests (tests/ai/grenade/stun_entry_*; not a test itself):
## `const Suspect := preload("res://tests/_ai/suspect_probe.gd")`. The behaviour they assert is `docs/grenades.md` G18 as amended by
## issue #51 (R6): besides gunfire heard there and a hostile seen going in, a room is suspect when an ally radioed a hostile or a fight
## in it, the NPC was shot at from it, a hostile was lost near its doorway or heading in, or footsteps were heard there; a stack that
## carries a stun then takes STUN ENTRY into it, and quiet ENTER where nothing makes it suspect (`quiet_entry_unsuspected_room`).
##
## The world is `stun_entry_suspect_room`'s: the bare Terrace house and a stack of two invaders in the back garden, both armed with
## one stun at the start of `run` (the test world keeps the default inventory; this is how Main arms a spawn). Each test adds the one
## thing that makes the kitchen suspect, first thing in `run` so it is in the stack's first decision.

const Entry := preload("res://tests/_ai/entry_probe.gd")
const Maps := preload("res://tests/_ai/flank_maps.gd")
const Probe := preload("res://tests/_ai/grenade_probe.gd")
const IDS := [&"a", &"b"]
const A_AT := Vector2(960, 60)
const B_AT := Vector2(985, 110)


## The bare Terrace house with the two invaders at `a_at` and `b_at` (by default north-east of the back door, as in
## `stun_entry_suspect_room`), with character `props` (e.g. a `facing`). `b_at` `Vector2.INF` leaves `b` out: a lone invader
## is a stack of one, its own thrower.
static func world(s: TestSetup, a_at := A_AT, b_at := B_AT, props: Dictionary = {}) -> void:
	Maps.house(s, false)
	s.actor(&"a", &"invader", a_at, props.duplicate())
	if b_at != Vector2.INF:
		s.actor(&"b", &"invader", b_at, props.duplicate())


## The stack's members in this test's world (`a`, and `b` when it was placed).
static func ids(t: TestContext) -> Array:
	return IDS.filter(func(id): return t.actor(id) != null)


## Arm both invaders with one stun (call it first thing in `run`); false when they do not carry it.
static func arm(t: TestContext) -> bool:
	for id in ids(t):
		Probe.arm(t.actor(id), 1, 0)
	return ids(t).all(func(id): return Probe.count(t.actor(id), Probe.STUN) == 1)


## Watch the stack for up to `duration` sim s, until one of them has radioed `going_in` for the back door (or the time is out):
## `{ seen: { id: [acts] }, acts: { id: [[time, act]] }, entered_kitchen: bool }` (`acts`: each new act as it was adopted), where
## `entered_kitchen` says one of them stood in the kitchen before any claim on the back door (it went in some other way, a set-up
## finding). `tick` (a Callable taking the sim time) runs every frame, for a test's own prop.
static func watch(t: TestContext, duration: float, tick := Callable()) -> Dictionary:
	var members := ids(t)
	var seen := {}
	var acts := {}
	for id in members:
		seen[id] = []
		acts[id] = []
	var entered := false
	var door := Entry.BACK
	var end := t.time + duration
	while t.time < end and Entry.calls(t, "going_in").filter(func(c): return String(c.get("opening", "")) == door["id"]).is_empty():
		for id in members:
			var act := str(Entry.brain(t, id).current_act())
			if not seen[id].has(act):
				seen[id].append(act)
			if acts[id].is_empty() or acts[id].back()[1] != act:
				acts[id].append([t.time, act])
			if Entry.in_room(door, t.actor(id).global_position) and Entry.calls(t, "claim").is_empty():
				entered = true
		if tick.is_valid():
			tick.call(t.time)
		await t.frames(1)
	return { "seen": seen, "acts": acts, "entered_kitchen": entered }


## The stack's first decision that is not a fight or a hold (a SEARCH or INVESTIGATE order, the one made on the suspicion), from
## `watch`'s result: `[time, act]`, or `[INF, ""]` when it never made one.
static func first_search(result: Dictionary) -> Array:
	var first := [INF, ""]
	for id in result["acts"]:
		for pair in result["acts"][id]:
			var act: String = pair[1]
			if act.begins_with("search") or act.begins_with("investigate"):
				if float(pair[0]) < float(first[0]):
					first = pair
				break
	return first


## The checks every suspect-room test makes once `watch` is done: `require` that neither invader got into the kitchen before the
## stack formed and that the stack went for the back door by an entry (a claim on it from either), then check that the stack's
## first SEARCH or INVESTIGATE decision was STUN ENTRY into the kitchen (not the quiet ENTER, nor an investigation of what made the
## room suspect), and that a bang was called.
static func check_stun_entry(t: TestContext, result: Dictionary, why: String) -> void:
	var seen: Dictionary = result["seen"]
	if not t.require(not result["entered_kitchen"], "set-up: neither invader got into the kitchen before the stack formed (acts %s)" % str(seen)):
		return
	var claimed := not Entry.calls(t, "claim").filter(func(c): return String(c.get("opening", "")) == Entry.BACK["id"]).is_empty()
	if not t.require(claimed, "the stack went for the kitchen by its back door (acts %s)" % str(seen)):
		return
	var first := first_search(result)
	t.check(String(first[1]).begins_with("search/stun_entry/%s" % Entry.BACK["id"]), "with %s, the stack's first search decision was STUN ENTRY into the kitchen, not the quiet ENTER or an investigation (first %s at %.1f s; acts %s)" % [why, first[1], first[0], str(seen)])
	t.check(not Entry.calls(t, "bang").is_empty(), "and a bang was called at the back door")


## Watch the stack for up to `duration` sim s until every member has radioed `going_in` for the back door (or the time is out): `watch`'s
## result plus `heard_at` (id -> the sim time its footsteps memory, `debug_memory()["footsteps"]`, first held a step; INF: never),
## `going_in` (id -> the sim time of its first `going_in` for the back door; INF: never) and `in_kitchen` (id -> the sim time it first
## stood inside the kitchen; INF: never). For a test that judges the entry the stack went in with, not its first decision.
static func watch_in(t: TestContext, duration: float, tick := Callable()) -> Dictionary:
	var members := ids(t)
	var seen := {}
	var acts := {}
	var heard_at := {}
	var going_in := {}
	var in_kitchen := {}
	for id in members:
		seen[id] = []
		acts[id] = []
		heard_at[id] = INF
		going_in[id] = INF
		in_kitchen[id] = INF
	var entered := false
	var door := Entry.BACK
	var end := t.time + duration
	while t.time < end and members.any(func(id): return going_in[id] == INF):
		for id in members:
			var brain := Entry.brain(t, id)
			var act := str(brain.current_act())
			if not seen[id].has(act):
				seen[id].append(act)
			if acts[id].is_empty() or acts[id].back()[1] != act:
				acts[id].append([t.time, act])
			if heard_at[id] == INF and not brain.debug_memory().get("footsteps", []).is_empty():
				heard_at[id] = t.time
			var at: Vector2 = t.actor(id).global_position
			if in_kitchen[id] == INF and Maps.HOUSE_KITCHEN.grow(-Entry.INSIDE_DEPTH).has_point(at):
				in_kitchen[id] = t.time
			if Entry.in_room(door, at) and Entry.calls(t, "claim").is_empty():
				entered = true
			if going_in[id] == INF and not Probe.raw(t, &"callout", func(d): return d.get("speaker") == t.actor(id) \
					and String(d.get("entry_step", "")) == "going_in" and String(d.get("opening", "")) == door["id"]).is_empty():
				going_in[id] = t.time
		if tick.is_valid():
			tick.call(t.time)
		await t.frames(1)
	return { "seen": seen, "acts": acts, "entered_kitchen": entered, "heard_at": heard_at, "going_in": going_in, "in_kitchen": in_kitchen }


## The act member `id` was carrying out at sim time `at`, from `watch_in`'s result ("" before its first).
static func act_at(result: Dictionary, id: StringName, at: float) -> String:
	var out := ""
	for pair in result["acts"][id]:
		if float(pair[0]) <= at:
			out = pair[1]
	return out


## The checks for a stack that heard footsteps in the kitchen only after its first decision (`docs/tactical-entry.md` E17, a late
## reason, issue #51 R11), judged on the entry it went in with: `require` the set-up (nobody in the kitchen before the stack formed, a
## claim on the back door) and that each member had heard the steps (its footsteps memory) before it took STUN ENTRY, then check that
## every member went in under STUN ENTRY by the back door, that a bang was radioed and a stun went off in the kitchen before any member's
## `going_in`, and that nobody stood in the kitchen before that burst.
static func check_stun_entry_gone_in(t: TestContext, result: Dictionary, why: String) -> void:
	var seen: Dictionary = result["seen"]
	if not t.require(not result["entered_kitchen"], "set-up: neither invader got into the kitchen before the stack formed (acts %s)" % str(seen)):
		return
	var claimed := not Entry.calls(t, "claim").filter(func(c): return String(c.get("opening", "")) == Entry.BACK["id"]).is_empty()
	if not t.require(claimed, "the stack went for the kitchen by its back door (acts %s)" % str(seen)):
		return
	var stun_entry := "search/stun_entry/%s" % Entry.BACK["id"]
	for id in result["acts"]:
		var took := INF
		for pair in result["acts"][id]:
			if String(pair[1]).begins_with(stun_entry):
				took = float(pair[0])
				break
		if not t.require(float(result["heard_at"][id]) <= took, "%s heard the steps (its footsteps memory) before it took STUN ENTRY (heard at %.2f s, STUN ENTRY at %.2f s; acts %s)" % [id, result["heard_at"][id], took, str(result["acts"][id])]):
			return
	var first_in := INF
	for id in result["going_in"]:
		var at: float = result["going_in"][id]
		first_in = minf(first_in, at)
		t.check(at < INF and act_at(result, id, at).begins_with(stun_entry), "with %s, %s went in under STUN ENTRY into the kitchen (going_in at %.2f s under '%s'; acts %s)" % [why, id, at, act_at(result, id, at), str(result["acts"][id])])
	var bangs := Probe.raw(t, &"callout", func(d): return String(d.get("entry_step", "")) == "bang")
	t.check(not bangs.is_empty() and float(bangs[0]["time"]) < first_in, "a bang was radioed before anyone went in (bang at %s, first going_in at %.2f s)" % [str(bangs.map(func(b): return snappedf(float(b["time"]), 0.01))), first_in])
	var booms := Probe.booms(t, &"stun").filter(func(b): return Maps.HOUSE_KITCHEN.has_point(b["data"]["position"]))
	var burst: float = float(booms[0]["time"]) if not booms.is_empty() else INF
	t.check(burst < first_in, "a stun went off in the kitchen before anyone went in (burst at %.2f s, first going_in at %.2f s)" % [burst, first_in])
	for id in result["in_kitchen"]:
		t.check(float(result["in_kitchen"][id]) > burst, "%s stood in the kitchen only after the burst (in at %.2f s, burst at %.2f s)" % [id, result["in_kitchen"][id], burst])

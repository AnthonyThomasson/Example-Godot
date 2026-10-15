extends RefCounted

## Shared helpers for the listen-at-the-stack tests (tests/ai/grenade/quiet_entry_listen_*; not a test itself):
## `const Listen := preload("res://tests/_ai/listen_probe.gd")`. The behaviour they assert is `docs/tactical-entry.md` E17 as amended by issue
## #51 R17: a quiet entry whose stack carries a stun holds `entry_listen_time` (3 s) at the stack before the point starts the pie, so a late
## reason (R11) can arrive; a hostile in view or coming under fire ends the hold; a stack without a stun does not hold.
##
## The world is the bang-fallback tests' (tests/_ai/bang_probe.gd): the bare Terrace house, a stack of two invaders north-east of the back door,
## each armed with one stun at the start of `run` (the way Main arms a spawn), and scripted Von: SEARCH > ENTER (quiet) > the back door. Nothing
## makes the kitchen suspect. The point is the member whose claim holds slot 1; it is "holding" while its order is still that ENTER and its entry
## is in the `stack` phase.

const Bang := preload("res://tests/_ai/bang_probe.gd")
const Entry := preload("res://tests/_ai/entry_probe.gd")
const Maps := preload("res://tests/_ai/flank_maps.gd")
const Probe := preload("res://tests/_ai/grenade_probe.gd")
const IDS := [&"a", &"b"]
## The listen hold (R17, `entry_listen_time`), and the tolerance a test reads it with.
const LISTEN := 3.0
const LISTEN_MIN := 2.7


## The stack of two at the back door with scripted Von for the quiet ENTER (and, for a member inside the hall, ENTER into the living room).
static func world(s: TestSetup) -> void:
	Maps.house(s, false)
	Entry.rules(s, Entry.BACK, [{ "pick": Entry.HALL_LIVING["id"] }])
	Bang.stack(s)


## The member of the stack whose claim on the back door holds slot 1 (the point), or &"" before anyone has claimed it.
static func point(t: TestContext) -> StringName:
	for id in IDS:
		if Entry.calls(t, "claim", id).any(func(c): return String(c.get("opening", "")) == Entry.BACK["id"] and int(c.get("slot", 0)) == 1):
			return id
	return &""


## Whether member `id` is holding at the stack: its order is still the quiet ENTER through the back door and its entry is in `stack`.
static func holding(t: TestContext, id: StringName) -> bool:
	var brain := Entry.brain(t, id)
	return str(brain.current_act()).begins_with("search/enter/%s" % Entry.BACK["id"]) and str(Entry.entry(brain).get("phase", "")) == "stack"


## Wait until the point has radioed `ready` at the back door (it stands in its slot); returns its id, or &"" on time out.
static func wait_point_ready(t: TestContext, timeout: float) -> StringName:
	var ok := await t.until(func(): return point(t) != &"" and Entry.first_call_time(t, "ready", point(t), Entry.BACK["id"]) < INF, timeout)
	return point(t) if ok else &""


## Sample member `id`'s entry phase each frame for `duration` sim s (or until `stop` holds): `[[time, phase]]`, a row per change.
static func phases(t: TestContext, id: StringName, duration: float, stop := Callable()) -> Array:
	var out: Array = []
	var end := t.time + duration
	while t.time < end and not (stop.is_valid() and stop.call()):
		var phase := str(Entry.entry(Entry.brain(t, id)).get("phase", ""))
		if out.is_empty() or out.back()[1] != phase:
			out.append([t.time, phase])
		await t.frames(1)
	return out


## The first time at or after `from` that `samples` (from `phases`) shows `phase`, or INF.
static func first(samples: Array, phase: String, from := -INF) -> float:
	for p in samples:
		if p[1] == phase and float(p[0]) >= from:
			return float(p[0])
	# A run of the phase that began before `from` and was still on at it.
	var on := ""
	for p in samples:
		if float(p[0]) <= from:
			on = p[1]
	return from if on == phase else INF

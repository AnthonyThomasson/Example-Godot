extends GameTest

## E17 as amended by issue #51 R17: a quiet entry whose stack carries a stun holds `entry_listen_time` (3 s) at the stack before the point starts
## the pie, so a late reason to suspect the room (R11) has time to arrive; a stack without a stun does not hold. The matches showed first stacks
## claimed 0.2 to 2.5 s in with nothing known, and the steps that would have turned them bang heard 1.5 to 3 s after the claim.
##
## Two entries at once in the bare Terrace house, scripted Von (SEARCH > ENTER, quiet): a stack of two invaders, each with a stun, at the back
## door into the kitchen, nothing making the kitchen suspect; and a lone invader with no grenade in the hall, going into the living room by the
## hall's doorway. The stack's point stands in its slot `LISTEN` s (no less than `LISTEN_MIN`, no more than `LISTEN_MAX`) before it starts the pie,
## and the entry stays quiet; the lone invader without a stun starts its pie at once (under `AT_ONCE` s from its `ready`).
##
## Premise: the stack's invaders are armed with one stun each, the lone one with none, at the start of `run`, the way Main arms a spawn.

const Entry := preload("res://tests/_ai/entry_probe.gd")
const Listen := preload("res://tests/_ai/listen_probe.gd")
const Probe := preload("res://tests/_ai/grenade_probe.gd")
const LONE_AT := Vector2(420, 415)
const LISTEN_MAX := 4.5
const AT_ONCE := 1.0


func describe() -> Dictionary:
	return {
		"name": "A quiet stack with a stun listens at the stack before the pie",
		"description": "A stack of two with a stun at the back door, nothing suspected, holds about 3 s in its slot before the point slices the pie and goes in quietly; a lone invader with no stun at the hall's doorway into the living room starts its pie at once.",
		"tags": ["ai", "grenade", "entry", "stun", "listen", "scripted"],
		"timeout": 60.0,
	}


func configure(s: TestSetup) -> void:
	Listen.world(s)
	s.actor(&"lone", &"invader", LONE_AT, { "facing": Vector2.UP })


func run(t: TestContext) -> void:
	for id in Listen.IDS:
		Probe.arm(t.actor(id), 1, 0)
	Probe.arm(t.actor(&"lone"), 0, 0)
	if not t.require(Listen.IDS.all(func(id): return Probe.count(t.actor(id), Probe.STUN) == 1) and Probe.count(t.actor(&"lone"), Probe.STUN) == 0,
			"the stack carries a stun each, the lone invader none"):
		return
	var hall_door: String = Entry.HALL_LIVING["id"]
	var samples := { &"a": [], &"b": [], &"lone": [] }
	var done := func() -> bool:
		for id in samples:
			var phase := str(Entry.entry(Entry.brain(t, id)).get("phase", ""))
			if samples[id].is_empty() or samples[id].back()[1] != phase:
				samples[id].append([t.time, phase])
		var lead := Listen.point(t)
		return lead != &"" and Listen.first(samples[lead], "pie") < INF and Listen.first(samples[&"lone"], "pie") < INF
	await t.until(done, 40.0)
	var p := Listen.point(t)
	if not t.require(p != &"", "the stack claimed the back door"):
		return
	if not t.require(Entry.calls(t, "claim").filter(func(c): return String(c.get("opening", "")) == Entry.BACK["id"]).all(func(c): return c.get("bang") == false),
			"set-up: the stack went for it quietly (ENTER, nothing suspected)"):
		return
	var ready := Entry.first_call_time(t, "ready", p, Entry.BACK["id"])
	var pie := Listen.first(samples[p], "pie", ready)
	if not t.require(ready < INF, "the point got to its slot (phases %s)" % str(samples[p])):
		return
	t.check(pie - ready >= Listen.LISTEN_MIN, "the point held in its slot about %.0f s before it started the pie (%.2f s from its ready to the pie; phases %s)" % [Listen.LISTEN, pie - ready, str(samples[p])])
	t.check(pie - ready <= LISTEN_MAX, "and not much longer (%.2f s)" % (pie - ready))
	t.check(Entry.calls(t, "bang").is_empty() and not t.happened(&"throw"), "with nothing heard, the entry stayed quiet")
	var lone_ready := Entry.first_call_time(t, "ready", &"lone", hall_door)
	if t.check(lone_ready < INF, "the lone invader stacked at the hall's doorway into the living room (phases %s; acts %s)" % [str(samples[&"lone"]), Probe.acts(t, &"lone")]):
		var lone_pie := Listen.first(samples[&"lone"], "pie", lone_ready)
		t.check(lone_pie - lone_ready < AT_ONCE, "without a stun it did not hold: its pie began %.2f s after its ready" % (lone_pie - lone_ready))

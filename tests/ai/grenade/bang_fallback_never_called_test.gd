extends GameTest

## G18 / E17, the third fallback: the point of a stack in bang mode waits in its slot for the thrower to call the bang, and gives the bang up when it is
## not called within `BANG_CALL_CAP` (8 s) of the stack being ready: it slices the pie and goes in quietly, throwing nothing, its claims saying quiet. The
## thrower here is a teammate that is a puppet (slot 2, one stun, bang mode) that radios ready and never calls it. Scripted Von (SEARCH > STUN ENTRY >
## the back door); the AI invader carries a stun the way Main arms a spawn.

const Bang := preload("res://tests/_ai/bang_probe.gd")
const Entry := preload("res://tests/_ai/entry_probe.gd")
const Maps := preload("res://tests/_ai/flank_maps.gd")
const Probe := preload("res://tests/_ai/grenade_probe.gd")
const CALL_CAP := 8.0


func describe() -> Dictionary:
	return {
		"name": "A stack whose thrower never calls the bang goes in quietly",
		"description": "The AI point stacks at the back door with a teammate that radios ready in bang mode and never calls it: after 8 s it gives the bang up, slices the pie and goes in, throwing nothing.",
		"tags": ["ai", "grenade", "entry", "stun", "scripted"],
		"timeout": 60.0,
	}


func configure(s: TestSetup) -> void:
	Maps.house(s, false)
	Bang.rules(s)
	s.actor(&"a", &"invader", Bang.A_AT)
	s.actor(&"mate", &"puppet", Bang.B_AT, { "faction": &"invader", "max_health": 1000000.0 })


func run(t: TestContext) -> void:
	if not t.require(Bang.arm(t, [&"a"]), "the AI invader carries a stun grenade (Character.item_count(7))"):
		return
	var brain := Entry.brain(t, &"a")
	var seen := { &"a": [] }
	if not t.require(await t.until(func(): return not Entry.calls(t, "claim", &"a").is_empty(), 5.0), "the AI claimed the doorway"):
		return
	var side := int(Entry.entry(brain).get("side", 0))
	var next := 0.0
	var phases: Array = []
	var end := t.time + 40.0
	while t.time < end and Entry.calls(t, "going_in").is_empty():
		if t.time >= next:
			next = t.time + 1.0
			Bang.radio_mate(t, &"mate", side, "ready")
		Bang.note_acts(t, seen)
		var phase := str(Entry.entry(brain).get("phase", ""))
		if phases.is_empty() or phases.back() != phase:
			phases.append(phase)
		await t.frames(1)
	if not t.require(Bang.took(seen, "stun_entry"), "the AI took STUN ENTRY (acts: %s)" % str(seen)):
		return
	if not t.require(not Entry.calls(t, "going_in").is_empty(), "the AI went in (phases: %s)" % str(phases)):
		return
	var ready := Entry.first_call_time(t, "ready", &"a")
	var went_in := Entry.first_call_time(t, "going_in", &"a")
	t.check(went_in - ready >= CALL_CAP, "it waited for the bang at least %.0f s after it was ready (ready at %.1f s, in at %.1f s)" % [CALL_CAP, ready, went_in])
	t.check(phases.has("pie"), "and sliced the pie, being quiet (phases: %s)" % str(phases))
	t.check(Entry.calls(t, "bang", &"a").is_empty() and not t.happened(&"throw") and Probe.booms(t).is_empty(), "it called no bang and nothing was thrown")
	t.check(Entry.calls(t, "", &"a").back().get("bang") == false, "its latest call says the stack is quiet")

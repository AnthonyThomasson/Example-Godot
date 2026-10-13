extends GameTest

## G18 / E17, the fourth fallback: a stack that holds its slot turned away from the door for the bang gives the bang up when the stun does not go off within
## `BANG_BURST_CAP` (5 s) of the call: the point slices the pie and goes in quietly, nothing thrown by it, its claims saying quiet. The thrower here is a
## teammate that is a puppet (slot 2, one stun, bang mode) that calls the bang and throws nothing. Scripted Von (SEARCH > STUN ENTRY > the back door); the
## AI invader carries a stun the way Main arms a spawn.

const Bang := preload("res://tests/_ai/bang_probe.gd")
const Entry := preload("res://tests/_ai/entry_probe.gd")
const Maps := preload("res://tests/_ai/flank_maps.gd")
const Probe := preload("res://tests/_ai/grenade_probe.gd")
const BURST_CAP := 5.0


func describe() -> Dictionary:
	return {
		"name": "A stack whose stun never goes off goes in quietly",
		"description": "The AI point holds its slot for a bang that a teammate calls and never throws: after 5 s it gives the bang up, slices the pie and goes in.",
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
	if not t.require(await t.until(func(): return str(Entry.entry(brain).get("phase", "")) == "stack", 10.0), "the AI stacked at the door"):
		return
	var next := 0.0
	var called := t.time + 1.0  # the mate radios ready now and calls the bang with its next heartbeat
	var phases: Array = []
	var end := t.time + 40.0
	while t.time < end and Entry.calls(t, "going_in").is_empty():
		if t.time >= next:
			next = t.time + 1.0
			Bang.radio_mate(t, &"mate", side, "bang" if t.time >= called - 0.01 else "ready")
		Bang.note_acts(t, seen)
		var phase := str(Entry.entry(brain).get("phase", ""))
		if phases.is_empty() or phases.back() != phase:
			phases.append(phase)
		await t.frames(1)
	if not t.require(Bang.took(seen, "stun_entry"), "the AI took STUN ENTRY (acts: %s)" % str(seen)):
		return
	if not t.require(phases.has("bang"), "the AI held for the bang (phases: %s)" % str(phases)):
		return
	if not t.require(not Entry.calls(t, "going_in").is_empty(), "the AI went in (phases: %s)" % str(phases)):
		return
	var in_bang := phases.find("bang")
	t.check(phases.slice(in_bang).has("pie"), "and then sliced the pie, being quiet (phases: %s)" % str(phases))
	var went_in := Entry.first_call_time(t, "going_in", &"a")
	t.check(went_in - called >= BURST_CAP, "it waited at least %.0f s for the burst (the bang called at %.1f s, in at %.1f s)" % [BURST_CAP, called, went_in])
	t.check(Entry.calls(t, "bang", &"a").is_empty() and not t.happened(&"throw") and Probe.booms(t).is_empty(), "it called no bang and nothing was thrown")
	t.check(Entry.calls(t, "", &"a").back().get("bang") == false, "its latest call says the stack is quiet")

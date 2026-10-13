extends GameTest

## G18 / E17, the second fallback: the thrower of a bang entry has lost its stun by the time it gets to throw (it is not in its hand to take: the throw
## fails). The bang is given up, nothing is thrown, the rest of the stack, holding its slot turned away from the door for the bang, is told over the radio
## (the claims say `bang` false) and goes in quietly without waiting out `BANG_BURST_CAP`. Scripted Von (SEARCH > STUN ENTRY > the back door); both invaders
## carry a stun, the way Main arms a spawn; the test takes the thrower's stun away the moment it radios `bang`.

const Bang := preload("res://tests/_ai/bang_probe.gd")
const Entry := preload("res://tests/_ai/entry_probe.gd")
const Maps := preload("res://tests/_ai/flank_maps.gd")
const Probe := preload("res://tests/_ai/grenade_probe.gd")
## The most seconds the rest of the stack may keep waiting in the bang phase after the thrower has given the bang up: well short of the 5 s
## a stun that never goes off is waited for.
const PROMPT := 3.0


func describe() -> Dictionary:
	return {
		"name": "A stack whose thrower lost its stun goes in quietly",
		"description": "The thrower calls the bang and then has no stun to throw: the bang is given up, nothing is thrown, the claims say quiet and the stack goes in within a few seconds.",
		"tags": ["ai", "grenade", "entry", "stun", "scripted"],
		"timeout": 60.0,
	}


func configure(s: TestSetup) -> void:
	Maps.house(s, false)
	Bang.rules(s)
	Bang.stack(s)


func run(t: TestContext) -> void:
	if not t.require(Bang.arm(t, Bang.IDS), "both invaders carry a stun grenade (Character.item_count(7))"):
		return
	if not t.require(await t.until(func(): return not Entry.calls(t, "bang").is_empty(), 30.0), "the thrower radioed bang"):
		return
	var thrower: Node = Entry.calls(t, "bang")[0]["speaker"]
	var called := t.time
	Probe.arm(thrower, 0, 0)
	t.require(Probe.count(thrower, Probe.STUN) == 0, "set-up: the thrower's stun is gone (item_count(7) = %d)" % Probe.count(thrower, Probe.STUN))
	var banging := { &"a": 0.0, &"b": 0.0 }  # seconds each spent in the bang phase after the stun was taken away
	while t.time < called + 20.0 and Entry.calls(t, "going_in").is_empty():
		for id in banging:
			if str(Entry.entry(Entry.brain(t, id)).get("phase", "")) == "bang":
				banging[id] += 1.0 / 60.0
		await t.frames(1)
	if not t.require(not Entry.calls(t, "going_in").is_empty(), "the stack went in"):
		return
	var waiting: StringName = &"a" if thrower == t.actor(&"b") else &"b"
	t.check(banging[waiting] <= PROMPT, "the member that did not throw left the bang phase within %.0f s of the call (%.1f s in it)" % [PROMPT, banging[waiting]])
	t.check(not t.happened(&"throw") and Probe.booms(t).is_empty(), "nothing was thrown")
	for id in Bang.IDS:
		var last: Dictionary = Entry.calls(t, "", id).back()
		t.check(last.get("bang") == false, "%s's latest call says the stack is quiet (bang %s)" % [id, str(last.get("bang"))])

extends GameTest

## Desired (E10): a human far from the doorway (beyond the stack range) is no part of the team: it is offered no slot,
## says nothing on the radio, holds nobody up, and a lone AI keeps its solo entry (it slices the pie from both sides).

const Entry := preload("res://tests/_ai/entry_probe.gd")
const Maps := preload("res://tests/_ai/flank_maps.gd")
const Stack := preload("res://tests/_ai/stack_probe.gd")


func describe() -> Dictionary:
	return {
		"name": "A far-off human does not join the stack",
		"description": "The human stands far from the back door: no reservation, nothing on the radio, and the lone invader's entry is solo, both pie sides.",
		"tags": ["ai", "entry", "stack", "scripted", "callout"],
		"timeout": 70.0,
	}


func configure(s: TestSetup) -> void:
	Maps.house(s, false)
	Entry.rules(s, Entry.BACK)
	Entry.npc(s, &"a", Vector2(930, 90), 0.4)
	Stack.human(s, &"me", Stack.FAR)


func run(t: TestContext) -> void:
	var door := Entry.BACK
	var stack := Stack.attach(t, &"me")
	if not t.require(stack != null, "the human has a stack radio (PlayerStack.attach)"):
		return
	var seen := { "reserved": false, "solo_always": true, "most_sides": 0 }   # a lambda cannot reassign outer locals
	await Entry.watch(t, [&"a"], door, 60.0, func():
		seen["reserved"] = seen["reserved"] or Stack.mine(stack) > 0
		var e := Entry.entry(Entry.brain(t, &"a"))
		if String(e.get("phase", "")) in ["pie", "cross", "corner"]:
			seen["solo_always"] = seen["solo_always"] and bool(e.get("solo", false))
			seen["most_sides"] = maxi(int(seen["most_sides"]), int(e.get("pie_sides", 0)))
		return not Entry.calls(t, "going_in", &"a").is_empty())
	if not t.require(not Entry.calls(t, "going_in", &"a").is_empty(), "the invader went in (act %s)" % Entry.brain(t, &"a").current_act()):
		return
	t.check(not seen["reserved"], "the far-off human was never reserved a slot")
	t.check(not Stack.radioed(t, &"me"), "the far-off human said nothing on the entry radio")
	t.check(seen["solo_always"], "the invader's entry stayed solo")
	t.expect_eq(seen["most_sides"], 2, "and it sliced the pie from both sides")

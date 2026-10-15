extends GameTest

## Desired (E16): the human keeps the slot it was reserved. An AI invader that claims the doorway later takes the slot
## behind it, and the human's marker does not move.

const Entry := preload("res://tests/_ai/entry_probe.gd")
const Maps := preload("res://tests/_ai/flank_maps.gd")
const Stack := preload("res://tests/_ai/stack_probe.gd")


func describe() -> Dictionary:
	return {
		"name": "The human keeps its slot when an AI joins late",
		"description": "A late AI invader claims slot 3, behind the human, and the human stays in slot 2.",
		"tags": ["ai", "entry", "stack", "scripted", "callout"],
		"timeout": 80.0,
	}


func configure(s: TestSetup) -> void:
	Maps.house(s, false)
	Entry.rules(s, Entry.BACK)
	# A long ready timeout so the stack is still forming when the late invader turns up.
	Entry.npc(s, &"a", Vector2(930, 90), 0.4, { "entry_ready_timeout": 40.0 })
	# Held back (it neither enters nor moves) until the human has its slot: the premise is a late joiner, as in the
	# solo-entry ally test.
	Entry.npc(s, &"b", Vector2(990, 450), 0.4, { "entry_enabled": false, "max_commit_time": 0.5, "entry_ready_timeout": 40.0 }, { "speed": 0.0 })
	Stack.human(s, &"me", Stack.NEAR)


func run(t: TestContext) -> void:
	var door := Entry.BACK
	var stack := Stack.attach(t, &"me")
	if not t.require(stack != null, "the human has a stack radio (PlayerStack.attach)"):
		return
	if not t.require(await t.until(func(): return Stack.mine(stack) == 2, 30.0), "the human was reserved slot 2"):
		return
	t.actor(&"b").set("speed", 150.0)
	Entry.brain(t, &"b").set("entry_enabled", true)
	if not t.require(await t.until(func(): return not Entry.calls(t, "claim", &"b").is_empty(), 40.0), "the late invader claimed a slot"):
		return
	t.expect_eq(int(Entry.calls(t, "claim", &"b")[0].get("slot", 0)), 3, "the late invader took the slot behind the human")
	await t.seconds(1.0)
	t.expect_eq(Stack.mine(stack), 2, "the human still holds slot 2")
	var held := (Stack.view(stack).get("slots", []) as Array).filter(func(s): return bool(s["held"]) and not bool(s["mine"])).map(func(s): return int(s["n"]))
	held.sort()
	t.expect_eq(held, [1, 3], "slots 1 and 3 are shown as held by the AI")
	var mine_now := Stack.slot_point(stack, 2)
	t.check(absf(Entry.lateral(door, Stack.slot_point(stack, 3))) > absf(Entry.lateral(door, mine_now)), "slot 3 is behind the human's slot")

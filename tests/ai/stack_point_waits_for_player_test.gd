extends GameTest

## Desired (E16, with E6): a nearby human holds the AI point at the ready barrier like any teammate. One that never
## reaches its slot is waited for `entry_ready_timeout`, then the point goes in without it.

const Entry := preload("res://tests/_ai/entry_probe.gd")
const Maps := preload("res://tests/_ai/flank_maps.gd")
const Stack := preload("res://tests/_ai/stack_probe.gd")
const TIMEOUT := 8.0


func describe() -> Dictionary:
	return {
		"name": "The point waits for a human who has not reached its slot",
		"description": "The human is reserved a slot but stays where it is: the point waits out the ready timeout, then goes in.",
		"tags": ["ai", "entry", "stack", "scripted", "callout"],
		"timeout": 60.0,
	}


func configure(s: TestSetup) -> void:
	Maps.house(s, false)
	Entry.rules(s, Entry.BACK)
	Entry.npc(s, &"a", Vector2(930, 90), 0.4, { "entry_ready_timeout": TIMEOUT })
	Stack.human(s, &"me", Stack.NEAR)   # reserved a slot, never walks to it


func run(t: TestContext) -> void:
	var door := Entry.BACK
	var stack := Stack.attach(t, &"me")
	if not t.require(stack != null, "the human has a stack radio (PlayerStack.attach)"):
		return
	await Entry.watch(t, [&"a"], door, 50.0, func(): return not Entry.calls(t, "going_in", &"a").is_empty())
	var ready_at := Entry.first_call_time(t, "ready", &"a")
	var going_at := Entry.first_call_time(t, "going_in", &"a")
	if not t.require(going_at < INF, "the invader went in (act %s)" % Entry.brain(t, &"a").current_act()):
		return
	t.check(not Entry.calls(t, "claim", &"me").is_empty(), "the human held a claim on the doorway")
	t.check(Entry.calls(t, "ready", &"me").is_empty(), "the human never reached its slot")
	t.check(going_at - ready_at >= TIMEOUT - 0.2, "the point waited out the timeout for the human (%.1f s)" % (going_at - ready_at))
	t.check(going_at - ready_at <= TIMEOUT + 6.0, "and not much longer (%.1f s)" % (going_at - ready_at))

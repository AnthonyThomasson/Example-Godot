extends GameTest

## Desired (E16, with E6): a human that walks to its reserved slot radios `ready`, and the point, which was waiting for
## it, goes in then, well before the ready timeout.

const Entry := preload("res://tests/_ai/entry_probe.gd")
const Maps := preload("res://tests/_ai/flank_maps.gd")
const Stack := preload("res://tests/_ai/stack_probe.gd")
const TIMEOUT := 20.0


func describe() -> Dictionary:
	return {
		"name": "The point goes in when the human is in its slot",
		"description": "The human walks to its reserved slot and is ready; the point goes in without waiting out the ready timeout.",
		"tags": ["ai", "entry", "stack", "scripted", "callout"],
		"timeout": 70.0,
	}


func configure(s: TestSetup) -> void:
	Maps.house(s, false)
	Entry.rules(s, Entry.BACK)
	Entry.npc(s, &"a", Vector2(930, 90), 0.4, { "entry_ready_timeout": TIMEOUT })
	Stack.human(s, &"me", Stack.NEAR)


func run(t: TestContext) -> void:
	var door := Entry.BACK
	var stack := Stack.attach(t, &"me")
	if not t.require(stack != null, "the human has a stack radio (PlayerStack.attach)"):
		return
	if not t.require(await t.until(func(): return Stack.mine(stack) == 2, 30.0), "the human was reserved slot 2"):
		return
	if not t.require(await Stack.walk(t, &"me", [Stack.slot_point(stack, 2)], 15.0), "the human walked to its slot"):
		return
	await Entry.watch(t, [&"a", &"me"], door, 50.0, func(): return not Entry.calls(t, "going_in", &"a").is_empty())
	var my_ready := Entry.first_call_time(t, "ready", &"me")
	var ai_ready := Entry.first_call_time(t, "ready", &"a")
	var going_at := Entry.first_call_time(t, "going_in", &"a")
	if not t.require(going_at < INF, "the point went in (act %s)" % Entry.brain(t, &"a").current_act()):
		return
	t.check(my_ready < INF, "the human radioed ready once it stood in its slot")
	t.check(going_at >= my_ready, "the point waited for the human to be ready")
	t.check(going_at - ai_ready < TIMEOUT * 0.5, "and did not wait out the timeout (%.1f s after it was ready)" % (going_at - ai_ready))

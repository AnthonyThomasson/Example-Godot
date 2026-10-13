extends GameTest

## Desired (E10, with E6): an AI that stacked behind the human crosses only after the human is through (its `in` call
## plus the follow gap), not alongside the point.

const Entry := preload("res://tests/_ai/entry_probe.gd")
const Maps := preload("res://tests/_ai/flank_maps.gd")
const Stack := preload("res://tests/_ai/stack_probe.gd")


func describe() -> Dictionary:
	return {
		"name": "The AI behind the human crosses after it",
		"description": "AI point, then the human, then a late AI: the point goes in, the human follows it, and the third crosses after the human.",
		"tags": ["ai", "entry", "stack", "scripted", "callout"],
		"timeout": 120.0,
	}


func configure(s: TestSetup) -> void:
	Maps.house(s, false)
	Entry.rules(s, Entry.BACK)
	Entry.npc(s, &"a", Vector2(930, 90), 0.4, { "entry_ready_timeout": 40.0 })
	# Held back until the human has its slot: the premise is an AI that stacks behind the human.
	Entry.npc(s, &"b", Vector2(990, 450), 0.4, { "entry_enabled": false, "max_commit_time": 0.5, "entry_ready_timeout": 40.0 }, { "speed": 0.0 })
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
	t.actor(&"b").set("speed", 150.0)
	Entry.brain(t, &"b").set("entry_enabled", true)
	if not t.require(await t.until(func(): return not Entry.calls(t, "in", &"a").is_empty(), 80.0), "the point went in (act %s)" % Entry.brain(t, &"a").current_act()):
		return
	t.check(Entry.calls(t, "ready", &"b").size() > 0, "the third invader was ready behind the human")
	t.check(Entry.calls(t, "going_in", &"b").is_empty(), "and had not crossed while the human was still in the stack")
	# The human goes in behind the point.
	if not t.require(await Stack.walk(t, &"me", Stack.crossing(door), 8.0), "the human walked in through the door"):
		return
	if not t.require(await t.until(func(): return not Entry.calls(t, "going_in", &"b").is_empty(), 40.0), "the AI behind the human went in"):
		return
	var my_in := Entry.first_call_time(t, "in", &"me")
	t.check(my_in < INF, "the human radioed `in` once it was through")
	t.check(Entry.first_call_time(t, "going_in", &"b") >= my_in, "the AI behind crossed after the human was in")

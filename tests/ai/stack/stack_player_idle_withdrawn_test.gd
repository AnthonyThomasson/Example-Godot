extends GameTest

## Desired (E16): a human that does not follow the point in does not hold the AI behind it for ever. Once the point is
## through and the human has not crossed within `go_timeout`, its claim is withdrawn (marker gone, `abort` on the
## radio) and the AI behind goes in.

const Entry := preload("res://tests/_ai/entry_probe.gd")
const Maps := preload("res://tests/_ai/flank_maps.gd")
const Stack := preload("res://tests/_ai/stack_probe.gd")
const GO_TIMEOUT := 6.0


func describe() -> Dictionary:
	return {
		"name": "An idle human is dropped from the stack",
		"description": "The human sits in its slot while the point goes in; after the go timeout its claim is withdrawn and the AI behind goes in.",
		"tags": ["ai", "entry", "stack", "scripted", "callout"],
		"timeout": 120.0,
	}


func configure(s: TestSetup) -> void:
	Maps.house(s, false)
	Entry.rules(s, Entry.BACK)
	Entry.npc(s, &"a", Vector2(930, 90), 0.4, { "entry_ready_timeout": 40.0 })
	# It starts north of the door, on the human's side: a one-sided stack (a late AI from the other side splits the stack, E19).
	Entry.npc(s, &"b", Vector2(980, -70), 0.4, { "entry_enabled": false, "max_commit_time": 0.5, "entry_ready_timeout": 40.0 }, { "speed": 0.0 })
	Stack.human(s, &"me", Stack.NEAR)


func run(t: TestContext) -> void:
	var stack := Stack.attach(t, &"me")
	if not t.require(stack != null, "the human has a stack radio (PlayerStack.attach)"):
		return
	stack.set("go_timeout", GO_TIMEOUT)
	if not t.require(await t.until(func(): return Stack.mine(stack) == 2, 30.0), "the human was reserved slot 2"):
		return
	if not t.require(await Stack.walk(t, &"me", [Stack.slot_point(stack, 2)], 15.0), "the human walked to its slot"):
		return
	t.actor(&"b").set("speed", 150.0)
	Entry.brain(t, &"b").set("entry_enabled", true)
	if not t.require(await t.until(func(): return not Entry.calls(t, "in", &"a").is_empty(), 80.0), "the point went in (act %s)" % Entry.brain(t, &"a").current_act()):
		return
	var point_in := Entry.first_call_time(t, "in", &"a")
	# The human stays where it is. Its claim is withdrawn, and then the AI behind goes in.
	var withdrawn := func(): return Stack.mine(stack) == 0
	if not t.require(await t.until(withdrawn, GO_TIMEOUT + 10.0), "the idle human's slot was withdrawn"):
		return
	var dropped := t.time
	t.check(dropped - point_in >= GO_TIMEOUT - 0.5, "not before the human had its go timeout (%.1f s after the point was in)" % (dropped - point_in))
	t.check(not Entry.calls(t, "abort", &"me").is_empty(), "the human's claim was withdrawn on the radio")
	if not t.require(await t.until(func(): return not Entry.calls(t, "going_in", &"b").is_empty(), 40.0), "the AI behind went in without the human"):
		return
	t.check(Entry.first_call_time(t, "going_in", &"b") >= Entry.first_call_time(t, "abort", &"me") - 0.05, "it went in after the claim was withdrawn, not past the human")
	t.check(Entry.calls(t, "going_in", &"me").is_empty(), "the human never went in")

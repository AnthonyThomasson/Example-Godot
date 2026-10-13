extends GameTest

## Desired (E16): the reservation lasts only while the human is near the doorway. Walking well away from it withdraws
## the claim: the marker goes and `abort` is radioed, so nobody waits for a human who has left.

const Entry := preload("res://tests/_ai/entry_probe.gd")
const Maps := preload("res://tests/_ai/flank_maps.gd")
const Stack := preload("res://tests/_ai/stack_probe.gd")


func describe() -> Dictionary:
	return {
		"name": "A human who walks away loses its slot",
		"description": "The human is reserved a slot, then walks far from the doorway: the claim is withdrawn and the view is empty.",
		"tags": ["ai", "entry", "stack", "scripted", "callout"],
		"timeout": 80.0,
	}


func configure(s: TestSetup) -> void:
	Maps.house(s, false)
	Entry.rules(s, Entry.BACK)
	# A long ready timeout so the point is still stacking while the human leaves.
	Entry.npc(s, &"a", Vector2(930, 90), 0.4, { "entry_ready_timeout": 60.0 })
	Stack.human(s, &"me", Stack.NEAR)


func run(t: TestContext) -> void:
	var stack := Stack.attach(t, &"me")
	if not t.require(stack != null, "the human has a stack radio (PlayerStack.attach)"):
		return
	if not t.require(await t.until(func(): return Stack.mine(stack) == 2, 30.0), "the human was reserved slot 2"):
		return
	t.puppet(&"me").walk_to(Stack.FAR)
	if not t.require(await t.until(func(): return Stack.mine(stack) == 0, 30.0), "the slot was withdrawn once the human was far from the door"):
		return
	t.check(Stack.view(stack).is_empty(), "the stack shows nothing")
	t.check(not Entry.calls(t, "abort", &"me").is_empty(), "the human withdrew its claim on the radio")

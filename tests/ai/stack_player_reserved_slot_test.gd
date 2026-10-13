extends GameTest

## Desired (E10): a human invader standing near the doorway an AI invader is stacking at is given the first free slot
## (slot 2, behind the AI point) on the AI's side of the door, over the radio, and the stack shows it where to stand.

const Entry := preload("res://tests/_ai/entry_probe.gd")
const Maps := preload("res://tests/_ai/flank_maps.gd")
const Stack := preload("res://tests/_ai/stack_probe.gd")


func describe() -> Dictionary:
	return {
		"name": "A nearby human is given the next stack slot",
		"description": "An AI invader stacks at the back door; the human invader near it is reserved slot 2, on the same side, on the radio and in its view.",
		"tags": ["ai", "entry", "stack", "scripted", "callout"],
		"timeout": 60.0,
	}


func configure(s: TestSetup) -> void:
	Maps.house(s, false)
	Entry.rules(s, Entry.BACK)
	# A long ready timeout so the point is still waiting in its stack while the reservation is read.
	Entry.npc(s, &"a", Vector2(930, 90), 0.4, { "entry_ready_timeout": 30.0 })
	Stack.human(s, &"me", Stack.NEAR)


func run(t: TestContext) -> void:
	var door := Entry.BACK
	var stack := Stack.attach(t, &"me")
	if not t.require(stack != null, "the human has a stack radio (PlayerStack.attach)"):
		return
	if not t.require(await t.until(func(): return Stack.mine(stack) > 0, 30.0), "the human was reserved a slot (act %s)" % Entry.brain(t, &"a").current_act()):
		return
	var v := Stack.view(stack)
	t.expect_eq(str(v.get("opening", "")), door["id"], "the reservation is at the doorway the AI stacks at")
	t.expect_eq(Stack.mine(stack), 2, "the human is reserved the first free slot, behind the AI point")
	var point := Stack.slot_point(stack, 2)
	t.check(point != Vector2.INF and Entry.beside_door(door, point), "the human's slot is against the wall beside the door (%s)" % point)
	var held := (v.get("slots", []) as Array).filter(func(s): return bool(s["held"]) and not bool(s["mine"]))
	t.check(held.size() == 1 and int(held[0]["n"]) == 1, "slot 1 is shown as held by the AI point")
	var mine_slots := (v.get("slots", []) as Array).filter(func(s): return bool(s["mine"]))
	t.check(mine_slots.size() == 1 and int(mine_slots[0]["n"]) == 2, "exactly the human's own slot is flagged mine")
	var ai_claims := Entry.calls(t, "claim", &"a")
	var my_claims := Entry.calls(t, "claim", &"me")
	if not t.require(not ai_claims.is_empty() and not my_claims.is_empty(), "both radioed a claim (the human's is on the radio like an NPC's)"):
		return
	t.expect_eq(int(ai_claims[0].get("slot", 0)), 1, "the AI took slot 1")
	t.expect_eq(int(my_claims[0].get("slot", 0)), 2, "the human's claim is slot 2")
	t.expect_eq(str(my_claims[0].get("opening", "")), door["id"], "the human's claim names the doorway")
	t.expect_eq(int(my_claims[0].get("side", 0)), int(ai_claims[0].get("side", 0)), "on the AI's side of the door")

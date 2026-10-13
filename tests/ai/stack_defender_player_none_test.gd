extends GameTest

## Desired (E16): the stack is the invaders' radio. A human on the other side, standing as close as an invader would, is
## not an ally of the stacking team: it is reserved nothing and says nothing on the entry radio.

const Entry := preload("res://tests/_ai/entry_probe.gd")
const Maps := preload("res://tests/_ai/flank_maps.gd")
const Stack := preload("res://tests/_ai/stack_probe.gd")


func describe() -> Dictionary:
	return {
		"name": "A defending human gets no stack slot",
		"description": "An invader stacks at the back door with a household human close by: the human is not reserved a slot and never radios an entry step.",
		"tags": ["ai", "entry", "stack", "scripted", "callout"],
		"timeout": 40.0,
	}


func configure(s: TestSetup) -> void:
	Maps.house(s, false)
	Entry.rules(s, Entry.BACK)
	Entry.npc(s, &"a", Vector2(930, 90), 0.4, { "entry_ready_timeout": 30.0 })
	# Premise: the human defends (the household faction), so the invaders are not its team.
	Stack.human(s, &"me", Stack.NEAR, { "faction": &"household" })


func run(t: TestContext) -> void:
	var stack := Stack.attach(t, &"me")
	if not t.require(stack != null, "the human has a stack radio (PlayerStack.attach)"):
		return
	if not t.require(await t.until(func(): return not Entry.calls(t, "claim", &"a").is_empty(), 25.0), "the invader claimed the doorway (act %s)" % Entry.brain(t, &"a").current_act()):
		return
	var reserved := false
	var end := t.time + 12.0
	while t.time < end:
		reserved = reserved or Stack.mine(stack) > 0
		await t.frames(1)
	t.check(not reserved, "the defending human was never reserved a slot")
	t.check(not Stack.radioed(t, &"me"), "and never radioed an entry step")

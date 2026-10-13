extends GameTest

## Desired (E16), judged by the shipped AI: an invader with the real Von server walks up to the back door of an unexplored
## house to enter it, and the human invader standing near the door is reserved the slot behind it. Nothing is scripted:
## Von chooses to enter, and by which doorway. Needs the Von decision server.

const Entry := preload("res://tests/_ai/entry_probe.gd")
const Maps := preload("res://tests/_ai/flank_maps.gd")
const Stack := preload("res://tests/_ai/stack_probe.gd")


func describe() -> Dictionary:
	return {
		"name": "A human invader joins the stack of a Von-driven entry",
		"description": "The invader decides to enter the house by the back door; the nearby human is reserved slot 2 behind it.",
		"tags": ["ai", "entry", "stack", "von", "callout"],
		"requires_von": true,
		"timeout": 90.0,
	}


func configure(s: TestSetup) -> void:
	Maps.house(s, false)
	# Premises: no trespass hostility (nobody lives here to fight) and no bullets flying over cover, as in every entry test.
	s.switch(&"ai.hostile_on_trespass", false)
	s.switch(&"projectile.flyover", false)
	Entry.npc(s, &"a", Vector2(930, 90), 0.4)
	Stack.human(s, &"me", Stack.NEAR)


func run(t: TestContext) -> void:
	var door := Entry.BACK
	var stack := Stack.attach(t, &"me")
	if not t.require(stack != null, "the human has a stack radio (PlayerStack.attach)"):
		return
	var brain := Entry.brain(t, &"a")
	var entering := func(): return String(Entry.entry(brain).get("opening", "")) != ""
	if not t.require(await t.until(entering, 40.0), "Von sent the invader into the house by an entry (act %s)" % brain.current_act()):
		return
	if not t.require(String(Entry.entry(brain).get("opening", "")) == door["id"], "and by the back door, where the human stands (it chose %s)" % Entry.entry(brain).get("opening", "")):
		return
	if not t.require(await t.until(func(): return Stack.mine(stack) > 0, 20.0), "the human was reserved a slot"):
		return
	t.expect_eq(Stack.mine(stack), 2, "slot 2, behind the invader")
	t.expect_eq(str(Stack.view(stack).get("opening", "")), door["id"], "at the doorway being entered")
	t.check(not Entry.calls(t, "claim", &"me").is_empty(), "on the radio too")

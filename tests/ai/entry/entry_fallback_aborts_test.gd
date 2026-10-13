extends GameTest

## Desired (E6, E9): when Von cannot be reached the NPC takes its steady stance, and a tactical entry it was stacked for
## is given up with it: the stack is told over the radio (`abort`), so the rest of the team stops counting on it. The
## server goes down while the invader is stacked at the back door; a defender it then sees through the door during the
## pie forces a decision, which fails.

const Entry := preload("res://tests/_ai/entry_probe.gd")
const Maps := preload("res://tests/_ai/flank_maps.gd")


func describe() -> Dictionary:
	return {
		"name": "Entry is given up when Von is unreachable",
		"description": "Stacked at the back door, the invader loses its decision server; the next decision fails and it radios abort and holds.",
		"tags": ["ai", "entry", "scripted", "callout"],
		"timeout": 40.0,
	}


func configure(s: TestSetup) -> void:
	Maps.house(s, false)
	Entry.rules(s, Entry.BACK)
	s.set_static(DecisionStub, &"fail", false)   # Flipped mid-test; recorded here so it is restored after.
	Entry.npc(s, &"inv", Vector2(960, 60))
	# Hidden from the stack slot, in view from the pie arc (as in entry_pie_engages_from_outside).
	Entry.target(s, &"defender", Vector2(560, 215), Maps.DOOR_BACK)


func run(t: TestContext) -> void:
	var brain := Entry.brain(t, &"inv")
	if not t.require(await t.until(func(): return String(Entry.entry(brain).get("phase", "")) in ["stack", "pie"], 30.0), "the invader stacked at the door (act %s)" % brain.current_act()):
		return
	DecisionStub.fail = true
	var aborted := func(): return not Entry.calls(t, "abort", &"inv").is_empty()
	if not t.require(await t.until(aborted, 20.0), "it radioed abort once its decision failed (act %s)" % brain.current_act()):
		return
	await t.frames(5)
	t.expect_eq(Entry.entry(brain), {}, "it is no longer entering")

extends GameTest

## With the `ai.entry_guard` switch off a plain order into a room that is not cleared is walked straight in: no stack
## is claimed at any doorway and nothing is radioed about an entry. The same order as the entry-guard search test
## (the living room, two doors deep, from the garden), which the guard turns into two tactical entries.

const Entry := preload("res://tests/_ai/entry_probe.gd")
const Maps := preload("res://tests/_ai/flank_maps.gd")


func describe() -> Dictionary:
	return {
		"name": "No tactical entry with entry_guard off",
		"description": "ai.entry_guard off: sent to search the living room two doors deep, the invader walks in through both doorways without claiming a stack or radioing an entry step.",
		"tags": ["ai", "entry", "guard", "switch", "scripted"],
		"timeout": 110.0,
	}


func configure(s: TestSetup) -> void:
	Maps.house(s, false)
	Entry.guard_rules(s, ["room_living_room"])
	s.switch(&"ai.entry_guard", false)
	Entry.npc(s, &"inv", Maps.GARDEN)
	s.set_props(&"inv", "GoalController", { "familiar_with_house": true })


func run(t: TestContext) -> void:
	var inv := t.actor(&"inv")
	var in_goal := func(): return Maps.HOUSE_LIVING.grow(-30).has_point(inv.global_position)
	if not t.require(await t.until(in_goal, 100.0), "the invader reached the living room (act %s)" % Entry.brain(t, &"inv").current_act()):
		return
	t.check(Entry.asked(t, "room_living_room"), "the order was a plain search of the living room, not ENTER")
	t.check(Entry.calls(t).is_empty(), "it radioed no entry step on the way (%d heard)" % Entry.calls(t).size())
	t.check(Entry.entry(Entry.brain(t, &"inv")).is_empty(), "and no entry is running now it is there")

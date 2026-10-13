extends GameTest

## Desired (E9): an invader that knows the house and is sent to search a room two doors deep crosses each doorway on
## the way by tactical entry. Von names the living room (`room_living_room`, a plain search order) from the garden.

const Entry := preload("res://tests/_ai/entry_probe.gd")
const Maps := preload("res://tests/_ai/flank_maps.gd")


func describe() -> Dictionary:
	return {
		"name": "Entry guard on a search order",
		"description": "Sent to search the living room two doors deep, the invader enters through the front door and the hall's door by tactical entry.",
		"tags": ["ai", "entry", "guard", "scripted"],
		"timeout": 110.0,
	}


func configure(s: TestSetup) -> void:
	Maps.house(s, false)
	Entry.guard_rules(s, ["room_living_room"])
	Entry.npc(s, &"inv", Maps.GARDEN)
	s.set_props(&"inv", "GoalController", { "familiar_with_house": true })


func run(t: TestContext) -> void:
	var inv := t.actor(&"inv")
	var in_goal := func(): return Maps.HOUSE_LIVING.grow(-30).has_point(inv.global_position)
	var samples: Array = await Entry.watch(t, [&"inv"], Entry.FRONT, 100.0, in_goal)
	if not t.require(in_goal.call(), "the invader reached the living room (act %s)" % Entry.brain(t, &"inv").current_act()):
		return
	t.check(Entry.asked(t, "room_living_room"), "the order was a plain search of the living room, not ENTER")
	Entry.check_entered(t, samples, &"inv", Entry.FRONT)
	Entry.check_entered(t, samples, &"inv", Entry.HALL_LIVING)

extends GameTest

## Desired (E9): an invader that is sent to a room it has not seen goes through every doorway on the way by tactical
## entry, not only the one a ENTER order would name. Von is only asked to explore, from the back garden, and the one
## room left unseen is the living room: two doors deep (the front door into the hall, then the hall's door into the
## living room). Neither doorway is an ENTER option, so a plain walk would cross both with no stack and no pie.

const Entry := preload("res://tests/_ai/entry_probe.gd")
const Maps := preload("res://tests/_ai/flank_maps.gd")
## Whichever compass word the living room gets from the garden (the script takes the first one offered).
const EXPLORE := ["explore_north_east", "explore_east", "explore_north", "explore_south_east", "explore_south",
	"explore_south_west", "explore_west", "explore_north_west"]


func describe() -> Dictionary:
	return {
		"name": "Entry guard on an explore order",
		"description": "Sent to explore the living room two doors deep, the invader stacks and slices at the front door and again at the hall's door instead of walking through them.",
		"tags": ["ai", "entry", "guard", "scripted"],
		"timeout": 110.0,
	}


func configure(s: TestSetup) -> void:
	Maps.house(s, false)
	Entry.guard_rules(s, EXPLORE)
	Entry.npc(s, &"inv", Maps.GARDEN)


func run(t: TestContext) -> void:
	var inv := t.actor(&"inv")
	var in_goal := func(): return Maps.HOUSE_LIVING.grow(-30).has_point(inv.global_position)
	var samples: Array = await Entry.watch(t, [&"inv"], Entry.FRONT, 100.0, in_goal)
	if not t.require(in_goal.call(), "the invader reached the living room (act %s)" % Entry.brain(t, &"inv").current_act()):
		return
	t.check(Entry.asked(t, "explore_"), "the order was a plain explore, not ENTER")
	Entry.check_entered(t, samples, &"inv", Entry.FRONT)
	Entry.check_entered(t, samples, &"inv", Entry.HALL_LIVING)

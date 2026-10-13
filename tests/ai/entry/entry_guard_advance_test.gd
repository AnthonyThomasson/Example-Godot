extends GameTest

## Desired (E9): closing in on a hostile in the next room is no excuse to skip the entry. The invader sees a household
## target through the kitchen's back door and is ordered to rush it; the straight route is through that doorway, so it
## stacks beside it and slices the pie first, and it does not run from the moment it turns to the door.

const Entry := preload("res://tests/_ai/entry_probe.gd")
const Maps := preload("res://tests/_ai/flank_maps.gd")
const START := Vector2(990, 190)    # in the back garden, in line with the door
const TARGET := Vector2(620, 190)   # in the kitchen, in line with the door


func describe() -> Dictionary:
	return {
		"name": "Entry guard on an advance order",
		"description": "Ordered to rush a target seen through the back door, the invader stacks and slices at the door before it crosses, and never runs once it turns to it.",
		"tags": ["ai", "entry", "guard", "scripted"],
		"timeout": 60.0,
	}


func configure(s: TestSetup) -> void:
	Maps.house(s, false)
	Entry.guard_rules(s, ["combat", "advance", "rush"])
	Entry.npc(s, &"inv", START, 0.4, {}, { "facing": Vector2.LEFT })
	Entry.target(s, &"tgt", TARGET, Vector2(0, 190))


func run(t: TestContext) -> void:
	var inv := t.actor(&"inv")
	var ran := [0.0]
	var in_kitchen := func():
		var claimed := Entry.first_call_time(t, "claim", &"inv", Entry.BACK["id"])
		if claimed < INF and t.time > claimed + 0.3 and inv.is_running():
			ran[0] += 1.0 / 60.0
		return Maps.HOUSE_KITCHEN.grow(-30).has_point(inv.global_position)
	var samples: Array = await Entry.watch(t, [&"inv"], Entry.BACK, 55.0, in_kitchen)
	if not t.require(in_kitchen.call(), "the invader reached the kitchen (act %s)" % Entry.brain(t, &"inv").current_act()):
		return
	t.check(Entry.asked(t, "rush"), "the order was a plain rush on the target, not ENTER")
	Entry.check_entered(t, samples, &"inv", Entry.BACK)
	t.check(ran[0] == 0.0, "it did not run once it had turned to the door (ran for %.2f s)" % ran[0])
